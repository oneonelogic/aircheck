import SwiftUI

@main
struct AircheckApp: App {
    var body: some Scene {
        WindowGroup {
            // Spike 1: prove clip -> Apple Music song -> clip handoff.
            // Replace with the real hot-clock player once the spike passes.
            HandoffSpikeView()
        }
    }
}
