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
service name `Claude Code-credentials`. The token is read by running
`/usr/bin/security find-generic-password`, captured from that process's pipe,
and is never logged, written anywhere, or passed as a command argument.

**macOS will prompt for Keychain access on first run.** Granting it (either
"Allow" or "Always Allow") is required for the app to read the token; without
it the dropdown shows that no credentials were found.

For "Always Allow" to actually stick across rebuilds, the app has to be signed
with a stable identity — see [Code signing](#code-signing).

The response's `limits` array is the single source of truth for the rows that
are rendered, so any limit kind the server adds later shows up automatically.
Bar and percent colors follow each limit's `severity`.

Usage refreshes on launch, every 60 seconds, and again whenever the dropdown is
opened.

The endpoint's rate limit is per-account and shared with the `claude` CLI and
the Claude desktop app, so a poll can be throttled even while this app is
polling gently. A 429 (or a network blip) therefore keeps the last good reading
on screen — the menu bar title stays put and the panel explains why the numbers
are stale — rather than blanking the panel.

After a 429, polling backs off: `Retry-After` is honored when it carries a real
delay, otherwise the delay doubles from 60 seconds, and either way it is capped
at 15 minutes. A success clears the backoff, and clicking Refresh is deliberate
and skips it. Network failures keep the normal 60-second cadence, since a blip
is worth retrying promptly.

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
./Scripts/install.sh          # release build, installed to /Applications, launched
```

For a throwaway build in the source directory:

```sh
./Scripts/build-app.sh        # builds ClaudeUsageMenuBar.app (debug)
open ClaudeUsageMenuBar.app
```

Prefer `install.sh` for the copy you actually use. Two bundles sharing a
an identifier but built separately are two distinct code identities, and the
Keychain authorizes them separately — so running one out of the source
directory while a login item points at `/Applications` means each prompts on
its own, and neither prompt says which is which.

`swift run` alone is not enough — several menu bar / status item behaviors
expect a real, LaunchServices-registered `.app` bundle rather than a bare
executable, so the build script packages one using `Resources/Info.plist`
(whose `LSUIElement` keeps it out of the Dock).

Pass `release` to build optimized: `./Scripts/build-app.sh release`.

## Code signing

Run this once, before the first build:

```sh
./Scripts/create-signing-identity.sh
```

It creates a self-signed `ClaudeUsageMenuBar Local Signing` certificate in the
login keychain, trusted for code signing in the **user** trust domain only (not
system-wide). Marking it trusted needs the login password, via the standard
macOS authorization prompt. `build-app.sh` picks the identity up automatically
and warns if it is missing.

This exists because of how Keychain authorization is scoped. An ad-hoc
signature (`codesign --sign -`) has no certificate, so the app's designated
requirement is a bare `cdhash` — a hash of that exact binary, different after
every code change. Signing with a certificate pins the requirement to the
certificate leaf instead, which survives rebuilds.

The first build after creating the identity prompts once for `codesign` to use
the private key — choose Always Allow.

## Why the read is delegated to `security`

Claude Code rewrites the credentials item every time it refreshes the OAuth
token. Each rewrite invalidates the stored authorization for every *other*
application holding a grant on that item — the ACL entries and the partition
list both survive the rewrite untouched, but macOS stops honoring them, because
the item's `ACLAuthorizationIntegrity` record no longer describes its contents.
The next in-process read then asks for the login password again.

Nothing about the reading application changes that. Trusted-application entries
are matched by designated requirement and partition entries by cdhash; both
describe *who* may read, and neither survives the item being mutated by someone
else. Signing stably, reinstalling, and pruning stale ACL entries all leave the
behavior unchanged. The observable signature is a prompt arriving within a
minute of the item's modification date changing, while `security dump-keychain`
shows an access list that already names the app.

`/usr/bin/security` is not affected, because it belongs to the item's
`apple-tool:` partition, so the app runs it as a subprocess and takes the token
from its pipe. This is also why `probe-usage.sh` has never prompted.

Code signing still matters for the reasons above, but it is not what keeps the
Keychain quiet.

## Inspecting the raw API response

`./Scripts/probe-usage.sh` pretty-prints the raw `/api/oauth/usage` response,
which is useful when the response shape changes. It reads the token from the
Keychain and does not print it.
