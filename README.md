# Mashawi Tycoon (مشاوي تايكون)

A 2.5D Dubai charcoal-grill (mashawi) stand business sim in the spirit of the classic
*Lemonade Tycoon*, built with **Godot 4.7** for Android (and desktop). Arabic (RTL) by
default with an English toggle on the title screen; prices in AED.

Buy supplies, tune your recipe and prices, pick a spot in Dubai, invest in your stand
and marketing, then open and watch the day play out on a low-poly Gulf street with
Emirati locals in kandura and abaya alongside residents and tourists.

## Stage 1: Dubai

| Place             | Rent    | Crowd                                      |
|-------------------|---------|--------------------------------------------|
| Al Fahidi Corner  | free    | quiet lane under the wind towers           |
| Creek Park        | AED 125 | families, weather sensitive                |
| Metro Station     | AED 200 | commuters in a hurry, won't wait           |
| JBR Beach         | AED 275 | tourists, drinks sell by the crate in heat |
| Downtown          | AED 450 | high standards, deep pockets               |
| Mall Food Court   | AED 600 | all-day crowds, fierce competition         |
| Global Village    | AED 500 | opens 16:00 to 24:00, fierce competition   |

Menu (Dubai cafeteria style, priced per skewer): Chicken Tikka, Mutton Tikka, Kebab, Tikka Sandwich, Mixed Grill Plate, Salad, Fries, Laban, Soda, Karak. Every grilled item burns charcoal.
Each dish can be enhanced up to three times. Grilled dishes use the meat / salad / sauce recipe.
Weather: sunny, heatwave, cloudy, sandstorm, winter breeze.

Progression: the Street Cart reaches Al Fahidi and Creek Park; the **Food Truck** (AED 2,500) opens the
Metro, JBR and Downtown; the **Big Grill Truck** (AED 7,000) opens the Mall Food Court and Global Village,
where rival stalls take over half your customers unless you promote (promotions count x1.8 to x2.0 there).
The **Sweets Counter** upgrade (needs the Food Truck) adds saffron milk cake, sago halwa and Omani halwa.

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
scripts/world     world.gd (Dubai street builder, Gulf architecture), cart.gd, customer.gd, gulf_person.gd, car.gd, model_lib.gd
scripts/ui        hud.gd (all panels), ui_theme.gd, icons.gd (3D model icons, weather glyphs)
assets/models     curated Kenney GLB kits (CC0)      raw/   full kits, ignored by Godot (.gdignore)
tests/            headless logic tests               tools/ check/shot/export/deploy scripts, GLB + Blender helpers
web/              custom HTML shell, Shopify embed snippet, static extras for the web build
```

## Credits

3D models (city, roads, nature, food, cars, Mini Characters), sounds: [Kenney](https://kenney.nl) (CC0).
Trees, bench, bush, rocks: [KayKit](https://kaylousberg.com) (CC0). Food models (spit, wrap, pita, salad, meat trays, mashawi platter, karak): generated with Blender (`tools/make_*.py`). Emirati characters: procedural (`gulf_person.gd`).
Font: Fredoka (SIL OFL).
