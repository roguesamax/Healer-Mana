# HealerManaTracker

A lightweight WoW addon that shows healer mana percentages in a movable vertical list.

## Install
1. Put the addon folder in:
   - `World of Warcraft/_retail_/Interface/AddOns/`
2. Final structure must look like:
   - `.../AddOns/<AddonFolder>/<MatchingName>.toc`
   - `.../AddOns/<AddonFolder>/HealerManaTracker.lua`
3. Restart WoW or run `/reload`.

## Usage
- `/hmt` or `/healermana`
  - Opens/closes the config panel.
- `/hmt unlock`
  - Unlocks tracker frame so you can drag it.
- `/hmt lock`
  - Locks tracker frame in place.
- `/hmt help`
  - Prints command help in chat.

## Customization
Open the panel with `/hmt` and adjust:
- Tracker unlock/lock
- Scale
- Font size
- Row spacing
- Font
- X/Y position
- Default/drinking/dead colors
- Per-class text colors


> Important: WoW expects the `.toc` filename to match the addon folder name.
> This repo now includes both `HealerManaTracker.toc` and `Healer-Mana.toc` so either folder name can load.
