# Grey-box riding prototype — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A playable plain-shapes prototype of one bike on one test track, so the owner can judge and tune gas, boost, heat, jumps, air lean, landings and crashes.

**Architecture:** A pure-Swift package `RaceCore` holds the track format, terrain profile and the fixed-step race simulation, with no SpriteKit import. A thin SpriteKit app draws the simulation state with shapes, feeds it keyboard and touch input, and exposes a tuning panel.

**Tech stack:** Swift 6, Swift Testing, SpriteKit, SwiftUI (app shell and tuning panel), GameController (keyboard), XcodeGen (project file generation only).

**Spec:** `docs/superpowers/specs/2026-11-09-dune-bike-racer-design.md` — this plan covers "Order of work" step 1 only. Rivals, lanes, art, tournament, builder, audio and App Store get their own plans after the owner approves the riding feel.

## Global constraints

- Native Swift, iOS 17 or later, iPhone and iPad, landscape only.
- No third-party packages or engines in the app. XcodeGen is a build tool on the Mac, not shipped.
- `RaceCore` must not import SpriteKit, UIKit or SwiftUI.
- Simulation advances at a fixed step of 1/60 s, driven only by `RiderInput`. Same inputs give the same race on one device and build. Ordinary `Double` maths; any randomness is seeded.
- Custom bike physics; do not use SpriteKit's physics engine.
- One track format (length plus placed pieces, JSON) for built-in and player-made tracks.
- Piece rules: pieces never overlap; terrain pieces need at least one flat cell between them; surface pieces sit only on flat sand; start and finish stretches are flat and empty.
- No words drawn into art; prefer numbers and bars over text. Any user-visible string goes through a String Catalog.
- No network, analytics or accounts.
- Out of scope here: lanes, rivals, mud and boost-pad effects (the format and validation accept them; the simulation ignores them until the next plan).
- The folder name contains `!` — always quote paths in shell commands.
- Git: `git init` locally, commit per task, no remote, no push.

## Starting values (all tunable in Task 8)

World units are metres. `Track.cellWidth = 4`.

| Piece | Width (cells) | Height | Shape |
|---|---|---|---|
| smallHill | 2 | 1.5 | raised cosine `h·(1−cos 2πt)/2` |
| bigHill | 4 | 3.5 | raised cosine |
| rockRamp | 3 | 2.5 | linear rise over first 85 % of width, linear drop over last 15 % |
| bumps | 3 | 0.5 | three raised cosines, one cell each |
| mud | 2 | 0 | surface, one lane |
| boostPad | 1 | 0 | surface, one lane |

Start zone: first 5 cells. Finish zone: last 5 cells. Finish line: `length − 2·cellWidth`. Minimum track length: 20 cells. Lanes are numbered 0–2.

`Tuning` defaults: `gravity 20`, `slopeGravityFactor 0.35` (how much of gravity pulls a grounded bike along a slope; kept low so a bike stopped on the steepest hill can always pull away on gas), `gasAccel 8`, `boostAccel 12`, `normalTopSpeed 16`, `boostTopSpeed 24`, `coastDecel 3`, `leanRate 2.5` (rad/s), `cleanLandingAngle 0.26`, `crashLandingAngle 0.79` (rad), `sloppyLandingSpeedFactor 0.6`, `crashDuration 2.0`, `stallDuration 3.0`, `heatFillTime 4.0`, `heatDrainTime 6.0`.

## Review focus

1. A long frame gap (app backgrounded, debugger pause) must not make the bike teleport: the step clock caps catch-up at 5 steps and drops the rest. Test in Task 6.
2. Holding lean through a long flight wraps the angle past a full turn; landing must compare the normalised angle difference, so a full flip that ends level is a clean landing. Test in Task 5.
3. The bike must never end a step below the terrain, including on the steep back face of a rock ramp and at hill crests. Soak test in Task 6.
4. Crossing the finish while airborne, crashed or stalled still finishes; time freezes and later input is ignored. Tests in Tasks 3 and 5.
5. A track file with an unknown piece kind, a negative cell or a missing lane must fail to load with an error, never crash or load half a track. Tests in Task 1.

---

### Task 1: Repository, package skeleton, track format and validation

**Files:**
- Create: `.gitignore` (`.build/`, `DerivedData/`, `*.xcodeproj`, `.DS_Store`, `xcuserdata/`)
- Create: `Packages/RaceCore/Package.swift` (library `RaceCore`, test target `RaceCoreTests`, tools 6.0, platforms iOS 17 and macOS 14)
- Create: `Packages/RaceCore/Sources/RaceCore/Track.swift`
- Test: `Packages/RaceCore/Tests/RaceCoreTests/TrackTests.swift`

