# Feu Rouge Codex

Pastille tricolore dans la **barre de menus** macOS, qui reflète l'état des sessions
`codex` CLI ouvertes.

| Pastille | État |
|---|---|
| 🟡 jaune | codex travaille (tour en cours, outil en train de tourner) |
| 🔴 rouge | codex attend une action de ta part (demande d'autorisation) |
| 🟢 vert  | au moins une session ouverte et disponible |
| ⚪ gris  | aucune session codex |

Quand plusieurs sessions tournent, la pastille montre la plus « urgente »
(rouge > jaune > vert). Le menu déroulant détaille chaque session par projet.

> macOS ne permet pas d'ajouter un module tiers au **Centre de contrôle** :
> la barre de menus est la seule cible possible.

## Comment ça marche

Les **hooks** de codex CLI (≥ 0.153) écrivent l'état dans
`~/.local/state/codex-feu-rouge/<session_id>.json` :

| Hook | État écrit |
|---|---|
| `SessionStart` | vert |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse` | jaune |
| `PermissionRequest` | rouge |
| `Stop`, `Interrupt` | vert |
| `SessionEnd` | fichier supprimé |

L'app relit ce dossier toutes les 0,5 s. Chaque fichier mémorise le PID du process
codex parent : si une session meurt sans `SessionEnd` (crash, `kill`), l'app détecte
le PID mort et nettoie — pas de pastille fantôme.

## Installation

```sh
./install.sh
```

Puis, **une seule fois**, dans une session codex : `/hooks` → faire confiance aux
entrées `codex-feu-rouge-hook`. Les hooks ne s'appliquent qu'aux **nouvelles**
sessions codex.

`install.sh` :
- crée/complète `~/.codex/hooks.json` (sauvegarde `.bak.<ts>` si le fichier existait) ;
- installe un LaunchAgent `fr.max.feurouge` (relance l'app à l'ouverture de session) ;
- lance l'app.

## Désinstallation

```sh
./uninstall.sh
```

## Fichiers

- `bin/codex-feu-rouge-hook` — script appelé par les hooks, écrit l'état
- `src/main.swift` — app barre de menus (AppKit, sans dépendance)
- `build.sh` — compile `build/FeuRouge.app`

## Dépannage

- **Pastille invisible** : si la barre de menus est pleine, macOS range l'icône dans
  le débordement `•••` (à gauche de la batterie). Cliquer dessus, ou masquer un autre
  élément dans Réglages → Barre des menus.
- **Pastille figée** : `ls ~/.local/state/codex-feu-rouge/` pour voir l'état brut.
- **Position de l'icône** : `FEUROUGE_DEBUG=1 ./build/FeuRouge.app/Contents/MacOS/FeuRouge`
  affiche les coordonnées de l'élément (x négatif = masqué faute de place).

## Agents pris en charge

| Agent | Forme | Configuration des hooks | Rouge (attente d'une action) |
|---|---|---|---|
| codex | rond | `~/.codex/hooks.json` | oui (`PermissionRequest`) |
| Claude Code | carre arrondi | `~/.claude/settings.json` | oui (`Notification`) |
| Antigravity (`agy`) | losange | `~/.gemini/config/hooks.json` | **non** |

Antigravity n'expose que cinq evenements (`PreInvocation`, `PreToolUse`,
`PostToolUse`, `PostInvocation`, `Stop`), aucun ne signalant une demande
d'autorisation ni la fin d'une session. Ses pastilles ne passent donc jamais au
rouge, et disparaissent quand le process meurt plutot que sur un `SessionEnd`.
Son `hooks.json` suit un schema qui lui est propre : la cle de premier niveau
est le *nom* du hook (`feu-rouge`), les evenements sont dedans, et le hook doit
repondre un objet JSON sur stdout.

Seul codex demande une approbation explicite des hooks (`/hooks`, touche `t`).
