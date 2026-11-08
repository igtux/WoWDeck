# WoWDeck

A touchscreen/gamepad-friendly companion addon for World of Warcraft, built for the Steam Deck and designed to work alongside [ConsolePort](https://www.curseforge.com/wow/addons/consoleport). WoWDeck adds a set of large, flat, modern-styled panels you can reach without a keyboard or mouse — apply saved ConsolePort configs, manage your bags and quest log, track gathering, and type short messages, all with big tap targets.

## Features

- **Apply Pending Config** — drives ConsolePort's own Import dialog to apply a saved config with one tap, no copy/paste required.
- **On-Screen Keyboard** — a compact tap-to-type keyboard for short text and slash commands, with quick `/say`, `/party`, `/r` send buttons.
- **Gathering Assistant** — shows a small card near the top of the screen when you're near a gatherable node (herb/ore), with your current profession skill level and, for known Classic herbs, whether it's still likely to raise your skill.
- **Bag Manager** — browse your bags 3 pages at a time, Use/Sell/Delete any item, and a **Find Unused Quest Items** filter that flags quest-class items no longer tied to any quest in your log.
- **Quest Manager** — browse your quest log 3 pages at a time, abandon a quest (and optionally delete its tied item in the same step), and a **Show Low-Level Only** filter (using Blizzard's own quest-difficulty coloring) with a bulk **Abandon All Low-Level Quests** action.
- **Track Herbs / Track Minerals** — one-tap buttons to toggle herb/mineral tracking, since the default UI buries this in a mouse-driven minimap menu.

## Requirements

- [ConsolePort](https://www.curseforge.com/wow/addons/consoleport) and `ConsolePort_Config` — required for the Apply Pending Config feature; the rest of WoWDeck works standalone.

## Installation

1. Download this repository (Code → Download ZIP, or `git clone`).
2. Copy the `WoWDeck` folder into your WoW `Interface/AddOns/` directory.
3. Fully restart WoW (not just `/reload` — a new addon needs a full client restart to be picked up).
4. Enable **WoWDeck** on the character-select AddOns list.

Once running, tap the small **WD** launcher button (draggable, appears near the bottom-left of the screen) to open the main panel.

## Notes

- **Low-level quest detection** uses Blizzard's own `GetQuestDifficultyColor` (the same gray used for trivial quest markers), not a hardcoded level table — it should stay accurate across content patches.
- **Classic herb skill-up estimates** use a static table of standard Classic-era Herbalism requirements plus the well-known "+75 skill = trivial" rule of thumb. This is a solid estimate, not a guarantee, especially on a heavily customized server.
- **Bag Manager's Use/Sell buttons** are implemented as secure action buttons (`SecureActionButtonTemplate`), since calling `UseContainerItem` directly from addon code is blocked by Blizzard for items whose on-use effect casts a protected spell.
- Deleting items or abandoning quests always requires an explicit confirmation — nothing is ever deleted or abandoned automatically or in bulk without you seeing exactly what's affected first.

## License

No license has been chosen yet for this repository. All rights reserved by default until one is added.