**Interfaces — produces:**

```swift
public enum PieceKind: String, Codable, Sendable, CaseIterable {
    case smallHill, bigHill, rockRamp, bumps, mud, boostPad
    public var widthCells: Int { get }
    public var isTerrain: Bool { get }      // false for mud, boostPad
}
public struct PlacedPiece: Codable, Equatable, Sendable {
    public var kind: PieceKind; public var cell: Int; public var lane: Int?
    public init(kind: PieceKind, cell: Int, lane: Int? = nil)
}
public struct Track: Codable, Equatable, Sendable {
    public static let cellWidth = 4.0, startZoneCells = 5, finishZoneCells = 5, minLengthCells = 20, laneCount = 3
    public var lengthCells: Int; public var pieces: [PlacedPiece]
    public init(lengthCells: Int, pieces: [PlacedPiece])
    public func validate() throws(TrackError)
    public static func load(from data: Data) throws -> Track   // decode, then validate
}
public enum TrackError: Error, Equatable {
    case trackTooShort
    case outsideBuildZone(cell: Int)   // start zone, finish zone, negative, or runs past the end
    case overlap(cell: Int)            // any two pieces sharing a cell, except two surface pieces in different lanes
    case noFlatGap(cell: Int)          // terrain piece starting right after another terrain piece
    case laneRequired(cell: Int), laneNotAllowed(cell: Int), badLane(cell: Int)
}
```

`validate()` checks pieces in ascending `cell` order and throws for the first offender.

- [ ] **Step 1: `git init`, create `.gitignore` and `Package.swift`.**
- [ ] **Step 2: Write the failing tests**

```swift
@Test func validTrackPasses() throws {
    try Track(lengthCells: 40, pieces: [
        .init(kind: .smallHill, cell: 6), .init(kind: .mud, cell: 9, lane: 1),
        .init(kind: .boostPad, cell: 9, lane: 2), .init(kind: .bigHill, cell: 13)]).validate()
}
@Test(arguments: [
    ([PlacedPiece(kind: .smallHill, cell: 6), .init(kind: .bigHill, cell: 8)], TrackError.noFlatGap(cell: 8)),
    ([.init(kind: .smallHill, cell: 6), .init(kind: .rockRamp, cell: 7)], .overlap(cell: 7)),
    ([.init(kind: .smallHill, cell: 6), .init(kind: .mud, cell: 6, lane: 0)], .overlap(cell: 6)),
    ([.init(kind: .mud, cell: 8, lane: 1), .init(kind: .boostPad, cell: 9, lane: 1)], .overlap(cell: 9)),
    ([.init(kind: .smallHill, cell: 3)], .outsideBuildZone(cell: 3)),
    ([.init(kind: .bigHill, cell: 33)], .outsideBuildZone(cell: 33)),   // 33..36 enters finish zone 35..39
    ([.init(kind: .smallHill, cell: -1)], .outsideBuildZone(cell: -1)),
    ([.init(kind: .mud, cell: 8)], .laneRequired(cell: 8)),
    ([.init(kind: .smallHill, cell: 8, lane: 0)], .laneNotAllowed(cell: 8)),
    ([.init(kind: .mud, cell: 8, lane: 3)], .badLane(cell: 8)),
])
func invalidTrackThrows(pieces: [PlacedPiece], expected: TrackError) {
    #expect(throws: expected) { try Track(lengthCells: 40, pieces: pieces).validate() }
}
@Test func tooShort() { #expect(throws: TrackError.trackTooShort) { try Track(lengthCells: 19, pieces: []).validate() } }
@Test func roundTripsThroughJSON() throws {
    let t = Track(lengthCells: 40, pieces: [.init(kind: .rockRamp, cell: 10), .init(kind: .mud, cell: 20, lane: 2)])
    #expect(try Track.load(from: JSONEncoder().encode(t)) == t)
}
@Test func unknownKindFailsToLoad() {
    let json = Data(#"{"lengthCells":40,"pieces":[{"kind":"loop","cell":8}]}"#.utf8)
    #expect(throws: DecodingError.self) { try Track.load(from: json) }
}
@Test func invalidJSONTrackFailsToLoad() {
    let json = Data(#"{"lengthCells":40,"pieces":[{"kind":"mud","cell":8}]}"#.utf8)
    #expect(throws: TrackError.laneRequired(cell: 8)) { try Track.load(from: json) }
}
```

