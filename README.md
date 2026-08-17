# PUPMan

PUPMan is a small Ashita v4 addon for managing Puppetmaster maneuvers.

Its Puppetmaster models use the shared `burdenmodel.lua`, `burdenforecast.lua`,
`pupstats.lua`, and `pupcooldowns.lua`
libraries from Ashita's `addons/libs` directory. Both PUPMan and Arcane
Automata consume these same implementations rather than maintaining separate
stat or burden parsers.

It provides:

- a decision-focused maneuver plan and next-action recommendation;
- head/frame profiles and configurable role plans;
- a chic micro HUD by default, with the expanded compact layout available;
- automatic HUD hiding in towns and cutscenes;
- exact automaton HP plus MP and TP vitals, with escalating low-MP warnings;
- packet-tracked automaton buffs and debuffs in both HUD layouts;
- an optional, separately anchored Puppet Systems cooldown panel;
- Activate, Repair, Deploy, Deactivate, and Retrieve recasts;
- Repair readiness, inventory oil count, and a configurable HP warning;
- post-maneuver overload risk (`SAFE`, `LOW`, `WARM`, or `DANGER`) for the next plan element;
- fixed-region warnings that do not resize the HUD when state changes;
- explicit `UNKNOWN` state until a server result anchors an element;
- vector element glyphs and an optional colorblind-safe palette;
- server-anchored overload percentages with modeled decay between attempts;
- the shared maneuver recast timer;
- short commands for one-input/one-action manual use;
- an exact-HP, one-shot Deactivate command;
- configurable plans for common automaton roles.

The compact HUD uses ToAU-inspired imperial blue-green, aged brass, and parchment colors. Its header uses aligned pet/mode and head/frame columns, followed by equal HP/MP/TP cards. Each vital keeps its label on a consistently dark surface and uses a thin colored meter below it: deep red for HP, olive-gold for MP, and cyan for weaponskill-ready TP. At 800 TP the fill and label brighten to signal that a weaponskill is close; at 1,000 TP the card gains a stronger fill, subtle cyan tint, and slow pulsing cyan border; it brightens again at 2,000. Brass `// MANEUVER CONTROL` and `// AUTOMATON` dividers separate planning from the Deactivate/Repair/ability footer. The recommended maneuver receives an element-tinted decision card with its actionable context built into the card, ability recasts use readiness dots, and a faint gear/circuit watermark gives the panel a Puppetmaster identity.

Low MP is deliberately difficult to overlook. Below 30%, the MP card becomes
amber and pulses with `MP!`; below 20% it becomes orange with `MP!!`; below
10% it becomes a fast red critical card with `MP!!!`, and the HUD's left status
rail adopts the same warning color. The thresholds use strictly less than
30/20/10. Frames with no MP pool are excluded.

Warnings stay in fixed UI regions so state changes never resize the HUD. The
decision row reports conditions such as overload, no pet, and maneuver recast;
the MP card and left rail carry low-MP urgency; and the automaton footer keeps
Deactivate, Repair, ability readiness, and oil information visible.

The `PET FX` row reconstructs automaton status changes from the same action and message packet families used by XIUI's pet bar. Teal `+` tags are buffs and orange-red `-` tags are debuffs, with debuffs sorted first. Because the client does not expose a complete pet-effect list, effects already active when the addon loads may not appear until they are reapplied; the tracker clears when the automaton changes or you zone.

Micro mode is the default. It begins with aligned two-column rows for mode/combat and Deactivate/risk, followed by the equal HP/MP/TP cards, plan circuit, and next action/status. The slim three-node circuit displays the ordered elemental plan: filled sigils represent active maneuver copies, and a softly pulsing outer ring marks the element PUPMan would recommend next. Duplicate elements retain separate nodes, so plans such as Fire / Fire / Thunder remain unambiguous. Decision status is reduced to a terse value such as `MISSING`, `RECAST`, `STABLE 32s`, `REFRESH 8s`, `OVERLOAD`, or `NO PET`. Compact and micro layouts share a fixed 382 px width with additional edge padding for border decoration, so switching layouts does not move the right edge. It remains click-through and can be expanded with `/pm layout compact`.

