import SwiftUI

@main
struct RaceMeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // Dark only. There is no light theme and there isn't going to be
                // one — the palette is built on a deep pre-dawn base that glass
                // needs something to refract, and inverting it would destroy the
                // one rule the whole product rests on.
                .preferredColorScheme(.dark)
                .tint(Track.you)
        }
    }
}
