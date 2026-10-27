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
| Global Village    | AED 350 | opens 16:00 to 24:00, lanterns & crowds    |

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

# logic tests (headless)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --tests

# 30-day balance simulation (headless, prints a table)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --autodays=30

# screenshot a phase (for review without touching the editor)
tools/shot.sh out.png 4 --phase=prep --panel=menu
tools/shot.sh out.png 10 --phase=day --location=jbr --weather=hot --speed=4
```

Dev flags (after `--`): `--phase=title|prep|day|report`, `--panel=supplies|menu|place|upgrades|promote`,
`--location=fahidi|creek|metro|jbr|downtown|mall|gv`, `--vehicle=cart|truck|truck2`, `--weather=sunny|hot|cloudy|sandstorm|breeze`, `--speed=<n>`, `--upgrades=a,b,c`, `--money=<n>`,
`--screenshot=<path> --delay=<s>`.

## Android

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-debug Android build/mashawi-tycoon.apk
adb install -r build/mashawi-tycoon.apk
```

The export preset (`export_presets.cfg`) targets arm64 and uses the debug keystore configured
in the Godot editor settings. Switch `package/signed` + a release keystore for store builds.

## Project layout

```
scripts/core      data.gd (all tuning tables), economy.gd (pure formulas), game.gd (state + save)
scripts/sim       day_sim.gd (clock, passers-by, queue, sales, reactions)
scripts/world     world.gd (Dubai street builder, Gulf architecture), cart.gd, customer.gd, gulf_person.gd, car.gd, model_lib.gd
scripts/ui        hud.gd (all panels), ui_theme.gd, icons.gd (3D model icons, weather glyphs)
assets/models     curated Kenney GLB kits (CC0)      raw/   full kits, ignored by Godot (.gdignore)
tests/            headless logic tests               tools/ screenshot + GLB inspection helpers
```

## Credits

3D models (city, roads, nature, food, cars, Mini Characters), sounds: [Kenney](https://kenney.nl) (CC0).
Trees, bench, bush, rocks: [KayKit](https://kaylousberg.com) (CC0). Food models (spit, wrap, pita, salad, meat trays, mashawi platter, karak): generated with Blender (`tools/make_*.py`). Emirati characters: procedural (`gulf_person.gd`).
Font: Fredoka (SIL OFL).
