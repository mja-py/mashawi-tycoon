# Mashawi Tycoon (مشاوي تايكون)

A 2.5D Dubai charcoal-grill (mashawi) stand business sim in the spirit of the classic
*Lemonade Tycoon*, built with **Godot 4.7** for Android (and desktop). Arabic (RTL) by
default with an English toggle on the title screen; prices in AED.

Copyright (c) 2026 Mohammad Jassem. All rights reserved. This is a proprietary game;
see [LICENSE.txt](LICENSE.txt) for permitted use and third-party asset exceptions.
The in-game **Credits** button contains the attribution notice.

New games include a hands-on mentor who stays beside the real game. She responds to
recipe and price edits, ingredient purchases, a customer's order and handoff, and
the first day's report. Then she helps you review an upgrade, decide whether to
promote, and work toward stars and rewards. Purchases remain your choice.
Progress saves automatically. Pause the guidance whenever you like, then resume
from **Settings → How to play → Play with me**. The eight reference chapters are
also available in Arabic and English; reading them pauses the street.

The approved plum Creek abaya character anchors the cast's style. The guide's charcoal
abaya and the teal souq outfit share her sculpt, face and rig; clothing palettes add no
duplicate model downloads. The male vendor uses the mature Creek kandura character.
Active character files are approximately 0.62–0.85 MB each, with lossless atlas imports
to prevent dark or white facial seams. The guide uses a bounded,
supersampled portrait and real-time animation independent of trading speed.
Normal play, 2×, 4× and Skip share the same business simulation; readable service
beats slow the whole clock together, so faster play does not penalize sales.

Buy supplies, tune your recipe and prices, pick a spot in Dubai, invest in your stand
and marketing, then open and watch the day play out on a low-poly Gulf street with
Emirati locals in kandura and abaya alongside residents and tourists.

## Stage 1: Dubai

| Place             | Rent    | Crowd                                      |
|-------------------|---------|--------------------------------------------|
| Souk Al Seef      | free    | heritage Creek promenade and local shoppers |
| Creek Park        | AED 125 | families, weather sensitive                |
| Metro Station     | AED 200 | commuters in a hurry, won't wait           |
| JBR Beach         | AED 275 | tourists, drinks sell by the crate in heat |
| Downtown          | AED 450 | high standards, deep pockets               |
| Mall Food Court   | AED 600 | all-day crowds, fierce competition         |
| Global Village    | AED 500 | opens 16:00 to 24:00, fierce competition   |

Menu (Dubai cafeteria style, priced per skewer): Chicken Tikka, Mutton Tikka, Kebab, Tikka Sandwich, Mixed Grill Plate, Salad, Fries, Laban, Soda, Karak. Every grilled item burns charcoal.
Each dish can be enhanced up to three times. Grilled dishes use the meat / salad / sauce recipe.
Weather: sunny, heatwave, cloudy, sandstorm, winter breeze.

Progression: cart → stall (AED 2,000) → truck (AED 6,000), followed by location-owned
kiosks, restaurants and flagships. The Metro and JBR require a stall plus reputation;
Downtown, the Mall and Global Village require a truck plus reputation. Promotions
have a stronger effect against Mall and Global Village competition (x1.8 and x2.0).
The truck can fit a sweets counter; buy it, unlock the dishes, then stock ingredients
for saffron milk cake, sago halwa and Omani halwa.

Strings live in `assets/i18n/strings.csv` (keys, en, ar); all data names are keys.

## Run

```sh
# desktop
/Applications/Godot.app/Contents/MacOS/Godot --path .

# compile-check every script, logic tests, 25-day balance simulation (all headless)
tools/check.sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --tests
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --autodays=25

# screenshot a phase (for review without touching the editor)
tools/shot.sh out.png 4 --phase=prep --panel=menu --lang=en
tools/shot.sh out.png 10 --phase=day --location=gv --vehicle=truck2 --weather=sandstorm --speed=4
```

