# ActionWheels

[![Tests](https://github.com/coffeemkr0/ActionWheels/actions/workflows/ci.yml/badge.svg)](https://github.com/coffeemkr0/ActionWheels/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Radial, customizable action bars for WoW Classic-era clients.** Press a key and a wheel of actions appears at your cursor. Click a slice to cast a spell, use an item, run a macro or command your pet. It works in combat.

> **Status: 0.1.0, milestone 1.** The secure wheel and slash-command setup work in code and tests, but have not been verified in the game client yet. Please report what you see.

## Install
1. Copy the `ActionWheels` folder into `Interface/AddOns/` (the folder name must be exactly `ActionWheels`).
2. Start the game. **Esc > Key Bindings > AddOns > ActionWheels** and bind **Action wheel (open / hold)**.

## Set up slots (for now)
| Command | Does |
|---|---|
| `/aw set 1 spell Aimed Shot` | Cast a spell |
| `/aw set 2 item Hearthstone` | Use an item |
| `/aw set 3 macro /cast Hunter's Mark` | Run macro text |
| `/aw set 4 pet attack` | Pet command: attack, follow, stay, passive, defensive, aggressive, assist |
| `/aw clear 3`, `/aw list`, `/aw slots 10` | Manage slots (4 to 12) |
| `/aw mode hold`, `/aw at center`, `/aw scale 1.2` | Open behaviour and size |
| `/aw reset` | Restore the starter wheel |

Changes made during combat are held back and applied when combat ends.

## How combat works
Spells, items and macros are protected in combat, so every slice is a secure action button and the key binding is a secure click handler. Because of that, slot contents, layout and icons can only change out of combat.

## Roadmap
1. **Done:** secure wheel, slot types, slash setup.
2. Cooldowns, charges, usable and range state on slices; sub-wheels and paging.
3. Drag and drop from the spellbook, right-click editor, wheel manager, import / export.
4. Minimap button, settings window, per-character wheels, auto-switch by stance.

## Development
```bash
pip install lupa
python tests/run_tests.py
scripts/package.sh
```
