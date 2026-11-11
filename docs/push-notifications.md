# Push notifications: Telegram → Cloud Functions → FCM

MusiX receives announcements through Firebase Cloud Messaging (FCM). The app no
longer polls Telegram directly, so a message reaches every installation —
including apps that are closed or in the background.

```
Telegram chat
     │  webhook POST
     ▼
Cloud Function  telegramWebhook
     │  verifies secret + allowed chat id
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

The backend never needs the bot token: Telegram pushes updates to the webhook.
The only credentials are the webhook secret, the allowed chat IDs, and the
Firebase project's own service account (automatic inside Cloud Functions).

---

## 1. Create the Firebase project

1. Open the [Firebase console](https://console.firebase.google.com/) and create
   a project (for example `musix-app`).
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

5. Cloud Functions requires the **Blaze (pay as you go)** plan. The free tier is
   generous; this setup sends one function invocation per Telegram message.

No service-account JSON is needed locally or in CI. Firebase Admin uses the
function's own runtime credentials.

---

## 2. Authenticate the Firebase CLI

```powershell
npm install -g firebase-tools
firebase login
cd C:\Users\Armstrong\Desktop\flutter\music_app
firebase use --add
```

Choose the project and accept the `default` alias. This creates `.firebaserc`,
which is gitignored.

---

## 3. Configure the function secrets

`TELEGRAM_WEBHOOK_SECRET` — a random string shared with Telegram. Generate one:

```powershell
# PowerShell
-join ((48..57) + (97..102) | Get-Random -Count 64 | ForEach-Object { [char]$_ })
```

or on bash:

```bash
openssl rand -hex 32
```

Store both secrets:

```powershell
firebase functions:secrets:set TELEGRAM_WEBHOOK_SECRET
firebase functions:secrets:set TELEGRAM_ALLOWED_CHAT_IDS
```

`TELEGRAM_ALLOWED_CHAT_IDS` is a comma-separated allow-list. Messages from any
other chat are ignored. Reuse the chat behind `TELEGRAM_CRASH_CHAT_ID` if
announcements come from the same place; otherwise send a message to the bot and
read the chat id from `getUpdates` (see below) or from the function logs.

To find a chat id before the webhook is active:

```powershell
$token = "<BOT_TOKEN>"
Invoke-RestMethod "https://api.telegram.org/bot$token/getUpdates" |
  ConvertTo-Json -Depth 8
```

For a channel, add the bot as an administrator; its id starts with `-100`.

The topic defaults to `musix_broadcasts`. To change it, update
`PushNotificationService.broadcastTopic` in the app and set the
`FCM_BROADCAST_TOPIC` parameter in `functions/.env` (gitignored) before deploying.

---

## 4. Deploy the Cloud Function

```powershell
firebase deploy --only functions
```

The first deploy enables Cloud Build, Artifact Registry and the Cloud Functions
APIs. When it finishes, note the URL:

```
https://us-central1-<PROJECT_ID>.cloudfunctions.net/telegramWebhook
```

The function is deployed with `invoker: 'public'` because Telegram must reach it
without Google credentials. Requests are rejected unless they carry the webhook
secret header.

If the deployed function rejects unauthenticated calls, grant public invoke
access once:

```powershell
gcloud functions add-invoker-policy-binding telegramWebhook `
  --region=us-central1 `
  --member="allUsers" `
  --role="roles/cloudfunctions.invoker"
```

---

## 5. Point Telegram at the function

```powershell
$token  = "<BOT_TOKEN>"
$secret = "<TELEGRAM_WEBHOOK_SECRET>"
$url    = "https://us-central1-<PROJECT_ID>.cloudfunctions.net/telegramWebhook"

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

## 6. Build the app with Firebase config

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

## 7. Test it

1. Install the build on a device.
2. Open the app once and grant notification permission during onboarding.
3. Send a normal text message from the allowed Telegram chat (commands such as
   `/start` are ignored).
4. The app should receive it in the foreground, background, and terminated
   states.

Useful logs:

```powershell
firebase functions:log --only telegramWebhook
```

Each accepted message logs `Broadcast sent` with an FCM message id.

---

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Webhook returns `401 unauthorized` | The `secret_token` used in `setWebhook` differs from `TELEGRAM_WEBHOOK_SECRET`. Set the secret again and redeploy. |
| Function returns `chat_not_allowed` | The chat id is missing from `TELEGRAM_ALLOWED_CHAT_IDS`. Update the secret and redeploy. |
| Function returns `403` / webhook shows an error | The function is not publicly invokable. See the `add-invoker-policy-binding` command above. |
| Notification never appears | Check `POST_NOTIFICATIONS` permission, the `Announcements` channel, and battery optimisation. The foreground path also requires the local-notification service to be initialised at startup. |
| `Push notifications unavailable` in logs | `google-services.json` is missing or the package name does not match `com.khisa318.musiX`. |
| Build fails after adding the plugin | Confirm the file exists at `android/app/google-services.json` before running Gradle. |
| Duplicate notifications after a webhook retry | Telegram retries when the function returns non-2xx. Retries are rare; a failed FCM send is retried on purpose. |

---

## Security notes

- Keep `google-services.json`, the bot token, `.firebaserc`, and service-account
  JSON out of git. All are gitignored.
- The webhook secret and chat allow-list are the only gates. Rotate the secret
  if it leaks, then call `setWebhook` again.
- The Cloud Function never stores the bot token; it only validates Telegram's
  secret header and publishes to FCM.
- FCM topic messages are not encrypted end-to-end. Do not use them for secrets.
