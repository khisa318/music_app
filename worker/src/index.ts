/**
 * Telegram -> FCM announcement relay, running on a Cloudflare Worker.
 *
 * This is the free-plan replacement for the Firebase Cloud Functions backend:
 * Cloud Functions requires the Blaze plan, while the Worker free tier needs no
 * billing account. The app only needs Firebase Cloud Messaging, which is free.
 *
 * Flow:
 *   Telegram webhook POST
 *     -> verify x-telegram-bot-api-secret-token
 *     -> verify the chat id is allow-listed
 *     -> mint a Google OAuth token from the Firebase service account (RS256 JWT)
 *     -> POST to the FCM HTTP v1 API for the musix_broadcasts topic
 *
 * Required Worker secrets:
 *   TELEGRAM_WEBHOOK_SECRET       random string shared with Telegram
 *   TELEGRAM_ALLOWED_CHAT_IDS     comma-separated chat id allow-list
 *   FIREBASE_SERVICE_ACCOUNT      service account JSON (single line or pretty)
 *
 * Setup: docs/push-notifications.md
 */

interface Env {
  TELEGRAM_WEBHOOK_SECRET: string;
  TELEGRAM_ALLOWED_CHAT_IDS: string;
  FIREBASE_SERVICE_ACCOUNT: string;
}

type ServiceAccount = {
  client_email: string;
  private_key: string;
  project_id: string;
};

type TelegramChat = {
  id?: number | string;
};

type TelegramMessage = {
  message_id?: number;
  chat?: TelegramChat;
  text?: string;
  caption?: string;
};

type TelegramUpdate = {
  update_id?: number;
  message?: TelegramMessage;
  channel_post?: TelegramMessage;
};

const FCM_TOPIC = 'musix_broadcasts';

// Keep the Android channel in sync with DownloadNotificationService.
const ANDROID_CHANNEL_ID = 'musix_broadcasts';

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const TOKEN_URL = 'https://oauth2.googleapis.com/token';

// FCM payloads are capped at 4 KB. Keep a single Telegram message well under
// that, including the JSON envelope.
const MAX_BODY_LENGTH = 500;

// OAuth access tokens live for an hour. The Worker isolate may handle several
// webhook calls, so cache the token until shortly before it expires.
let cachedToken: { value: string; expiresAt: number } | null = null;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === 'GET') {
      return json({ ok: true, service: 'musix-broadcasts' });
    }

    if (request.method !== 'POST') {
      return json({ ok: false, error: 'method_not_allowed' }, 405);
    }

    const providedSecret =
      request.headers.get('x-telegram-bot-api-secret-token') ?? '';

    if (!safeEqual(providedSecret, env.TELEGRAM_WEBHOOK_SECRET ?? '')) {
      return json({ ok: false, error: 'unauthorized' }, 401);
    }

    let update: TelegramUpdate;
    try {
      update = (await request.json()) as TelegramUpdate;
    } catch {
      return json({ ok: false, error: 'invalid_json' }, 400);
    }

    const message = update?.message ?? update?.channel_post;

    if (!message) {
      return json({ ok: true, skipped: 'not_a_message' });
    }

    const chatId = message.chat?.id?.toString() ?? '';
    const allowedChatIds = (env.TELEGRAM_ALLOWED_CHAT_IDS ?? '')
      .split(',')
      .map((id) => id.trim())
      .filter((id) => id.length > 0);

    if (!chatId || !allowedChatIds.includes(chatId)) {
      console.warn('Ignoring Telegram message from an unapproved chat', {
        chatId,
      });
      return json({ ok: true, skipped: 'chat_not_allowed' });
    }

    const text = (message.text ?? message.caption ?? '').trim();

    // Commands such as /start are not announcements.
    if (!text || text.startsWith('/')) {
      return json({ ok: true, skipped: 'empty_or_command' });
    }

    try {
      const messageId = await sendBroadcast(env, text);
      console.log('Broadcast sent', { messageId, chatId });
      return json({ ok: true, messageId });
    } catch (error) {
      console.error('Failed to send FCM broadcast', error);
      // A non-2xx response makes Telegram retry the webhook.
      return json({ ok: false, error: 'fcm_send_failed' }, 502);
    }
  },
};

