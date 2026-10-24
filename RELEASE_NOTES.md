# 1.1.0

## Added

- Added shuffle and repeat controls to the queue menu.
- Added Telegram crash reports to the configured bot chat.
- Added Telegram message notifications while the app is running and polling.

## Notes

- Telegram message polling uses the bot's shared update queue, so it is not a reliable broadcast to all installations. The app needs to be running to poll for messages.
- Built with Flutter.
- Full changelog: https://github.com/khisa318/music_app/compare/v1.0.9...v1.1.0
