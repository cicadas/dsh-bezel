# DSH Bezel

**English** · [简体中文](docs/README.zh-Hans.md) · [繁體中文](docs/README.zh-Hant.md) · [日本語](docs/README.ja.md) · [Français](docs/README.fr.md) · [Deutsch](docs/README.de.md) · [Español](docs/README.es.md)

A native macOS shell that loads a dsh Host's own Web UI
straight into a `WKWebView`, and adds exactly what a shell can legitimately add
around a display: **choosing which dsh to connect to**, **knowing when the
display is calling for you**, **finding text on the page the way a browser
does**, and **an interface language of its own**.

The full engineering design — the wire contract, the decision rules, the state
model, the source map — lives in [architecture.md](architecture.md). This
README keeps the shape of the design, how to use the app, and how it compares
to the alternatives.

## Design in brief

Four decisions define the whole app:

- **The page is the app.** One `WKWebView` loads the Host's own Web UI — pure
  display, zero injection, zero readback. Every feature of dsh's interface
  follows the Host version automatically because the app neither modifies nor
  interprets the page.
- **Notifications come from the Host API, not from the page.** A separate,
  cheap channel — `HostFeed` — holds one cookie-authorized WebSocket and
  occasionally pulls the session list. A finish is a `running` flag falling; a
  summons is a waterfall event listened to passively, while the displayed page
  keeps its monopoly on answering.
- **The display renews itself.** A page left up for days piles up renderer
  memory, so the app reloads it after a day of age — but only while no window
  is visible, never while the Host is waiting for an answer.
- **One JSON file remembers everything**, written atomically and decoded
  tolerantly; a managed `dsh` child is found through the user's real shell
  environment, spawned, and terminated on quit.

What each of these means in detail, and why they are shaped that way, is the
subject of [architecture.md](architecture.md).

## Quick start

```sh
swift build --disable-sandbox   # compile (the flag is only needed under the DSH harness)
swift test --disable-sandbox    # unit tests for the connection model, the notification wire, the config file
./scripts/make-app.sh           # produce build/DSH Bezel.app
open "build/DSH Bezel.app"
```

`swift run dsh-bezel` works too, but that is a bare executable: with no bundle,
the ATS exception in `Info.plist` does not apply, cookie/preference ownership is
unstable, and macOS refuses to deliver notifications. Use the `.app` for real
work.

Or skip the build: the [Releases page](https://github.com/cicadas/dsh-bezel/releases/latest)
carries a universal DMG and zip (Apple silicon and Intel) plus their SHA-256
checksums. The binaries are ad-hoc signed, so the first open on a machine
without a Developer ID certificate may need a right-click → Open.

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

The one part that cannot switch mid-session is the native menu bar: macOS draws
it from the bundle's localization at launch. Every launch, the app mirrors its
configured language into `AppleLanguages` before the UI is built, and the bundle
ships a `.lproj` for each supported language, so the menus follow the setting on
the next start. While the picked language and the menu bar's disagree, Settings
offers a restart button for exactly that.

This setting covers this app's own interface only. The Host's Web UI is served
by the Host and keeps its own language setting.

## Find in page

⌘F opens the standard macOS find bar over the page — AppKit's `NSTextFinder`
driving WebKit's own find machinery, the same bar, incremental search and
match feedback that TextEdit and Preview use. Nothing is injected into the
page to search it.

Enter or ⌘G jumps to the next match, ⇧⌘G (or Shift-Enter) to the previous;
Esc or the bar's Done button closes it; ⌘E takes the selected text as the
search string (Edit → Find). A line left of the bar reports how many matches
the search found. The bar belongs to each tab — every tab keeps its own
search — and a reload, manual or automatic, re-runs the current search over
the fresh page. One browser habit is missing: switching tabs does not carry
the query along, because AppKit's public find interface offers no way to hand
the bar's text to another web view.

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
| dsh executable path | which `dsh` to run in managed mode; empty means search |

**General** — preferences that belong to the app rather than to one Host:

| Field | Meaning |
| --- | --- |
| Language | interface language: English (default), 简体中文, 繁體中文, 日本語, Français, Deutsch or Español |
| Notifications | macOS notifications for waiting Hosts and finished tasks; on by default |
| Auto-refresh page | reload the page on its own after a day of age, in the background; on by default |
| Config file | where the configuration is stored; the path is shown, and selecting it lets you copy it |

Bookmarks and the rest of the configuration are written to that file as you
edit; how it is written, migrated and protected is described in
[architecture.md](architecture.md) under "What is remembered".

## How it compares

Every tool that puts a dsh Web UI in a window is one of three shapes: a plain
browser tab on the Host's own page, a generic web-wrapper app around it, or a
native client that reimplements the wire protocol.

| | A browser tab on `dsh web` | A generic web-wrapper app | DSH Bezel | A native protocol reimplementation |
| --- | --- | --- | --- | --- |
| Interaction | the Host Web UI | the Host Web UI | the same Host Web UI, in a WebKit view — zero protocol drift | a native reimplementation of the interface |
| Protocol to maintain | none | none | none for interaction; a narrow, test-pinned slice for notifications | the entire wire protocol |
| macOS notifications | none | none | yes — waits and finishes, in any session | yes |
| Bookmarks, managed child, first-launch guide | none | none | yes | yes |
| Interface languages | the Host's own | its own | seven, including the menu bar | its own |
| Page search (⌘F) | the browser's own | varies | yes — WebKit's own find machinery, nothing injected | yes |
| Memory beside the page | none | a second, bundled browser engine | a socket | a native interface |

- **Versus the tab**: the page is identical — this app never improves it. What
  the shell adds lives entirely around it: the bookmarks and managed child so
  opening the app is enough, notifications so a waiting Host is not missed, the
  renewal so a display left up for weeks stays healthy, and the language
  handling.
- **Versus the generic wrapper**: those bundle their own browser engine — a
  whole second runtime's memory for showing the same page in a dressed-up
  window — and know nothing about what they are wrapping. This app uses the
  system WebKit, so the page costs what the page costs, and the shell
  understands its Host: how to find it, start it, watch it, and reconnect.
- **Versus the native reimplementation**: fully native interaction is the
  prize, and the price is tracking the wire protocol yourself and owning the
  drift. This project deliberately does not — for interaction. Everything you
  click, type and read is the Host's own Web UI, and the app understands none
  of it. The one exception is notifications: `HostFeed` subscribes to a narrow
  slice of the same API — the session list, one status event, two summons
  gates — because learning these from the page meant injecting a script into it
  and paying for a second renderer. The slice is exactly `HostFeedWire`, pure
  parsing functions pinned by tests recorded from a live Host, so drift lands
  in one testable place. The shapes can coexist; what this app adds —
  notifications, the language-following menu bar — wraps the page without
  touching how you drive it.
- **What is traded**: a finish notification no longer quotes the user's own
  prompt (the session title names the task instead), and the notification wire
  format follows the Host version within that small test-pinned surface.
- **Prerequisites**: a dsh Host that can serve a Web UI (stable since
  0.1.5-rc.1). A remote Host reached by domain name must be started with
  `--trusted-host` — dsh's `/api` has a browser trust fence; see architecture.md
  under "Known constraints" for the rest.

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
