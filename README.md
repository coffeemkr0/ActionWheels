# ActionWheels

[![Tests](https://github.com/coffeemkr0/ActionWheels/actions/workflows/ci.yml/badge.svg)](https://github.com/coffeemkr0/ActionWheels/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Radial, customizable action bars for WoW Classic-era clients (Interface 16001).** Press a key and a wheel of actions appears at your cursor. Click a slice to cast a spell, use an item, run a macro, command your pet or open another wheel. It works in combat.

> **Status: 0.3.0 (feature complete, not yet verified in the game client).** The logic is covered by tests, but the secure-frame behaviour has to be confirmed in-game. Please report what you see.

## Install
1. Copy the `ActionWheels` folder into `Interface/AddOns/` (the folder name must be exactly `ActionWheels`).
2. Start the game. Press **Esc > Key Bindings > AddOns > ActionWheels** and bind **Action wheel (open / hold)**. (`/aw keys` opens the key bindings.)
3. Type `/aw` (or click the minimap button) to open the editor.

## Using the wheel
- **Open:** press your key. Toggle mode: press again to close. Hold mode: the wheel shows while the key is held (`Settings > Key behaviour`).
- **Click a slice** to run it. Item, macro and pet slices close the wheel right away. A **spell** slice stays open until the spell actually casts (so you can keep clicking if the first try is blocked), then closes; in combat the game won't let an addon hide the wheel, so close it with your key or by clicking outside. Change this under Settings > *After clicking a spell* or `/aw close success|click|never`. The slice darkens while pressed, flashes white on click and green when the cast is confirmed.
- Click outside the wheel to close it.
- **More than one wheel:** use the `<` `>` arrows in the centre, or bind **Next wheel / Previous wheel**. A slot can open another wheel; that wheel has a **back** button.
- Each slice shows its **cooldown**, **charges / item count**, and is **grey** when unusable, **blue** without mana and **red** when your target is out of range.

## `#showtooltip` macros
A macro slot whose text starts with `#showtooltip Aimed Shot` (or just `#showtooltip`, meaning the first `/cast` or `/use`) shows that spell's icon, cooldown, charges, usable / range state and active-buff glow. Conditionals work and are evaluated live while the wheel is open, e.g. `#showtooltip [mod:shift] Hunter's Mark; Aimed Shot`. Remove the line to use your own icon.

## Setting up slots
Open the editor (`/aw` or the minimap button), **Wheels** tab:
- **Drag a spell** from your spellbook, an **item** from your bags or a **macro** onto a slot in the ring. This also works on the real wheel while it is open.
- Or click a slot and fill in the form: type (Spell / Item / Macro / Pet / Wheel), value, optional label and icon.
- Use **New / Delete**, the `<` `>` picker and the `-` `+` buttons to manage wheels and their size (4 to 12 slots, up to 8 wheels).
- **Opens first when:** a macro condition such as `[mounted]`, `[combat]` or `[stance:1]` makes that wheel open first while it holds. Otherwise the wheel you are editing opens first.

**Settings** tab: open behaviour and position, button size, ring radius, wheel scale, the minimap button, separate wheels for this character, key bindings, restore the starter wheel. **Share** tab: export one or all wheels as text and import them (macros from an import are shown to you first).

### Slash commands
| Command | Does |
|---|---|
| `/aw` | Open the editor |
| `/aw set 1 spell Aimed Shot` | Cast a spell |
| `/aw set 2 item Hearthstone` | Use an item |
| `/aw set 3 macro /cast Hunter's Mark` | Run macro text |
| `/aw set 4 pet attack` | Pet command: attack, follow, stay, passive, defensive, aggressive, assist |
| `/aw set 8 wheel Extra` | A slot that opens another wheel (name or number) |
| `/aw clear 3`, `/aw list`, `/aw slots 10` | Manage slots |
| `/aw wheels`, `/aw wheel new Name` / `select <n>` / `rename Name` / `delete` | Manage wheels |
| `/aw wheel auto [mounted]` (or `off`) | Open the selected wheel first when a condition holds |
| `/aw mode hold`, `/aw at center`, `/aw scale 1.2` | Open behaviour and size |
| `/aw minimap`, `/aw keys`, `/aw reset` | Minimap button, key bindings, restore the starter wheel |

## How combat works
Spells, items and macros are protected in combat, so every slice is a secure action button and the key binding is a secure click handler. Opening, closing, switching wheels and running slices all work in combat. **Editing is locked in combat**: the editor closes when combat starts and changes made by command wait until combat ends.

## Development
```bash
pip install lupa
python tests/run_tests.py
scripts/package.sh
```
Releases: push a `v*` tag and the workflow attaches `ActionWheels-<version>.zip`.
