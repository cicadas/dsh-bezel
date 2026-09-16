# DSH Bezel — Architecture

The engineering design of DSH Bezel: what the app is made of, why each piece
is shaped the way it is, and where the rules live. For the short version —
what the app does and how to use it — read the [README](README.md).

## Design principles

- **The page is the source of truth.** Everything you click, type and read is
  the Host's own Web UI in a WebKit view. Session rendering, approvals, plans,
  goals, tool cards, attachments, settings, model selection and third-party
  browser plugins all follow the Host version automatically, because this app
  neither modifies nor interprets the page.
- **The page is never touched.** Nothing is injected into it, nothing is read
  back from it, and its view state is nobody's business but the page's. The
  only things the app ever does with the page are load it, reload it on its
  own schedule (Page renewal), search within it through WebKit's own find
  machinery (Find in page), and report navigation facts (loading, title,
  401) that WebKit hands out anyway.
- **Notifications are Host API facts, listened to passively.** The app
  subscribes to a narrow slice of the Host's own API and never answers
  anything on it — the displayed page keeps its monopoly on responding.
- **Tolerance everywhere.** A config file written by a newer build loads but
  is never overwritten; unknown keys are carried through; a scalar of the
  wrong type falls back to its default; a wire frame that does not parse is
  dropped, never fatal.
- **One write path for state.** Every mutation of remembered state funnels
  through one store, which persists atomically — two writers would each
  rewrite the other's fields away.
- **Housekeeping only in the background.** A finish notification is suppressed
  while the app is frontmost, and a page renewal fires only while no window is
  visible. What the user can see is theirs; the shell works when they are not
  looking.
- **Small surfaces, pinned by tests.** Wherever the app touches something
  that can drift — the Host's wire format, its own decision rules — the touch
  point is a pure function behind unit tests, so drift lands in one testable
  place.

## Why a shell instead of a protocol reimplementation

A dsh Web UI is not a static frontend to bundle inside an app — it is a complete
application served by the Host itself:

- the SPA is served from the Host's frontend-static seat;
- every `dsh.client` plugin's browser bundle is served from `/plugins/<id>/client.js`;
- the `window.__DSH_BOOT__` bootstrap payload is injected by the Host on every index render.

So "which dsh do I connect to" comes down, in implementation, to "which URL does
a `WKWebView` load". What that buys is **zero protocol drift for interaction**:
session rendering, approvals, plans, goals, tool cards, attachments, settings,
model selection and third-party browser plugins all follow the Host version
automatically, because this app neither modifies nor interprets the page. The
one place the app speaks to the Host's API directly is notifications — a narrow
slice, fenced off and explained under Notifications below — because the
alternative was injecting scripts into the page and paying for a second
renderer.

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
terminated, so the interface never sits on "Starting" for ever. Before
launching, the process table is asked whether the bookmark's own port is
already served by a running dsh; when it is, the launch is replaced by a
question — bind to the one that is there, or cancel — and no second dsh
starts.

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

## Notifications

The one capability a bezel can legitimately add around a display is knowing
that the display is calling for you. Two moments are worth calling out: the
Host is waiting for your decision (a tool approval, a question, a plan
review), or a running task just finished. Everything below is **Host API
monitoring**: this app learns both from the Host itself, over the same API
the Web UI is served through. The page is a pure display — nothing is
injected into it, nothing is read back from it, and its view state is
nobody's business but the page's.

### The channel

One `WKWebView` renders the Web UI exactly as the Host serves it. A separate,
much cheaper channel — `HostFeed` — talks to the Host's own API and produces
every notification fact:

- **One WebSocket** (`/api/remote.mux`, the same route the Web UI's own client
  uses) carries the Host's pushed events, authorized with the same signed
  `dsh-auth` cookie the page minted — the page owns the credential, the feed
  only presents it. The Gateway pings and URLSession answers, a dropped
  socket reconnects with backoff, and every attempt re-reads the cookie, so a
  rotation is caught on the next attempt.
- **Occasional `session.list` POSTs** return every session with its title and
  a `running` flag. The first pull is the baseline; later ones keep titles
  fresh and catch up on anything missed while the socket was down. One pull
  also follows, within seconds, any event that makes a fresh title
  worthwhile — a session appearing, a summons, a finish.

