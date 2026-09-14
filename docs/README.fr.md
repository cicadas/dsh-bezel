# DSH Bezel

[English](../README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · **Français** · [Deutsch](README.de.md) · [Español](README.es.md)

Une enveloppe macOS native qui charge la propre Web UI d'un Host dsh directement dans une `WKWebView`, et n'ajoute autour de l'écran que ce qu'une enveloppe peut légitimement ajouter : **choisir à quel dsh se connecter**, **savoir quand l'écran vous appelle**, et **une langue d'interface qui lui appartient**.

Le design d'ingénierie complet — le contrat câblé, les règles de décision, le modèle d'état, la carte des sources — vit dans [architecture.md](../architecture.md), en anglais uniquement. Ce README garde la forme du design, comment utiliser l'app, et comment elle se compare aux autres outils.

## Le design en bref

Quatre décisions définissent toute l'app :

- **La page est l'app.** Une seule `WKWebView` charge la propre Web UI du Host — affichage pur, zéro injection, zéro relecture. Chaque fonction de l'interface de dsh suit automatiquement la version du Host, parce que l'app ne modifie ni n'interprète la page.
- **Les notifications viennent de l'API du Host, pas de la page.** Un canal séparé et peu coûteux — `HostFeed` — tient un unique WebSocket autorisé par cookie et collecte de temps en temps la liste des sessions. Une fin, c'est un drapeau `running` qui retombe ; une convocation, c'est un événement en cascade écouté passivement, pendant que la page affichée garde son monopole sur la réponse.
- **L'affichage se renouvelle lui-même.** Une page laissée ouverte des jours accumule de la mémoire de rendu, donc l'app la recharge après un jour d'affichage — mais seulement quand aucune fenêtre n'est visible, jamais pendant que le Host attend une réponse.
- **Un seul fichier JSON retient tout**, écrit atomiquement et décodé avec tolérance ; un enfant `dsh` géré est trouvé via le véritable environnement de shell de l'utilisateur, engendré, et terminé à la fermeture.

Ce que chacune signifie en détail, et pourquoi elle est façonnée ainsi, fait l'objet d'[architecture.md](../architecture.md).

## Démarrage rapide

```sh
swift build --disable-sandbox   # compiler (le drapeau n'est requis que sous le harness DSH)
swift test --disable-sandbox    # tests unitaires du modèle de connexion, du format câblé des notifications et du fichier de configuration
./scripts/make-app.sh           # produire build/DSH Bezel.app
open "build/DSH Bezel.app"
```

`swift run dsh-bezel` fonctionne aussi, mais c'est un exécutable nu : sans bundle, l'exception ATS d'`Info.plist` ne s'applique pas, la propriété des cookies et des préférences est instable, et macOS refuse de livrer des notifications. Pour un vrai usage, prenez le `.app`.

## Guide de premier lancement

Le premier lancement ouvre un court guide plutôt que la fenêtre principale. Il détecte si un processus DSH sert déjà une Web UI et propose ce que cette détection permet :

- **Lier le processus en cours** — pointer cette app vers un `dsh` que vous avez démarré vous-même, en collant l'adresse et le token de sa sortie de démarrage.
- **En lancer un en gestion** — l'app exécute l'enfant et le termine à la fermeture. *Automatique* cherche un `dsh` installé (et propose de l'installer via npm s'il n'y en a pas, ce qui requiert Node.js) ; *manuel* exécute une commande de lancement que vous fournissez, pourvu qu'elle imprime la ligne de démarrage `dsh web: http://…`.

Passer le guide vous laisse sur l'invite de connexion, à un clic ; le guide ne revient que si le fichier de configuration est supprimé.

## Langue de l'interface

L'interface est en anglais par défaut, quelle que soit la langue de macOS lui-même. Réglages → Général → Langue bascule en 简体中文, 繁體中文, 日本語, Français, Deutsch ou Español, et le choix est écrit dans le fichier de configuration décrit plus bas, donc il survit à un relancement.

La seule partie qui ne peut pas basculer en pleine session, c'est la barre de menus native : macOS la dessine au lancement à partir de la localisation du bundle. À chaque lancement, l'app reflète la langue configurée dans `AppleLanguages` avant que l'interface ne soit construite, et le bundle embarque un `.lproj` pour chaque langue prise en charge, donc les menus suivent le réglage au prochain démarrage. Tant que la langue choisie et celle de la barre de menus divergent, les Réglages proposent un bouton de redémarrage prévu exactement pour ça.

Ce réglage ne couvre que l'interface de cette app. La Web UI du Host est servie par le Host et garde sa propre langue.

## Réglages

La fenêtre Réglages (menu Host de la barre d'outils → Gérer les Hosts…, ou ⌘,) a deux onglets.

**Hosts** — ajouter, retirer et éditer des signets :

| Champ | Signification |
| --- | --- |
| Nom | affiché dans le sélecteur ; l'adresse est utilisée si laissé vide |
| Adresse | l'origin du Host, p. ex. `http://127.0.0.1:3080` |
| Token de lancement | le `?token=…` de la sortie de `dsh web` ; requis seulement sans cookie |
| Démarrer un dsh local pour ce Host | l'app engendre le processus enfant |
| profile | le `--profile` en mode géré, `web` par défaut |
| Arguments supplémentaires | ajoutés à l'appel `dsh`, p. ex. `--trusted-host dsh.internal` |
| Commande de lancement personnalisée | remplace tout l'appel en mode géré ; doit imprimer la ligne `dsh web: http://…` |
| Chemin de l'exécutable dsh | quel `dsh` exécuter en mode géré ; vide signifie chercher |

**Général** — préférences appartenant à l'app plutôt qu'à un Host :

| Champ | Signification |
| --- | --- |
| Langue | langue d'interface : anglais (défaut), 简体中文, 繁體中文, 日本語, Français, Deutsch ou Español |
| Notifications | notifications macOS pour les Hosts en attente et les tâches terminées ; actives par défaut |
| Renouvellement automatique de la page | recharge la page en arrière-plan après un jour d'affichage ; activé par défaut |
| Fichier de configuration | où la configuration est stockée ; le chemin est affiché, et le sélectionner permet de le copier |

Les signets et le reste de la configuration sont écrits dans ce fichier au fil de l'édition ; la façon dont il est écrit, migré et protégé est décrite dans [architecture.md](../architecture.md) sous « What is remembered ».

## Comparaison avec les autres outils

Tout outil qui met une Web UI dsh dans une fenêtre est l'une de trois formes : un simple onglet de navigateur sur la page du Host, une application d'emballage générique autour d'elle, ou un client natif qui réimplémente le protocole câblé.

| | Un onglet de navigateur sur `dsh web` | Une application d'emballage générique | DSH Bezel | Un client natif réimplémentant le protocole |
| --- | --- | --- | --- | --- |
| Interaction | la Web UI du Host | la Web UI du Host | la même Web UI du Host, dans une vue WebKit — zéro dérive de protocole | une réimplémentation native de l'interface |
| Protocole à maintenir | aucun | aucun | aucun pour l'interaction ; une tranche étroite arrimée par des tests pour les notifications | tout le protocole câblé |
| Notifications macOS | aucune | aucune | oui — attentes et fins, dans n'importe quelle session | oui |
| Signets, enfant géré, guide de premier lancement | aucun | aucun | oui | oui |
| Langues de l'interface | celle du Host | les siennes | sept, barre de menus comprise | les siennes |
| Mémoire outre la page | aucune | un second moteur de navigateur embarqué | un socket | une interface native |

- **Face à l'onglet** : la page est identique — cette app ne l'améliore jamais. Ce que l'enveloppe ajoute vit entièrement autour d'elle : les signets et l'enfant géré pour qu'ouvrir l'app suffise, les notifications pour qu'un Host en attente ne passe pas inaperçu, le renouvellement pour qu'un écran laissé ouvert des semaines reste sain, et la gestion des langues.
- **Face à l'emballage générique** : ils embarquent leur propre moteur de navigateur — la mémoire d'un second runtime entier pour montrer la même page dans une fenêtre habillée — et ne savent rien de ce qu'ils emballent. Cette app utilise le WebKit du système, si bien que la page coûte ce que la page coûte, et la coquille comprend son Host : comment le trouver, le lancer, l'observer, s'y reconnecter.
- **Face à la réimplémentation native** : celui-ci prend l'autre route — réimplémenter le protocole câblé en Swift (RPC unaire + `/api/remote.mux` + le flux d'événements), ce qui donne une interaction entièrement native mais signifie suivre le protocole soi-même et assumer la dérive. Ce projet ne le fait délibérément pas — pour l'interaction. Tout ce que vous cliquez, tapez et lisez est la propre Web UI du Host, et l'app n'en comprend rien. La seule exception, ce sont les notifications : `HostFeed` s'abonne à une tranche étroite de la même API — la liste des sessions, un événement d'état, deux portes de convocation — parce qu'apprendre cela depuis la page signifiait y injecter un script et payer un second moteur de rendu. La tranche est exactement `HostFeedWire`, des fonctions d'analyse pures arrimées par des tests enregistrés depuis un Host vivant. Les deux projets peuvent coexister ; les morceaux de forme native que cette app ajoute — les notifications, la barre de menus qui suit la langue — enveloppent la page sans toucher à la façon dont vous la pilotez.
- **Ce qui est échangé** : une fin ne cite plus la propre invite de l'utilisateur (le titre de la session nomme la tâche à la place), et le format câblé des notifications suit la version du Host sur cette petite surface arrimée par des tests.
- **Prérequis** : un Host dsh capable de servir une Web UI (stable depuis 0.1.5-rc.1). Un Host distant joint par nom de domaine doit être démarré avec `--trusted-host` — le `/api` de dsh a une barrière de confiance navigateur ; voir architecture.md sous « Known constraints » pour le reste.

## Développement

```sh
swift build --disable-sandbox
swift test --disable-sandbox
swift run dsh-bezel --dump-config   # le fichier de configuration : son chemin, ou ce qu'il contient
swift run dsh-bezel --dump-hosts    # seulement les signets enregistrés
swift run dsh-bezel --watch-feed "http://127.0.0.1:PORT/?token=…"
                                    # attacher le canal de notification à un Host
                                    # et imprimer chaque fait qu'il apprend — le
                                    # contrat câblé, en direct
```

L'exécutable nu et le bundle partagent un fichier de configuration, donc une expérience avec `swift run` utilise votre vraie configuration, sauf si `BEZEL_CONFIG` pointe ailleurs. Le drapeau `--disable-sandbox` est requis pour construire sous le harness DSH, qui ne peut pas imbriquer son propre bac à sable.