The optional `PUPPET SYSTEMS` window is off by default and anchors to the
right of the main HUD without changing its size. `/pm systems on` enables it;
`/pm systems side left` moves it to the other side. It lists only discrete
timed systems supplied by the equipped frame and attachments, such as
Valoredge Shield Bash, Shock Absorber's Stoneskin, Strobe, and Flashbulb.

The HUD is always click-through: it does not capture the mouse, and all actions and positioning are command-driven.

Town and cutscene auto-hide are enabled by default. Auto-hide only suppresses rendering; packet tracking and direct commands continue normally. `/pm autohide off` disables both conditions; `/pm townhide` and `/pm cshide` control them independently.

PUPMan uses 14 px Tahoma Bold by default to match XIUI's typography and improve small-label readability. HP, MP, and TP use 16 px bold labels on dark bordered cards with six-pixel meters underneath. HP and MP fill by percentage; TP fills across the 0-3000 range. If the Windows font cannot be loaded, PUPMan silently falls back to Ashita's default ImGui font.

The recast display uses Ashita's maneuver ability resource plus an independent 10-second Horizon fallback. The local fallback begins only after a maneuver action packet confirms that the server processed the action. Merely queueing `/pm n` does not start it, so a command rejected while resting, standing up, or otherwise unable to act remains eligible on the next input. A short 0.75-second input guard prevents accidental command floods without treating the maneuver as used.

PUPMan verifies that an Animator is actually equipped in the ranged slot before it queues a maneuver. If the slot is empty or contains another item, the command reports the problem and takes no action.

PUPMan tracks maneuver expiration internally for plan recommendations, refresh decisions, and burden display, but leaves visible maneuver timers to a dedicated visualization addon.

The presets are starting points only. The best elements depend on your head, frame, attachments, target, and party role.

## Load

In game:

```text
/addon load pupman
```

To load it automatically, add the same line to your Ashita startup script. The HUD only renders while Puppetmaster is your main job.

## Fast macro and keyboard commands

| Command | Action |
| --- | --- |
| `/pm n` | Use the recommended maneuver once |
| `/pm f` / `i` / `w` / `e` | Fire / Ice / Wind / Earth |
| `/pm t` / `wa` / `l` / `d` | Thunder / Water / Light / Dark |
| `/pm 1` / `2` / `3` | Use that slot from the current plan |
| `/pm da` | Use Deactivate once, only at exact full HP |
| `/pm hp` | Print the synchronized raw HP integers |
| `/pm rep` | Use Repair once if it is ready and oil is present |
| `/pm mode melee` | Select a role plan |
| `/pm layout micro` | Switch to the minimal HUD |
| `/pm systems on` | Show the anchored Puppet Systems panel |

Full element names also work, such as `/pm fire` and `/pm light`. `/pupman` can be used in place of `/pm`.

Ashita passes native FFXI macro lines through addon command handlers, so the in-game macro lines are simply:

```text
/pm n
```

For a direct keyboard shortcut, add a bind to an Ashita script or enter it in the console. This example uses Ctrl+F8; choose a key that does not collide with your setup:

```text
/bind ^F8 /pm n
```

No key is bound automatically.

## Other commands

```text
/pm
/pm plan fire fire thunder
/pm preset melee
/pm next
/pm use light
/pm da
/pm hp
/pm repair
/pm repairwarn 40
/pm recasts
/pm mode
/pm mode profile
/pm mode melee
/pm mode set melee fire fire thunder
/pm profile tank
/pm layout micro
/pm layout compact
/pm systems on
/pm systems off
/pm systems status
/pm systems side left
/pm systems side right
/pm autohide on
/pm townhide on
/pm cshide on
/pm colorblind on
/pm burden
/pm burden reset
/pm burden threshold 0
/pm burden threshold 5
/pm burden heatsink auto
/pm burden heatsink on
/pm burden heatsink off
/pm burden guard 20
/pm burden guard off
/pm burden log on
/pm burden note no-heatsink fresh-activate trial
/pm burden log status
/pm burden log off
/pm keys
/pm pos 420 260
/pm nudge left 10
/pm show
/pm hide
/pm reset
/pm help
```