### The two facts

**A finish is a running flag falling.** `api-session/status` pushes
`(sessionId, running)` on every change, and `session.list` carries the same
flag. A `running` true→false edge — from the push, or from a reconciling
pull — is "the task finished": the same fact the Web UI's own green sidebar
dot is derived from. The notification names the session with the Host's own
title for it.

**A summons is a waterfall event.** `approval/request` and
`user-questions/request` mean the Host is blocked waiting for a client's
answer. The Gateway delivers a copy to every connected client and settles on
the first result, so this app can listen passively while the Web page keeps
its monopoly on answering: the page's decision resolves the request for
everyone, and the `cancel` frame the Gateway then sends for that event id is
this app's "the waiting ended" edge. A plan review arrives through the
question gate, marked by a `plan-review` intent inside the payload; the
parser walks the payload tolerantly, so the notification can say which of the
three is waiting.

### From facts to notifications

A pure, unit-tested detector turns the feed's stream into notification
events. The first list snapshot is a **baseline** — where things stand is
state, not news, so a feed that starts mid-run does not announce every
already-running session. After the baseline, edges are the news: a flag
falling once per session, a summons arriving (a redelivery is deduped by the
Host's event id), a summons being answered.

### Delivery rules

Two rules, one per class of event. A summons — the Host waiting on input or
confirmation, in any session — is always delivered: frontmost, background, or
minimized, because it blocks the Host until answered, and the visible page
does not cover every source. A finish is a status report: while this app is
frontmost with its window up, the page is its own notification, and a banner
would only repeat what is already on screen. Clicking a notification brings
the window forward, restoring it from the Dock if it was minimized there.

Notifications are on by default; Settings → General has the switch — turning
them off tears the channel down, so a bezel that is not notifying holds no
connection at all — the system's permission dialog is asked once at first
launch, and a status line under the switch speaks up when the channel is
waiting for a credential or reconnecting. macOS delivers notifications only
from an app bundle — the bare `swift run` executable neither asks nor
notifies (though `--watch-feed` under Development can prove the channel
itself, notification plumbing and all).

**What this buys, and what it costs.** No injected script, no hidden second
renderer — which measured about 330 MB, a whole WebKit content process spent
producing one small struct per second — and coverage no longer bounded by
what the sidebar happens to render. Two things are traded away: a finish no
longer quotes the user's own prompt (the session title names the task
instead), and the wire format is now a small surface that follows the Host
version. That surface is exactly `HostFeedWire` — pure parsing functions,
pinned by tests recorded from a live Host — so drift lands in one testable
place instead of everywhere.

## Page renewal

A WebKit content process sheds nothing on its own: a page left up for days
piles up renderer memory the Host's SPA never reclaims, however well the page
behaves. The app therefore renews the display itself — reloads the page —
when its load has been alive for a day. Since notifications moved to the Host
API channel, the reload is nearly free: the feed keeps running through it,
and the page reattaches to the same Host.

The renewal waits for the right moment, and the rules live in one pure,
unit-tested place (`PageRenewal`):

- **Never while the Host is blocked on an answer.** Whether the SPA replays a
  pending summons after a reload is the page's business, not something this
  app can promise — an open approval or question outranks the housekeeping.
  The feed's own summons events say when one is open.
- **Only while no window is visible.** The page may hold an unsent composer
  draft, and a reload the user can see is one that can destroy it. This is
  also what "in the background" means without touching the page: the renewal
  fires when the window is hidden or minimized.
- **At most one renewal per hour.** A freshly loaded page has nothing to
  shed, and the mechanism must never oscillate.

A visibility change re-checks immediately, so a renewal that had to wait for
the user to hide the window fires within moments of that; a five-minute clock
covers the quiet stretches. The clock runs only while a Host is attached, and
Settings → General has the switch, on by default.

## Find in page

A display one reads for hours needs the one interaction every browser has:
⌘F. The display-only principle decides the shape of the feature, and it
points at the native answer: the search is **AppKit's `NSTextFinder` driving
the `WKWebView`'s own `NSTextFinderClient`** — the same machinery, bar and
match feedback that TextEdit and Preview use. Nothing is injected into the
page and nothing is read back from it: the searching happens inside WebKit,
and this app contributes exactly two things — where the bar sits (top-
trailing, as browsers put it, in a small `FindBarHost` view over the page)
and what the rest of the interface knows about the search.