async function sendBroadcast(env: Env, text: string): Promise<string> {
  const account = parseServiceAccount(env.FIREBASE_SERVICE_ACCOUNT);

  const payload = {
    message: {
      topic: FCM_TOPIC,
      notification: { title: 'MusiX', body: truncate(text, MAX_BODY_LENGTH) },
      data: { type: 'broadcast' },
      android: {
        priority: 'high',
        notification: {
          channelId: ANDROID_CHANNEL_ID,
          sound: 'default',
          defaultVibrateTimings: true,
        },
      },
    },
  };

  const send = async (token: string) =>
    fetch(
      `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          authorization: `Bearer ${token}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify(payload),
      },
    );

  let response = await send(await getAccessToken(env, account));

  // A cached token can be revoked or expire early. Drop it and retry once.
  if (response.status === 401 || response.status === 403) {
    cachedToken = null;
    response = await send(await getAccessToken(env, account));
  }

  const result = (await response.json()) as {
    name?: string;
    error?: unknown;
  };

  if (!response.ok || !result.name) {
    throw new Error(
      `FCM responded ${response.status}: ${JSON.stringify(result).slice(0, 400)}`,
    );
  }

  return result.name;
}

async function getAccessToken(
  env: Env,
  account: ServiceAccount,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  if (cachedToken && cachedToken.expiresAt - 60 > now) {
    return cachedToken.value;
  }

  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64Url(
    JSON.stringify({
      iss: account.client_email,
      scope: FCM_SCOPE,
      aud: TOKEN_URL,
      iat: now,
      exp: now + 3600,
    }),
  );

  const signingInput = `${header}.${claims}`;
  const key = await importPrivateKey(account.private_key);
  const signature = await crypto.subtle.sign(
    { name: 'RSASSA-PKCS1-v1_5' },
    key,
    new TextEncoder().encode(signingInput),
  );

  const assertion = `${signingInput}.${base64UrlBytes(new Uint8Array(signature))}`;

  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(
      `Google token exchange failed (${response.status}): ${detail.slice(0, 300)}`,
    );
  }

  const data = (await response.json()) as {
    access_token: string;
    expires_in: number;
  };

  cachedToken = {
    value: data.access_token,
    expiresAt: now + data.expires_in,
  };

  return data.access_token;
}

function parseServiceAccount(raw: string): ServiceAccount {
  let parsed: unknown;

  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error('FIREBASE_SERVICE_ACCOUNT is not valid JSON');
  }

  const account = parsed as Partial<ServiceAccount>;

  if (!account.client_email || !account.private_key || !account.project_id) {
    throw new Error(
      'FIREBASE_SERVICE_ACCOUNT is missing client_email, private_key, or project_id',
    );
  }

  return account as ServiceAccount;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const base64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');

  const bytes = Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));

  return crypto.subtle.importKey(
    'pkcs8',
    bytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

/**
 * Compares two strings without leaking their length or contents through early
 * exits. Mirrors the constant-time comparison the Cloud Functions version used.
 */
function safeEqual(provided: string, expected: string): boolean {
  if (!provided || !expected) return false;

  const left = new TextEncoder().encode(provided);
  const right = new TextEncoder().encode(expected);

  let diff = left.length ^ right.length;
  const length = Math.max(left.length, right.length);

  for (let index = 0; index < length; index += 1) {
    diff |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }

  return diff === 0;
}

function truncate(value: string, maxLength: number): string {
  // Count code points so a multi-byte character is never split.
  const characters = Array.from(value);
  if (characters.length <= maxLength) return value;
  return `${characters.slice(0, maxLength - 1).join('')}…`;
}

function base64Url(value: string): string {
  return base64UrlBytes(new TextEncoder().encode(value));
}

function base64UrlBytes(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}
