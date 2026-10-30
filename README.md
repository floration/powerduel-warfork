# Power Duel (Warfork gametype)

Duel with a fighting-game life bar.

- 1v1, each player is their own team.
- Each side starts with **5000 team HP** (team score + HUD bars at the top of the screen).
- Every point of health/armor you lose comes off your team HP (overkill doesn't count). Self/fall damage counts too.
- Health/armor pickups only refill your current life, never team HP.
- Team HP 0 = K.O., you lose. On time limit, more team HP wins.
- At **500 team HP or less** you respawn with quad for that whole life.
- Everyone spawns with every weapon, infinite ammo.
- Ammo pickups are replaced with armor shards (+5, up to 200). No weapon pickups.
- Nothing drops on death (no weapons, no backpacks).

## Install

Copy `progs/` into your Warfork `basewf/` folder so you have `basewf/progs/gametypes/powerduel.gt`.

Then in the console: `g_gametype powerduel` and `map wfdm5` (any duel map works).

Tweak numbers at the top of `progs/gametypes/powerduel.as` (`PD_TEAM_HP`, `PD_QUAD_HP`, ...).