`/pm n` (or `/pm next`) is the primary action command. It evaluates the current plan and performs at most one recommended maneuver in direct response to that command. PUPMan has no combat controller, action timer, automatic retry, or background action path. After an Overload, `/pm n` temporarily skips the element that caused it and selects the next missing, different element in the plan. If no different element is missing, it holds until the failed element's projected risk is acceptable. With the burden guard enabled, its configured percentage is the acceptable limit; with the guard off, the failed element must reach a zero-percent projection. Direct element and numbered commands remain manual overrides. The skip clears when the projection reaches that limit, when burden projections are manually reset, when a fresh automaton is activated, or when changing zones.

An optional burden guard can hold any recommendation above a chosen projected overload percentage: `/pm burden guard 20` allows risks through 20% and holds at 21% or higher. For modeled `estimate` quality, the guard compares against a conservative upper projection that allows for one uncertain decay tick. An enabled guard also holds on `UNKNOWN`; direct commands such as `/pm light`, `/pm use light`, and `/pm 1` remain manual overrides. The guard defaults to off.

A successful maneuver action packet is treated as provisional. After a one-second buff-list grace period, PUPMan allows up to 2.5 seconds for live confirmation before discarding the provisional slot. Plan completeness always comes from the live buff list. A clipped or otherwise unconfirmed maneuver therefore becomes eligible again after the normal 10-second recast instead of leaving the plan falsely `STABLE` until an older timer expires.

Move the HUD with `/pm pos <x> <y>` or `/pm nudge <left|right|up|down> [pixels]`.

## Plans and head/frame profiles

`/pm mode profile` selects a role plan from the equipped automaton head and frame. This only changes the recommendation plan; it never performs an action. The built-in mappings are:

| Head / frame | Mode |
| --- | --- |
| Harlequin / Harlequin | balanced |
| Valoredge / Valoredge | melee |
| Sharpshot / Sharpshot | ranged |
| Stormwaker / Stormwaker | nuker |
| Soulsoother / Stormwaker | healer |
| Spiritreaver / Stormwaker | nuker |

For a mixed or preferred setup, equip it and use `/pm profile <mode>`. That stores a mapping for the exact current head/frame pair. `/pm mode set <name> <element> <element> <element>` changes a mode's plan; custom mode names are allowed. `/pm plan ...` remains available and switches directly to a standalone `custom` plan.

## Exact-HP Deactivate

`/pm da` queues Deactivate only when the raw automaton `Current HP` integer is exactly equal to its raw `Max HP` integer and Deactivate is ready. It never uses the rounded entity HP percentage. It performs no follow-up action; Activate remains entirely player-controlled.

The raw HP snapshot is invalidated whenever an action or direct action message targets the automaton, or a pet-status update indicates that its vitals may have changed. Percentages may invalidate a snapshot but can never approve Deactivate. Until a new PUP stat packet supplies exact HP, `/pm da` fails closed with no action.

## Puppet Systems cooldown panel

The side panel reads the twelve equipped attachment slots from the PUP `0x44`
packet and watches incoming `0x28` actions performed by your automaton. An
observed use anchors that system's countdown. A leading `~` means the remaining
time uses the LandSandBoat duration as a model because Horizon's private-fork
value cannot be read directly from the client.

The panel uses four practical states:

- `READY` means the modeled cooldown has elapsed and known client-visible
  requirements are satisfied.
- `WAIT F/E/W/L/D`, `WAIT HP`, or `WAIT MP` means the cooldown has elapsed but
  its maneuver or resource trigger is not currently satisfied.
- `UNKNOWN` means PUPMan loaded with an automaton already active and did not
  observe the earlier spawn or ability use.
