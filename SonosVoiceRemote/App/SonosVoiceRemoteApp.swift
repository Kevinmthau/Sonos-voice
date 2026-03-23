import SwiftUI

@main
@MainActor
struct SonosVoiceRemoteApp: App {
    @StateObject private var viewModel = AppEnvironment.makeViewModel()

    var body: some Scene {
        WindowGroup {
            VoiceRemoteView(viewModel: viewModel)
                .onOpenURL { url in
                    Task {
                        await viewModel.handleIncomingURL(url)
                    }
                }
        }
    }
}
