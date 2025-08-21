<img width="251" height="74" alt="image" src="https://github.com/user-attachments/assets/6291b77b-0a49-4a73-8d5b-8466e0723c5d" />

TacoRotSwingTimer (WoW 3.3.5a)

What it is:
A simple swing timer with three bars: MH (red), OH (blue), Ranged (yellow). Uses combat log timing so it matches real hits. Animation smoothness is adjustable but does not change accuracy.

Requirements:

WoW 3.3.5a client

Ace3 libraries (AceAddon, AceConsole, AceEvent, AceTimer, AceDB). Either embedded or installed as a separate addon.

Install:

Put this folder in: World of Warcraft/Interface/AddOns/TacoRotSwingTimer

Make sure the folder contains at least:
TacoRotSwingTimer.toc
core.lua
ui.lua
Compat-335.lua
(plus any XML included with the addon)

Enable TacoRotSwingTimer on the character select screen.

Basic use:

Three bars: MH, OH, Ranged.

Frames can be shown out of combat and dragged when unlocked.

OH frame can be visible even if you don’t have an off-hand; it only animates when you actually do.

Commands (use /st or /swingtimer):
lock lock frames (can’t drag)
unlock unlock frames (drag to move)
reset recenter the group
scale <0.5-3> UI scale
alpha <0.1-1> overall transparency
width <px> bar width
height <px> bar height
gap <px> space between bars
fps <15-240> animation refresh (higher = smoother)
show ooc toggle “always show out of combat”

Per-bar toggles:
mh on|off show/hide Main-Hand
oh on|off show/hide Off-Hand
rg on|off show/hide Ranged
ranged on|off same as rg

Test:
test simulate one full cycle for all bars (for positioning)

Examples:
/st unlock
/st show ooc
/st fps 60
/st width 260
/st oh on

Troubleshooting:

Bars not visible out of combat: /st show ooc (should say ON)

OH bar frame missing: /st oh on (frame shows; it animates only with an off-hand)

Bar looks choppy: increase with /st fps 60 or higher

Timing off after haste/weapon swap: it recalibrates on the next hit; you can /st test to preview placement