- [ ] **Step 3: Run `swift test --package-path "Packages/RaceCore"` — expect compile failure (types missing).**
- [ ] **Step 4: Implement `Track.swift` to the interface above.**
- [ ] **Step 5: Run the tests — expect all pass.**
- [ ] **Step 6: Commit** `feat: track format and validation`.

### Task 2: Terrain profile

**Files:**
- Create: `Packages/RaceCore/Sources/RaceCore/Terrain.swift`
- Test: `Packages/RaceCore/Tests/RaceCoreTests/TerrainTests.swift`

**Interfaces:**
- Consumes: `Track`, `PieceKind`, `Track.cellWidth`.
- Produces:

```swift
public struct Terrain: Sendable {
    public init(track: Track)                 // precondition: track is valid; surface pieces contribute no height
    public let length: Double                 // lengthCells * cellWidth
    public let finishX: Double                // length - 2 * cellWidth
    public func height(at x: Double) -> Double   // 0 outside 0...length
    public func slope(at x: Double) -> Double    // radians, atan of analytic derivative; 0 outside pieces
}
```

Shapes and heights come from the "Starting values" table; put the per-kind height next to `widthCells` as `PieceKind.height`.

- [ ] **Step 1: Write the failing tests** (tolerance 1e-9 unless stated)

```swift
let track = Track(lengthCells: 40, pieces: [.init(kind: .smallHill, cell: 6), .init(kind: .rockRamp, cell: 10),
                                            .init(kind: .bumps, cell: 15), .init(kind: .mud, cell: 20, lane: 0)])
let t = Terrain(track: track)
@Test func lengthAndFinish() { #expect(t.length == 160); #expect(t.finishX == 152) }
@Test func flatWhereNoTerrain() { for x in [-5.0, 0, 10, 82, 159, 200] { #expect(t.height(at: x) == 0); #expect(t.slope(at: x) == 0) } }
@Test func smallHillProfile() {            // spans x 24...32, crest at 28
    #expect(abs(t.height(at: 28) - 1.5) < 1e-9); #expect(abs(t.height(at: 24)) < 1e-9); #expect(abs(t.height(at: 32)) < 1e-9)
    #expect(t.slope(at: 26) > 0); #expect(t.slope(at: 30) < 0); #expect(abs(t.slope(at: 28)) < 1e-9)
}
@Test func rockRampProfile() {             // spans x 40...52, peak at 40 + 0.85*12 = 50.2
    #expect(abs(t.height(at: 50.2) - 2.5) < 1e-9); #expect(abs(t.height(at: 45.1) - 1.25) < 1e-9)
    #expect(t.slope(at: 45) > 0); #expect(t.slope(at: 51) < -0.9)
}
@Test func bumpsProfile() {                // spans x 60...72, crests at 62, 66, 70
    for x in [62.0, 66, 70] { #expect(abs(t.height(at: x) - 0.5) < 1e-9) }
    for x in [60.0, 64, 68, 72] { #expect(abs(t.height(at: x)) < 1e-9) }
}
@Test func slopeMatchesNumericDerivative() {
    for x in stride(from: 24.5, to: 72, by: 0.37) where abs(x - 50.2) > 0.01 {
        let numeric = atan((t.height(at: x + 1e-5) - t.height(at: x - 1e-5)) / 2e-5)
        #expect(abs(t.slope(at: x) - numeric) < 1e-4)
    }
}
```

- [ ] **Step 2: Run the tests — expect compile failure.**
- [ ] **Step 3: Implement `Terrain.swift`.**
- [ ] **Step 4: Run the tests — expect all pass.**
- [ ] **Step 5: Commit** `feat: terrain profile from track pieces`.

### Task 3: Race simulation — ground riding and finish

**Files:**
- Create: `Packages/RaceCore/Sources/RaceCore/Tuning.swift`, `RiderInput.swift`, `BikeState.swift`, `Race.swift`
- Test: `Packages/RaceCore/Tests/RaceCoreTests/GroundRidingTests.swift`

**Interfaces:**
- Consumes: `Track`, `Terrain`.
- Produces:

