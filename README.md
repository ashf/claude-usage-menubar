# ClaudeUsageMenuBar

A macOS menu bar app that shows your Claude usage — the same numbers as the
Claude desktop app's Settings > Usage panel, always visible in the menu bar.

> Written with [Claude Code](https://claude.com/claude-code).

The menu bar title is driven by the current session limit, as a filling ring
glyph, a percent, and the time until the session resets:

```
◔ 18% · 2h31m
```

Clicking it opens a dropdown mirroring the Usage panel: a "Current session"
row and a "Weekly limits" section (All models plus any per-model rows), each
with a progress bar and its own reset line, followed by a last-updated line, a
Refresh button, and Quit.

## How it works

Usage comes from `GET https://api.anthropic.com/api/oauth/usage`, the same
endpoint the Claude Code CLI uses. It is authenticated with the OAuth access
token that the CLI stores in the macOS Keychain as a generic password under the
service name `Claude Code-credentials`. The token is read in-process via the
Security framework, and is never logged or written anywhere.

**macOS will prompt for Keychain access on first run.** Granting it (either
"Allow" or "Always Allow") is required for the app to read the token; without
it the dropdown shows that no credentials were found.

The response's `limits` array is the single source of truth for the rows that
are rendered, so any limit kind the server adds later shows up automatically.
Bar and percent colors follow each limit's `severity`.

Usage refreshes on launch, every 60 seconds, and again whenever the dropdown is
opened.

If the token has expired, the app re-reads the Keychain once (Claude Code may
have refreshed it in the meantime) and retries. It never performs the OAuth
refresh flow itself — if the retry still fails it shows "Sign in to Claude
Code", and running `claude` again resolves it.

## Requirements

- macOS 13+
- Swift 5.9+ (Xcode 15+ or the Swift toolchain)
- `claude` must have been logged in at least once, so that the credentials
  exist in the Keychain

## Build & run

```sh
./Scripts/build-app.sh        # builds ClaudeUsageMenuBar.app (debug)
open ClaudeUsageMenuBar.app
```

`swift run` alone is not enough — several menu bar / status item behaviors
expect a real, LaunchServices-registered `.app` bundle rather than a bare
executable, so the build script packages one using `Resources/Info.plist`
(whose `LSUIElement` keeps it out of the Dock).

Pass `release` to build optimized: `./Scripts/build-app.sh release`.

## Inspecting the raw API response

`./Scripts/probe-usage.sh` pretty-prints the raw `/api/oauth/usage` response,
which is useful when the response shape changes. It reads the token from the
Keychain and does not print it.
