import Testing
import Foundation
@testable import RaceCore

struct WheelieTests {
    let flat = Track(lengthCells: 80, pieces: [])
    let back = RiderInput(gas: true, lean: -1)
    func run(_ r: inout Race, _ n: Int, _ i: RiderInput) { for _ in 0..<n { r.step(i) } }
    func crashed(_ b: BikeState) -> Bool { if case .crashed = b.phase { true } else { false } }

    @Test func leaningBackWithGasLiftsTheFrontWheel() {
        var r = Race(track: flat); run(&r, 60, .init(gas: true)); #expect(r.bike.wheelie == 0)
        run(&r, 30, back)
        #expect(abs(r.bike.wheelie - 0.5 * r.tuning.wheelieRate) < 1e-9); #expect(r.bike.phase == .grounded)
    }
    @Test func lettingGoDropsTheWheelAndLeaningForwardDropsItFaster() {
        var a = Race(track: flat); run(&a, 60, .init(gas: true)); run(&a, 40, back); var b = a
        run(&a, 6, .init(gas: true)); run(&b, 6, .init(gas: true, lean: 1))
        #expect(a.bike.wheelie > 0); #expect(b.bike.wheelie < a.bike.wheelie)
        run(&a, 60, .init(gas: true)); #expect(a.bike.wheelie == 0)
    }
    @Test func noLiftWithoutGasOrAtAStandstill() {
        var r = Race(track: flat); run(&r, 60, .init(lean: -1)); #expect(r.bike.wheelie == 0)
        run(&r, 120, .init(gas: true)); run(&r, 30, .init(lean: -1)); #expect(r.bike.wheelie == 0)
    }
    @Test func pullingTooFarFlipsTheBike() {
        var r = Race(track: flat); run(&r, 60, .init(gas: true)); var steps = 0
        while !crashed(r.bike) && steps < 600 { r.step(back); steps += 1 }
        #expect(crashed(r.bike)); #expect(r.bike.speed == 0); #expect(r.bike.wheelie == 0)
        let expected = r.tuning.wheelieFlipAngle / r.tuning.wheelieRate / Race.dt
        #expect(abs(Double(steps) - expected) <= 1)
        run(&r, 300, .init(gas: true)); #expect(r.bike.phase == .grounded); #expect(r.bike.speed > 5)
    }
    @Test func aWheelieFloatsOverMud() {
        let t = Track(lengthCells: 60, pieces: [.init(kind: .mud, cell: 20, lane: 1)])
        var r = Race(track: t); var slowest = 99.0
        while r.bike.x < 90 {
            // Lift before the mud (x 80...88) and hold the wheel at about 0.5 rad through it.
            let lift = r.bike.x > 70 && r.bike.wheelie < 0.5
            r.step(.init(gas: true, lean: lift ? -1 : 0))
            if r.bike.x > 81 && r.bike.x < 88 { slowest = min(slowest, r.bike.speed) }
        }
        #expect(slowest > r.tuning.normalTopSpeed - 0.5); #expect(!crashed(r.bike))
    }
    @Test func aLowWheelieStillSinksIntoMud() {
        let t = Track(lengthCells: 60, pieces: [.init(kind: .mud, cell: 20, lane: 1)])
        var r = Race(track: t); var slowest = 99.0
        while r.bike.x < 90 {
            let lift = r.bike.x > 70 && r.bike.wheelie < r.tuning.wheelieFloatAngle * 0.5
            r.step(.init(gas: true, lean: lift ? -1 : 0))
            if r.bike.x > 81 && r.bike.x < 88 { slowest = min(slowest, r.bike.speed) }
        }
        #expect(abs(slowest - r.tuning.mudTopSpeed) < 0.5)
    }
    @Test func takingOffInAWheelieLeavesTheGroundNoseUp() {
        let t = Track(lengthCells: 60, pieces: [.init(kind: .rockRamp, cell: 12)])
        var plain = Race(track: t), lifted = Race(track: t)
        while plain.bike.phase == .grounded { plain.step(.init(gas: true)) }
        while lifted.bike.phase == .grounded {
            lifted.step(.init(gas: true, lean: lifted.bike.x > 40 && lifted.bike.wheelie < 0.4 ? -1 : 0))
        }
        #expect(lifted.bike.phase == .airborne); #expect(lifted.bike.wheelie == 0)
        #expect(lifted.bike.angle > plain.bike.angle + 0.25)
    }
    @Test func rivalsNeverWheelie() {
        var r = Race(track: .duskRun, rivals: 3)
        var riders = [Rival(skill: .rookie, seed: 1), Rival(skill: .steady, seed: 2), Rival(skill: .sharp, seed: 3)]
        var highest = 0.0
        for _ in 0..<3600 {
            var inputs = [RiderInput()]
            for i in riders.indices { inputs.append(riders[i].input(for: i + 1, in: r)) }
            r.step(inputs)
            highest = max(highest, r.bikes.map(\.wheelie).max() ?? 0)
        }
        #expect(highest == 0)
    }
}
