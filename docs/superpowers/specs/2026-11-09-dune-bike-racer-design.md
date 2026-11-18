# Dune bike racer — game design

Date: 2026-11-09
Status: draft, awaiting owner approval

Items marked **(my call)** were decided by the designer (Claude), not by the
owner. Everything else is what the owner said or confirmed.

## Intent

A simple, original 2D side-view off-road motorbike racing game for iPhone and
iPad, in 16-bit-style pixel art, to be published on the App Store.

It is inspired by the genre of the classic 8-bit side-view motocross game the
owner played on Dendy (Excitebike). The fun to preserve: accelerating over
hills and rocky ramps, flying, controlling the bike in the air, and landing
well, while racing other bikes on the same track. The second pillar is building
your own track out of hills and then riding it alone or against rivals.

It must be a visually and nominally distinct game: own name, world, riders,
bikes, obstacle set, UI, track layouts and (later) music. Only genre mechanics
are shared with the inspiration.

## Goals (version 1)

1. Riding that feels good: gas, boost, jumps, air lean, landings, crashes.
2. Tournament against computer-controlled rivals.
3. Solo run against a target time.
4. Track builder, with tracks playable solo or against rivals.
5. One world: "Dune dusk" (desert at dusk, mesas, sand hills, rock ramps).
6. Shippable on the App Store.

## Non-goals (version 1)

- Real-player multiplayer of any kind (planned later: nearby and/or online).
- Android (a full rewrite is planned later; no cross-platform engine now).
- Music, sound effects and voices (next step, with ElevenLabs).
- Additional worlds ("Frost pines", "Crystal moon" were sketched; later).
- Sharing player-made tracks between devices.
- Accounts, network calls, analytics, ads, in-app purchases **(my call)**.

## Anti-goals

- Anything that reads as a copy of the inspiration: its name, stadium setting,
  hay bales, palette, sprites, track layouts, UI layout, or jingles.
- Free-hand terrain that lets a player build an unrideable or broken track.
- A simulation that depends on frame rate or on rendering code, which would
  block adding human opponents later.

## The game

### View and world

- Landscape only. Side-on camera follows the player's bike; the track scrolls
  right to left. Parallax background: dusk sky, sun, mesas.
- The track is one long strip of sand with **three lanes** drawn as depth
  (near, middle, far). Bikes switch lanes to pass, block, and avoid or hit
  things that sit in a single lane.

### Riding

- **Gas:** hold to accelerate up to normal top speed.
- **Boost:** hold for a higher top speed; fills a heat bar. A full bar means
  overheat: the engine cuts out for a short stall (about 3 s **(my call)**),
  then the bar resets. Heat drains when not boosting.
- **Lane change:** step one lane up or down; takes a fraction of a second.
- **Jumps:** leaving the top of a hill or ramp with speed sends the bike into
  the air; distance and height come from speed and the slope left.
- **Air lean:** lean forward or back to rotate the bike in the air.
- **Landing:** landing with the bike's angle close to the ground's slope keeps
  speed; a moderately off landing loses speed; a badly off landing is a crash.
- **Crash:** rider tumbles, bike resets upright in place after about 2 s
  **(my call)**.
- **Bike contact (my call, tunable):** a lane change into an occupied spot is
  refused with a small slowdown for the mover; running into the back of a
  bike slows the rear bike. No contact crashes in version 1.

### Track pieces

Terrain pieces span all three lanes:

- Small hill, big hill, rock ramp (steep one-sided launch), bumps (a short
  series of small mounds that punish boost speed).

Surface pieces occupy one lane **(my call)**:

- Mud (slows the bike), boost pad (brief free speed burst, no heat).

### Controls

- Left thumb: lane up, lane down, lean back, lean forward.
- Right thumb: gas, boost.
- Exact on-screen layout (d-pad versus separate buttons) is left to the
  builder to prototype; it must be playable on the smallest supported iPhone.

### Races

- Point-to-point sprint, no laps, about 60–90 seconds.
- 4 bikes: the player and 3 computer rivals.
- HUD: heat bar, position (e.g. 2/4), progress along the track, timer.

### Modes

**Tournament.** One cup of 5 built-in Dune dusk tracks of rising difficulty.
Points per race by finishing position (10 / 6 / 3 / 1 **(my call)**). Finish
in the top 3 to unlock the next track. Highest total after 5 races wins the
cup. Progress is saved.

Retry rules **(my call)**: finishing 4th means retrying that race, not
restarting the cup. A retry replaces that race's points for the player and
the rivals. A track may also be replayed voluntarily before moving on; the
latest result counts. A finished cup can be started again from race 1 with
fresh points. Tracks unlocked for Solo run stay unlocked forever.

**Solo run.** Any unlocked built-in track, alone, against a target time. Best
time per track is saved.

**Track builder.**

- Screen: scrolling track preview on top with a mini-map bar to move along the
  track; palette of the six pieces below; buttons "Test ride", "Race rivals",
  "Save".