```swift
public struct Tuning: Codable, Equatable, Sendable { /* one `public var` Double per name in "Starting values", with those defaults */ public init() }
public struct RiderInput: Equatable, Sendable {
    public var gas = false, boost = false
    public var lean = 0.0                     // -1 lean back (nose up) ... +1 lean forward (nose down); clamped on use
    public init(gas: Bool = false, boost: Bool = false, lean: Double = 0)
}
public enum BikePhase: Equatable, Sendable { case grounded, airborne, crashed(remaining: Double) }
public struct BikeState: Equatable, Sendable {
    public var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
    public var angle = 0.0                    // radians, positive = nose up
    public var heat = 0.0                     // 0...1
    public var stallRemaining = 0.0           // seconds; > 0 means engine cut out
    public var phase = BikePhase.grounded
    public var finished = false
    public var speed: Double { get }          // hypot(vx, vy)
    public init()
}
public struct Race: Sendable {
    public static let dt = 1.0 / 60.0
    public let terrain: Terrain
    public var tuning: Tuning
    public private(set) var bike: BikeState
    public private(set) var time: Double      // stops advancing once bike.finished
    public init(track: Track, tuning: Tuning = Tuning(), bike: BikeState? = nil)   // default start: x = 2*cellWidth, on the ground
    public mutating func step(_ input: RiderInput)
}
```

Grounded model for this task: the bike has a scalar speed along the surface. Each step: accelerate by `gasAccel` when gas is held and speed is below `normalTopSpeed`, otherwise decelerate by `coastDecel`; add `−gravity·slopeGravityFactor·sin(slope)·dt`; clamp speed to `0...`; move `speed·cos(slope)·dt` in x; set `y = height(x)`, `angle = slope(x)`, `vx, vy` from speed and slope. The bike never rolls backwards. `Race.init` snaps a grounded starting bike to the terrain height and slope. When `x ≥ finishX`: `finished = true`, time freezes, input is treated as empty from then on.

- [ ] **Step 1: Write the failing tests**

```swift
let flat = Track(lengthCells: 60, pieces: [])
func run(_ r: inout Race, _ n: Int, _ i: RiderInput) { for _ in 0..<n { r.step(i) } }
@Test func gasReachesNormalTopSpeedAndHolds() {
    var r = Race(track: flat); var peak = 0.0
    for _ in 0..<300 { r.step(.init(gas: true)); peak = max(peak, r.bike.speed) }
    #expect(abs(r.bike.speed - 16) < 0.2); #expect(peak <= 16 + 8 * Race.dt)
}
@Test func coastsToStopWithoutGoingBackwards() {
    var r = Race(track: flat); run(&r, 120, .init(gas: true)); let x0 = r.bike.x
    run(&r, 600, .init()); #expect(r.bike.speed == 0); #expect(r.bike.x > x0)
    let x1 = r.bike.x; run(&r, 60, .init()); #expect(r.bike.x == x1)
}
@Test func followsTerrainWhenSlow() {
    var t = Tuning(); t.normalTopSpeed = 4
    var r = Race(track: Track(lengthCells: 60, pieces: [.init(kind: .smallHill, cell: 6)]), tuning: t)
    for _ in 0..<900 { r.step(.init(gas: true)); #expect(r.bike.phase == .grounded)
        #expect(abs(r.bike.y - r.terrain.height(at: r.bike.x)) < 1e-9) }
    #expect(r.bike.x > 32)
}
@Test func stoppedOnUphillDoesNotRollBack() {
    var b = BikeState(); b.x = 26
    var r = Race(track: Track(lengthCells: 60, pieces: [.init(kind: .smallHill, cell: 6)]), bike: b)
    run(&r, 120, .init()); #expect(r.bike.x == 26)
}
@Test func pullsAwayFromStandstillOnSteepestSlope() {      // big hill at cell 10 is steepest at x = 44
    var b = BikeState(); b.x = 44
    var r = Race(track: Track(lengthCells: 60, pieces: [.init(kind: .bigHill, cell: 10)]), bike: b)
    #expect(abs(r.bike.y - 1.75) < 1e-9); run(&r, 60, .init(gas: true)); #expect(r.bike.x > 45)
}
@Test func finishFreezesTimeAndIgnoresInput() {
    var r = Race(track: Track(lengthCells: 20, pieces: [])); var steps = 0
    while !r.bike.finished && steps < 5000 { r.step(.init(gas: true)); steps += 1 }
    #expect(r.bike.finished); let t = r.time
    run(&r, 600, .init(gas: true, boost: true)); #expect(r.time == t); #expect(r.bike.speed == 0)
}
@Test func timeAdvancesByDtPerStep() { var r = Race(track: flat); run(&r, 60, .init()); #expect(abs(r.time - 1) < 1e-9) }
```

- [ ] **Step 2: Run the tests — expect compile failure.**
- [ ] **Step 3: Implement the four files.**
- [ ] **Step 4: Run the tests — expect all pass.**
- [ ] **Step 5: Commit** `feat: ground riding and finish`.

### Task 4: Boost, heat and overheat stall

