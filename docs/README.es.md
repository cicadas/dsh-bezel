# DSH Bezel

[English](../README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · **Español**

Una carcasa nativa de macOS que carga la propia Web UI de un Host de dsh directamente en un `WKWebView`, y añade alrededor de la pantalla exactamente lo que una carcasa puede añadir legítimamente: **elegir a qué dsh conectarse**, **saber cuándo la pantalla te llama**, y **un idioma de interfaz propio**.

El diseño de ingeniería completo — el contrato del cable, las reglas de decisión, el modelo de estado, el mapa del código fuente — vive en [architecture.md](../architecture.md), que por ahora está solo en inglés. Este README conserva la forma del diseño, cómo usar la app y cómo se compara con las alternativas.

## El diseño en breve

Cuatro decisiones definen toda la app:

- **La página es la app.** Un `WKWebView` carga la Web UI del propio Host — pantalla pura, cero inyección, cero lectura de vuelta. Cada función de la interfaz de dsh sigue automáticamente la versión del Host, porque la app ni modifica ni interpreta la página.
- **Las notificaciones vienen de la API del Host, no de la página.** Un canal aparte y barato — `HostFeed` — mantiene un WebSocket autorizado por cookie y de vez en cuando pide la lista de sesiones. Una terminación es un flag `running` que cae; una llamada es un evento de cascada escuchado pasivamente, mientras la página mostrada conserva su monopolio de responder.
- **La pantalla se renueva a sí misma.** Una página que queda abierta durante días acumula memoria de renderizado, así que la app la recarga cuando lleva un día viva — pero solo cuando ninguna ventana es visible, nunca mientras el Host espera una respuesta.
- **Un solo archivo JSON lo recuerda todo**, escrito de forma atómica y decodificado con tolerancia; un hijo `dsh` gestionado se encuentra a través del entorno real de shell del usuario, se engendra y se termina al salir.

Lo que cada una significa en detalle, y por qué tiene la forma que tiene, es el tema de [architecture.md](../architecture.md).

## Inicio rápido

```sh
swift build --disable-sandbox   # compilar (la opción solo hace falta bajo el harness DSH)
swift test --disable-sandbox    # pruebas unitarias del modelo de conexión, el cable de las notificaciones y el archivo de configuración
./scripts/make-app.sh           # producir build/DSH Bezel.app
open "build/DSH Bezel.app"
```

`swift run dsh-bezel` también funciona, pero es un ejecutable desnudo: sin bundle, la excepción ATS de `Info.plist` no aplica, la propiedad de cookies y preferencias es inestable, y macOS se niega a entregar notificaciones. Para trabajo real, usa el `.app`.

¿Prefieres no compilar? La [página de releases](https://github.com/cicadas/dsh-bezel/releases/latest) ofrece un DMG y un zip universal (Apple silicon e Intel) con sus sumas de comprobación SHA-256. Los binarios están firmados ad-hoc: en una máquina sin certificado de desarrollador, la primera apertura puede requerir clic derecho → Abrir.

## Guía de primer arranque

El primer arranque abre una guía breve en lugar de la ventana principal. Detecta si un proceso DSH ya está sirviendo una Web UI y ofrece lo que ese hallazgo permite:

- **Vincular el proceso en ejecución** — apuntar esta app a un `dsh` que iniciaste tú mismo, pegando la dirección y el token de su salida de arranque.
- **Iniciar uno gestionado** — la app ejecuta el proceso hijo y lo termina al salir. *Automático* busca un `dsh` instalado (ofreciendo instalarlo vía npm si no hay ninguno, lo que requiere Node.js); *manual* ejecuta un comando de arranque que tú proves, siempre que imprima la línea de arranque `dsh web: http://…`.

Saltarse la guía deja en el aviso de conexión, a un clic; la guía solo vuelve cuando se borra el archivo de configuración.

## Idioma de la interfaz

La interfaz está en inglés por defecto, esté como esté el idioma del propio macOS. Ajustes → General → Idioma cambia a 简体中文, 繁體中文, 日本語, Français, Deutsch o Español, y la elección se escribe en el archivo de configuración descrito abajo, así que sobrevive a un reinicio.

La única parte que no puede cambiar en mitad de la sesión es la barra de menús nativa: macOS la dibuja al arrancar a partir de la localización del bundle. En cada arranque, la app refleja el idioma configurado en `AppleLanguages` antes de construirse la interfaz, y el bundle trae un `.lproj` por cada idioma admitido, de modo que los menús siguen el ajuste en el próximo arranque. Mientras el idioma elegido y el de la barra de menús discrepen, Ajustes ofrece un botón de reinicio justo para eso.

Este ajuste cubre solo la interfaz de esta app. La Web UI del Host la sirve el Host y mantiene su propio idioma.

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
| Ruta del ejecutable dsh | qué `dsh` ejecutar en modo gestionado; vacío significa buscar |

**General** — preferencias que pertenecen a la app y no a un Host:

| Campo | Significado |
| --- | --- |
| Idioma | idioma de la interfaz: inglés (por defecto), 简体中文, 繁體中文, 日本語, Français, Deutsch o Español |
| Notificaciones | notificaciones de macOS para Hosts en espera y tareas terminadas; activadas por defecto |
| Renovación automática de la página | recarga la página por su cuenta tras un día abierta, en segundo plano; activada por defecto |
| Archivo de configuración | dónde se guarda la configuración; la ruta se muestra y, al seleccionarla, se puede copiar |

Los marcadores y el resto de la configuración se escriben en ese archivo a medida que editas; cómo se escribe, migra y protege está descrito en [architecture.md](../architecture.md) bajo «What is remembered».

## Comparación con otras herramientas

Toda herramienta que mete una Web UI de dsh en una ventana es una de tres formas: una pestaña de navegador sencilla sobre la página del Host, una aplicación envolvente genérica alrededor de ella, o un cliente nativo que reimplementa el protocolo del cable.

| | Una pestaña de navegador sobre `dsh web` | Una app envolvente genérica | DSH Bezel | Una reimplementación nativa del protocolo |
| --- | --- | --- | --- | --- |
| Interacción | la Web UI del Host | la Web UI del Host | la misma Web UI del Host, en una vista WebKit — cero deriva de protocolo | una reimplementación nativa de la interfaz |
| Protocolo que mantener | ninguno | ninguno | ninguno para la interacción; una porción estrecha, fijada por pruebas, para las notificaciones | el protocolo del cable entero |
| Notificaciones de macOS | ninguna | ninguna | sí — esperas y terminaciones, en cualquier sesión | sí |
| Marcadores, hijo gestionado, guía de primer arranque | nada | nada | sí | sí |
| Idiomas de interfaz | el propio del Host | los suyos | siete, barra de menús incluida | los suyos |
| Memoria además de la página | ninguna | un segundo motor de navegador empaquetado | un socket | una interfaz nativa |

- **Frente a la pestaña**: la página es idéntica — esta app jamás la mejora. Lo que la carcasa añade vive por completo alrededor de ella: los marcadores y el hijo gestionado para que abrir la app baste, las notificaciones para que no se pase por alto un Host en espera, la renovación para que una pantalla dejada abierta semanas siga sana, y el manejo de idiomas.
- **Frente a la envolvente genérica**: empaquetan su propio motor de navegador — la memoria de un segundo runtime entero por mostrar la misma página en una ventana vestida — y no saben nada de lo que envuelven. Esta app usa el WebKit del sistema, así que la página cuesta lo que la página cuesta, y la carcasa entiende a su Host: cómo encontrarlo, arrancarlo, vigilarlo y reconectar.
- **Frente a la reimplementación nativa**: toma el otro camino — reimplementar el protocolo del cable en Swift (RPC unario + `/api/remote.mux` + el flujo de eventos), lo que da interacción totalmente nativa pero implica seguir tú mismo el protocolo y cargar con la deriva. Este proyecto deliberadamente no lo hace — en la interacción. Todo aquello sobre lo que haces clic, lo que escribes y lo que lees es la Web UI del propio Host, y la app no entiende nada de ello. La única excepción son las notificaciones: `HostFeed` se suscribe a una porción estrecha de la misma API — la lista de sesiones, un evento de estado, dos puertas de llamada — porque aprender estas cosas de la página significaba inyectarle un script y pagar un segundo renderer. La porción es exactamente `HostFeedWire`, funciones de análisis puras fijadas por pruebas grabadas de un Host en vivo. Los dos proyectos pueden seguir coexistiendo; las piezas de forma nativa que esta app sí añade — las notificaciones, la barra de menús que sigue el idioma — envuelven la página sin tocar cómo la conduces.
- **Lo que se intercambia**: una notificación de terminación ya no cita el propio prompt del usuario (el título de la sesión nombra la tarea en su lugar), y el formato del cable de las notificaciones sigue la versión del Host dentro de esa pequeña superficie fijada por pruebas.
- **Requisitos previos**: un Host de dsh capaz de servir una Web UI (estable desde 0.1.5-rc.1). Un Host remoto alcanzado por nombre de dominio debe arrancar con `--trusted-host` — el `/api` de dsh tiene una valla de confianza de navegador; el resto está en architecture.md bajo «Known constraints».

## Desarrollo

```sh
swift build --disable-sandbox
swift test --disable-sandbox
swift run dsh-bezel --dump-config   # el archivo de configuración: su ruta, o lo que contiene
swift run dsh-bezel --dump-hosts    # solo los marcadores guardados
swift run dsh-bezel --watch-feed "http://127.0.0.1:PORT/?token=…"
                                    # adjuntar el canal de notificaciones a un
                                    # Host e imprimir cada hecho que aprende —
                                    # el contrato del cable, en vivo
```

El ejecutable desnudo y el bundle comparten un archivo de configuración, así que un experimento con `swift run` usa tu configuración real, salvo que `BEZEL_CONFIG` apunte a otro sitio. La opción `--disable-sandbox` hace falta al compilar bajo el harness DSH, que no puede anidar su propio sandbox.
