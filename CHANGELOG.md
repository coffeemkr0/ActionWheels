# Changelog

## 0.14.5
- **Renaming a wheel now sticks.** The wheel name box (and the "Opens first when" condition box) only saved when you pressed Enter; clicking away lost the change. They now save as soon as you leave the box (Enter, Tab or clicking elsewhere), and Escape cancels.

## 0.14.4
- **Fix: error when clicking Delete (and Restore starter wheel) in the settings window.** Both buttons use a three-second "click again to confirm" timer that was never defined. It is now, and the test run fails if any `AW.*` function is called but not defined.

## 0.14.3
- **The key now opens the last wheel you used by default**, and remembers it across `/reload` and relogging. (It was opening the wheel selected in the editor, because that was the default; an existing profile is switched once. You can still choose *The wheel I'm editing* in Settings > *The key opens*.) An auto-open condition such as `[mounted]` still wins while it holds.
- **The mouse wheel no longer wraps around:** scrolling stops at the first and last wheel. The hub arrows and the next / previous keys still wrap.

## 0.14.2
- **The cooldown strip can be dragged from any of its icons.** Shift + drag always moves it (even when locked); a plain drag works while it is unlocked. Hovering an icon shows the spell's tooltip and a "Shift + drag" hint.

## 0.14.1
- **Tooltips on the wheel.** Hovering a slice shows the game's own tooltip for a spell or item (a `#showtooltip` macro shows the tooltip of the spell it points at). Macros list their lines, and pet commands and sub-wheel links get a short description. Turn them off in Look > *Show tooltips when hovering a slot* or with `/aw tooltips`.

## 0.14.0
- **Cooldown strip.** A small on-screen row of icons, visible with the wheel closed, showing spell cooldowns with a swirl and countdown, and a flash (optionally a sound) when a spell is ready again. Tick **On the cooldown strip** on any spell slot to always show it; spells with long cooldowns (30 seconds by default, adjustable) are added automatically while they cool down. Movable, lockable, resizable, four growth directions; Tracker tab and `/aw tracker [lock|unlock|reset]`. It is not clickable, so it works in combat (cooldowns in combat use the game's duration objects). Spells only for now.

## 0.13.2
- **Fix: spell cooldowns now show in combat.** In combat the game hides the cooldown numbers from addons, and passing them to the swirl did not work. ActionWheels now asks the game for a cooldown *duration object* and gives that to the swirl, which the game does allow. (Item cooldowns in combat still use the old way and may not show; `/aw debug` prints a "slice display problem" line if the game refuses anything.)

## 0.13.1
- **A wheel opened from an action bar button now opens at the screen centre** (the bar sits at the screen edge, so opening at the cursor pushed it off-screen). Setting: Settings > *Action bar buttons open*, or `/aw barat cursor|center`. The on-screen buttons still follow *Opens at*.

## 0.13.0
Ideas taken from ReactWheel:
- **Right-click a slice on the wheel** for *Edit slot...*, *Swap with another slot...* and *Clear slot* (out of combat).
- **Reorder and copy wheels:** editor buttons *Move <*, *Move >* and *Copy wheel*, plus `/aw wheel move up|down` and `/aw wheel copy`. Slots also swap with their neighbours (*Swap <  >*, `/aw swap a b`).
- **Border colour per slot** (None, White, Green, Red, Pink, Blue, Gold, Purple). Imported wheels keep colours.
- **Sounds:** an optional soft tick between slices and a click on use (Look tab, `/aw sounds`). Off by default.
- **Text size and centre-controls size** sliders in a new **Look** tab (which now also holds button size, ring radius and wheel scale).
- **`/aw open [first|last|<wheel>]`** opens a wheel from chat, out of combat.
- README gets a Troubleshooting table.

## 0.12.0
- **The key can open the last wheel you used** (Settings > *The key opens*, or `/aw opens last`). The default is still the wheel you are editing. An auto-open condition such as `[mounted]` still wins while it holds.
- **Mouse wheel switches wheels** while the wheel is open (scroll up = previous). Works in combat. Settings has an on/off switch and a *reverse direction* option (`/aw scroll on|off|reverse`). When switched off the mouse wheel passes through to the game again (camera zoom).

## 0.11.0
- **The on-screen button now opens the last wheel you used** (the wheel you were on when you last opened or paged), and there is a matching macro line, `/click ActionWheelsOpenLast`.
- **A movable on-screen button for each wheel** (editor > Wheels tab, or `/aw launcher wheel`). Each remembers its own position and follows its wheel if wheels are reordered.
- **Put them on an action bar:** the editor's **Put on action bar** button (and Settings > **Last wheel -> bar**, `/aw macro`) creates a small macro that clicks the right button and puts it on your cursor, ready to drop on a bar slot.
- `/aw launcher [wheel|lock|unlock|reset]`. Shift + drag moves buttons; lock applies to all of them.

## 0.10.0
- **Open the wheel with the mouse.** `/click ActionWheelsOpen` in a macro on any action bar opens the wheel (and `ActionWheelsOpen2` ... `8` open that wheel directly). An optional **on-screen button** (`/aw launcher` or Settings) does the same and can be moved with Shift + drag and locked. Both are secure click handlers, so they work in combat, and they act once per click whether the client sends a press, a release or both.

## 0.9.0
- **Auto key behaviour.** One keybind that acts as *hold to show* in combat and *press to open / press to close* out of combat. Choose it in Settings > Key behaviour, or `/aw mode auto`. The switch follows the game's combat state through a secure state driver, so it works without any addon code running in combat.

## 0.8.0
- **Square buttons.** The round discs and rings behind the slices are gone: each slice is now a square icon with a thin square border (gold while active), and the hover, pressed and click-flash overlays are square too. The editor preview matches. The centre hub stays round. Neighbouring buttons are spaced so even square corners never overlap.

## 0.7.1
- **Fix: gold highlight stuck on the wrong Aspect in combat.** If the game refused one part of a slice's display in combat (the cooldown swirl or count), the update stopped halfway and left the old highlight behind. The highlight and tint are now applied first, and the cooldown and count each fail on their own. With `/aw debug` on, such a failure prints a "slice display problem" line.

## 0.7.0
- **A spell slice stays open until the spell actually casts**, so you can keep clicking it when a cast gets blocked (auto-attack, global cooldown...). Out of combat the wheel closes once the cast is confirmed. In combat the game does not let an addon hide the wheel, so a spell slice stays open there: close it with your key or by clicking outside. Item, macro and pet slices still close on click.
- New setting **After clicking a spell**: *Close when it casts* (default), *Close right away* (the old behaviour) or *Stay open*. Also `/aw close success|click|never`.
- **Click feedback:** the slice darkens while the mouse is down, flashes white when the click registers and green when the cast is confirmed.

## 0.6.1
- **All Hunter Aspects share the active icon.** The starburst the bars show for an active Aspect is the same for every Aspect, so ActionWheels uses one icon for the whole family. It is built in (no learning step), and anything learned from your bars replaces it.

## 0.6.0
- **Active spells show their active icon, with or without an action bar.** The game swaps an Aspect's action-bar picture while it is active (your inspect output: bar icon 136116 vs the normal 136076) but no spell lookup reports it. ActionWheels now learns that icon whenever it can see it (from the bar slot, or the buff's own icon, out of combat), saves it, and shows it while the spell is active - in combat and for spells that are on no bar. The first time you have an Aspect up out of combat, it learns that Aspect.
- `/aw inspect` also shows the buff's icon and what has been learned.

## 0.5.4
- `/aw inspect <spell>` prints what the game reports about a spell: its icon from each lookup, any override, whether it is active, and (if on a bar) the bar slot's icon and checked state. A diagnostic for icon mismatches.

## 0.5.3
- **Spell slices mirror the built-in action bar.** When a spell is on one of your action bars, its slice now uses that bar slot's own icon (so it matches what the bar shows, including icon changes while an Aspect is active) and treats the bar's "checked" state as active. A spell that is not on any bar behaves as before.

## 0.5.2
- **Spell and item slices follow the live icon.** Like action-bar spell buttons, a slice re-reads its spell's icon while the wheel is open, so it changes when the game replaces or transforms the spell (override spells are resolved too). A slot with an icon you chose yourself keeps it.

## 0.5.1
- **Active slices look like the built-in action bars.** A slice whose buff is on (for example your active Aspect) now gets the game's own gold "checked" highlight over the icon and a gold frame, instead of the green ring.

## 0.5.0
- **`#showtooltip` for macro slots.** A macro slot whose text has `#showtooltip Spell` (or `/showtooltip`, or a bare `#showtooltip` meaning the first `/cast` or `/use`) now shows that spell's or item's icon, cooldown, charges, usable and range state, and the active-buff glow. Conditionals such as `#showtooltip [mod:shift] Spell A; Spell B` are evaluated live while the wheel is open. Remove the line to use a custom icon.

## 0.4.6
- **Fix: the active-Aspect highlight reverting a few seconds into combat.** Once the game starts hiding buffs, "nothing found" was being read as "buff is off". In combat a lookup can now only confirm a buff; a buff is turned off only by a removal event for one we tracked, or by you casting another Aspect. Only one Aspect can be on at a time.
- `/aw buffs` also prints the last buff changes and what caused each.

## 0.4.5
- **Fix: the active-Aspect highlight did not follow a new Aspect cast in combat.** The game hides the spell id of your casts in combat, so the cast could not be matched to a spell. ActionWheels now remembers which slice you clicked and treats the next successful cast as that spell.
- `/aw buffs` prints what each buff lookup returns for every spell slot; `/aw debug` also reports cast confirmations.

## 0.4.4
- **More accurate active-buff highlight in combat.** Asks the game's targeted player-buff lookup (`C_UnitAuras.GetPlayerAuraBySpellID`) first, which is exempt from the combat secrecy rules for your own buffs, and trusts an empty answer only when the game says the buff is readable. Buff removals are tracked through the never-secret `auraInstanceID`, and your own casts still fill in what the game hides. Outside combat nothing changes.

## 0.4.3
- **Fix: the active-Aspect highlight in combat.** The game stops reporting buffs to addons in combat, so the highlight went blank. ActionWheels now remembers which buffs were on before combat and follows your own successful casts during it (casting an Aspect turns the other Aspects off).

## 0.4.2
- **Fix: the wheel now closes after a click in combat.** The old close step ran inside a click wrapper that did not work. Each slice is now a secure macro that ends with `/click ActionWheelsClose` (a secure button that hides the wheel), and sub-wheel slices use `/click ActionWheelsGo<n>`. No more click wrapping.

## 0.4.1
- **Fix: errors in combat** ("attempt to compare ... a secret number value"). In combat the game hides cooldown numbers from addons. ActionWheels now hands them straight to the cooldown swirl without comparing them, ignores charges / usable / range when the game hides those too, and can no longer raise an error from the live display.

## 0.4.0
- **Active buffs are highlighted.** A spell slice whose buff is on you (for example your current Hunter Aspect) gets the action bar's gold "checked" highlight and frame while the wheel is open.

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