**Files:**
- Modify: `Packages/RaceCore/Sources/RaceCore/Race.swift`
- Test: `Packages/RaceCore/Tests/RaceCoreTests/HeatTests.swift`

**Interfaces:** consumes and produces nothing new; fills in `BikeState.heat` and `stallRemaining` behaviour.

Rules: boost implies gas. While boost is held and the engine is running: accelerate by `boostAccel` up to `boostTopSpeed`, and `heat += dt / heatFillTime`. Otherwise `heat −= dt / heatDrainTime` (floor 0). Above `normalTopSpeed` without boost the bike decelerates by `coastDecel` back to it. When heat reaches 1: `stallRemaining = stallDuration`, `heat = 0`. While `stallRemaining > 0` gas and boost do nothing and heat stays 0. Heat and stall timers run in every phase, including airborne and crashed.

- [ ] **Step 1: Write the failing tests**

```swift
let flat = Track(lengthCells: 400, pieces: [])
@Test func boostReachesBoostTopSpeed() {
    var r = Race(track: flat); for _ in 0..<200 { r.step(.init(boost: true)) }
    #expect(abs(r.bike.speed - 24) < 0.3)
}
@Test func overheatsAfterFillTimeThenStalls() {
    var r = Race(track: flat); var n = 0
    while r.bike.stallRemaining == 0 && n < 1000 { r.step(.init(boost: true)); n += 1 }
    #expect(abs(n - 240) <= 1); #expect(r.bike.heat == 0); #expect(abs(r.bike.stallRemaining - 3) < 0.02)
}
@Test func stalledEngineIgnoresGasThenRecovers() {
    var r = Race(track: flat); for _ in 0..<241 { r.step(.init(boost: true)) }
    var last = r.bike.speed
    for _ in 0..<170 { r.step(.init(gas: true, boost: true)); #expect(r.bike.speed < last || r.bike.speed == 0); last = r.bike.speed; #expect(r.bike.heat == 0) }
    for _ in 0..<60 { r.step(.init(gas: true)) }
    #expect(r.bike.stallRemaining == 0); #expect(r.bike.speed > last)
}
@Test func heatDrainsWhenNotBoosting() {
    var r = Race(track: flat); for _ in 0..<120 { r.step(.init(boost: true)) }
    #expect(abs(r.bike.heat - 0.5) < 0.01)
    for _ in 0..<180 { r.step(.init(gas: true)) }; #expect(r.bike.heat < 0.01)
    for _ in 0..<60 { r.step(.init(gas: true)) }; #expect(r.bike.heat == 0)
}
@Test func speedSettlesBackToNormalAfterBoost() {
    var r = Race(track: flat); for _ in 0..<120 { r.step(.init(boost: true)) }
    for _ in 0..<300 { r.step(.init(gas: true)) }; #expect(abs(r.bike.speed - 16) < 0.2)
}
```

- [ ] **Step 2: Run the tests — expect failures.**
- [ ] **Step 3: Implement in `Race.swift`.**
- [ ] **Step 4: Run all tests — expect pass.**
- [ ] **Step 5: Commit** `feat: boost, heat and overheat stall`.

### Task 5: Jumps, air lean, landings and crashes

**Files:**
- Modify: `Packages/RaceCore/Sources/RaceCore/Race.swift`
- Test: `Packages/RaceCore/Tests/RaceCoreTests/AirTests.swift`

**Interfaces:** fills in `BikePhase.airborne` and `.crashed`.

Algorithm:

- **Take-off (grounded):** after computing the new ground speed, form the velocity vector along the current slope and the ballistic candidate `x' = x + vx·dt`, `y' = y + vy·dt − ½·gravity·dt²`. If `y' > height(x') + 1e-6`, the bike becomes airborne at `(x', y')` with `vy −= gravity·dt`, keeping its angle. Otherwise it stays grounded as in Task 3.
- **Airborne:** ballistic motion; `angle −= clamp(lean, −1...1)·leanRate·dt`; gas and boost do not change velocity (heat rules still apply).
- **Landing:** when `y ≤ height(x)`: set `y = height(x)`. Let `d` be the absolute difference between `angle` and `slope(x)`, normalised to `0...π`. Let `s` be the velocity projected onto the slope direction, floored at 0. `d ≤ cleanLandingAngle`: grounded with speed `s`. `d ≤ crashLandingAngle`: grounded with speed `s·sloppyLandingSpeedFactor`. Otherwise `.crashed(remaining: crashDuration)`, velocity 0.
- **Crashed:** position fixed, input ignored, timer counts down; at 0 the bike is grounded, speed 0, `angle = slope(x)`.
- **Finish** applies in every phase when `x ≥ finishX`; a crashed bike can only finish by having crossed the line during the landing step.

