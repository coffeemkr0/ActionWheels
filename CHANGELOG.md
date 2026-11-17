# Changelog

## 0.4.2
- **Fix: the wheel now closes after a click in combat.** The old close step ran inside a click wrapper that did not work. Each slice is now a secure macro that ends with `/click ActionWheelsClose` (a secure button that hides the wheel), and sub-wheel slices use `/click ActionWheelsGo<n>`. No more click wrapping.

## 0.4.1
- **Fix: errors in combat** ("attempt to compare ... a secret number value"). In combat the game hides cooldown numbers from addons. ActionWheels now hands them straight to the cooldown swirl without comparing them, ignores charges / usable / range when the game hides those too, and can no longer raise an error from the live display.

## 0.4.0
- **Active buffs are highlighted.** A spell slice whose buff is on you (for example your current Hunter Aspect) gets a bright green ring and a soft glow while the wheel is open.

## 0.3.3
- The wheel now also closes from plain Lua after a click when you are out of combat (the secure close step did not work in testing). In combat it still relies on the secure step; `/aw debug` now shows whether that step ran.

## 0.3.2
- **Fix: the wheel now closes after a slice is clicked.** The close step read the click's press/release state in a place where it isn't available, so it never ran.

## 0.3.1
- **Fix: clicking a slice did nothing and left the wheel open.** Slices only listened for the mouse release, and newer clients ignore that when "cast on key press" is on. They now listen for both and act on the release, so the setting doesn't matter.
- `/aw debug` prints what a slice received when you click it.

## 0.3.0 (milestones 3 and 4)
- **Editor window** (`/aw` or the minimap button): a preview ring you can drop onto, a slot form (type, value, label, icon), wheel picker with New / Delete / rename / slot count. Locked in combat.
- **Drag and drop** spells, items, macros and pet bar buttons onto a slot, in the editor or on the open wheel.
- **Settings tab:** key behaviour, open position, button size, radius, scale, minimap button, key bindings button, restore the starter wheel.
- **Share tab:** export / import wheels as text. Imports are strictly validated and macros are shown for confirmation.
- **Separate wheels per character** (optional).
- **Auto-open wheel:** a macro condition (for example `[mounted]`, `[stance:1]`, `[combat]`) decides which wheel opens first, switched by a secure state driver so it works in combat.
- **Minimap button**: left-click for the editor, right-click to pick a wheel to edit.
- First-run hint to bind a key.

## 0.2.0 (milestone 2)
- **Live slice state:** cooldown swirl (the global cooldown is ignored), spell charges and item counts, grey-out when unusable, blue when out of mana, red when the target is out of range. Works in combat.
- **Multiple wheels and sub-wheels:** `/aw wheel new|select|rename|delete`, up to 8 wheels. A slot can open another wheel (`/aw set 8 wheel Extra`) and the sub-wheel gets a **back** button.
- **Paging:** hub arrows, plus key bindings for **Next wheel** and **Previous wheel** while the wheel is open. The wheel you are editing always opens first.
- All of the above switches pages through secure code, so it works in combat.

## 0.1.0 (first milestone)
- Secure radial wheel that opens, closes and acts in combat.
- Slice types: spell, item, macro and pet command.
- Open by toggle or hold, at the cursor or screen centre.
- `/aw` slash commands to fill slots until the drag-and-drop editor arrives.
