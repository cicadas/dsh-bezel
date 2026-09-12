# DSH Bezel

[English](../README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [Français](README.fr.md) · **Deutsch** · [Español](README.es.md)

yet-another-dsh-for-mac. Eine native macOS-Hülle, die die eigene Web UI eines dsh-Host direkt in ein `WKWebView` lädt — und um den Bildschirm herum nur ergänzt, was eine Hülle rechtmäßig ergänzen kann: **die Wahl, mit welchem dsh verbunden wird**, **das Wissen, wenn der Bildschirm Sie ruft**, und **eine eigene Sprache der Oberfläche**.

## Warum eine Hülle statt einer Protokoll-Reimplementierung

Eine dsh-Web-UI ist kein statisches Frontend, das man in eine App einpackt — sie ist eine vollständige Anwendung, die der Host selbst ausliefert:

- die SPA wird vom frontend-static-Sitz des Hosts ausgeliefert;
- das Browser-Bundle jedes `dsh.client`-Plugins wird von `/plugins/<id>/client.js` ausgeliefert;
- die Bootstrap-Nutzlast `window.__DSH_BOOT__` wird vom Host bei jedem Index-Rendering injiziert.

„Mit welchem dsh verbinde ich mich" fällt in der Implementierung also auf „welche URL lädt ein `WKWebView`" zurück. Was das einkauft, ist **null Protokolldrift**: Sitzungs-Rendering, Freigaben, Pläne, Ziele, Werkzeugkarten, Anhänge, Einstellungen, Modellauswahl und Browser-Plugins von Drittanbietern folgen alle automatisch der Host-Version. Dieses Projekt muss `/api`, `/api/remote.mux` oder irgendeinen Ereignistyp nie verstehen.

## Schnellstart

```sh
swift build --disable-sandbox   # kompilieren (das Flag ist nur unter dem DSH-Harness nötig)
swift test --disable-sandbox    # Unit-Tests für Verbindungsmodell und Seitensignale
./scripts/make-app.sh           # build/DSH Bezel.app erzeugen
open "build/DSH Bezel.app"
```

`swift run dsh-bezel` funktioniert auch, ist aber eine nackte ausführbare Datei: Ohne Bundle greift die ATS-Ausnahme in `Info.plist` nicht, der Besitz von Cookies und Voreinstellungen ist instabil, und macOS weigert sich, Benachrichtigungen zuzustellen. Für echte Arbeit nehmen Sie das `.app`.

## Anleitung beim ersten Start

Der erste Start öffnet eine kurze Anleitung statt des Hauptfensters. Sie erkennt, ob bereits ein DSH-Prozess eine Web UI ausliefert, und bietet an, was diese Erkenntnis erlaubt:

- **Den laufenden Prozess binden** — diese App auf ein `dsh` richten, das Sie selbst gestartet haben, indem Sie Adresse und Token aus seiner Startausgabe einfügen.
- **Einen verwalteten starten** — die App führt den Kindprozess aus und beendet ihn beim Verlassen. *Automatisch* sucht ein installiertes `dsh` (und bietet an, es über npm zu installieren, falls keines gefunden wird — das benötigt Node.js); *manuell* führt einen von Ihnen angegebenen Startbefehl aus, sofern er die Startzeile `dsh web: http://…` ausgibt.

Das Überspringen der Anleitung landet auf der Verbindungsaufforderung, einen Klick weit; die Anleitung kommt nur zurück, wenn die Konfigurationsdatei gelöscht wird.

## Sprache der Oberfläche

Die Oberfläche ist standardmäßig Englisch, egal auf welche Sprache macOS selbst eingestellt ist. Einstellungen → Allgemein → Sprache schaltet auf 简体中文, 繁體中文, 日本語, Français, Deutsch oder Español um, und die Wahl wird in die unten beschriebene Konfigurationsdatei geschrieben — sie überlebt also einen Neustart.

Alle sieben Sprachen leben in einer Datei hinter erschöpfenden Switches, deshalb kann eine Meldung nicht in nur einigen von ihnen ausgeliefert werden: Eine vergessene Übersetzung lässt das Build scheitern, statt eine chinesische Zeichenkette in einer englischen Oberfläche zurückzulassen. Dieselbe Datei hält auch die Formulierungen der Laufzeitdiagnosen, die als strukturierte Werte transportiert und erst bei der Anzeige gerendert werden — ein Sprachwechsel zeichnet also einen Fehler, der bereits auf dem Bildschirm steht, neu, statt ihn in der Sprache seiner Entstehung stehen zu lassen.

Der einzige Teil, der sich nicht mitten in einer Sitzung umschalten lässt, ist die native Menüleiste: macOS zeichnet sie beim Start aus der Lokalisierung des Bundles. Bei jedem Start spiegelt die App die eingestellte Sprache vor dem Aufbau der Oberfläche in `AppleLanguages` wider, und das Bundle führt ein `.lproj` für jede unterstützte Sprache mit — die Menüs folgen der Einstellung also beim nächsten Start. Solange gewählte Sprache und Menüleisten-Sprache auseinanderliegen, bietet der Einstellungen-Dialog genau dafür eine Neustart-Schaltfläche an.

Diese Einstellung deckt nur die eigene Oberfläche dieser App ab. Die Web UI des Hosts wird vom Host ausgeliefert und behält ihre eigene Sprache.

## Benachrichtigungen

Die eine Fähigkeit, die eine Lünette um einen Bildschirm herum rechtmäßig ergänzen kann, ist zu wissen, dass der Bildschirm Sie ruft. Zwei Momente verdienen einen Ruf: Der Host wartet auf Ihre Entscheidung (eine Werkzeugfreigabe, eine Frage, die Durchsicht eines Plans), oder eine laufende Aufgabe ist gerade beendet worden. Alles Folgende ist **Seitenüberwachung**: Diese App lernt beides von derselben Seite, die Sie ansehen — indem sie liest, was die eigene Web UI des Hosts für genau diese Situationen ohnehin rendert. Nichts wird abgefangen, nichts wird von der Leitung gelesen, nichts auf der Seite verändert.

### Seitenüberwachung

**Injektion.** Ein kleines Beobachterskript — pures JavaScript, nur lesend — wird als WebKit-Benutzerskript registriert und reitet auf jeder Seite mit, die das `WKWebView` lädt, injiziert am Dokumentende. Eine Wache hindert ein reinjiziertes Skript (ein Neuladen führt Benutzerskripte erneut aus) daran, Intervalle zu stapeln.

**Abfrage.** Das Skript nimmt pro Sekunde einen Schnappschuss; jeder Durchgang ist eine Handvoll `querySelector`-Aufrufe. Eine schlichte Abfrage statt eines `MutationObserver`, weil eine Abfrage ein Bedienfeld, das zwischen zwei Mutationen montiert und demontiert wird, nicht verpassen kann — einer naiven Beobachterzusammenfassung aber kann es entgehen.

**Was ein Schnappschuss liest** — nur Marker, die die eigene Web UI des Hosts rendert:

| Signal | Marker | Bedeutung |
| --- | --- | --- |
| Wartefeld | `data-approval-key` / `data-question-key` / `data-plan-review-key` | der Host hängt auf einer Freigabe, einer Frage oder einer Plandurchsicht fest |
| Zug beendet | `data-turn-tail` auf der Aktionszeile unter einer endgültigen Antwort (Kopieren, Forken, Verbrauch, Rückmeldung) | der eigene „dieser Zug ist beendet"-Marker des Hosts — veröffentlicht in dem Moment, in dem das `turn/end`-Ereignis des Zuges eintrifft, also bedeutet „Aufgabe beendet" exakt dasselbe wie auf der Seite, nicht etwas, das aus „die Streaming-Marker wurden still" gefolgert wäre |
| Aufgabenname | die Zugsnummer, die diese Zeile trägt, ortet die Benutzernachricht, die den Zug begann | die Benachrichtigung sagt Ihnen, **welche Aufgabe** beendet wurde — mit Ihren eigenen Worten |
| Noch dieselbe Unterhaltung? | `data-chat-anchor-key` der jüngsten Inhaltszeilen | ein Wechsel ersetzt jede Zeile; ein beendeter Zug fügt nur eine darunter hinzu — ein Sitzungswechsel gibt sich also nie als Beendigung aus |
| Sitzungsname | die ausgewählte Seitenleistenzeile, oder `document.title` (`"<Sitzung> — <Produkt>"`) | jede Benachrichtigung nennt ihre Unterhaltung |
| Hintergrundsitzungen | die `data-state`-Punkte der Seitenleistenzeilen | laufend / auf Sie wartend / beendet-aber-ungeöffnet |

**Vom Schnappschuss zum Ereignis.** Jede Sekunde postet das Skript seinen Schnappschuss über einen privaten Brückenkanal (`window.webkit.messageHandlers`); die App dekodiert ihn, und ein reiner, unit-getesteter Detektor leitet die Übergänge her, über die sich zu benachrichtigen lohnt: eine erscheinende Aufmerksamkeit, ein neuer Zug-Ende-Marker, während die Zeilen darüber noch stehen, ein kippender Statuspunkt. Der erste Schnappschuss nach einem Laden ist nur eine Basislinie — wie die Dinge stehen, ist Zustand, nicht Nachricht — und der nach einer Lücke erstmals gesehene Punkt ist Geschichte, kein Ereignis.

### Der Hintergrund, den niemand anzeigt

Aufgaben, die nicht auf dieser Seite liegen — Sitzungen, die im Hintergrund desselben Hosts laufen — sind über die eine Fläche abgedeckt, die sie zeigt: die Seitenleiste. Ihre Sitzungszeilen tragen den eigenen Live-Statuspunkt des Hosts (`data-state`): laufend, auf Sie wartend, oder beendet-aber-ungeöffnet — letzterer ist die eigene „Fertig"-Erinnerung des Hosts, genau dann bewaffnet, wenn eine Hintergrundsitzung vom Lauf in den Leerstand wechselte und sie seither niemand geöffnet hat. Die Flanke eines Punktes wird zu einer Benachrichtigung, die die Sitzung benennt.

Die Seitenleiste rendert allerdings nur, was ihr eigener Ansichtszustand zeigt — eine zusammengeklappte Workspace-Gruppe rendert gar keine Sitzungszeilen, und eine ausgeklappte kappelt bei ihren fünf jüngsten — also ist die Seitenleiste der angezeigten Seite nicht der ganze Hintergrund. Ein zweites, verborgenes `WKWebView` lädt dieselbe Host-Seite (eigener nicht-persistenter Speicher, das Cookie der angezeigten Seite hineinkopiert, die Adresse um das einmalige Token erleichtert) und klappt vor dem Abtasten jede Gruppe und jeden Überlauf aus: Niemand sieht diese Seite, also schreiben ihre Klicks einen ihr eigenen Ansichtszustand. Sie stellt keine Auswahl wieder her — sie öffnet nichts — also rüsten die client-eigenen Fertig-Punkte des Hosts sich für jede Sitzung, ohne dass die Sonde je einen löscht. Solange die Sonde lebt, sind ihre Zeilen die Wahrheit des Hintergrunds: Sie postet einmal pro Sekunde, Zeilen, die älter als fünfzehn Sekunden sind, weichen der eigenen Seitenleiste der angezeigten Seite, und eine Seite, die dreißig Sekunden stumm bleibt, wird mit einer frischen Kopie des Cookies neu geladen.

### Zustellregeln

Wann ein Schnappschuss zu einer macOS-Benachrichtigung wird, folgt zwei Regeln, einer je Ereignisklasse. Ein Ruf — der Host, der auf eine Eingabe oder Bestätigung wartet, auf dieser Seite oder in einer Hintergrundsitzung — wird **immer zugestellt**: im Vordergrund, im Hintergrund oder minimiert, denn er blockiert den Host bis zur Antwort, und die sichtbare Seite deckt nicht jede Quelle ab. Eine Beendigung ist ein Statusbericht: Solange diese App im Vordergrund und ihr Fenster aufgerichtet ist, ist die Seite ihre eigene Benachrichtigung, und ein Banner würde nur wiederholen, was schon auf dem Bildschirm steht. Ein Klick auf eine Benachrichtigung holt das Fenster nach vorn und stellt es aus dem Dock wieder her, falls es dort minimiert war.

Benachrichtigungen sind standardmäßig an; Einstellungen → Allgemein hat den Schalter, und der Berechtigungsdialog des Systems wird nur einmal beim ersten Start gefragt. macOS stellt Benachrichtigungen nur aus einem App-Bundle zu — die nackte ausführbare Datei von `swift run` fragt weder noch benachrichtigt sie.

## Was erinnert wird

Alles, was die App weiß, lebt in einer einzigen JSON-Datei:

```
~/Library/Application Support/dsh-bezel/config.json
```

Sie enthält die Host-Lesezeichen mit allen ihren Einstellungen, auf welchem Lesezeichen die Auswahl steht, an welchem die WebView zuletzt hing, und die Sprache der Oberfläche. Beim Start liest die App sie und **verbindet wieder mit dem Host, an dem sie zuletzt hing** — die App zu öffnen genügt also, um dorthin zurückzukehren, wo man war; ein verwalteter Host wird jedes Mal neu gestartet, denn sein Port und sein Token sind bei jedem Lauf neu. Das signierte `dsh-auth`-Cookie merkt sich der eigene Datenspeicher von WebKit separat — das Wiederverbinden braucht das Token also nicht erneut.

Eine Datei statt `UserDefaults`, damit man sie lesen, bearbeiten, auf eine andere Maschine kopieren und unter Versionskontrolle halten kann. Geschrieben wird pretty-printed mit sortierten Schlüsseln und nicht maskierten Schrägstrichen, gerade damit ein Diff lesbar bleibt; atomar über eine temporäre Datei, damit ein Absturz mitten im Schreiben sie nicht abschneiden kann; und `0600`, weil ein Lesezeichen einen Start-Token halten kann. `BEZEL_CONFIG` zeigt der App einen anderen Pfad, wenn Sie einen wollen.

Das Dekodieren ist Feld für Feld und duldsam: unbekannte Schlüssel werden ignoriert, ein Skalar vom falschen Typ fällt auf seinen Standard zurück, und Lesezeichen eines älteren Builds (fehlende, später hinzugefügte Felder) laden wie gewohnt. Eine Datei, die überhaupt nicht geparst werden kann, wird in den Einstellungen gemeldet und **exakt so belassen, wie sie ist** — niemals überschrieben —, damit eine Handbearbeitung mit Tippfehler oder eine Datei aus einem neueren Build wiederherstellbar bleibt. Die Datei zu löschen ist der Weg zum Zurücksetzen. Ein von Ihnen getippter Name ist Ihre Daten und wird in jeder Sprache unverändert gezeigt; nur der Name eines beim Erststart gesäten Lesezeichens folgt der aktuellen Sprache. Fenstergröße und -position sind nicht Teil dieser Datei: SwiftUI merkt sie sich selbst.

## Verbindungsmodell

Ein Host ist ein Lesezeichen mit vier Feldern, die zählen: **Name, Adresse (Origin), Start-Token (optional), und ob diese App ihn verwaltet**.

**Externer Host (nicht verwaltet)**: `http://host:port` eintragen. Hat dieser Host diesem Browser noch kein Cookie gegeben, fügen Sie die vollständige Adresse aus der Startausgabe von `dsh web` in „Start-Token" ein — oder öffnen Sie die Adresse mit ihrem `?token=` einmal in einem Browser und kehren zu dieser App zurück (Cookies werden pro Autorität im WebKit-Datenspeicher dieser App geteilt).

**Verwalteter Host**: die App führt aus

```sh
dsh --profile web --port 0 --no-open
```

Port `0` lässt das System wählen, und die URL wird aus der Zeile `dsh web: http://127.0.0.1:PORT/?token=…` auf der Standardausgabe des Kindprozesses geparst. Das Beenden der App beendet diesen Kindprozess (die Schaltfläche „Verbindung trennen" ebenso). Erscheint die Zeile nicht innerhalb von 30 Sekunden, gilt der Start als zeitüberschritten und der Kindprozess wird beendet — die Oberfläche bleibt also nie für immer auf „Startet".

**`dsh` finden**: Eine per Doppelklick im Finder gestartete App erbt den minimalen PATH von launchd (`/usr/bin:/bin:/usr/sbin:/sbin`), der weder node noch npm enthält — und nahezu jedes `dsh` auf einer echten Maschine ist ein Hüllprogramm, das einen Interpreter braucht (`#!/usr/bin/env node`, `npm exec …`, oder die Laufzeit-Shim von DSH Desktop). „Die Datei existiert und hat das x-Bit" reicht also keineswegs, um sie benutzbar zu nennen. Die Suche läuft in dieser Reihenfolge, und jeder Kandidat wird wirklich einmal mit `dsh --version` ausgeführt; nur einer, der erfolgreich ist, wird dem Kindprozess übergeben:

1. der „dsh-Programmpfad" in den Einstellungen des Hosts
2. die Umgebungsvariable `BEZEL_DSH_PATH`
3. das `command -v dsh` der Login-Shell
4. `dsh` auf dem eigenen PATH der App
5. übliche Installationsorte: `~/.local/bin`, `~/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`, `~/.bun/bin`, `/opt/anaconda3/bin`, …

Schritt 3 befragt eine **interaktive** Login-Shell (`zsh -l -i -c`, Rückfall auf `-l -c`): Die Verzeichnisse mit `node`/`npm` leben meist in `~/.zshrc`, den eine nicht-interaktive `zsh -l -c` nie liest — genau deshalb gehen der PATH einer GUI-App und das Terminal des Benutzers auseinander. Die Sonde trennt das rc-Datei-Geräusch mit einer Sentinelle-Zeile von der Antwort und hat ein 5-Sekunden-Limit.

Der PATH des Kindprozesses ist: der PATH der Login-Shell → der geerbte PATH der App → die Interpreter-Verzeichnisse, dedupliziert und zusammengeführt. Beachten Sie, dass nur **Interpreter-Verzeichnisse** injiziert werden — niemals Verzeichnisse wie `~/bin` oder `~/.local/bin`, in denen *ein anderes* `dsh` lebt: Manche Hüllprogramme durchsuchen selbst den PATH und fügen sich dem Gefundenen unter (die Shim von DSH Desktop tut es), also übergibt ein weiteres Hüllprogramm auf dem PATH den Start an jenes, statt die Laufzeit zu nutzen, die jene Shim mitbringt.

Wenn jeder Kandidat scheitert, listet die Verbindungsaufforderung jeden versuchten Ort auf und warum er nicht funktionierte (fehlend, oder `--version` lief nicht).

**Semantik der Anmeldedaten**: `GET /?token=…` wird vom Host gegen ein signiertes, 30 Tage gültiges Cookie eingetauscht (`dsh-auth-<hash(authority)>`, `HttpOnly`). Der Signaturschlüssel persistiert in den Anmeldedaten des Hosts, das Cookie überlebt also einen Host-Neustart; das Token wird nur gebraucht, solange kein Cookie gehalten wird. Ist das Cookie gültig, leitet die Index-Autorisierung des Hosts jede `?token=`-Anfrage per 303 zu einem sauberen `/` um — das Token in der Adresse zu lassen ist also ungefährlich, und ein abgelaufenes Token ist kein 401, solange das Cookie hält. Funktioniert beides nicht, sagt die Seite es offen.

**Mehrere Hosts**: Cookie-Namen tragen einen Autoritäts-Hash, also koexistieren Sitzungen mehrerer Hosts in einem WebKit-Datenspeicher; der Host-Wechsel ist nur ein URL-Wechsel.

## Einstellungen

Das Einstellungen-Fenster (Host-Menü der Werkzeugleiste → Hosts verwalten…, oder ⌘,) hat zwei Reiter.

**Hosts** — Lesezeichen hinzufügen, entfernen und bearbeiten:

| Feld | Bedeutung |
| --- | --- |
| Name | in der Auswahl gezeigt; leer lässt die Adresse gelten |
| Adresse | der Origin des Hosts, z. B. `http://127.0.0.1:3080` |
| Start-Token | das `?token=…` aus der Ausgabe von `dsh web`; nur nötig, solange kein Cookie gehalten wird |
| Ein lokales dsh für diesen Host starten | die App erzeugt den Kindprozess |
| profile | das `--profile` im verwalteten Modus, standardmäßig `web` |
| Zusätzliche Argumente | an den `dsh`-Aufruf angehängt, z. B. `--trusted-host dsh.internal` |
| Eigener Startbefehl | ersetzt im verwalteten Modus den ganzen Aufruf; muss die Zeile `dsh web: http://…` ausgeben |
| dsh-Programmpfad | welches `dsh` im verwalteten Modus läuft; leer heißt suchen (siehe „`dsh` finden") |

**Allgemein** — Einstellungen, die zur App gehören, nicht zu einem Host:

| Feld | Bedeutung |
| --- | --- |
| Sprache | Sprache der Oberfläche: Englisch (Standard), 简体中文, 繁體中文, 日本語, Français, Deutsch oder Español |
| Benachrichtigungen | macOS-Benachrichtigungen für wartende Hosts und beendete Aufgaben; standardmäßig an |
| Konfigurationsdatei | wo die Konfiguration liegt; der Pfad wird gezeigt, und ihn auszuwählen lässt ihn kopieren |

Lesezeichen und der Rest der Konfiguration werden beim Bearbeiten in diese Datei geschrieben; wie sie geschrieben, migriert und geschützt wird, steht oben unter „Was erinnert wird".

## Aufbau

```
Sources/BezelCore/          Verbindungs- und Signalmodell (ohne SwiftUI, unit-testbar)
  DSHHost.swift             Host-Lesezeichen: Origin-Normalisierung, Token→URL, Argument-Aufteilung
  AppConfig.swift           alles zwischen Starts Erinnerte, als ein Wert
  ConfigFile.swift          die JSON-Datei: Ort, atomares Schreiben, duldsames Lesen
  ConfigStore.swift         der einzige Eigentümer dieses Werts: laden, bearbeiten, persistieren
  Localization.swift        die sieben Sprachen und jede Meldung in allen
  DSHDiscovery.swift        ein benutzbares dsh finden: Login-Shell-Sonde, PATH-Zusammenführung, Kandidaten, Lauffähigkeit
  LocalHostRunner.swift     der verwaltete Kindprozess: asynchrone Suche, Parsen der Startzeile, Zeitlimit, Exit-Diagnose
  DSHProcessScan.swift      einen laufenden DSH per Prozess-Scan finden (der Erkennungsschritt der Anleitung)
  DSHInstall.swift          dsh über npm installieren (der automatische Weg der Anleitung)
  PageSignals.swift         Seiten-Schnappschüsse, Beobachter-/Sondenskripte und der Ereignis-Detektor
  ShellCommand.swift        einmalige Shell-Aufrufe mit Zeitlimit
  BoundedProcess.swift      ein Kindprozess mit begrenzter, nachträglich lesbarer Ausgabe
  OneShotCommand.swift      kleine Prozess-Hilfen
  JSONValue.swift           der duldsame JSON-Baum, durch den die Konfiguration dekodiert
Sources/dsh-bezel/          App und Oberfläche
  BezelApp.swift            Einstiegspunkt, Sprach-Spiegelung, --dump-config / --dump-hosts Smoke-Einstiege
  Model/AppState.swift      Konfiguration/Kindprozess/WebView/Sonde zusammengeklebt, Verbindungsstatus, Benachrichtigungs-Formulierung
  Model/Notifier.swift      macOS-Zustellung und die zwei Zustellregeln
  Web/WebView.swift         WKWebView-Wirt, Bericht des Navigationszustands, Kanal des Beobachterskripts
  Web/SidebarProbe.swift    die verborgene Seite, die die vollständige Seitenleiste liest
  UI/MainView.swift         Werkzeugleiste, Host-Auswahl, Verbindungsaufforderung, Fehlerbanner
  UI/OnboardingView.swift   die Anleitung beim ersten Start
  UI/SettingsView.swift     Host-Verwaltung und App-Einstellungen (zwei Reiter)
Tests/BezelCoreTests/       Adress-Normalisierung, Parsen der Startzeile, Konfigurationsdatei und -speicher, Lokalisierung, Seitensignale
```

## Bekannte Einschränkungen

- **Pures http und ATS**: Ein Host kann im LAN `http://` sein, darum setzt `Resources/Info.plist` `NSAllowsArbitraryLoadsInWebContent` (lockert nur WebView-Inhalte; die eigenen Anfragen der App bleiben unter ATS). Ein `https://`-Reverse-Proxy davor macht das überflüssig.
- **Ein entfernter Host muss diesen Client zulassen**: dshs `/api` hat einen Browser-Vertrauenszaun, der Loopback, ein deployments-abgeleitetes LAN-IP-Literal oder eine mit `--trusted-host` erklärte Autorität akzeptiert. Um einen entfernten Host per Domänennamen zu erreichen, muss jener Host mit `--trusted-host` gestartet werden. Beachten Sie auch, dass `dsh web`s CLI `--host 0.0.0.0` verweigert; Betrieb über die Maschine hinaus braucht `host: '0.0.0.0'` auf der Konfigurationsschicht.
- **Kein App Sandbox**: Der verwaltete Modus erzeugt `dsh`, und die Sitzungswerkzeuge des Harnesss laufen ohnehin schon Befehle auf der Maschine des Benutzers — eine Sandbox würde dieses Vertrauensmodell brechen. Wenn Sie nur externe Hosts verbinden, können Sie selbst eine Sandbox und `com.apple.security.network.client` hinzufügen.
- **Umfang**: Diese App trägt zur Unterhaltung selbst nichts bei — was die Web UI hat, ist das, was Sie haben. Um den Bildschirm herum ergänzt sie die Host-Auswahl, Benachrichtigungen, Sprachen und die Erststart-Anleitung.
- **Voraussetzungen**: ein dsh-Host, der eine Web UI ausliefern kann. `dsh web`-Startzeile und der `?token=`-Austausch sind seit 0.1.5-rc.1 stabil.

## Verhältnis zu dsh-for-mac

`dsh-for-mac` geht den anderen Weg: das Drahtprotokoll in Swift nachbauen (unäres RPC + `/api/remote.mux` + der Ereignis-Strom), was vollkommen native Interaktion ergibt, aber bedeutet, das Protokoll selbst zu verfolgen und die Drift zu tragen. Dieses Projekt tut das bewusst nicht. Beide können koexistieren; die einheimisch geformten Stücke, die diese App tatsächlich ergänzt — Benachrichtigungen, die sprachfolgende Menüleiste — hüllen die Seite ein, ohne das Verbindungsmodell zu berühren.

## Entwicklung

```sh
swift build --disable-sandbox
swift test --disable-sandbox
swift run dsh-bezel --dump-config   # die Konfigurationsdatei: ihr Pfad oder ihr Inhalt
swift run dsh-bezel --dump-hosts    # nur die gespeicherten Lesezeichen
```

Die nackte ausführbare Datei und das Bundle teilen sich eine Konfigurationsdatei — ein Experiment mit `swift run` benutzt also Ihre echte Konfiguration, sofern `BEZEL_CONFIG` nicht woandershin zeigt. Das `--disable-sandbox`-Flag wird beim Bauen unter dem DSH-Harness gebraucht, der keine eigene Sandbox schachteln kann.
