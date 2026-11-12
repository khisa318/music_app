# Push notifications: Telegram → Cloudflare Worker → FCM

MusiX receives announcements through Firebase Cloud Messaging (FCM). The app no
longer polls Telegram directly, so a message reaches every installation —
including apps that are closed or in the background.

The webhook relay runs on a **Cloudflare Worker on the free plan**. It replaces
the earlier Firebase Cloud Functions version, which required the paid Blaze
plan. FCM itself and the Firebase project stay on the free Spark plan.

```
Telegram chat
     │  webhook POST
     ▼
Cloudflare Worker  musix-broadcasts   (free plan)
     │  verifies secret + allowed chat id
     │  mints a Google OAuth token from a service account
     ▼
FCM topic  musix_broadcasts
     │
     ▼
Every installed MusiX app
```

- While the app is open, `PushNotificationService` shows the message through
  `flutter_local_notifications`.
- While the app is backgrounded or terminated, Android displays the FCM
  notification itself.
- Turning **Settings → General → Notifications** off unsubscribes the device
  from the broadcast topic, and turning it back on re-subscribes. The OS
  permission is not changed by this switch.

The Worker never needs the Telegram bot token: Telegram pushes updates to the
webhook. Its only credentials are the webhook secret, the chat allow-list, and
the Firebase service account key.

---

## 1. Create the Firebase project (Spark plan)

