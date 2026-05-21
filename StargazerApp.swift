import SwiftUI

@main
struct StargazerApp: App {
    @StateObject private var model = StargazerModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onAppear {
                    model.startTracking()
                }
        }
    }
}
