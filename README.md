# DSH Bezel

**English** · [简体中文](docs/README.zh-Hans.md) · [繁體中文](docs/README.zh-Hant.md) · [日本語](docs/README.ja.md) · [Français](docs/README.fr.md) · [Deutsch](docs/README.de.md) · [Español](docs/README.es.md)

yet-another-dsh-for-mac. A native macOS shell that loads a dsh Host's own Web UI
straight into a `WKWebView`, and adds exactly what a shell can legitimately add
around a display: **choosing which dsh to connect to**, **knowing when the
display is calling for you**, and **an interface language of its own**.

## Why a shell instead of a protocol reimplementation

A dsh Web UI is not a static frontend to bundle inside an app — it is a complete
application served by the Host itself:

- the SPA is served from the Host's frontend-static seat;
- every `dsh.client` plugin's browser bundle is served from `/plugins/<id>/client.js`;
- the `window.__DSH_BOOT__` bootstrap payload is injected by the Host on every index render.

So "which dsh do I connect to" comes down, in implementation, to "which URL does
a `WKWebView` load". What that buys is **zero protocol drift**: session
rendering, approvals, plans, goals, tool cards, attachments, settings, model
selection and third-party browser plugins all follow the Host version
automatically. This project never has to understand `/api`,
`/api/remote.mux`, or any event type.

## Quick start

```sh
swift build --disable-sandbox   # compile (the flag is only needed under the DSH harness)
swift test --disable-sandbox    # unit tests for the connection model and page signals
./scripts/make-app.sh           # produce build/DSH Bezel.app
open "build/DSH Bezel.app"
```

`swift run dsh-bezel` works too, but that is a bare executable: with no bundle,
the ATS exception in `Info.plist` does not apply, cookie/preference ownership is
unstable, and macOS refuses to deliver notifications. Use the `.app` for real
work.

## First-launch guide

The first launch opens a short guide instead of the main window. It detects
whether a DSH process is already serving a Web UI and offers what that finding
allows:

- **Bind the running process** — point this app at a `dsh` you started
  yourself, by pasting the address and token from its startup output.
- **Start a managed one** — this app runs the child and terminates it on quit.
  *Automatic* finds an installed `dsh` (offering to install it through npm if
  none is found, which needs Node.js); *manual* runs a launch command you
  provide, as long as it prints the `dsh web: http://…` startup line.

Skipping the guide lands on the connect prompt, one click away; the guide only
returns when the config file is deleted.

## Interface language

The interface is English by default, whatever language macOS itself is set to.
Settings → General → Language switches it to 简体中文, 繁體中文, 日本語, Français,
Deutsch or Español, and the choice is written to the config file described
below, so it survives a relaunch.

All seven languages live in one file behind exhaustive switches, so a message
cannot ship with only some of them: forgetting a translation fails the build
instead of leaving a stray Chinese string in an English UI. That file also holds
the wording for runtime diagnostics, which are carried as structured values and
rendered at display time — so switching the language re-renders a failure that
is already on screen instead of leaving it in the language it was produced in.

The one part that cannot switch mid-session is the native menu bar: macOS draws
it from the bundle's localization at launch. Every launch, the app mirrors its
configured language into `AppleLanguages` before the UI is built, and the bundle
ships a `.lproj` for each supported language, so the menus follow the setting on
the next start. While the picked language and the menu bar's disagree, Settings
offers a restart button for exactly that.

This setting covers this app's own interface only. The Host's Web UI is served
by the Host and keeps its own language setting.

## Notifications

The one capability a bezel can legitimately add around a display is knowing
that the display is calling for you. Two moments are worth calling out: the
Host is waiting for your decision (a tool approval, a question, a plan
review), or a running task just finished. Everything below is **page
monitoring**: this app learns both from the same page you are looking at, by
reading what the Host's own Web UI already renders for exactly these
situations — nothing is intercepted, nothing is read off the wire, nothing in
the page is modified.

### Page monitoring

**Injection.** A small observer script — plain JavaScript, read-only — is
registered as a WebKit user script and rides along with every page the
`WKWebView` loads, injected at document end. A guard keeps a reinjected script
(a reload re-runs user scripts) from stacking intervals.

**Polling.** The script takes one snapshot per second; each pass is a handful
of `querySelector` calls. A plain poll rather than a `MutationObserver`,
because a poll cannot miss a panel that mounts and unmounts between mutations
the way a naive observer summary can.

**What one snapshot reads** — only markers the Host's own Web UI renders:

