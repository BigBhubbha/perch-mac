# Perch

A Dynamic Island for Shabd's MacBook. It rests behind the lime camera cover, and when you rest
the pointer on it, it opens into a small panel with what is playing, quick notes, your Grok Bot
agents, and (next version) Gmail.

## Install

Paste into Terminal:

```
curl -fsSL https://raw.githubusercontent.com/BigBhubbha/perch-mac/main/scripts/install.sh | sh
```

It stops any stuck Perch, moves old copies to the Trash, downloads the newest release, checks it is
signed by the Perch Signing certificate, and installs it in /Applications (or ~/Applications when the
account is not an admin). A copy downloaded with a browser is quarantined, and on macOS 26 Gatekeeper can
hold it forever with the Dock icon bouncing; curl avoids that.

## What is in here

| Path | What it is |
| --- | --- |
| `Sources/Perch` | The app: Swift, SwiftUI and AppKit, built as a Swift package |
| `build.sh` | Builds `build/Perch.app` on a Mac without Xcode |
| `scripts/build_adapter.sh` | Builds the now playing helper (ungive/mediaremote-adapter, BSD-3-Clause) at a pinned commit |
| `.github/workflows/build.yml` | Builds, signs, checks, renders previews, makes `Perch.dmg` and the Sparkle update on macOS runners |
| `cloudflare/` | The agent board, a tiny Cloudflare Worker with one Durable Object |
| `scripts/perch-signal` | What agents run to say they started or finished |

## Releases

Pushing to `main` only builds. Nothing ships until someone runs the workflow by hand with
**publish** ticked, and only when `CFBundleShortVersionString` in `Resources/Info.plist` is new.

Updates come through Sparkle 2 with EdDSA signatures; the appcast is attached to the latest release.
Every build is signed with the same long-lived self-signed certificate ("Perch Signing", valid to 2046),
so macOS keeps Perch's permissions across updates. Never change that certificate or the bundle id
`com.bigbhubbha.perch`.

Secrets used by CI: `MACOS_SIGN_P12`, `MACOS_SIGN_P12_PASSWORD`, `SPARKLE_PRIVATE_KEY`, `PERCH_BOARD_READ_KEY`.

## The agent board

```
perch-signal start  "Architect III" "Building Perch v1"
perch-signal update "Architect III" "Waiting on CI"
perch-signal done   "Architect III" "CI is green"
perch-signal fail   "Architect III" "Build broke"
```

The script reads the write key from `~/.perch/board_write_key` on the box. Keep task lines short and
free of private details, since they show at the top of the screen.

Raw API (Bearer write key): `POST /v1/events` with `{"agent","status","task","note"}`, status one of
`started`, `working`, `finished`, `failed`. The app reads `GET /v1/agents` with the read key.

## The fit

The resting island is sized around the camera cover, not the notch. On first launch Perch asks you to
fit it: drag the coral pill until a thin, even ring shows around the cover. Arrows move it, Option +
arrows resize, `[` and `]` round the corners, Shift makes bigger steps. Redo it any time from the
island ("Refit") or Settings.

## Music

Perch reads now playing through `/usr/bin/perl` and the bundled MediaRemote adapter, which still works
on macOS 15.4 and later. If the adapter's self-test fails (a future macOS could break it), Perch falls
back to asking Spotify and Music with AppleScript. The helper is stopped on quit and on SIGTERM, and a
watchdog kills it if Perch ever crashes.
