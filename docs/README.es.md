# DSH Bezel

[English](../README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · **Español**

yet-another-dsh-for-mac. Una carcasa nativa de macOS que carga la propia Web UI de un Host de dsh directamente en un `WKWebView`, y añade alrededor de la pantalla exactamente lo que una carcasa puede añadir legítimamente: **elegir a qué dsh conectarse**, **saber cuándo la pantalla te llama**, y **un idioma de interfaz propio**.

## Por qué una carcasa y no una reimplementación del protocolo

Una Web UI de dsh no es un frontend estático para empaquetar dentro de una app — es una aplicación completa servida por el propio Host:

- la SPA se sirve desde el asiento frontend-static del Host;
- el bundle de navegador de cada plugin `dsh.client` se sirve desde `/plugins/<id>/client.js`;
- la carga de arranque `window.__DSH_BOOT__` la inyecta el Host en cada renderizado del índice.

Así que «a qué dsh me conecto» se reduce, en la implementación, a «qué URL carga un `WKWebView`». Lo que eso compra es **cero deriva de protocolo**: el renderizado de sesiones, las aprobaciones, los planes, los objetivos, las tarjetas de herramientas, los adjuntos, los ajustes, la selección de modelo y los plugins de navegador de terceros siguen todos automáticamente la versión del Host. Este proyecto nunca tiene que entender `/api`, `/api/remote.mux` ni ningún tipo de evento.

## Inicio rápido

```sh
swift build --disable-sandbox   # compilar (la opción solo hace falta bajo el harness DSH)
swift test --disable-sandbox    # pruebas unitarias del modelo de conexión y las señales de página
./scripts/make-app.sh           # producir build/DSH Bezel.app
open "build/DSH Bezel.app"
```

`swift run dsh-bezel` también funciona, pero es un ejecutable desnudo: sin bundle, la excepción ATS de `Info.plist` no aplica, la propiedad de cookies y preferencias es inestable, y macOS se niega a entregar notificaciones. Para trabajo real, usa el `.app`.

## Guía de primer arranque

El primer arranque abre una guía breve en lugar de la ventana principal. Detecta si un proceso DSH ya está sirviendo una Web UI y ofrece lo que ese hallazgo permite:

- **Vincular el proceso en ejecución** — apuntar esta app a un `dsh` que iniciaste tú mismo, pegando la dirección y el token de su salida de arranque.
- **Iniciar uno gestionado** — la app ejecuta el proceso hijo y lo termina al salir. *Automático* busca un `dsh` instalado (ofreciendo instalarlo vía npm si no hay ninguno, lo que requiere Node.js); *manual* ejecuta un comando de arranque que tú proves, siempre que imprima la línea de arranque `dsh web: http://…`.

Saltarse la guía deja en el aviso de conexión, a un clic; la guía solo vuelve cuando se borra el archivo de configuración.

## Idioma de la interfaz

La interfaz está en inglés por defecto, esté como esté el idioma del propio macOS. Ajustes → General → Idioma cambia a 简体中文, 繁體中文, 日本語, Français, Deutsch o Español, y la elección se escribe en el archivo de configuración descrito abajo, así que sobrevive a un reinicio.

Los siete idiomas viven en un solo archivo detrás de switches exhaustivos, así que un mensaje no puede salir con solo algunos de ellos: olvidar una traducción rompe la compilación en vez de dejar una cadena china suelta en una interfaz inglesa. Ese archivo también guarda la redacción de los diagnósticos en tiempo de ejecución, que viajan como valores estructurados y se renderizan al mostrarse — cambiar el idioma vuelve a dibujar un fallo que ya está en pantalla, en lugar de dejarlo en el idioma en que se produjo.

La única parte que no puede cambiar en mitad de la sesión es la barra de menús nativa: macOS la dibuja al arrancar a partir de la localización del bundle. En cada arranque, la app refleja el idioma configurado en `AppleLanguages` antes de construirse la interfaz, y el bundle trae un `.lproj` por cada idioma admitido, de modo que los menús siguen el ajuste en el próximo arranque. Mientras el idioma elegido y el de la barra de menús discrepen, Ajustes ofrece un botón de reinicio justo para eso.

Este ajuste cubre solo la interfaz de esta app. La Web UI del Host la sirve el Host y mantiene su propio idioma.

## Notificaciones

La única capacidad que un bisel puede añadir legítimamente alrededor de una pantalla es saber que la pantalla te llama. Dos momentos merecen un aviso: el Host espera tu decisión (una aprobación de herramienta, una pregunta, la revisión de un plan), o una tarea en curso acaba de terminar. Todo lo que sigue es **monitorización de página**: esta app aprende ambas cosas de la misma página que estás mirando, leyendo lo que la propia Web UI del Host ya renderiza para exactamente estas situaciones — no se intercepta nada, no se lee nada del cable, no se modifica nada de la página.

### Monitorización de página

**Inyección.** Un pequeño script observador — JavaScript puro, de solo lectura — se registra como script de usuario de WebKit y acompaña a cada página que el `WKWebView` carga, inyectado al final del documento. Una guardia impide que un script reinyectado (una recarga vuelve a ejecutar los scripts de usuario) apile intervalos.

**Sondeo.** El script toma una instantánea por segundo; cada pasada es un puñado de llamadas a `querySelector`. Un sondeo llano en lugar de un `MutationObserver`, porque un sondeo no puede perderse un panel que se monta y desmonta entre dos mutaciones, cosa que a un resumen de observador ingenuo sí puede escapársele.

**Qué lee una instantánea** — solo marcadores que la propia Web UI del Host renderiza:

| Señal | Marcador | Significado |
| --- | --- | --- |
| Panel de espera | `data-approval-key` / `data-question-key` / `data-plan-review-key` | el Host está bloqueado en una aprobación, una pregunta o la revisión de un plan |
| Turno terminado | `data-turn-tail` en la fila de acciones bajo una respuesta final (copiar, bifurcar, uso, valoración) | la propia marca «este turno terminó» del Host — publicada en el momento en que llega el evento `turn/end` del turno, así que «tarea terminada» significa exactamente lo que la página entiende por ello, no algo deducido de «los marcadores de streaming se quedaron callados» |
| Nombre de la tarea | el número de turno que porta esa fila localiza el mensaje de usuario que inició el turno | la notificación te dice **qué tarea** terminó — con tus propias palabras |
| ¿Sigue siendo la misma conversación? | `data-chat-anchor-key` de las filas de contenido más recientes | un cambio reemplaza cada fila; un turno terminado solo añade una debajo — así que cambiar de sesión jamás se disfraza de terminación |
| Nombre de la sesión | la fila lateral seleccionada, o `document.title` (`"<sesión> — <producto>"`) | cada notificación nombra su conversación |
| Sesiones en segundo plano | los puntos `data-state` de las filas laterales | en curso / esperándote / terminada-sin-abrir |

**De la instantánea al evento.** Cada segundo el script publica su instantánea por un canal privado de puente (`window.webkit.messageHandlers`); la app la decodifica, y un detector puro, con pruebas unitarias, deriva las transiciones que merecen notificación: una atención que aparece, una marca de fin de turno que cambia mientras las filas de arriba siguen en pie, un punto de estado que se voltea. La primera instantánea tras una carga es solo una línea base — cómo están las cosas es estado, no noticia — y el primer punto avistado tras un hueco es historia, no un evento.

### El segundo plano que nadie muestra

Las tareas que no están en esta página — sesiones corriendo en segundo plano dentro del mismo Host — quedan cubiertas a través de la única superficie que las muestra: la barra lateral. Sus filas de sesión llevan el punto de estado en vivo del propio Host (`data-state`): en curso, esperándote, o terminada-sin-abrir — esta última es el propio «recordatorio de completada» del Host, armado exactamente cuando una sesión en segundo plano que corría pasó a inactividad y nadie la ha abierto desde entonces. El borde de un punto se convierte en una notificación que nombra la sesión.

La barra lateral, eso sí, solo renderiza lo que su estado de vista muestra — un grupo de espacios de trabajo plegado no renderiza ninguna fila de sesión, y uno expandido se limita a sus cinco más recientes — así que la barra lateral de la página mostrada no es todo el segundo plano. Un segundo `WKWebView` oculto carga la misma página del Host (su propio almacén no persistente, la cookie de la página mostrada copiada dentro, su dirección sin el token de un solo uso) y abre cada grupo y cada desborde antes de escanear: nadie mira esa página, así que sus clics escriben un estado de vista propio. No restaura ninguna selección — no abre nada — así que los puntos de completada por cliente del Host se arman para cada sesión sin que la sonda borre nunca ninguno. Mientras la sonda vive, sus filas son la verdad del segundo plano: publica una vez por segundo, las filas con más de quince segundos ceden ante la barra lateral de la propia página mostrada, y una página que guarda silencio treinta segundos se recarga con una copia nueva de la cookie.

### Reglas de entrega

Cuándo una instantánea se convierte en notificación de macOS obedece a dos reglas, una por clase de evento. Una llamada — el Host esperando una entrada o confirmación, en esta página o en una sesión en segundo plano — se entrega **siempre**: en primer plano, en segundo plano o minimizada, porque bloquea al Host hasta ser respondida, y la página visible no cubre todas las fuentes. Una terminación es un informe de estado: mientras esta app esté en primer plano con su ventana en pie, la página es su propia notificación, y un banner solo repetiría lo que ya está en pantalla. Hacer clic en una notificación trae la ventana al frente, restaurándola del Dock si ahí estaba minimizada.

Las notificaciones están activadas por defecto; Ajustes → General tiene el interruptor, y el diálogo de permiso del sistema se pregunta una sola vez en el primer arranque. macOS solo entrega notificaciones desde un bundle de app — el ejecutable desnudo de `swift run` ni pregunta ni notifica.

## Qué se recuerda

Todo lo que la app sabe vive en un solo archivo JSON:

```
~/Library/Application Support/dsh-bezel/config.json
```

Contiene los marcadores de Host con todos sus ajustes, en qué marcador está el selector, a cuál estaba adjunta la WebView por última vez, y el idioma de la interfaz. Al arrancar, la app lo lee y **reconecta con el Host al que estaba adjunta por última vez**, así que abrir la app basta para volver a donde estabas; un Host gestionado arranca de cero cada vez, porque su puerto y su token son nuevos en cada ejecución. La cookie firmada `dsh-auth` la recuerda aparte el propio almacén de datos de WebKit, así que reconectar no vuelve a necesitar el token.

Un archivo en lugar de `UserDefaults`, para poder leerlo, editarlo, copiarlo a otra máquina y tenerlo bajo control de versiones. Se escribe pretty-print con claves ordenadas y barras sin escapar precisamente para que su diff siga siendo legible, de forma atómica mediante un archivo temporal para que un cuelgue a mitad de escritura no pueda truncarlo, y con `0600` porque un marcador puede guardar un token de arranque. `BEZEL_CONFIG` apunta la app a otra ruta si quieres.

El decodificado es campo a campo y tolerante: las claves desconocidas se ignoran, un escalar del tipo equivocado cae a su valor por defecto, y los marcadores escritos por una versión anterior (con campos añadidos después que faltan) cargan como siempre. Un archivo que no se puede analizar en absoluto se reporta en Ajustes y **se deja exactamente como está** — jamás se sobreescribe — para que una edición manual con una errata, o un archivo de una versión más nueva, siga siendo recuperable. Borrar el archivo es la forma de reiniciar. Un nombre que escribiste es tu dato y se muestra tal cual en todos los idiomas; solo el nombre de un marcador sembrado en el primer arranque sigue el idioma actual. El tamaño y la posición de la ventana no forman parte de este archivo: SwiftUI los recuerda por su cuenta.

## Modelo de conexión

Un Host es un marcador con cuatro campos que importan: **nombre, dirección (origin), token de arranque (opcional) y si esta app lo gestiona**.

**Host externo (no gestionado)**: escribe `http://host:port`. Si ese Host todavía no le ha dado una cookie a este navegador, pega la dirección completa de la salida de arranque de `dsh web` en «token de arranque», o abre la dirección con su `?token=` una vez en un navegador y vuelve a esta app (las cookies se comparten por autoridad, dentro del almacén de datos WebKit de esta app).

**Host gestionado**: la app ejecuta

```sh
dsh --profile web --port 0 --no-open
```

El puerto `0` deja que el sistema elija, y la URL se analiza desde la línea `dsh web: http://127.0.0.1:PORT/?token=…` en la salida estándar del hijo. Salir de la app termina ese hijo (el botón «Desconectar» también). Si la línea no ha aparecido en 30 segundos, el arranque se considera caducado y el hijo se termina, así que la interfaz nunca se queda en «Iniciando» para siempre.

**Encontrar `dsh`**: una app lanzada con doble clic en Finder hereda el PATH mínimo de launchd (`/usr/bin:/bin:/usr/sbin:/sbin`), que no trae ni node ni npm — y casi todo `dsh` de una máquina real es un envoltorio que necesita un intérprete (`#!/usr/bin/env node`, `npm exec …`, o el shim de ejecución de DSH Desktop). Así que «el archivo existe y tiene el bit x» no basta ni de lejos para llamarlo utilizable. La búsqueda corre en este orden, y cada candidato se ejecuta de verdad una vez con `dsh --version`; solo uno que lo logre se le entrega al hijo:

1. la «ruta del ejecutable dsh» en los ajustes del Host
2. la variable de entorno `BEZEL_DSH_PATH`
3. el `command -v dsh` del shell de inicio de sesión
4. `dsh` en el propio PATH de la app
5. ubicaciones de instalación habituales: `~/.local/bin`, `~/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`, `~/.bun/bin`, `/opt/anaconda3/bin`, …

El paso 3 pregunta a un shell de inicio de sesión **interactivo** (`zsh -l -i -c`, con caída a `-l -c`): los directorios que contienen `node`/`npm` suelen vivir en `~/.zshrc`, que una `zsh -l -c` no interactiva nunca lee — que es exactamente por lo que el PATH de una app con GUI y la terminal del usuario discrepan. La sonda separa el ruido del rc de la respuesta con una línea centinela, y tiene un tiempo límite de 5 segundos.

El PATH del hijo es: el PATH del shell de inicio → el PATH heredado de la app → los directorios de intérprete, deduplicados y fusionados. Nótese que solo se inyectan **directorios de intérprete** — nunca directorios como `~/bin` o `~/.local/bin` donde vive *otro* `dsh`: algunos envoltorios escanean el PATH por sí mismos y se pliegan a lo que encuentran (el shim de DSH Desktop lo hace), así que poner otro envoltorio en el PATH le entrega el arranque a él en vez de usar el runtime que ese shim trae.

Cuando todos los candidatos fallan, el aviso de conexión enumera cada ubicación probada y por qué no funcionó (faltante, o `--version` no corría).

**Semántica de credenciales**: `GET /?token=…` lo intercambia el Host por una cookie firmada válida 30 días (`dsh-auth-<hash(authority)>`, `HttpOnly`). La clave de firma persiste en las credenciales del Host, así que la cookie sobrevive a un reinicio del Host; el token solo hace falta mientras no se tenga cookie. Con la cookie válida, la autorización de índice del Host redirige con 303 cualquier petición `?token=` a un `/` limpio, así que dejar el token en la dirección es seguro — y un token caducado no es un 401 mientras la cookie siga viva. Cuando ninguno de los dos sirve, la página lo dice claramente.

**Varios Hosts**: los nombres de cookie llevan un hash de autoridad, así que las sesiones de varios Hosts coexisten en un almacén de datos WebKit; cambiar de Host es solo cambiar de URL.

## Ajustes

La ventana de Ajustes (menú Host de la barra de herramientas → Gestionar Hosts…, o ⌘,) tiene dos pestañas.

**Hosts** — añadir, quitar y editar marcadores:

| Campo | Significado |
| --- | --- |
| Nombre | se muestra en el selector; si se deja vacío se usa la dirección |
| Dirección | el origin del Host, p. ej. `http://127.0.0.1:3080` |
| Token de arranque | el `?token=…` de la salida de `dsh web`; solo hace falta sin cookie |
| Iniciar un dsh local para este Host | la app engendra el proceso hijo |
| profile | el `--profile` en modo gestionado, `web` por defecto |
| Argumentos extra | se añaden a la invocación de `dsh`, p. ej. `--trusted-host dsh.internal` |
| Comando de arranque personalizado | reemplaza toda la invocación en modo gestionado; debe imprimir la línea `dsh web: http://…` |
| Ruta del ejecutable dsh | qué `dsh` ejecutar en modo gestionado; vacío significa buscar (ver «Encontrar `dsh`») |

**General** — preferencias que pertenecen a la app y no a un Host:

| Campo | Significado |
| --- | --- |
| Idioma | idioma de la interfaz: inglés (por defecto), 简体中文, 繁體中文, 日本語, Français, Deutsch o Español |
| Notificaciones | notificaciones de macOS para Hosts en espera y tareas terminadas; activadas por defecto |
| Archivo de configuración | dónde se guarda la configuración; la ruta se muestra y, al seleccionarla, se puede copiar |

Los marcadores y el resto de la configuración se escriben en ese archivo a medida que editas; cómo se escribe, migra y protege está en «Qué se recuerda», más arriba.

## Distribución

```
Sources/BezelCore/          modelo de conexión y señales (sin SwiftUI, testable en unidades)
  DSHHost.swift             marcadores de Host: normalización de origin, token→URL, troceo de argumentos
  AppConfig.swift           todo lo recordado entre arranques, como un solo valor
  ConfigFile.swift          el archivo JSON: ubicación, escritura atómica, lectura tolerante
  ConfigStore.swift         el único dueño de ese valor: cargar, editar, persistir
  Localization.swift        los siete idiomas, y cada mensaje en todos ellos
  DSHDiscovery.swift        encontrar un dsh utilizable: sonda del shell de inicio, fusión de PATH, candidatos, ejecutabilidad
  LocalHostRunner.swift     el hijo gestionado: descubrimiento asíncrono, análisis de la línea de arranque, tiempo límite, diagnóstico de salida
  DSHProcessScan.swift      encontrar un DSH en ejecución escaneando procesos (el paso de detección de la guía)
  DSHInstall.swift          instalar dsh vía npm (el camino automático de la guía)
  PageSignals.swift         instantáneas de página, scripts observador/sonda y el detector de eventos
  ShellCommand.swift        invocaciones puntuales de shell con tiempo límite
  BoundedProcess.swift      un proceso hijo con salida acotada y legible a posteriori
  OneShotCommand.swift      pequeños ayudantes de ejecución de procesos
  JSONValue.swift           el árbol JSON tolerante por el que decodifica la configuración
Sources/dsh-bezel/          app e interfaz
  BezelApp.swift            punto de entrada, espejo del idioma, entradas de humo --dump-config / --dump-hosts
  Model/AppState.swift      pegamento de configuración / hijo / WebView / sonda, estado de conexión, redacción de notificaciones
  Model/Notifier.swift      la entrega de notificaciones de macOS y las dos reglas de entrega
  Web/WebView.swift         anfitrión WKWebView, reporte de estado de navegación, canal del script observador
  Web/SidebarProbe.swift    la página oculta que lee la barra lateral completa
  UI/MainView.swift         barra de herramientas, selector de Host, aviso de conexión, banner de error
  UI/OnboardingView.swift   la guía de primer arranque
  UI/SettingsView.swift     gestión de Hosts y preferencias de la app (dos pestañas)
Tests/BezelCoreTests/       normalización de direcciones, análisis de línea de arranque, archivo y almacén de config, localización, señales de página
```

## Limitaciones conocidas

- **http plano y ATS**: un Host puede ser `http://` en la LAN, así que `Resources/Info.plist` pone `NSAllowsArbitraryLoadsInWebContent` (relaja solo el contenido del WebView; las peticiones propias de la app siguen bajo ATS). Poner un proxy inverso `https://` delante lo vuelve innecesario.
- **Un Host remoto tiene que admitir a este cliente**: el `/api` de dsh tiene una valla de confianza de navegador que acepta loopback, un literal IP de LAN derivado del despliegue, o una autoridad declarada con `--trusted-host`. Para alcanzar un Host remoto por nombre de dominio, ese Host debe arrancar con `--trusted-host`. Nótese también que el CLI de `dsh web` rechaza `--host 0.0.0.0`; servir más allá de la máquina requiere `host: '0.0.0.0'` en la capa de configuración.
- **Sin App Sandbox**: el modo gestionado engendra `dsh`, y las herramientas de sesión del harness ya ejecutan comandos en la máquina del usuario, así que un sandbox rompería ese modelo de confianza. Si solo te conectas a Hosts externos, puedes añadir tú mismo un sandbox y `com.apple.security.network.client`.
- **Alcance**: esta app no aporta funciones propias a la conversación — lo que tiene la Web UI es lo que hay. Alrededor de la pantalla añade el selector de Host, las notificaciones, los idiomas y la guía de primer arranque.
- **Requisitos previos**: un Host de dsh capaz de servir una Web UI. La línea de arranque de `dsh web` y el intercambio de `?token=` son estables desde 0.1.5-rc.1.

## Relación con dsh-for-mac

`dsh-for-mac` toma el otro camino: reimplementar el protocolo del cable en Swift (RPC unario + `/api/remote.mux` + el flujo de eventos), lo que da interacción totalmente nativa pero implica seguir tú mismo el protocolo y cargar con la deriva. Este proyecto deliberadamente no lo hace. Ambos pueden coexistir; las piezas de forma nativa que esta app sí añade — las notificaciones, la barra de menús que sigue el idioma — envuelven la página sin tocar el modelo de conexión.

## Desarrollo

```sh
swift build --disable-sandbox
swift test --disable-sandbox
swift run dsh-bezel --dump-config   # el archivo de configuración: su ruta, o lo que contiene
swift run dsh-bezel --dump-hosts    # solo los marcadores guardados
```

El ejecutable desnudo y el bundle comparten un archivo de configuración, así que un experimento con `swift run` usa tu configuración real, salvo que `BEZEL_CONFIG` apunte a otro sitio. La opción `--disable-sandbox` hace falta al compilar bajo el harness DSH, que no puede anidar su propio sandbox.
