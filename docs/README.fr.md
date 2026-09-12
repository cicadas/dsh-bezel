# DSH Bezel

[English](../README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · **Français** · [Deutsch](README.de.md) · [Español](README.es.md)

yet-another-dsh-for-mac. Une enveloppe macOS native qui charge la propre Web UI d'un Host dsh directement dans une `WKWebView`, et n'ajoute autour de l'écran que ce qu'une enveloppe peut légitimement ajouter : **choisir à quel dsh se connecter**, **savoir quand l'écran vous appelle**, et **une langue d'interface qui lui appartient**.

## Pourquoi une enveloppe plutôt qu'une réimplémentation du protocole

Une Web UI dsh n'est pas un frontend statique à empaqueter dans une app — c'est une application complète servie par le Host lui-même :

- la SPA est servie depuis le siège frontend-static du Host ;
- le bundle navigateur de chaque plugin `dsh.client` est servi depuis `/plugins/<id>/client.js` ;
- la charge d'amorçage `window.__DSH_BOOT__` est injectée par le Host à chaque rendu de l'index.

Donc « à quel dsh me connecter-je » se ramène, dans l'implémentation, à « quelle URL une `WKWebView` charge-t-elle ». Ce que cela achète, c'est **zéro dérive de protocole** : le rendu des sessions, les approbations, les plans, les objectifs, les cartes d'outils, les pièces jointes, les réglages, la sélection de modèle et les plugins navigateur tiers suivent tous automatiquement la version du Host. Ce projet n'a jamais à comprendre `/api`, `/api/remote.mux`, ni aucun type d'événement.

## Démarrage rapide

```sh
swift build --disable-sandbox   # compiler (le drapeau n'est requis que sous le harness DSH)
swift test --disable-sandbox    # tests unitaires du modèle de connexion et des signaux de page
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

Les sept langues vivent dans un seul fichier derrière des switchs exhaustifs, donc un message ne peut pas paraître dans seulement certaines d'entre elles : oublier une traduction fait échouer la compilation au lieu de laisser une chaîne chinoise traîner dans une interface anglaise. Ce fichier porte aussi la formulation des diagnostics d'exécution, transportés comme des valeurs structurées et rendus à l'affichage — changer la langue redessine donc un échec déjà à l'écran au lieu de le laisser dans la langue où il a été produit.

La seule partie qui ne peut pas basculer en pleine session, c'est la barre de menus native : macOS la dessine au lancement à partir de la localisation du bundle. À chaque lancement, l'app reflète la langue configurée dans `AppleLanguages` avant que l'interface ne soit construite, et le bundle embarque un `.lproj` pour chaque langue prise en charge, donc les menus suivent le réglage au prochain démarrage. Tant que la langue choisie et celle de la barre de menus divergent, les Réglages proposent un bouton de redémarrage prévu exactement pour ça.

Ce réglage ne couvre que l'interface de cette app. La Web UI du Host est servie par le Host et garde sa propre langue.

## Notifications

La seule capacité qu'une lunette peut légitimement ajouter autour d'un écran, c'est de savoir que l'écran vous appelle. Deux moments méritent un appel : le Host attend votre décision (une approbation d'outil, une question, une relecture de plan), ou une tâche en cours vient de se terminer. Tout ce qui suit est de la **surveillance de page** : cette app apprend l'une et l'autre de la même page que vous regardez, en lisant ce que la propre Web UI du Host rend déjà pour exactement ces situations — rien n'est intercepté, rien n'est lu sur le câble, rien dans la page n'est modifié.

### Surveillance de page

**Injection.** Un petit script observateur — du JavaScript pur, en lecture seule — est enregistré comme script utilisateur WebKit et voyage avec chaque page que la `WKWebView` charge, injecté à la fin du document. Une garde empêche un script réinjecté (un rechargement réexécute les scripts utilisateur) d'empiler des intervalles.

**Sondage.** Le script prend un instantané par seconde ; chaque passe est une poignée d'appels `querySelector`. Un sondage simple plutôt qu'un `MutationObserver`, parce qu'un sondage ne peut pas manquer un panneau qui se monte et se démonte entre deux mutations, là où un résumé d'observateur naïf le peut.

**Ce qu'un instantané lit** — uniquement des marqueurs que la propre Web UI du Host rend :

| Signal | Marqueur | Signification |
| --- | --- | --- |
| Panneau d'attente | `data-approval-key` / `data-question-key` / `data-plan-review-key` | le Host est bloqué sur une approbation, une question ou une relecture de plan |
| Tour terminé | `data-turn-tail` sur la rangée d'actions sous une réponse finale (copier, forker, usage, retours) | le propre marqueur « ce tour est fini » du Host — publié à l'instant où l'événement `turn/end` du tour arrive, donc « tâche terminée » signifie exactement ce que la page entend par là, pas quelque chose déduit de « les marqueurs de streaming se sont tus » |
| Nom de la tâche | le numéro de tour que porte cette rangée localise le message utilisateur qui a lancé le tour | la notification vous dit **quelle tâche** s'est terminée — dans vos propres mots |
| Toujours la même conversation ? | `data-chat-anchor-key` des plus récentes rangées de contenu | un changement remplace chaque rangée ; un tour terminé n'en ajoute qu'une en dessous — donc changer de session ne se déguise jamais en fin |
| Nom de la session | la rangée latérale sélectionnée, ou `document.title` (`"<session> — <produit>"`) | chaque notification nomme sa conversation |
| Sessions d'arrière-plan | les points `data-state` des rangées latérales | en cours / en attente de vous / terminée-non-ouverte |

**De l'instantané à l'événement.** Chaque seconde, le script poste son instantané sur un canal privé de passerelle (`window.webkit.messageHandlers`) ; l'app le décode, et un détecteur pur, testé en unités, dérive les transitions qui méritent une notification : une attention qui apparaît, une marque de fin de tour qui change pendant que les rangées au-dessus tiennent encore, un point d'état qui bascule. Le premier instantané après un chargement n'est qu'une base — où les choses en sont, c'est un état, pas une nouvelle — et le premier point aperçu après un écart est de l'histoire, pas un événement.

### L'arrière-plan que personne n'affiche

Les tâches qui ne sont pas sur cette page — les sessions qui tournent en arrière-plan dans le même Host — sont couvertes à travers la seule surface qui les montre : la barre latérale. Ses rangées de sessions portent le point d'état en direct du Host lui-même (`data-state`) : en cours, en attente de vous, ou terminée-mais-non-ouverte — ce dernier est la propre « rappel de complétion » du Host, armé précisément quand une session d'arrière-plan qui tournait passe à l'inactivité sans que personne ne l'ait ouverte depuis. Le bord d'un point devient une notification qui nomme la session.

La barre latérale ne rend toutefois que ce que son état de vue montre — un groupe d'espaces de travail replié ne rend aucune rangée de session, et un groupe déplié plafonne à ses cinq plus récentes — donc la barre latérale de la page affichée n'est pas tout l'arrière-plan. Une seconde `WKWebView` cachée charge la même page du Host (son propre dépôt non persistant, le cookie de la page affichée copié dedans, son adresse débarrassée du token à usage unique) et ouvre chaque groupe et débordement avant de balayer : personne ne regarde cette page, donc ses clics écrivent un état de vue qui lui appartient. Elle ne restaure aucune sélection — elle n'ouvre rien — donc les points de complétion par client du Host s'arment pour chaque session sans que la sonde n'en efface jamais un. Tant que la sonde est vivante, ses rangées sont la vérité de l'arrière-plan : elle poste une fois par seconde, les rangées de plus de quinze secondes cèdent la place à la barre latérale propre de la page affichée, et une page qui reste silencieuse trente secondes est rechargée avec une copie fraîche du cookie.

### Règles de livraison

Quand un instantané devient une notification macOS obéit à deux règles, une par classe d'événement. Une convocation — le Host attendant une entrée ou une confirmation, sur cette page ou dans une session d'arrière-plan — est **toujours livrée** : au premier plan, en arrière-plan ou minimisée, parce qu'elle bloque le Host jusqu'à réponse, et que la page visible ne couvre pas toutes les sources. Une fin est un rapport d'état : tant que cette app est au premier plan avec sa fenêtre levée, la page est sa propre notification, et un bandeau ne ferait que répéter ce qui est déjà à l'écran. Cliquer une notification amène la fenêtre devant, la restaurant du Dock si elle y était minimisée.

Les notifications sont actives par défaut ; Réglages → Général a l'interrupteur, et le dialogue de permission du système n'est demandé qu'une fois au premier lancement. macOS ne livre des notifications que depuis un bundle d'app — l'exécutable nu de `swift run` ne demande pas et ne notifie pas.

## Ce qui est retenu

Tout ce que l'app sait vit dans un seul fichier JSON :

```
~/Library/Application Support/dsh-bezel/config.json
```

Il contient les signets de Host avec tous leurs réglages, le signet sur lequel le sélecteur se tient, celui auquel la WebView était attachée en dernier, et la langue d'interface. Au lancement l'app le lit et **reconnecte le Host auquel elle était attachée en dernier**, donc ouvrir l'app suffit pour retrouver où vous en étiez ; un Host géré repart de zéro, puisque son port et son token sont neufs à chaque exécution. Le cookie signé `dsh-auth` est retenu à part par le propre dépôt de données de WebKit, donc se reconnecter n'exige plus le token.

Un fichier plutôt que `UserDefaults`, pour pouvoir le lire, l'éditer, le copier sur une autre machine et le garder en gestion de versions. Il est écrit en pretty-print avec clés triées et barres obliques non échappées précisément pour qu'un diff reste lisible, atomiquement via un fichier temporaire pour qu'un crash en pleine écriture ne puisse pas le tronquer, et en `0600` parce qu'un signet peut tenir un token de lancement. `BEZEL_CONFIG` pointe l'app vers un autre chemin si vous le voulez.

Le décodage est champ par champ et tolérant : les clés inconnues sont ignorées, un scalaire du mauvais type retombe sur son défaut, et un signet écrit par une version antérieure (champs ajoutés plus tard manquants) se charge comme d'habitude. Un fichier tout bonnement illisible est signalé dans les Réglages et **laissé exactement tel quel** — jamais écrasé — donc une retouche manuelle à corriger, ou un fichier d'une version plus récente, reste récupérable. Supprimer le fichier, c'est réinitialiser. Un nom que vous avez tapé est votre donnée et s'affiche tel quel dans toutes les langues ; seul le nom d'un signet semé au premier lancement suit la langue courante. La taille et la position de la fenêtre ne font pas partie de ce fichier : SwiftUI s'en souvient elle-même.

## Modèle de connexion

Un Host est un signet avec quatre champs qui comptent : **nom, adresse (origin), token de lancement (optionnel), et si cette app le gère**.

**Host externe (non géré)** : entrez `http://host:port`. Si ce Host n'a pas encore donné de cookie à ce navigateur, collez l'adresse complète de la sortie de démarrage de `dsh web` dans « token de lancement », ou ouvrez l'adresse avec son `?token=` une fois dans un navigateur et revenez dans cette app (les cookies sont partagés par autorité, dans le dépôt de données WebKit de cette app).

**Host géré** : l'app exécute

```sh
dsh --profile web --port 0 --no-open
```

Le port `0` laisse le système choisir, et l'URL est analysée depuis la ligne `dsh web: http://127.0.0.1:PORT/?token=…` sur la sortie standard de l'enfant. Quitter l'app termine cet enfant (le bouton « Déconnecter » aussi). Si la ligne n'est pas apparue en 30 secondes, le lancement est jugé expiré et l'enfant terminé, donc l'interface ne reste jamais sur « Démarrage » indéfiniment.

**Trouver `dsh`** : une app lancée en double-cliquant dans Finder hérite du PATH minimal de launchd (`/usr/bin:/bin:/usr/sbin:/sbin`), qui ne contient ni node ni npm — et presque chaque `dsh` d'une vraie machine est un enveloppe qui a besoin d'un interpréteur (`#!/usr/bin/env node`, `npm exec …`, ou le shim d'exécution de DSH Desktop). Donc « le fichier existe et a le bit x » est loin de suffire pour le dire utilisable. La recherche suit cet ordre, et chaque candidat est réellement exécuté une fois avec `dsh --version` ; seul un qui réussit est confié à l'enfant :

1. le « chemin de l'exécutable dsh » dans les réglages du Host
2. la variable d'environnement `BEZEL_DSH_PATH`
3. le `command -v dsh` du shell de connexion
4. `dsh` sur le propre PATH de l'app
5. les emplacements d'installation classiques : `~/.local/bin`, `~/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.npm-global/bin`, `~/.bun/bin`, `/opt/anaconda3/bin`, …

L'étape 3 interroge un shell de connexion **interactif** (`zsh -l -i -c`, repli sur `-l -c`) : les répertoires tenant `node`/`npm` vivent d'ordinaire dans `~/.zshrc`, qu'un `zsh -l -c` non interactif ne lit jamais — c'est exactement pourquoi le PATH d'une app GUI et le terminal de l'utilisateur divergent. La sonde sépare le bavardage du rc de la réponse par une ligne sentinelle, avec un délai de 5 secondes.

Le PATH de l'enfant est : le PATH du shell de connexion → le PATH hérité de l'app → les répertoires d'interpréteur, dédupliqués et fusionnés. Notez que seuls les **répertoires d'interpréteur** sont injectés — jamais des répertoires comme `~/bin` ou `~/.local/bin` où vit *un autre* `dsh` : certains enveloppes parcourent eux-mêmes le PATH et défèrent à ce qu'ils trouvent (le shim de DSH Desktop le fait), donc mettre un autre enveloppe sur le PATH lui confie le lancement au lieu d'utiliser l'exécution que ce shim embarque.

Quand chaque candidat échoue, l'invite de connexion énumère chaque emplacement essayé et pourquoi il n'a pas fonctionné (absent, ou `--version` refusait de tourner).

**Sémantique des justificatifs** : `GET /?token=…` est échangé par le Host contre un cookie signé valable 30 jours (`dsh-auth-<hash(authority)>`, `HttpOnly`). La clé de signature persiste dans les justificatifs du Host, donc le cookie survit à un redémarrage du Host ; le token n'est nécessaire que tant qu'aucun cookie n'est détenu. Quand le cookie est valide, l'autorisation d'index du Host redirige en 303 toute requête `?token=` vers un `/` propre, donc laisser le token dans l'adresse est sans danger — et un token expiré n'est pas un 401 tant que le cookie tient. Quand aucun des deux ne marche, la page le dit franchement.

**Hosts multiples** : les noms de cookies portent un hachage d'autorité, donc les sessions de plusieurs Hosts coexistent dans un dépôt de données WebKit ; changer de Host, c'est juste changer d'URL.

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
| Chemin de l'exécutable dsh | quel `dsh` exécuter en mode géré ; vide signifie chercher (voir « Trouver `dsh` ») |

**Général** — préférences appartenant à l'app plutôt qu'à un Host :

| Champ | Signification |
| --- | --- |
| Langue | langue d'interface : anglais (défaut), 简体中文, 繁體中文, 日本語, Français, Deutsch ou Español |
| Notifications | notifications macOS pour les Hosts en attente et les tâches terminées ; actives par défaut |
| Fichier de configuration | où la configuration est stockée ; le chemin est affiché, et le sélectionner permet de le copier |

Les signets et le reste de la configuration sont écrits dans ce fichier au fil de l'édition ; voir « Ce qui est retenu » plus haut pour la façon dont il est écrit, migré et protégé.

## Disposition

```
Sources/BezelCore/          modèle de connexion et de signaux (sans SwiftUI, testable en unités)
  DSHHost.swift             signets de Host : normalisation d'origin, token→URL, découpage d'arguments
  AppConfig.swift           tout ce qui est retenu entre lancements, comme une seule valeur
  ConfigFile.swift          le fichier JSON : emplacement, écriture atomique, lecture tolérante
  ConfigStore.swift         l'unique propriétaire de cette valeur : charger, éditer, persister
  Localization.swift        les sept langues, et chaque message dans chacune
  DSHDiscovery.swift        trouver un dsh utilisable : sonde du shell de connexion, fusion de PATH, candidats, exécution
  LocalHostRunner.swift     l'enfant géré : découverte asynchrone, analyse de la ligne de démarrage, délai, diagnostics de sortie
  DSHProcessScan.swift      trouver un DSH en cours en scannant les processus (l'étape de détection du guide)
  DSHInstall.swift          installer dsh via npm (le chemin automatique du guide)
  PageSignals.swift         instantanés de page, scripts observateur/sonde, et détecteur d'événements
  ShellCommand.swift        invocations shell ponctuelles avec délai
  BoundedProcess.swift      un processus enfant à sortie bornée et lisible après coup
  OneShotCommand.swift      petits utilitaires d'exécution de processus
  JSONValue.swift           l'arbre JSON tolérant par lequel la configuration décode
Sources/dsh-bezel/          app et interface
  BezelApp.swift            point d'entrée, reflet de la langue, points d'entrée de fumée --dump-config / --dump-hosts
  Model/AppState.swift      colle configuration / enfant / WebView / sonde, état de connexion, formulation des notifications
  Model/Notifier.swift      livraison des notifications macOS et les deux règles de livraison
  Web/WebView.swift         hôte WKWebView, signalement d'état de navigation, canal du script observateur
  Web/SidebarProbe.swift    la page cachée qui lit la barre latérale complète
  UI/MainView.swift         barre d'outils, sélecteur de Host, invite de connexion, bandeau d'erreur
  UI/OnboardingView.swift   le guide de premier lancement
  UI/SettingsView.swift     gestion des Hosts et préférences de l'app (deux onglets)
Tests/BezelCoreTests/       normalisation d'adresses, analyse de ligne de démarrage, fichier et dépôt de config, localisation, signaux de page
```

## Contraintes connues

- **http en clair et ATS** : un Host peut être en `http://` sur le LAN, donc `Resources/Info.plist` pose `NSAllowsArbitraryLoadsInWebContent` (ne relâche que le contenu WebView ; les propres requêtes de l'app restent sous ATS). Placer un proxy inverse `https://` devant rend cela inutile.
- **Un Host distant doit admettre ce client** : le `/api` de dsh a une barrière de confiance navigateur qui accepte le loopback, un littéral IP LAN dérivé du déploiement, ou une autorité déclarée avec `--trusted-host`. Pour joindre un Host distant par nom de domaine, ce Host doit être démarré avec `--trusted-host`. Notez aussi que le CLI de `dsh web` refuse `--host 0.0.0.0` ; servir au-delà de la machine exige `host: '0.0.0.0` à la couche configuration.
- **Pas d'App Sandbox** : le mode géré engendre `dsh`, et les outils de session du harness exécutent déjà des commandes sur la machine de l'utilisateur, donc un bac à sable casserait ce modèle de confiance. Si vous ne vous connectez qu'à des Hosts externes, vous pouvez ajouter un sandbox et `com.apple.security.network.client` vous-même.
- **Périmètre** : cette app n'apporte aucune fonction propre à la conversation — ce que la Web UI a est ce que vous avez. Autour de l'écran, elle ajoute le sélecteur de Host, les notifications, les langues et le guide de premier lancement.
- **Prérequis** : un Host dsh capable de servir une Web UI. La ligne de démarrage de `dsh web` et l'échange `?token=` sont stables depuis 0.1.5-rc.1.

## Relation avec dsh-for-mac

`dsh-for-mac` prend l'autre route : réimplémenter le protocole câblé en Swift (RPC unaire + `/api/remote.mux` + le flux d'événements), ce qui donne une interaction entièrement native mais signifie suivre le protocole soi-même et assumer la dérive. Ce projet ne le fait délibérément pas. Les deux peuvent coexister ; les morceaux natifs que cette app ajoute réellement — les notifications, la barre de menus qui suit la langue — enveloppent la page sans toucher au modèle de connexion.

## Développement

```sh
swift build --disable-sandbox
swift test --disable-sandbox
swift run dsh-bezel --dump-config   # le fichier de configuration : son chemin, ou ce qu'il contient
swift run dsh-bezel --dump-hosts    # seulement les signets enregistrés
```

L'exécutable nu et le bundle partagent un fichier de configuration, donc une expérience avec `swift run` utilise votre vraie configuration, sauf si `BEZEL_CONFIG` pointe ailleurs. Le drapeau `--disable-sandbox` est requis pour construire sous le harness DSH, qui ne peut pas imbriquer son propre bac à sable.