- [ ] **Step 1: Write the failing tests**

```swift
let flat = Track(lengthCells: 400, pieces: [])
func airborne(y: Double = 0.5, vx: Double = 16, vy: Double = -2, angle: Double = 0, x: Double = 100) -> BikeState {
    var b = BikeState(); b.x = x; b.y = y; b.vx = vx; b.vy = vy; b.angle = angle; b.phase = .airborne; return b
}
func land(_ r: inout Race) { var n = 0; while r.bike.phase == .airborne && n < 600 { r.step(.init()); n += 1 } }
@Test func takesOffFromBigHillAtSpeed() {
    var r = Race(track: Track(lengthCells: 60, pieces: [.init(kind: .bigHill, cell: 10)])); var flew = false
    for _ in 0..<600 { r.step(.init(gas: true)); if r.bike.phase == .airborne { flew = true; #expect(r.bike.x > 44) } }   // only on the convex part, past the inflection
    #expect(flew)
}
@Test func leanRotatesOnlyInAir() {
    var r = Race(track: flat, bike: airborne(y: 50)); for _ in 0..<30 { r.step(.init(lean: 1)) }
    #expect(abs(r.bike.angle - (-1.25)) < 1e-9)
    for _ in 0..<30 { r.step(.init(lean: -5)) }; #expect(abs(r.bike.angle) < 1e-9)      // lean clamps to -1
    var g = Race(track: flat); for _ in 0..<30 { g.step(.init(gas: true, lean: 1)) }; #expect(g.bike.angle == 0)
}
@Test func cleanLandingKeepsSpeed() {
    var r = Race(track: flat, bike: airborne(angle: 0.1)); land(&r)
    #expect(r.bike.phase == .grounded); #expect(abs(r.bike.speed - 16) < 0.1); #expect(r.bike.y == 0)
}
@Test func sloppyLandingLosesSpeed() {
    var r = Race(track: flat, bike: airborne(angle: 0.5)); land(&r)
    #expect(r.bike.phase == .grounded); #expect(abs(r.bike.speed - 9.6) < 0.1)
}
@Test func badLandingCrashesThenResets() {
    var r = Race(track: flat, bike: airborne(angle: 1.2)); land(&r)
    #expect(r.bike.phase == .crashed(remaining: 2.0)); #expect(r.bike.speed == 0); let x = r.bike.x
    for _ in 0..<119 { r.step(.init(gas: true)) }; #expect(r.bike.x == x); #expect(r.bike.phase != .grounded)
    for _ in 0..<2 { r.step(.init()) }; #expect(r.bike.phase == .grounded); #expect(r.bike.angle == 0)
}
@Test func fullFlipEndingLevelIsClean() {
    var r = Race(track: flat, bike: airborne(angle: 2 * .pi + 0.1)); land(&r)
    #expect(r.bike.phase == .grounded); #expect(abs(r.bike.speed - 16) < 0.1)
    var u = Race(track: flat, bike: airborne(angle: .pi)); land(&u)          // upside down
    if case .crashed = u.bike.phase {} else { Issue.record("upside-down landing must crash") }
}
@Test func heatAndStallRunWhileAirborne() {
    var b = airborne(y: 200); b.stallRemaining = 1.0
    var r = Race(track: flat, bike: b); for _ in 0..<61 { r.step(.init()) }; #expect(r.bike.stallRemaining == 0)
}
@Test func finishesWhileAirborne() {
    var r = Race(track: Track(lengthCells: 20, pieces: []), bike: airborne(y: 5, x: 70))   // finishX = 72
    for _ in 0..<30 { r.step(.init()) }; #expect(r.bike.finished); let t = r.time
    for _ in 0..<60 { r.step(.init(gas: true)) }; #expect(r.time == t)
}
```

- [ ] **Step 2: Run the tests — expect failures.**
- [ ] **Step 3: Implement in `Race.swift`.**
- [ ] **Step 4: Run all tests (Tasks 1–5) — expect pass.** If `followsTerrainWhenSlow` now reports airborne, the take-off threshold is wrong, not the test.
- [ ] **Step 5: Commit** `feat: jumps, air lean, landings and crashes`.

### Task 6: Step clock, prototype track, soak and repeatability

