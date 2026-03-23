# Smart Display Control Room

## Lancer la vue de suivi

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-device-dashboard.ps1
```

Le dashboard expose par defaut `http://127.0.0.1:8765`.

## Workflow clean sur E:

1. `Provisionner WSL clean E:`
2. `Installer prerequis WSL`
3. `Bootstrap WSL 16.0`

Ou bien en un seul run:

1. `Workflow complet WSL 16.0`

## Ce que tu peux surveiller

- `WSL 16.0`: distro, chemin d'installation et artifact root actifs
- `Jobs`: statut live, code retour, log persistant
- `Artifacts 16.0`: presence de `boot.img`, `system.img`, `vendor.img`, `vbmeta.img`

## Logs persistants

- Dossier: `memory/dashboard-jobs`
- Chaque action garde un `.json` de statut et un `.log` texte

## Regle de portage

- Garder `slot a` comme baseline connue
- Reserve `slot b` aux essais Lineage 16
- Ne pas retester TWRP avant un boot Lineage 16 stable avec adb