| Signal | Marker | Meaning |
| --- | --- | --- |
| Waiting panel | `data-approval-key` / `data-question-key` / `data-plan-review-key` | the Host is blocked on an approval, a question or a plan review |
| Turn ended | `data-turn-tail` on the actions row under a final answer (copy, fork, usage, feedback) | the Host's own "this turn ended" mark — published the moment the turn's `turn/end` event arrives, so "task finished" means exactly what the page means by it, not something inferred from "the streaming markers went quiet" |
| Task name | the turn number that row carries locates the user message that started the turn | the notification tells you **which task** finished — in your own words |
| Still the same conversation? | `data-chat-anchor-key` of the newest content rows | a switch replaces every row; a finished turn only adds one below — so switching sessions never masquerades as a finish |
| Session name | the selected sidebar row, or `document.title` (`"<session> — <product>"`) | every notification names its conversation |
| Background sessions | the sidebar rows' `data-state` dots | running / waiting for you / finished-but-unopened |

**From snapshot to event.** Each second the script posts its snapshot over a
private bridge channel (`window.webkit.messageHandlers`); the app decodes it,
and a pure, unit-tested detector derives the transitions worth notifying: an
attention appearing, a turn-end mark changing while the rows above it still
stand, a status dot flipping. The first snapshot after a load is only a
baseline — where things stand is state, not news — and a dot's first sighting
after a gap is history, not an event.

### The background nobody displays

Tasks not on this page — sessions running in the background of the same Host —
are covered through the one surface that shows them: the sidebar. Its session
rows carry the Host's own live status dot (`data-state`): running, waiting for
you, or finished-but-unopened — that last one is the Host's own "completed"
reminder, armed exactly when a background session that was running went idle
and nobody has opened it since. A dot's edge becomes a notification that names
the session.

The sidebar only renders what its view state shows, though — a collapsed
workspace group renders no session rows, and an expanded one caps at its five
most recent — so the displayed page's sidebar is not the whole background. A
second, hidden `WKWebView` loads the same Host page (its own non-persistent
store, the displayed page's cookie copied in, its address stripped of the
single-use token) and opens every group and overflow before scanning: nobody
watches that page, so its clicks write a view state of its own. It restores no
selection — it opens nothing — so the Host's per-client completion dots arm for
every session while the probe never clears one. While the probe is alive, its
rows are the background's truth: it posts once a second, rows older than
fifteen seconds defer to the displayed page's own sidebar, and a page that
stays silent for thirty seconds is reloaded with a fresh copy of the cookie.

### Delivery rules

When a snapshot becomes a macOS notification follows two rules, one per class
of event. A summons — the Host waiting on input or confirmation, on this page
or in a background session — is always delivered: frontmost, background, or
minimized, because it blocks the Host until answered, and the visible page
does not cover every source. A finish is a status report: while this app is
frontmost with its window up, the page is its own notification, and a banner
would only repeat what is already on screen. Clicking a notification brings
the window forward, restoring it from the Dock if it was minimized there.

Notifications are on by default; Settings → General has the switch, and the
system's permission dialog is asked once at first launch. macOS delivers
notifications only from an app bundle — the bare `swift run` executable
neither asks nor notifies.

## What is remembered

Everything the app knows lives in one JSON file:

```
~/Library/Application Support/dsh-bezel/config.json
```

It holds the Host bookmarks with all their settings, which bookmark the picker
is on, which one the WebView was last attached to, and the interface language.
On launch the app reads it and **reconnects to the Host it was last attached
to**, so opening the app is enough to get back to where you were; a managed Host
is started fresh, since its port and token are new on every run. The signed
`dsh-auth` cookie is remembered separately by WebKit's own data store, so
reconnecting does not need the token again.

A file rather than `UserDefaults`, so it can be read, edited, copied to another
machine and kept in version control. It is written pretty-printed with sorted
keys and unescaped slashes precisely so a diff of it stays readable, atomically
through a temporary file so a crash mid-write cannot truncate it, and `0600`
because a bookmark may hold a launch token. `BEZEL_CONFIG` points the app at a
different path if you want one.

Decoding is field-by-field and tolerant: unknown keys are ignored, a scalar of
the wrong type falls back to its default, and bookmarks written by an older
build (missing fields added later) load as usual. A file that cannot be parsed
at all is reported in Settings and **left exactly as it is** — never overwritten
— so a hand edit that needs a typo fixed, or a file from a newer build, stays
recoverable. Deleting the file is how you reset. A name you typed is your data
and is shown as-is in every language; only the name of a freshly seeded first-run
bookmark follows the current language. Window size and position are not part of
this file: SwiftUI remembers those itself.

