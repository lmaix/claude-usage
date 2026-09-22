# ClaudeUsageBar — design (v4, session Claude Code + barre Fable)

App macOS native de barre de menus affichant l'usage du plan Claude via l'API
d'usage OAuth, en réutilisant la session de Claude Code.

## Affichage (validé)
- Deux mini barres empilées : 5 h en haut, hebdo Fable en bas (repli : hebdo
  tous modèles). Largeur ajustée au pourcentage le plus large.
  Vert < 60 %, orange 60–85 %, rouge ≥ 85 %. « C! » orange sans données.
- Menu : une ligne par fenêtre renvoyée par l'API + reset, usage extra,
  « Mis à jour à », « Se connecter dans le Terminal… » (seulement en erreur),
  Quitter. Rien d'autre (demande explicite). Lancement au login automatique.

## Données
- `GET https://api.anthropic.com/api/oauth/usage`, Bearer +
  `anthropic-beta: oauth-2025-04-20`. Toutes les 60 s et au réveil.
- Parsing tolérant : chaque objet de premier niveau avec `utilization` est une
  fenêtre, sauf `extra_usage` et `seven_day_overage_included`.

## Authentification
- Lecture de l'élément Trousseau `Claude Code-credentials` (compte = user
  macOS), JSON `claudeAiOauth{accessToken, refreshToken, expiresAt, scopes}`.
- Le scope `user:profile` est requis. `claude setup-token` ne donne que
  `user:inference` → 401, donc écarté. `claude auth login` fournit tout.
- Renouvellement : POST `https://platform.claude.com/v1/oauth/token`
  `{grant_type: refresh_token, refresh_token, client_id: <client Claude Code>}`
  si expiration < 2 min ou sur 401, puis réécriture atomique des jetons dans
  le même élément Trousseau (les autres champs sont conservés).
- Historique : v2 (fichier local via status line) abandonnée — la status line
  ne transmet pas la limite par modèle et n'est pas exécutée par l'app
  desktop ; v3 (setup-token) abandonnée — scope insuffisant.

## Structure
- `Sources/UsageModel.swift`, `Sources/BarRenderer.swift`,
  `Sources/Keychain.swift` (purs, testés), `Sources/main.swift`,
  `Tests/main.swift`, `build.sh`.
