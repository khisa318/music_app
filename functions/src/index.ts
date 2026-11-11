import { timingSafeEqual } from 'crypto';

import { initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions';
import { onRequest } from 'firebase-functions/v2/https';
import { defineSecret, defineString } from 'firebase-functions/params';

initializeApp();

// Set with:
//   firebase functions:secrets:set TELEGRAM_WEBHOOK_SECRET
//   firebase functions:secrets:set TELEGRAM_ALLOWED_CHAT_IDS
const telegramWebhookSecret = defineSecret('TELEGRAM_WEBHOOK_SECRET');
const telegramAllowedChatIds = defineSecret('TELEGRAM_ALLOWED_CHAT_IDS');

// Defaults match PushNotificationService.broadcastTopic in the Flutter app.
const broadcastTopic = defineString('FCM_BROADCAST_TOPIC', {
  default: 'musix_broadcasts',
});

// FCM payloads are capped at 4 KB. Keep a single Telegram message well under
// that, including the JSON envelope.
const MAX_BODY_LENGTH = 500;

type TelegramChat = {
  id?: number | string;
  title?: string;
  username?: string;
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

function safeEqual(provided: string, expected: string): boolean {
  if (!provided || !expected) return false;

  const providedBuffer = Buffer.from(provided);
  const expectedBuffer = Buffer.from(expected);

  if (providedBuffer.length !== expectedBuffer.length) return false;

  return timingSafeEqual(providedBuffer, expectedBuffer);
}

function parseAllowedChatIds(value: string): string[] {
  return value
    .split(',')
    .map((id) => id.trim())
    .filter((id) => id.length > 0);
}

function truncate(value: string, maxLength: number): string {
  const characters = Array.from(value);
  if (characters.length <= maxLength) return value;
  return `${characters.slice(0, maxLength - 1).join('')}…`;
}

/**
 * Receives Telegram bot updates and publishes them to the FCM broadcast topic.
 *
 * Setup (webhook URL and secret token) is documented in
 * docs/push-notifications.md. Requests without Telegram's secret header are
 * rejected, and messages from any chat other than the allow-list are ignored.
 */
export const telegramWebhook = onRequest(
  {
    region: 'us-central1',
    secrets: [telegramWebhookSecret, telegramAllowedChatIds],
    invoker: 'public',
  },
  async (request, response) => {
    if (request.method !== 'POST') {
      response.status(405).json({ ok: false, error: 'method_not_allowed' });
      return;
    }

    const providedSecret =
      request.header('x-telegram-bot-api-secret-token') ?? '';

    if (!safeEqual(providedSecret, telegramWebhookSecret.value())) {
      response.status(401).json({ ok: false, error: 'unauthorized' });
      return;
    }

    const update = request.body as TelegramUpdate | undefined;
    const message = update?.message ?? update?.channel_post;

    if (!message) {
      response.status(200).json({ ok: true, skipped: 'not_a_message' });
      return;
    }

    const chatId = message.chat?.id?.toString() ?? '';
    const allowedChatIds = parseAllowedChatIds(
      telegramAllowedChatIds.value(),
    );

    if (!chatId || !allowedChatIds.includes(chatId)) {
      logger.warn('Ignoring Telegram message from an unapproved chat', {
        chatId,
      });
      response.status(200).json({ ok: true, skipped: 'chat_not_allowed' });
      return;
    }

    const text = (message.text ?? message.caption ?? '').trim();

    // Commands such as /start are not announcements.
    if (!text || text.startsWith('/')) {
      response.status(200).json({ ok: true, skipped: 'empty_or_command' });
      return;
    }

    const body = truncate(text, MAX_BODY_LENGTH);
    const title = 'MusiX';

    try {
      const messageId = await getMessaging().send({
        topic: broadcastTopic.value(),
        notification: { title, body },
        data: { type: 'broadcast' },
        android: {
          priority: 'high',
          notification: {
            channelId: 'musix_broadcasts',
            sound: 'default',
            defaultVibrateTimings: true,
          },
        },
      });

      logger.info('Broadcast sent', { messageId, chatId });
      response.status(200).json({ ok: true, messageId });
    } catch (error) {
      logger.error('Failed to send FCM broadcast', error);
      // A non-2xx response makes Telegram retry the webhook.
      response.status(500).json({ ok: false, error: 'fcm_send_failed' });
    }
  },
);