## Connection model

A Host is a bookmark with four fields that matter: **name, address (origin),
launch token (optional), and whether this app manages it**.

**External Host (not managed)**: enter `http://host:port`. If that Host has not
given this browser a cookie yet, paste the full address from `dsh web`'s startup
output into "launch token", or open the address with its `?token=` once in a
browser and come back to this app (cookies are shared per authority, within this
app's WebKit data store).

**Managed Host**: the app runs

```sh
dsh --profile web --port 0 --no-open
```

Port `0` lets the system choose, and the URL is parsed from the
`dsh web: http://127.0.0.1:PORT/?token=…` line on the child's stdout. Quitting
the app terminates that child (so does the "Disconnect" button). If the line has
not appeared within 30 seconds the launch is judged timed out and the child is
terminated, so the interface never sits on "Starting" for ever.

**Finding `dsh`**: an app launched by double-clicking in Finder inherits
launchd's minimal PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), which holds neither
node nor npm — and nearly every `dsh` on a real machine is a wrapper that needs
an interpreter (`#!/usr/bin/env node`, `npm exec …`, or DSH Desktop's runtime
shim). So "the file exists and has the x bit" is nowhere near enough to call it
usable. The search runs in this order, and every candidate is genuinely run once
with `dsh --version`; only one that succeeds is handed to the child:

1. the "dsh executable path" in the Host's settings
2. the `BEZEL_DSH_PATH` environment variable
3. the login shell's `command -v dsh`
4. `dsh` on the app's own PATH
5. conventional install locations: `~/.local/bin`, `~/bin`, `/opt/homebrew/bin`,
   `/usr/local/bin`, `~/.npm-global/bin`, `~/.bun/bin`, `/opt/anaconda3/bin`, …

Step 3 asks an **interactive** login shell (`zsh -l -i -c`, falling back to
`-l -c`): the directories holding `node`/`npm` usually live in `~/.zshrc`, which
a non-interactive `zsh -l -c` never reads — which is exactly why a GUI app's
PATH and the user's terminal disagree. The probe separates rc-file chatter from
the answer with a sentinel line, and has a 5-second timeout.

The child's PATH is the login shell's PATH → the app's inherited PATH →
interpreter directories, deduplicated and merged. Note that only **interpreter
directories** are injected — never directories like `~/bin` or `~/.local/bin`
where *another* `dsh` lives: some wrappers scan PATH themselves and defer to
whatever they find (DSH Desktop's shim does), so putting another wrapper on PATH
hands the launch to it instead of using the runtime that shim ships with.

When every candidate fails, the connect prompt lists each location that was
tried and why it did not work (missing, or `--version` would not run).

**Credential semantics**: `GET /?token=…` is exchanged by the Host for a signed
cookie valid for 30 days (`dsh-auth-<hash(authority)>`, `HttpOnly`). The signing
key is persisted in the Host's credentials, so the cookie survives a Host
restart; the token is only needed while no cookie is held. When the cookie is
valid, the Host's index authorization 303-redirects any `?token=` request to a
clean `/`, so leaving the token in the address is safe — and an expired token is
not a 401 as long as the cookie is still there. When neither works, the page
says so plainly.

**Multiple Hosts**: cookie names carry an authority hash, so sessions for several
Hosts coexist in one WebKit data store; switching Hosts is just switching URL.

## Settings

The Settings window (toolbar Host menu → Manage Hosts…, or ⌘,) has two tabs.

**Hosts** — add, remove and edit bookmarks:

| Field | Meaning |
| --- | --- |
| Name | shown in the picker; the address is used when left empty |
| Address | the Host's origin, e.g. `http://127.0.0.1:3080` |
| Launch token | the `?token=…` from `dsh web`'s output; needed only while no cookie is held |
| Start a local dsh for this Host | the app spawns the child process |
| profile | `--profile` in managed mode, `web` by default |
| Extra arguments | appended to the `dsh` invocation, e.g. `--trusted-host dsh.internal` |
| Custom launch command | replaces the whole invocation in managed mode; must print the `dsh web: http://…` line |
| dsh executable path | which `dsh` to run in managed mode; empty means search (see "Finding `dsh`") |

**General** — preferences that belong to the app rather than to one Host:

| Field | Meaning |
| --- | --- |
| Language | interface language: English (default), 简体中文, 繁體中文, 日本語, Français, Deutsch or Español |
| Notifications | macOS notifications for waiting Hosts and finished tasks; on by default |
| Config file | where the configuration is stored; the path is shown, and selecting it lets you copy it |

Bookmarks and the rest of the configuration are written to that file as you
edit; see "What is remembered" above for how it is written, migrated and
protected.

## Layout

```
Sources/BezelCore/          connection and signal model (no SwiftUI, unit-testable)
  DSHHost.swift             Host bookmarks: origin normalisation, token→URL, argument splitting
  AppConfig.swift           everything remembered between launches, as one value
  ConfigFile.swift          the JSON file: location, atomic write, tolerant read
  ConfigStore.swift         the single owner of that value: load, edit, persist
  Localization.swift        the seven languages, and every message in all of them
  DSHDiscovery.swift        finding a usable dsh: login-shell probe, PATH merge, candidates, runnability
  LocalHostRunner.swift     the managed child: async discovery, startup-line parsing, timeout, exit diagnostics
  DSHProcessScan.swift      finding a running DSH by scanning processes (the guide's detection step)
  DSHInstall.swift          installing dsh through npm (the guide's automatic path)
  PageSignals.swift         page snapshots, the observer/probe scripts, and the event detector
  ShellCommand.swift        one-shot shell invocations with a timeout
  BoundedProcess.swift      a child process whose output is bounded and readable after the fact
  OneShotCommand.swift      small process-running helpers
  JSONValue.swift           the tolerant JSON tree the config decodes through
Sources/dsh-bezel/          app and UI
  BezelApp.swift            entry point, language mirroring, --dump-config / --dump-hosts smoke entry points
  Model/AppState.swift      config / child process / WebView / probe glue, connection status, notification wording
  Model/Notifier.swift      macOS notification delivery and the two delivery rules
  Web/WebView.swift         WKWebView host, navigation state reporting, the observer script's channel
  Web/SidebarProbe.swift    the hidden page that reads the complete sidebar
  UI/MainView.swift         toolbar, Host picker, connect prompt, error banner
  UI/OnboardingView.swift   the first-launch guide
  UI/SettingsView.swift     Host management and app preferences (two tabs)
Tests/BezelCoreTests/       address normalisation, startup-line parsing, config file and store, localisation, page signals
```

## Known constraints

- **Plain http and ATS**: a Host may be `http://` on the LAN, so
  `Resources/Info.plist` sets `NSAllowsArbitraryLoadsInWebContent` (relaxing
  WebView content only; the app's own requests stay under ATS). Putting a
  `https://` reverse proxy in front makes this unnecessary.
- **A remote Host has to admit this client**: dsh's `/api` has a browser trust
  fence that accepts loopback, a deployment-derived LAN IP literal, or an
  authority declared with `--trusted-host`. To reach a remote Host by domain
  name, that Host must be started with `--trusted-host`. Note also that
  `dsh web`'s CLI refuses `--host 0.0.0.0`; serving beyond the machine needs
  `host: '0.0.0.0'` at the config layer.
- **No App Sandbox**: managed mode spawns `dsh`, and the harness's session tools
  already run commands on the user's machine, so a sandbox would break that
  trust model. If you only ever connect to external Hosts you can add a sandbox
  and `com.apple.security.network.client` yourself.
- **Scope**: this app contributes no features of its own to the conversation —
  what the Web UI has is what you get. Around the display it adds the Host
  picker, notifications, languages and the first-launch guide.
- **Prerequisites**: a dsh Host that can serve a Web UI. `dsh web`'s startup line
  and the `?token=` exchange have been stable since 0.1.5-rc.1.

## Relationship to dsh-for-mac

`dsh-for-mac` takes the other road: reimplementing the wire protocol in Swift
(unary RPC + `/api/remote.mux` + the event stream), which yields fully native
interaction but means tracking the protocol yourself and owning the drift. This
project deliberately does not. The two can coexist; the native-shaped pieces
this app does add — notifications, the language-following menu bar — wrap the
page without touching the connection model.

## Development

```sh
swift build --disable-sandbox
swift test --disable-sandbox
swift run dsh-bezel --dump-config   # the config file: its path, or what it holds
swift run dsh-bezel --dump-hosts    # just the saved bookmarks
```

The bare executable and the bundle share one config file, so an experiment with
`swift run` uses your real configuration unless `BEZEL_CONFIG` points somewhere
else. The `--disable-sandbox` flag is needed when building under the DSH
harness, which cannot nest a sandbox of its own.