- **The bar is AppKit's.** `NSTextFinder` builds the standard find bar and
  hands it to the container; Enter, Shift-Enter, ⌘G, ⇧⌘G, Esc and the Done
  button are its own, as is the background incremental search and its
  system-language localization. The app's menu commands (⌘F, ⌘G, ⇧⌘G, ⌘E
  under Edit → Find) only call `performAction` on the selected tab's finder,
  over the same command-token channel the reload button uses.
- **The count is public.** `incrementalMatchRanges` is KVO-observable and
  carries every match the incremental search has found; its size is the
  number shown left of the bar. The precise "3 of 42" position is not
  exposed by the public API, so the line reads "42 found" and stays silent
  while there is nothing to count — the way Safari's bar stays silent.
- **The bar is per tab.** Each tab's `WKWebView` has its own finder and its
  own bar session, so switching tabs shows the target tab's bar state as
  that tab left it. What is traded against the browsers: the query does not
  follow the user across tabs, because AppKit's public interface offers no
  way to set the bar's text — the field is AppKit's own.
- **Reloads keep the search.** A manual reload or a page renewal replaces
  the page's text wholesale; `noteClientStringWillChange` at provisional
  navigation is the public hook that tells the incremental search to re-run
  over the new document, so the bar keeps working across the renewal the
  same way it keeps working while the SPA streams new text.

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
  HostFeed.swift            the notification channel: one WebSocket, cookie-authenticated pulls, backoff
  SessionEventDetector.swift  baselines and edges: feed facts in, notification events out
  PageRenewal.swift         when the display gets renewed: a day per load, background-only, summons-safe
  ShellCommand.swift        one-shot shell invocations with a timeout
  BoundedProcess.swift      a child process whose output is bounded and readable after the fact
  OneShotCommand.swift      small process-running helpers
  JSONValue.swift           the tolerant JSON tree the config decodes through
Sources/dsh-bezel/          app and UI
  BezelApp.swift            entry point, language mirroring, --dump-config / --dump-hosts / --watch-feed smoke entry points
  Model/AppState.swift      config / child process / WebView glue, connection status, notification wording
  Model/Notifier.swift      macOS notification delivery and the two delivery rules
  Web/WebView.swift         WKWebView host and navigation state reporting — a pure display
  Web/FindBarHost.swift     the AppKit strip hosting the system find bar over the page
  Web/PageFind.swift        the find directive the UI hands to a tab's WebView
  Web/WebKitCredentials.swift  the page's cookies, handed to the notification channel
  UI/MainView.swift         toolbar, Host picker, connect prompt, error banner
  UI/OnboardingView.swift   the first-launch guide
  UI/SettingsView.swift     Host management and app preferences (two tabs)
Tests/BezelCoreTests/       address normalisation, startup-line parsing, config file and store, localisation, the feed's wire and detector
```

## Known constraints

- **Plain http and ATS**: a Host may be `http://` on the LAN, so
  `Resources/Info.plist` sets `NSAllowsArbitraryLoads` — the notification
  channel makes the app's own requests to the same Host the WebView loads, so
  the exception can no longer be scoped to web content alone. The only
  addresses this app ever contacts are the ones you configured; putting a
  `https://` reverse proxy in front makes the exception unnecessary.
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
  picker, notifications, find-in-page, languages and the first-launch guide.
- **Prerequisites**: a dsh Host that can serve a Web UI. `dsh web`'s startup line
  and the `?token=` exchange have been stable since 0.1.5-rc.1.

## Development

```sh
swift build --disable-sandbox
swift test --disable-sandbox
swift run dsh-bezel --dump-config   # the config file: its path, or what it holds
swift run dsh-bezel --dump-hosts    # just the saved bookmarks
swift run dsh-bezel --watch-feed "http://127.0.0.1:PORT/?token=…"
                                    # attach the notification channel to a Host
                                    # and print every fact it learns — the wire
                                    # contract, live
```

The bare executable and the bundle share one config file, so an experiment with
`swift run` uses your real configuration unless `BEZEL_CONFIG` points somewhere
else. The `--disable-sandbox` flag is needed when building under the DSH
harness, which cannot nest a sandbox of its own.
