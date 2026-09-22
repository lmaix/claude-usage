# ClaudeUsageBar

App macOS de barre de menus qui affiche l'usage du plan Claude : deux mini
barres (limite 5 h en haut, limite hebdo Fable en bas) avec leur pourcentage,
et un menu avec le détail de toutes les fenêtres, le temps avant reset et
l'usage extra.

## Installation

```bash
./build.sh
```

Compile, lance les tests, installe `~/Applications/ClaudeUsageBar.app`, la
démarre et l'inscrit au lancement à l'ouverture de session.

## Token (une seule fois)

1. Dans un Terminal : `claude setup-token` → copie le token `sk-ant-oat01-…`.
2. Clique sur l'icône « C! » → « Configurer le token… » → ⌘V ou
   « Coller depuis le presse-papiers ».

Le token est stocké dans ton Trousseau (service `ClaudeUsageBar`). Les
identifiants de Claude Code ne sont jamais lus ni modifiés.

## Détails

- Source : `GET https://api.anthropic.com/api/oauth/usage`, toutes les 60 s et
  au réveil de la machine.
- La 2e barre montre la fenêtre hebdo dont la clé contient « fable » ; à
  défaut, la fenêtre hebdo tous modèles.
- Couleurs : vert < 60 %, orange 60–85 %, rouge ≥ 85 %.
- Réponses inattendues consignées dans `~/Library/Logs/ClaudeUsageBar.log`.
