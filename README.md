# Feu Rouge

Feu tricolore dans la **barre de menus** macOS : une pastille par session d'agent
CLI ouverte — `codex`, Claude Code, Antigravity et Oh My Pi (`omp`).

| Pastille | État |
|---|---|
| 🟡 jaune | l'agent travaille (tour en cours, outil en train de tourner) |
| 🔴 rouge | l'agent attend une action de ta part (demande d'autorisation) |
| 🟢 vert  | session ouverte et disponible |
| ⚪ gris  | aucune session (pastille unique) |

La **forme** distingue l'agent, sans avoir à ouvrir le menu :

| Agent | Forme | Hooks | Rouge |
|---|---|---|---|
| codex | ● rond | `~/.codex/hooks.json` | oui (`PermissionRequest`) |
| Claude Code | ▢ carré arrondi | `~/.claude/settings.json` | oui (`Notification`) |
| Antigravity (`agy`) | ◆ losange | `~/.gemini/config/hooks.json` | **non** |
| Oh My Pi (`omp`) | ▲ triangle | `~/.omp/agent/extensions/feu-rouge.ts` | oui |

Le menu de chaque pastille donne `agent · projet — état`, le chemin complet, et
l'ouvre dans le Finder d'un clic.

> macOS ne permet pas d'ajouter un module tiers au **Centre de contrôle** :
> la barre de menus est la seule cible possible.

## Installation

```sh
git clone git@github.com:fiftycommit/feu-rouge.git
cd feu-rouge
./install.sh
```

Puis, **une seule fois**, dans une session codex : `/hooks` → touche `t` pour faire
confiance aux entrées `codex-feu-rouge-hook`. Claude Code et Antigravity ne
demandent aucune approbation.

Dans tous les cas, les hooks ne s'appliquent qu'aux **nouvelles** sessions : une
fenêtre déjà ouverte au moment de l'installation doit être relancée
(`codex resume --last` conserve la conversation).

`install.sh` :

- câble les hooks des trois agents, en sauvegardant chaque fichier existant en
  `.bak.<horodatage>` ; l'opération est idempotente, une réinstallation ne
  duplique rien ;
- installe le LaunchAgent `fr.max.feurouge` (`RunAtLoad`, `KeepAlive`) ;
- installe l’extension Oh My Pi dans `~/.omp/agent/extensions/` (ou
  `$PI_CODING_AGENT_DIR/extensions/` si défini) ;
- recompile l’app si les sources ont changé et la lance.

Une fois installé, rien n'est à refaire au redémarrage : réglages des hooks,
approbations codex et LaunchAgent sont tous persistés sur disque.

### Déplacer ou cloner ailleurs

`install.sh` inscrit le **chemin absolu** du dépôt dans les trois fichiers de
hooks et dans le LaunchAgent. Déplacer le dossier, ou le cloner sur une autre
machine, casse donc l'installation précédente : il faut relancer `./install.sh`
depuis le nouvel emplacement.

Et comme codex approuve ses hooks par un hash qui inclut la commande — chemin
compris — le changement de chemin **invalide les approbations**. Il faut refaire
`/hooks` une fois côté codex.

## Comment ça marche

Les hooks de chaque agent appellent `bin/codex-feu-rouge-hook <état> [agent]`,
qui écrit `~/.local/state/codex-feu-rouge/<agent>-<session>.json`.

| Événement | État écrit |
|---|---|
| `SessionStart` | vert |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse` | jaune |
| `PermissionRequest` | rouge |
| `Stop`, `Interrupt` | vert |
| `SessionEnd` | fichier supprimé |

L'app relit ce dossier toutes les 0,5 s et ne redessine que si l'état a changé.
Chaque fichier mémorise le PID du process de l'agent : si une session meurt sans
`SessionEnd` (crash, `kill`), l'app détecte le PID mort et nettoie — pas de
pastille fantôme. Un verrou `flock` garantit une seule instance de l'app.

### Particularités par agent

**Claude Code** n'a pas d'événement de permission dédié : son `Notification` sert
aussi bien à « j'ai besoin d'une autorisation » qu'à « j'attends ta saisie »,
ce dernier tirant après ~60 s d'inactivité. Le script tranche sur le contenu du
message ; sans ce tri, la pastille repassait au rouge juste après le vert de fin
de tour.

**Antigravity** utilise un schéma qui lui est propre : la clé de premier niveau
de `hooks.json` est le *nom* du hook (`feu-rouge`), les événements sont dedans,
et le hook doit répondre un objet JSON sur stdout. Il n'expose que cinq
événements (`PreInvocation`, `PreToolUse`, `PostToolUse`, `PostInvocation`,
`Stop`) : aucun ne signale une demande d'autorisation ni la fin d'une session.
Ses pastilles ne passent donc jamais au rouge et disparaissent à la mort du
process. Il n'envoie par ailleurs aucun dossier de travail (`workspacePaths`
arrive vide en CLI) : le projet est déduit du répertoire courant du process.

**Oh My Pi** utilise une extension TypeScript, chargée automatiquement au
lancement. `session_start` crée une pastille par processus principal ;
`agent_start` la passe au jaune et `agent_end` au vert. Les demandes
d’autorisation, les validations de plan et l’outil `ask` la passent au rouge
jusqu’à leur résolution. Les sous-agents n’ajoutent pas de pastille.
`session_shutdown` supprime l’état ; le PID permet aussi le nettoyage après
un arrêt brutal. Le nom du projet suit le dossier courant de la session.
Après installation, relancer OMP ou utiliser `/reload` dans une session ouverte.
L’extension est copiée et ne dépend pas du chemin du dépôt.

Le nom du script est resté `codex-feu-rouge-hook` et l'agent y est un argument
**optionnel** : les commandes codex sont ainsi restées identiques au caractère
près lors de l'ajout des deux autres agents, ce qui a préservé les approbations
existantes.

## Désinstallation

```sh
./uninstall.sh
```

## Fichiers

- `bin/codex-feu-rouge-hook` — pont hook → fichier d'état
- `extensions/feu-rouge.ts` — extension Oh My Pi → fichier d’état
- `src/main.swift` — app barre de menus (AppKit, sans dépendance)
- `build.sh` — compile `build/FeuRouge.app`
- `install.sh` / `uninstall.sh`

## Dépannage

- **Pastille invisible** : si la barre de menus est pleine, macOS range l'icône
  dans le débordement `•••`. Avec un gestionnaire type Bartender, ajouter
  `fr.max.feurouge-Item-0` … `-Item-N` à la liste « Show » (une entrée par
  pastille possible), sans quoi `special.AllOtherItems` les masque.
- **Pastille figée** : `ls ~/.local/state/codex-feu-rouge/` pour voir l'état brut.
- **Position de l'icône** : `FEUROUGE_DEBUG=1 ./build/FeuRouge.app/Contents/MacOS/FeuRouge`
  affiche les coordonnées des éléments (x négatif = masqué faute de place).