1. Open the [Firebase console](https://console.firebase.google.com/) and create
   a project (for example `musix-push`).
2. Add an **Android app** with package name:

   ```
   com.khisa318.musiX
   ```

3. Download `google-services.json`.
4. Place it at:

   ```
   android/app/google-services.json
   ```

   It is gitignored on purpose. Never commit it.

Spark is enough: Cloud Messaging and Android app registration are free. Only
the old Cloud Functions backend needed Blaze.

---

## 2. Create the service account key

The Worker uses this key to call the FCM HTTP v1 API.

1. In the Firebase console open **Project settings → Service accounts**.
2. Click **Generate new private key** and confirm.
3. Save the downloaded JSON somewhere outside the repository, for example:

   ```
   %TEMP%\musix-push-service-account.json
   ```

4. Never commit it. `.gitignore` also rejects names matching
   `*service-account*.json`.

The key belongs to the Firebase Admin SDK account, so treat it as a
project-wide secret. The Worker only requests the
`https://www.googleapis.com/auth/firebase.messaging` scope, but anyone holding
the key can mint tokens for other scopes. Rotate it immediately if it leaks
(Firebase console → Service accounts → delete the old key, generate a new one,
update the Worker secret).

---

## 3. Prepare the Cloudflare Worker

1. Create a free account at [dash.cloudflare.com](https://dash.cloudflare.com/)
   if you do not have one. No payment method is required.
2. Install the Worker dependencies:

   ```powershell
   cd worker
   npm install
   ```

3. Log in:

   ```powershell
   npx wrangler login
   ```

   The browser opens; approve the CLI. On first deploy Cloudflare may ask you to
   register a `workers.dev` subdomain — this is free.

The Worker source is `worker/src/index.ts`. It verifies the Telegram secret,
checks the chat allow-list, caches the OAuth token, and posts to FCM. It needs
no KV, D1, Durable Objects, or paid features.

---

## 4. Configure the Worker secrets

Three secrets are required:

| Secret | Purpose |
| --- | --- |
| `TELEGRAM_WEBHOOK_SECRET` | Random string shared with Telegram |
| `TELEGRAM_ALLOWED_CHAT_IDS` | Comma-separated allow-list of chat ids |
| `FIREBASE_SERVICE_ACCOUNT` | Contents of the service account JSON |

Generate the webhook secret:

```powershell
# PowerShell: 64 hex characters
-join (1..32 | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })
```

or on bash:

```bash
openssl rand -hex 32
```

`TELEGRAM_ALLOWED_CHAT_IDS` is a comma-separated allow-list. Messages from any
other chat are ignored. Reuse the chat behind `TELEGRAM_CRASH_CHAT_ID` if
announcements come from the same place; otherwise send a message to the bot and
read the chat id from `getUpdates` (see below) or from the Worker logs.

To find a chat id:

```powershell
$token = "<BOT_TOKEN>"
Invoke-RestMethod "https://api.telegram.org/bot$token/getUpdates" |
  ConvertTo-Json -Depth 8
```

For a channel, add the bot as an administrator; its id starts with `-100`.

Store all three secrets at once. Build a temporary bulk file so the JSON is
escaped correctly, then delete it:

```powershell
$sa = Get-Content -Raw "$env:TEMP\musix-push-service-account.json" |
  ConvertFrom-Json | ConvertTo-Json -Compress -Depth 10

$secrets = @{
  TELEGRAM_WEBHOOK_SECRET   = "<RANDOM_SECRET>"
  TELEGRAM_ALLOWED_CHAT_IDS = "<CHAT_ID>"
  FIREBASE_SERVICE_ACCOUNT  = $sa
} | ConvertTo-Json -Compress

$file = Join-Path $env:TEMP "musix-worker-secrets.json"
Set-Content -Path $file -Value $secrets -NoNewline
npx wrangler secret bulk $file
Remove-Item $file
```

You can also set them one at a time with
`npx wrangler secret put <NAME>` and paste the value when prompted.

---

## 5. Deploy the Worker

```powershell
cd worker
npm run deploy
```

Wrangler prints the public URL:

```
https://musix-broadcasts.<your-subdomain>.workers.dev
```

Open it in a browser; it returns:

```json
{ "ok": true, "service": "musix-broadcasts" }
```

That confirms the Worker is live. The `GET` health check does not touch FCM.

---

## 6. Point Telegram at the Worker

```powershell
$token  = "<BOT_TOKEN>"
$secret = "<TELEGRAM_WEBHOOK_SECRET>"
$url    = "https://musix-broadcasts.<your-subdomain>.workers.dev"

Invoke-RestMethod -Method Post `
  -Uri "https://api.telegram.org/bot$token/setWebhook" `
  -ContentType "application/json" `
  -Body (@{
    url = $url
    secret_token = $secret
    allowed_updates = @("message", "channel_post")
  } | ConvertTo-Json)
```

Verify:

```powershell
Invoke-RestMethod "https://api.telegram.org/bot$token/getWebhookInfo" |
  ConvertTo-Json -Depth 5
```

The response should show the URL, no `last_error_message`, and the expected
`pending_update_count`.

---

## 7. Build the app with Firebase config

### Locally

After placing `android/app/google-services.json`, run normally:

```powershell
flutter run
```

The Gradle plugin is applied only when that file exists. Without it the app
still builds and runs; push notifications are simply disabled and the app logs
`Push notifications unavailable`.

### CI / releases

The release workflow restores the file from a GitHub Actions secret:

1. Base64-encode the config:

   ```powershell
   [Convert]::ToBase64String(
     [IO.File]::ReadAllBytes("android\app\google-services.json")
   ) | Set-Clipboard
   ```

2. In **GitHub → Settings → Secrets and variables → Actions**, add:

   | Secret | Purpose |
   | --- | --- |
   | `GOOGLE_SERVICES_JSON_BASE64` | Injects `android/app/google-services.json` into release builds |
   | `TELEGRAM_CRASH_BOT_TOKEN` | Existing crash reports |
   | `TELEGRAM_CRASH_CHAT_ID` | Existing crash reports |

3. `.github/workflows/release.yml` decodes the file before `flutter build apk`.
   A missing secret fails the release instead of shipping an APK without push.

---

## 8. Test it

1. Install the build on a device.
2. Open the app once and grant notification permission during onboarding.
3. Send a normal text message from the allowed Telegram chat (commands such as
   `/start` are ignored).
4. The app should receive it in the foreground, background, and terminated
   states.

A healthy request returns HTTP 200 with `{"ok":true,"messageId":"projects/..."}`.
Inspect live logs with:

```powershell
cd worker
npx wrangler tail
```

---

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Worker returns `401 unauthorized` | The `secret_token` used in `setWebhook` differs from `TELEGRAM_WEBHOOK_SECRET`. Set the secret again with `wrangler secret put` and call `setWebhook` again. |
| Response is `chat_not_allowed` | The chat id is missing from `TELEGRAM_ALLOWED_CHAT_IDS`. Update the secret and retry. |
| Response is `fcm_send_failed` (502) | Check `wrangler tail`. Usually the service account JSON is malformed, belongs to another project, or the key was deleted. |
| `FIREBASE_SERVICE_ACCOUNT is not valid JSON` | The secret was pasted with surrounding quotes or line breaks. Re-create it with the bulk-file command above. |
| `Google token exchange failed (400)` | The service account key is invalid or revoked. Generate a new key in the Firebase console and update the secret. |
| Notification never appears | Check `POST_NOTIFICATIONS` permission, the `Announcements` channel, and battery optimisation. The foreground path also requires the local-notification service to be initialised at startup. |
| Announcements stop after toggling a setting | **Settings → General → Notifications** off unsubscribes the device from `musix_broadcasts`. Turn it back on to re-subscribe; the OS permission is unchanged. |
| `Push notifications unavailable` in app logs | `google-services.json` is missing or the package name does not match `com.khisa318.musiX`. |
| `Error 1102` / CPU limit in `wrangler tail` | The Worker exceeded the free-plan CPU limit. This relay normally uses a few milliseconds; retry and check for an unusually large message. |
| Duplicate notifications after a webhook retry | Telegram retries when the Worker returns non-2xx. Retries are rare; a failed FCM send is retried on purpose. |

---

## Security notes

- Keep `google-services.json`, the service account JSON, the bot token, and the
  Worker secret file out of git. All are gitignored or live in `%TEMP%`.
- The webhook secret and chat allow-list are the only request gates. Rotate the
  secret if it leaks, then call `setWebhook` again with the new value.
- The service account key is stored only as an encrypted Worker secret. Delete
  the local copy after uploading it.
- The Worker never stores the bot token; it only validates Telegram's secret
  header and publishes to FCM.
- FCM topic messages are not encrypted end-to-end. Do not use them for secrets.

---

## Optional: Firebase Cloud Functions backend (paid)

The previous implementation in `functions/` still works, but Cloud Functions
requires the Blaze plan. With the Worker in place there is no reason to deploy
it. If you ever move to Blaze, `firebase.json` and
`docs/push-notifications.md` history describe that path; the FCM topic and app
code are identical.
