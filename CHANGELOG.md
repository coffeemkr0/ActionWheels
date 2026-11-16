# Changelog

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
