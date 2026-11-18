import RaceCore
import SwiftUI
import UIKit

/// Developer tool: one slider per `Tuning` field. English only, deliberately not localised.
struct TuningPanel: View {
    @Binding var tuning: Tuning
    let close: () -> Void

    /// Every `Tuning` field, defined once; each gets a slider.
    private static let fields: [(name: String, keyPath: WritableKeyPath<Tuning, Double>)] = [
        ("gravity", \.gravity),
        ("slopeGravityFactor", \.slopeGravityFactor),
        ("gasAccel", \.gasAccel),
        ("boostAccel", \.boostAccel),
        ("normalTopSpeed", \.normalTopSpeed),
        ("boostTopSpeed", \.boostTopSpeed),
        ("coastDecel", \.coastDecel),
        ("minTakeoffSpeed", \.minTakeoffSpeed),
        ("leanRate", \.leanRate),
        ("cleanLandingAngle", \.cleanLandingAngle),
        ("crashLandingAngle", \.crashLandingAngle),
        ("sloppyLandingSpeedFactor", \.sloppyLandingSpeedFactor),
        ("crashDuration", \.crashDuration),
        ("stallDuration", \.stallDuration),
        ("heatFillTime", \.heatFillTime),
        ("heatDrainTime", \.heatDrainTime),
    ]

    var body: some View {
        NavigationStack {
            List(Self.fields, id: \.name) { field in
                let base = Tuning()[keyPath: field.keyPath]
                VStack(alignment: .leading) {
                    HStack {
                        Text(verbatim: field.name)
                        Spacer()
                        Text(verbatim: String(format: "%.2f", tuning[keyPath: field.keyPath]))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $tuning[dynamicMember: field.keyPath], in: (0.25 * base)...(3 * base))
                }
            }
            .navigationTitle(Text(verbatim: "Tuning"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { tuning = Tuning() } label: { Image(systemName: "arrow.counterclockwise") }
                        .accessibilityLabel(Text(verbatim: "Reset to defaults"))
                    Button(action: copyValues) { Image(systemName: "doc.on.doc") }
                        .accessibilityLabel(Text(verbatim: "Copy values"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: close) { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel(Text(verbatim: "Close and restart"))
                }
            }
        }
    }

    private func copyValues() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(tuning), let json = String(data: data, encoding: .utf8) {
            UIPasteboard.general.string = json
        }
    }
}
