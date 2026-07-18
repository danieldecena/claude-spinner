# Claude 5h-reset notifier

A tiny launchd routine that warns you **30 minutes before the Claude 5-hour
rate-limit window resets** — as a macOS notification, and optionally as a push
to your phone. One alert per window, no repeats.

Built from the same usage plumbing as the claude-spinner menu-bar app.

## Install

```sh
./install.sh                      # prompts for an optional ntfy phone topic
./install.sh --ntfy-topic NAME    # non-interactive, phone push preconfigured
./install.sh --uninstall          # remove everything
```

This copies `check-reset.sh` to `~/.claude/reset-notifier/`, installs a launchd
user agent (`com.danieldecena.claude-reset-notifier`, every 5 minutes), and
starts it immediately.

## Phone push (optional)

1. Install the free [ntfy](https://ntfy.sh) app (iOS/Android).
2. In the app, subscribe to the topic name you gave the installer.
3. That's it — no account, no API key. Topics are public-by-knowledge, so use
   an unguessable name (the installer suggests a random one) and keep it to
   yourself.

## How it finds the reset time

1. **Feed files** — the newest `~/.claude/spinnerfeed/*.status.json` (the raw
   Claude Code statusLine payload the spinner already captures). Free and
   local, but only fresh while a Claude Code session is running; files older
   than 30 minutes are treated as stale.
2. **API fallback** — one `max_tokens: 1` request to `api.anthropic.com` using
   your Claude Code login token from the keychain, reading the
   `anthropic-ratelimit-unified-5h-reset` response header. This is the same
   trick the spinner's usage poller uses. Note: it is a (tiny) billable
   request, and it only happens when the feed files can't answer.

If neither source works, the check exits silently and the next 5-minute tick
retries — it never notifies on bad data.

## Notes

- **Notification permission:** the first banner may require allowing
  notifications from "Script Editor"/osascript in System Settings →
  Notifications.
- **Timing:** the agent ticks every 5 minutes, so the alert lands 25-30
  minutes before the reset.
- **Debugging:** `bash ~/.claude/reset-notifier/check-reset.sh --dry-run`
  prints the current decision; the agent's output lands in
  `~/.claude/reset-notifier/log`.

## Tests

`./test.sh` — fixture-driven, runs on macOS or Linux, no network/osascript
(channels are stubbed via `NOTIFY_CMD`/`PUSH_CMD`, API disabled via `NO_API=1`).
