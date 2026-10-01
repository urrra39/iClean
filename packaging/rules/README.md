# Rule packs

Import with `iclear config import <file>`. A pack may contain only `allow`, `deny`,
`tiers`, `wakeWindows` and `workspaces`; it is validated before anything is written.
`iclear compat <app>` shows an app's class, tier and what pausing does to it.

| File | What it does | Tradeoff |
|---|---|---|
| `chat-wake-windows.json` | Lets Slack, Discord, Telegram, WhatsApp and Teams be paused when idle, but resumes each for 20 s every 5 minutes so it can sync | Messages can arrive up to 5 minutes late; the app's server may drop and re-open its connection; calls and notifications in between are missed. Never refrozen during a call (Focus Safe Mode). Measured in [VALIDATION.md](../../docs/VALIDATION.md) with a simulated chat app. |
| `browsers-never.json` | Never pause the common browsers | Browsers keep their memory |
