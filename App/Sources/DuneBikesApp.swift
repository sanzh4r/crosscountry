import RaceCore
import SpriteKit
import SwiftUI

@main
struct DuneBikesApp: App {
    @State private var scene = GameScene()
    @State private var editedTuning = Tuning()
    @State private var showsPanel = false

    /// The tuning panel is a development tool: never in release builds, and in debug
    /// builds only when launched with TUNING set in the environment.
    private static var showsTuningButton: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["TUNING"] != nil
        #else
        false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            SpriteView(scene: scene, preferredFramesPerSecond: 60)
                .ignoresSafeArea()
                .statusBarHidden()
                .overlay(alignment: .topTrailing) {
                    if Self.showsTuningButton { Button {
                        editedTuning = scene.tuning
                        scene.isPaused = true
                        showsPanel = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(Text(verbatim: "Tuning"))
                    .padding(8) }
                }
                .sheet(isPresented: $showsPanel, onDismiss: {
                    scene.restart(with: editedTuning)
                    scene.isPaused = false
                }, content: {
                    TuningPanel(tuning: $editedTuning) { showsPanel = false }
                })
        }
    }
}