**Files:**
- Create: `Packages/RaceCore/Sources/RaceCore/FixedStepClock.swift`, `PrototypeTrack.swift`
- Test: `Packages/RaceCore/Tests/RaceCoreTests/FixedStepClockTests.swift`, `SoakTests.swift`

**Interfaces — produces:**

```swift
public struct FixedStepClock: Sendable {
    public static let maxStepsPerAdvance = 5
    public init()
    public mutating func advance(by seconds: Double) -> Int   // whole steps of Race.dt owed; surplus beyond the cap is dropped
}
extension Track { public static let prototype: Track }
```

`Track.prototype`: 150 cells, pieces at cells `8 smallHill, 13 bigHill, 20 bumps, 26 rockRamp, 32 smallHill, 35 smallHill, 40 bigHill, 46 bigHill, 54 rockRamp, 60 bumps, 66 bigHill, 73 smallHill, 78 rockRamp, 85 bigHill, 91 bumps, 97 smallHill, 100 smallHill, 105 bigHill, 112 rockRamp, 118 bigHill, 125 smallHill, 130 bigHill, 137 rockRamp` (ends before the finish zone at 145). Layout is a starting point for Task 8 tuning.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func oneFrameOneStep() { var c = FixedStepClock(); #expect(c.advance(by: 1.0 / 60) == 1) }
@Test func accumulatesPartialFrames() { var c = FixedStepClock(); #expect(c.advance(by: 0.008) == 0); #expect(c.advance(by: 0.010) == 1) }
@Test func capsCatchUpAndDropsSurplus() { var c = FixedStepClock(); #expect(c.advance(by: 3.0) == 5); #expect(c.advance(by: 0) == 0) }
@Test func ignoresBadInput() { var c = FixedStepClock(); for s in [-1.0, .nan, .infinity] { #expect(c.advance(by: s) == 0) } }

@Test func prototypeTrackIsValid() throws { try Track.prototype.validate() }

struct SplitMix64: RandomNumberGenerator { var state: UInt64
    mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }
func inputs(seed: UInt64, count: Int) -> [RiderInput] {       // each random input held for 20 steps
    var g = SplitMix64(state: seed)
    return (0..<count / 20).flatMap { _ -> [RiderInput] in
        let i = RiderInput(gas: Bool.random(using: &g), boost: Bool.random(using: &g), lean: Double.random(in: -1...1, using: &g))
        return Array(repeating: i, count: 20) }
}
@Test(arguments: [1, 2, 3, 4, 5] as [UInt64]) func soakKeepsInvariants(seed: UInt64) {
    var r = Race(track: .prototype); var lastX = r.bike.x
    for i in inputs(seed: seed, count: 20_000) { r.step(i); let b = r.bike
        #expect(b.y >= r.terrain.height(at: b.x) - 1e-6)
        #expect([b.x, b.y, b.vx, b.vy, b.angle, b.heat, b.stallRemaining].allSatisfy(\.isFinite))
        #expect((0...1).contains(b.heat)); #expect(b.x >= lastX); lastX = b.x }
}
@Test func prototypeTrackCanBeFinishedOnGasAlone() {
    var r = Race(track: .prototype); var n = 0
    while !r.bike.finished && n < 60 * 600 { r.step(.init(gas: true)); n += 1 }
    #expect(r.bike.finished)
}
@Test func sameInputsGiveSameRace() {
    let seq = inputs(seed: 42, count: 6_000); var a = Race(track: .prototype), b = Race(track: .prototype)
    for i in seq { a.step(i); b.step(i) }; #expect(a.bike == b.bike); #expect(a.time == b.time)
}
```

- [ ] **Step 2: Run the tests — expect compile failure, then after implementing the two files, real failures point at simulation bugs.**
- [ ] **Step 3: Implement the two files; fix any simulation defect the soak exposes in `Race.swift` (add a focused regression test for each).**
- [ ] **Step 4: Run all tests — expect pass.**
- [ ] **Step 5: Commit** `feat: step clock, prototype track, soak tests`.

### Task 7: App shell — draw the race, keyboard and touch, HUD

**Files:**
- Create: `project.yml` (XcodeGen: app target `DuneBikes`, bundle id `dev.placeholder.dunebikes`, iOS 17, devices iPhone and iPad, landscape left and right only, Swift 6, local package `Packages/RaceCore`, sources `App/Sources`, resources `App/Resources`)
- Create: `App/Sources/DuneBikesApp.swift` — SwiftUI `App`, full-screen `SpriteView`, status bar hidden
- Create: `App/Sources/GameScene.swift` — owns `Race`, `FixedStepClock`, nodes; `update(_:)` steps the race
- Create: `App/Sources/TerrainNode.swift` — one filled `SKShapeNode` path sampled every 0.25 m
- Create: `App/Sources/BikeNode.swift` — rectangle body, two circle wheels, rider block; tinted red while crashed, blue while stalled
- Create: `App/Sources/HUDNode.swift` — heat bar, time as `0:00.0`, speed as a whole number
- Create: `App/Sources/InputSource.swift` — merges keyboard and touch into one `RiderInput`
- Create: `App/Resources/Localizable.xcstrings` (empty catalog, English base)

**Interfaces:**
- Consumes: `Race`, `RiderInput`, `BikeState`, `Terrain`, `FixedStepClock`, `Track.prototype`, `Tuning`.
- Produces: `GameScene.restart(with tuning: Tuning)`, `GameScene.tuning: Tuning` (used by Task 8); `InputSource.current: RiderInput`, `InputSource.restartPressed: Bool`.

Decisions:
- Scale 12 points per metre; scene size 480×270 points, `.aspectFill`. Camera keeps the bike 30 % from the left edge and eases vertically toward the bike.
- Keyboard (polled each frame through `GCKeyboard.coalesced`): `Z` gas, `X` boost, left arrow lean back, right arrow lean forward, `R` restart.
- Touch: four on-screen buttons — bottom-left pair lean back and lean forward, bottom-right pair gas and boost; each at least 64 points, multi-touch enabled, a button is held while any touch is inside it. Arrow and flame glyphs from SF Symbols, no words.
- When finished: show the final time large in the centre; `R` or a restart button (circular-arrow glyph) starts again.

- [ ] **Step 1: Check tooling.** Run `which xcodegen` and `xcrun simctl list devices available`. If XcodeGen is missing, ask the owner before `brew install xcodegen`. If no iOS simulator is listed (none were on 2026-11-18), stop and ask the owner to install the iOS platform in Xcode settings; do not download it unasked.
- [ ] **Step 2: Write `project.yml`, run `xcodegen generate`, confirm `DuneBikes.xcodeproj` appears and `xcodebuild -list` shows scheme `DuneBikes`.**
- [ ] **Step 3: Implement the app files.**
- [ ] **Step 4: Build:** `xcodebuild -project DuneBikes.xcodeproj -scheme DuneBikes -destination 'generic/platform=iOS Simulator' build` — expect `BUILD SUCCEEDED` with no warnings from project code.
- [ ] **Step 5: Run in the simulator and verify by screenshot:** terrain and bike are visible at start; holding the gas button for 3 s moves the bike and the timer; holding boost fills the heat bar and the bike turns blue on overheat; the bike leaves the ground over the first big hill.
- [ ] **Step 6: Run `swift test --package-path "Packages/RaceCore"` again — expect pass.**
- [ ] **Step 7: Commit** `feat: playable grey-box app`.

### Task 8: Tuning panel and owner playtest

**Files:**
- Create: `App/Sources/TuningPanel.swift` — SwiftUI sheet opened from a slider-glyph button in the top-right corner
- Modify: `App/Sources/DuneBikesApp.swift` (present the panel), `App/Sources/GameScene.swift` (pause while the panel is open)
- Create: `docs/tuning-notes.md` — the agreed numbers after the playtest

**Interfaces:** consumes `GameScene.tuning`, `GameScene.restart(with:)`, `Tuning` (Codable).

Panel: one slider per `Tuning` field, labelled with the field name and current value (developer tool, English only, not localised). Ranges are 0.25× to 3× each default. Buttons: reset to defaults; copy values (JSON of `Tuning` to the pasteboard); close, which restarts the race with the new values.

- [ ] **Step 1: Implement the panel and wiring.**
- [ ] **Step 2: Build and verify in the simulator by screenshot:** panel opens, a changed `gravity` value survives close and visibly changes a jump, copy puts valid `Tuning` JSON on the pasteboard (`xcrun simctl pbpaste booted`).
- [ ] **Step 3: Commit** `feat: tuning panel`.
- [ ] **Step 4: Owner playtest in the simulator (keyboard).** Hand over the run instructions and key map. For play on the owner's iPhone, ask the owner for the signing team and bundle prefix used for their Nasreddin game, set them in `project.yml`, and install; do not guess them.
- [ ] **Step 5: Record the owner's copied values and feel notes in `docs/tuning-notes.md`, make them the new `Tuning` defaults, update any test constant that encoded an old default, run all tests, commit** `chore: tuned riding defaults`.

**Done when:** the owner says the riding feels right. Changes to the model itself (not just numbers) go back to the spec before the next plan.