- A `~M:SS` or `~Ns` value is the modeled remaining recharge.

LandSandBoat applies attachment recasts when an automaton spawns, so a fresh
Activate observed after PUPMan loads begins those countdowns immediately.
Valoredge Shield Bash begins ready and is modeled at 180 seconds after use;
Barrier Module reduces that interval by five seconds per active Earth Maneuver.
The supported base systems are Strobe (30s), Shock Absorber/Stoneskin (180s),
Flashbulb (45s), Mana Converter (180s), Eraser (30s), Reactive Shield (60s),
Economizer (60s), Replicator (60s), and Disruptor (60s). Definitions for later
timed attachments are harmlessly dormant unless those attachments exist and
are equipped on Horizon.

`READY` describes recharge and visible eligibility, not a guarantee that the
automaton AI will activate the system immediately. Target effects, interrupt
windows, status effects, distance, and the automaton's internal action priority
can still delay selection. The baseline comes from LandSandBoat's
[`automaton.lua`](https://github.com/LandSandBoat/server/blob/base/scripts/globals/pets/automaton.lua),
attachment scripts, and
[`automaton_controller.cpp`](https://github.com/LandSandBoat/server/blob/base/src/map/ai/controllers/automaton_controller.cpp).

## HorizonXI approval required

PUPMan is designed around one-input/one-action commands. It does not maintain maneuvers, retry actions, or trigger abilities from packet, render, timer, or status events. HorizonXI approval is still required before use; follow the current process on the official [HorizonXI Addons page](https://horizonxi.com/addons).

## Presets

| Preset | Initial plan |
| --- | --- |
| balanced | Fire / Wind / Light |
| melee | Fire / Fire / Thunder |
| ranged | Wind / Wind / Fire |
| tank | Earth / Light / Fire |
| healer | Light / Light / Dark |
| nuker | Ice / Ice / Dark |

When the addon is loaded in the middle of existing maneuvers, their initial timers are marked with `~` because FFXI exposes the active effects but not their original application times through the normal buff list. New maneuvers are timed exactly from their action packets.

## Repair and burden notes

The Repair assistant counts Automaton Oil, Automaton Oil +1, Automaton Oil +2, and Automaton Oil +3 in the main inventory. `/pm repair` is a manual one-shot command; it checks for an active automaton, oil, and Repair readiness before issuing the job ability. Set the warning threshold with `/pm repairwarn <0-99>`; zero disables the warning.

The `RISK` value is the burden model's projection for using the displayed
element now: it includes the gain that would be added before Horizon makes the
overload roll. The displayed element is the actual next plan element even
while a maneuver is on recast or a stable plan is waiting for its refresh
window. `SAFE` means exactly zero modeled risk; `LOW` means a real nonzero roll
below 20%, while `WARM` begins at 20% and `DANGER` at 50%. When the projected
roll is above zero, `safe ~Ns` (compact) or `S~Ns`
(micro) estimates when decay will make that same maneuver a zero-percent roll.
The estimate uses the model's local three-second tick phase and can be off by
roughly one tick. Action results 798/799 anchor its gauge to the percentage reported by
the server, then the telemetry-fitted Horizon model projects the value between
observations. It uses a fresh burden of 30 at the assumed base threshold of 30,
a normal-frame Dark gain of 15, and one decay per three-second server tick. A
cold-attached element remains `UNKNOWN` until its first server result. The compact HUD shows the projection quality (`exact`,
`estimate`, or `bound`) beside the element; `estimate` is the normal steady-state
quality after modeled decay has occurred.

`/pm burden` or `/pm burden status` prints the configuration and all eight
elemental projections, followed by the seven live non-Dark master-minus-pet
stat comparisons. The printed chances are also next-maneuver projections, not
idle-gauge chances. `/pm burden reset` returns the active pet's gauges to
unknown. The Valoredge/Sharpshot reduced Dark-burden rule is selected
automatically from PUPMan's synchronized frame data. Use `/pm burden threshold
5` only when wearing Puppetry Dastanas and testing Horizon's unverified +5
effect; otherwise leave the default at `0`. Heatsink defaults to `auto` and is
detected from the twelve attachment slots in the same PUP job-info packet used
for automaton stats. `/pm burden heatsink on|off` provides an explicit testing
override; `/pm burden heatsink auto` restores attachment detection. Heatsink
decay is driven by active Water Maneuvers:
total decay is modeled as 1/2/3/4 per tick at zero through three Water
Maneuvers. Zero through two were measured directly on Horizon; three is the
linear extrapolation. Buffoon's Collar is not available on Horizon.

### Burden telemetry

`/pm burden log on` starts an opt-in diagnostic CSV alongside the normal Logs
addon output in Ashita's `chatlogs` directory. It follows Logs' character and
date naming convention, for example `Koruru_2026.08.14.burden.csv`, while using
a sidecar file because Logs exposes no public addon-writer API and only records
incoming chat. `/pm burden log off` flushes the final event and reports the full
path. Logging is session-only and never enables itself automatically.
If a same-day file has an older CSV header, PUPMan preserves it and writes the
new schema to a versioned name such as `Koruru_2026.08.15.burden.v2_5.csv`.

The file records lifecycle events, observed maneuver buffs, every modeled
three-second decay, configuration changes, packet parse failures, and every
798/799 maneuver result. Maneuver rows include the server parameter,
`predicted_param` for the matching wire value, `predicted_risk` for the actual
overload roll, `residual` (server parameter minus predicted parameter), and a
`gauge_residual` when a positive server parameter permits exact reconstruction.
They also include before and after gauges and quality, configured threshold, estimated gain, decay rate,
tick phase, frame rule, Heatsink state, and observed Fire and Water counts.
For non-Dark maneuvers it also records the relevant stat name, master base and
gear modifier, automaton base and additional stat, both totals, their
difference, and whether the values came from the outgoing-action snapshot or
an incoming fallback. A completed snapshot means the master was captured on
the outgoing request and the pet half arrived in a subsequent `0x44` before
the result. `/pm burden note <text>` inserts a
timestamped annotation for gear swaps or controlled-test boundaries.

For a useful baseline, disable Heatsink, set threshold to `0`, start logging,
record a note describing the frame and gear, then Activate a fresh automaton.
Use repeated maneuvers of one element with deliberately recorded wait periods,
and stop logging afterward. A persistent gauge residual immediately after controlled
uses points toward a different gain, spawn, or threshold; a residual that grows
with idle time points toward decay rate or tick-phase behavior. Param `0` is
only an upper bound, so positive server percentages provide the strongest
evidence. Non-Dark gain varies with the relevant master-minus-pet stat
difference. PUPMan now reads the automaton's exact base/additional stats from
PUP packet `0x44`, reads the master's live base/modifier values from Ashita,
and snapshots both when the outgoing Maneuver request is sent. This accounts
for deliberate maneuver gear and prevents a fast aftercast swap from being
mistaken for the gear the server evaluated. Repeat separately with Heatsink
and with Valoredge/Sharpshot Dark
maneuvers to isolate those branches. The absolute spawn value cannot be
separated from the absolute threshold using 798/799 alone; the observed result
is `spawn - threshold = 0`, represented as 30/30 under Horizon's base-threshold
assumption.

Element glyphs are code-drawn vector shapes, so they add no image files or texture-loading overhead. Use `/pm colorblind on`, `/pm colorblind off`, or `/pm cb` to select the alternate palette. Shapes remain different in either palette, so element identity does not depend on color alone.

The compact HUD aligns ability recasts in two equal columns, spells out each ability, and displays `READY` explicitly. Deactivate is omitted from this grid because its protected readiness has a dedicated row. The `/pm recasts` chat command still reports every ability and remains abbreviated: `ACT` Activate, `REP` Repair, `DEP` Deploy, `DEA` Deactivate, and `RET` Retrieve. In chat output, `--` means ready.
