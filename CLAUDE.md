# Mashawi Tycoon - working notes

Godot 4.7 project (GDScript), mobile renderer, landscape, Android export preset in `export_presets.cfg`.
Godot binary on this Mac: `/Applications/Godot.app/Contents/MacOS/Godot`.

## Verify changes
- Compile check first: `tools/check.sh` (must print `all scripts parse`). A script error otherwise hangs headless runs; use `--quit-after N` as a safety net.
- Logic tests: `Godot --headless --path . -- --tests` (must print `0 failed`).
- Balance: `Godot --headless --path . -- --autodays=25` prints a day table; day-1 profit should be mildly positive.
- Visual: `tools/shot.sh out.png <delay> --phase=day --location=creek --speed=4` then look at the PNG.
- After adding assets run `Godot --headless --path . --import` once. `tools/unused_assets.sh` lists models nothing references (`--delete` removes them; originals stay in `raw/`).
- Exports: `--export-release Android build/mashawi-tycoon-release.apk` (keystore creds in `.godot/export_credentials.cfg`, never committed); `tools/export_web.sh` + `tools/serve_web.sh` + `node tools/web_smoke.mjs` for the web build; `tools/deploy_web.sh` pushes it to `gh-pages`.

## Conventions
- All tuning lives in `scripts/core/data.gd` (AED); formulas in `scripts/core/economy.gd` (static, pure).
- Every visible string is a key in `assets/i18n/strings.csv` (en, ar); use `tr(key)` and `Loc.money(v)`. Arabic is RTL: build UI with containers, never hard-coded x offsets.
- UI is built in code (`scripts/ui/hud.gd` + `ui_theme.gd`), no .tscn UI. Keep touch targets >= 48 px.
- World is data-driven per location layout in `scripts/world/world.gd`. Kenney building footprints are in `BUILDING_DIMS`.
- `raw/` holds full Kenney kits and is ignored by Godot (`.gdignore`); copy only what is used into `assets/models/`.
- Model inspection: `cd tools && node inspect-glb.mjs <file.glb>` (prints size, origin, tris, animations).