- Drag a piece from the palette onto the track; it snaps to a grid. Tap a
  placed piece to select it; a selected piece can be removed.
- Grid snapping and piece rules guarantee every track can be finished.
  Piece rules **(my call)**: pieces never overlap; terrain pieces need at
  least one flat grid cell between them; surface pieces sit only on flat
  sand; the start and finish stretches are always flat and empty. No cap on
  piece count beyond what fits the track length. Built-in tracks obey the
  same rules.
- Tracks are saved on the device with a name; the player can keep several and
  reopen, edit, or delete them.
- "Test ride" rides the track alone; "Race rivals" adds the 3 computer bikes.
- Track length is chosen when creating a track: short, medium, or long
  **(my call)**.

### Computer rivals

- Rivals drive through exactly the same input set as the player (gas, boost,
  lean, lane change) into the same simulation; they get no hidden speed.
- Three skill levels, mixed per race and rising across the cup **(my call)**.
  Skill changes boost discipline, landing accuracy, and lane choice.
- Rivals must cope with any track the builder can produce.

## How it gets made

Decided by the owner:

- **Swift, native iOS.** Android will be a complete rewrite later.
- **PixelLab** generates the art. **ElevenLabs** generates audio in a later
  step.
- Computer rivals first; real players later (owner mentioned BLE; Apple's
  MultipeerConnectivity and Game Center are the likely routes, to be decided
  then).

- **Art generation:** Claude generates the assets with the owner's PixelLab
  access. Hard budget: 5000 generations in total. Plan the asset list first,
  generate in small batches, and reuse or recolour (e.g. bike colours by
  palette swap in code) rather than regenerate.
- **Languages:** English, Swedish, Russian, Spanish, Persian, Uzbek, Kyrgyz,
  Kazakh. Text is kept very short and simple: the game is about fun on the
  track, not reading.
- **Apple side:** the owner has an Apple Developer account and an iPhone for
  testing, the same setup as for their Nasreddin game. Take team and bundle
  identifier conventions from that project when signing is set up.

My calls:

- **Text and localisation:** prefer icons and numbers over words. No text is
  ever drawn into the art. All strings are localised from the start (String
  Catalog). Text is rendered with the system font, not a pixel font, because
  no single pixel font covers Latin, Cyrillic with Kazakh and Kyrgyz letters,
  and Persian. Menus mirror for Persian (right to left); the race itself and
  its HUD keep the same direction in every language. Player-typed track
  names accept any script.
- **SpriteKit** for rendering and input; no third-party engine or packages.
- **Simulation separate from rendering.** The race (bikes, terrain, heat,
  collisions, rivals) lives in a plain-Swift module with no SpriteKit import,
  advanced at a fixed time step and driven only by per-rider input. Same
  inputs give the same race. This keeps it unit-testable, makes a human
  opponent a drop-in replacement for a rival later, and gives the Android
  rewrite a clear thing to port. "Same race" means repeatable on one device
  and build: ordinary floating point, seeded random numbers. Bit-exact
  results across devices or platforms are not required; future multiplayer
  will sync state from a host rather than rely on lockstep.
- **Keyboard controls** in the prototype, so riding can be judged in the
  simulator where two-thumb touch is impractical.
- **Custom bike physics**, not SpriteKit's physics engine, for tunable jumps
  and repeatable results.
- **One track format** (a length plus a list of placed pieces with grid
  position and, for surface pieces, lane) used by both built-in and
  player-made tracks, stored as JSON.
- **Saves** are local files only (progress, best times, player tracks).
- **Pixel-art rendering:** low internal resolution scaled up with
  nearest-neighbour filtering; exact resolution and sprite sizes to be fixed
  with the first PixelLab assets.
- **Targets:** iPhone and iPad, landscape, iOS 17 or later.
- **Name:** not chosen. Use a placeholder; the owner picks the final name and
  checks App Store availability before submission.

## Order of work

1. **Grey-box prototype:** plain shapes, one test track, player only — tune
   gas, boost, heat, jumps, lean, landing, crash until it feels right. The
   owner plays it in the simulator before anything else is built.
2. **Rivals and a full race:** 3 computer bikes, lanes, contact, HUD, finish.
3. **Art pass:** PixelLab assets for Dune dusk (bikes in 4 colours, rider
   states: ride, lean, air, crash; terrain and the six pieces; background
   layers; UI). Needs the owner's PixelLab access.
4. **Tournament and solo run:** 5 tracks, points, unlocks, saves, menus.
5. **Track builder.**
6. **Audio** with ElevenLabs (separate step, own design).
7. **App Store preparation:** icon, screenshots, name, listing, privacy
   answers ("no data collected").

## Left to the builder

- All physics numbers (speeds, gravity, heat rates, landing tolerances),
  tuned by feel in step 1.
- Control layout details.
- Grid size, track lengths in grid units, and the five built-in track layouts.
- Rival decision logic.
- Screen flow and menu design beyond what is described above.
- Internal code structure within the split described above.
