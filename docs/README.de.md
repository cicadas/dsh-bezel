# DSH Bezel

[English](../README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [Français](README.fr.md) · **Deutsch** · [Español](README.es.md)

Eine native macOS-Hülle, die die eigene Web UI eines dsh-Host direkt in ein `WKWebView` lädt — und um den Bildschirm herum nur ergänzt, was eine Hülle rechtmäßig ergänzen kann: **die Wahl, mit welchem dsh verbunden wird**, **das Wissen, wenn der Bildschirm Sie ruft**, und **eine eigene Sprache der Oberfläche**.

Den vollständigen technischen Entwurf — den Drahtvertrag, die Entscheidungsregeln, das Zustandsmodell, die Quellübersicht — führt [architecture.md](../architecture.md) (nur auf Englisch). Dieses README bewahrt den Umriss des Entwurfs, die Bedienung der App und das Verhältnis zu den Alternativen.

## Das Design in Kürze

Vier Entscheidungen definieren die ganze App:

- **Die Seite ist die App.** Ein einziges `WKWebView` lädt die eigene Web UI des Hosts — reine Anzeige, null Injektion, null Zurücklesen. Jedes Merkmal der dsh-Oberfläche folgt automatisch der Host-Version, weil die App die Seite weder verändert noch interpretiert.
- **Benachrichtigungen kommen aus der Host-API, nicht von der Seite.** Ein separater, billiger Kanal — `HostFeed` — hält ein cookie-autorisiertes WebSocket und zieht gelegentlich die Sitzungsliste. Eine Beendigung ist ein fallendes `running`-Flag; ein Ruf ist ein Wasserfall-Ereignis, dem passiv gelauscht wird, während die angezeigte Seite ihr Monopol auf das Antworten behält.
- **Die Anzeige erneuert sich selbst.** Eine Seite, die tagelang offen bleibt, häuft Renderspeicher an, deshalb lädt die App sie nach einem Tag Alter neu — aber nur, solange kein Fenster sichtbar ist, und nie, während der Host auf eine Antwort wartet.
- **Eine JSON-Datei merkt sich alles**, atomar geschrieben und duldsam dekodiert; ein verwaltetes `dsh`-Kind wird über die echte Shell-Umgebung des Benutzers gefunden, erzeugt und beim Verlassen beendet.

Was jede dieser Entscheidungen im Einzelnen bedeutet und warum sie so geformt sind, ist das Thema von [architecture.md](../architecture.md).

## Schnellstart

```sh
swift build --disable-sandbox   # kompilieren (das Flag ist nur unter dem DSH-Harness nötig)
swift test --disable-sandbox    # Unit-Tests für Verbindungsmodell, Benachrichtigungs-Drahtformat und Konfigurationsdatei
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

Der einzige Teil, der sich nicht mitten in einer Sitzung umschalten lässt, ist die native Menüleiste: macOS zeichnet sie beim Start aus der Lokalisierung des Bundles. Bei jedem Start spiegelt die App die eingestellte Sprache vor dem Aufbau der Oberfläche in `AppleLanguages` wider, und das Bundle führt ein `.lproj` für jede unterstützte Sprache mit — die Menüs folgen der Einstellung also beim nächsten Start. Solange gewählte Sprache und Menüleisten-Sprache auseinanderliegen, bietet der Einstellungen-Dialog genau dafür eine Neustart-Schaltfläche an.

Diese Einstellung deckt nur die eigene Oberfläche dieser App ab. Die Web UI des Hosts wird vom Host ausgeliefert und behält ihre eigene Sprache.

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
| dsh-Programmpfad | welches `dsh` im verwalteten Modus läuft; leer heißt suchen |

**Allgemein** — Einstellungen, die zur App gehören, nicht zu einem Host:

| Feld | Bedeutung |
| --- | --- |
| Sprache | Sprache der Oberfläche: Englisch (Standard), 简体中文, 繁體中文, 日本語, Français, Deutsch oder Español |
| Benachrichtigungen | macOS-Benachrichtigungen für wartende Hosts und beendete Aufgaben; standardmäßig an |
| Seite automatisch erneuern | lädt die Seite von selbst nach einem Tag Alter neu, im Hintergrund; standardmäßig an |
| Konfigurationsdatei | wo die Konfiguration liegt; der Pfad wird gezeigt, und ihn auszuwählen lässt ihn kopieren |

Lesezeichen und der Rest der Konfiguration werden beim Bearbeiten in diese Datei geschrieben; wie sie geschrieben, migriert und geschützt wird, beschreibt [architecture.md](../architecture.md) unter „What is remembered".

## Vergleich mit anderen Werkzeugen

Jedes Werkzeug, das eine dsh-Web-UI in ein Fenster setzt, hat eine von drei Formen: ein schlichter Browser-Tab auf der Seite des Hosts, eine generische Verpackungs-App um sie herum, oder ein nativer Client, der das Drahtprotokoll nachbaut.

| | Ein Browser-Tab auf `dsh web` | Eine generische Verpackungs-App | DSH Bezel | Eine native Protokoll-Reimplementierung |
| --- | --- | --- | --- | --- |
| Interaktion | die Web UI des Hosts | die Web UI des Hosts | dieselbe Web UI des Hosts, in einer WebKit-Ansicht — null Protokolldrift | eine native Reimplementierung der Oberfläche |
| Zu pflegendes Protokoll | keines | keines | keines für die Interaktion; ein schmaler, durch Tests verankerter Ausschnitt für die Benachrichtigungen | das gesamte Drahtprotokoll |
| macOS-Benachrichtigungen | keine | keine | ja — Warten und Beendigungen, in jeder Sitzung | ja |
| Lesezeichen, verwaltetes Kind, Anleitung beim ersten Start | keine | keine | ja | ja |
| Sprachen der Oberfläche | die eigene des Hosts | ihre eigene | sieben, einschließlich der Menüleiste | ihre eigene |
| Speicher neben der Seite | keiner | eine zweite, mitgelieferte Browser-Engine | ein Socket | eine native Oberfläche |

- **Gegenüber dem Tab**: Die Seite ist identisch — diese App verbessert sie nie. Was die Hülle ergänzt, lebt ganz um sie herum: Lesezeichen und verwaltetes Kind, damit das Öffnen der App genügt; Benachrichtigungen, damit ein wartender Host nicht verpasst wird; die Erneuerung, damit eine Anzeige, die wochenlang offen steht, gesund bleibt; und die Sprachbehandlung.
- **Gegenüber der generischen Verpackung**: Sie bündeln ihre eigene Browser-Engine — den Speicher eines ganzen zweiten Laufzeitsystems, um dieselbe Seite in einem aufgeputzten Fenster zu zeigen — und wissen nichts davon, was sie einpacken. Diese App nutzt das WebKit des Systems, die Seite kostet also genau das, was die Seite kostet, und die Hülle versteht ihren Host: wie man ihn findet, startet, beobachtet und wieder verbindet.
- **Gegenüber der nativen Reimplementierung**: Es geht den anderen Weg — das Drahtprotokoll in Swift nachbauen (unäres RPC + `/api/remote.mux` + der Ereignis-Strom), was vollkommen native Interaktion ergibt, aber bedeutet, das Protokoll selbst zu verfolgen und die Drift zu tragen. Dieses Projekt tut das für die Interaktion bewusst nicht: Alles, was Sie klicken, tippen und lesen, ist die eigene Web UI des Hosts, und die App versteht nichts davon. Die eine Ausnahme sind die Benachrichtigungen: `HostFeed` abonniert einen schmalen Ausschnitt derselben API — die Sitzungsliste, ein Statusereignis, zwei Ruf-Tore —, weil das Lernen dieser Dinge aus der Seite bedeutete, ein Skript in sie zu injizieren und für einen zweiten Renderer zu zahlen. Der Ausschnitt ist genau `HostFeedWire`, reine Parsing-Funktionen, durch Tests verankert, die an einem laufenden Host aufgezeichnet wurden. Beide Projekte können koexistieren; die einheimisch geformten Stücke, die diese App ergänzt — Benachrichtigungen, die sprachfolgende Menüleiste — hüllen die Seite ein, ohne zu berühren, wie Sie sie bedienen.
- **Was es kostet**: Eine Beendigungs-Benachrichtigung zitiert nicht mehr die eigene Eingabe des Benutzers (der Sitzungstitel nennt stattdessen die Aufgabe), und das Benachrichtigungs-Drahtformat folgt der Host-Version innerhalb dieser kleinen, durch Tests verankerten Oberfläche.
- **Voraussetzungen**: ein dsh-Host, der eine Web UI ausliefern kann (stabil seit 0.1.5-rc.1). Ein entfernter Host, der per Domänennamen erreicht wird, muss mit `--trusted-host` gestartet werden — dshs `/api` hat einen Browser-Vertrauenszaun; den Rest beschreibt [architecture.md](../architecture.md) unter „Known constraints".

## Entwicklung

```sh
swift build --disable-sandbox
swift test --disable-sandbox
swift run dsh-bezel --dump-config   # die Konfigurationsdatei: ihr Pfad oder ihr Inhalt
swift run dsh-bezel --dump-hosts    # nur die gespeicherten Lesezeichen
swift run dsh-bezel --watch-feed "http://127.0.0.1:PORT/?token=…"
                                    # den Host-API-Kanal an einen Host anhängen und
                                    # jede Tatsache ausgeben, die er lernt — der
                                    # Drahtvertrag, live
```

Die nackte ausführbare Datei und das Bundle teilen sich eine Konfigurationsdatei — ein Experiment mit `swift run` benutzt also Ihre echte Konfiguration, sofern `BEZEL_CONFIG` nicht woandershin zeigt. Das `--disable-sandbox`-Flag wird beim Bauen unter dem DSH-Harness gebraucht, der keine eigene Sandbox schachteln kann.