Dev flags (after `--`): `--phase=title|prep|day|report`, `--panel=supplies|menu|place|upgrades|promote`,
`--location=fahidi|creek|metro|jbr|downtown|mall|gv`, `--vehicle=cart|truck|truck2`,
`--weather=sunny|hot|cloudy|sandstorm|breeze`, `--lang=ar|en`, `--speed=<n>`, `--upgrades=a,b,c`,
`--money=<n>`, `--screenshot=<path> --delay=<s>`, `--gallery=<models folder>`.

## Android (release APK)

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release Android build/mashawi-tycoon-release.apk
adb install -r build/mashawi-tycoon-release.apk
```

Signing uses the release keystore at `~/keystores/mashawi-release.jks` (alias `mashawi`); the path and
password live in `.godot/export_credentials.cfg`, which is not committed. **Back up the keystore and
`~/keystores/README.txt`**: without them a published app can never be updated. Bump `version/code` in
`export_presets.cfg` before every store upload. Release size is about 30 MB (arm64); ~26 MB of that is
the Godot engine itself, so only a custom-built export template would go lower.

## Web (GitHub Pages + Shopify)

The Web preset is a single-threaded build (`variant/thread_support=false`), so it needs no special
headers and runs on GitHub Pages, inside a Shopify iframe and in iPhone Safari / web views.
`web/shell.html` is the custom page: download first, a **Play** tap starts the engine (this is what
unlocks audio on iOS), and a "rotate your phone" overlay blocks portrait on phones.

```sh
tools/export_web.sh          # -> build/web (index.html, .wasm ~39 MB raw / ~10 MB gzipped, .pck ~3.5 MB)
tools/serve_web.sh           # http://localhost:8080/  (test on an iPhone on the same Wi-Fi: http://<mac-ip>:8080/)
node tools/web_smoke.mjs     # headless Chrome smoke test (needs `cd tools && npm i` once)
```

Publish:
1. Create an empty GitHub repository and add it as `origin` (`git remote add origin <url>`).
2. `tools/deploy_web.sh` exports and force-pushes `build/web` to the `gh-pages` branch.
3. GitHub: Settings > Pages > Deploy from a branch > `gh-pages` / root. The game is then at
   `https://mja-py.github.io/mashawi-tycoon/`.
4. Shopify: Online Store > Pages > your page > Add section > **Custom Liquid**, paste
   `web/shopify-section.html` (the address is already filled in). Desktop visitors get the game
   inline after clicking Play; phones open it full-page in a new tab.

## Project layout

```
scripts/core      data.gd (all tuning tables), economy.gd (pure formulas), game.gd (state + save)
scripts/sim       day_sim.gd (clock, passers-by, queue, sales, reactions), fast_sim.gd (headless balance)
scripts/world     world.gd (Dubai street builder), gulf_arch.gd, souq_scenery.gd, cart.gd, customer.gd, car.gd, model_lib.gd
scripts/ui        hud.gd (all panels), ui_theme.gd, icons.gd (3D model icons, weather glyphs)
assets/models     game models and third-party GLBs   raw/   source assets, ignored by Godot (.gdignore)
tests/            headless logic tests               tools/ check/shot/export/deploy scripts, GLB + Blender helpers
web/              custom HTML shell, Shopify embed snippet, static extras for the web build
```

## Copyright and credits

© 2026 Mohammad Jassem. All rights reserved. The proprietary end-user license
permits personal play of authorized releases. Reuse of original game code,
artwork, and models requires separate permission where copyright applies.
[License and third-party notices](LICENSE.txt)

The game includes CC0 assets from [Kenney](https://kenney.nl) and [KayKit](https://kaylousberg.com).
Custom food models are made with Blender (`tools/make_*.py`). Meshy-assisted models
are adapted for the game. The game uses [Baloo Bhaijaan 2](assets/fonts/OFL-BalooBhaijaan2.txt)
under the SIL Open Font License 1.1.
