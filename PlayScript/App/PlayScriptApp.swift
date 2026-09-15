import SwiftUI
import StoryCore

@main
struct PlayScriptApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @State private var auth = AuthModel()
    @State private var model: ReadingModel?
    @State private var loadFailed = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !auth.isAuthenticated {
                LoginView(auth: auth)
            } else if let model {
                LibraryView(model: model)
                    .fullScreenCover(isPresented: Binding(
                        get: { model.isReading },
                        set: { if !$0 { model.returnToLibrary() } }
                    )) {
                        BookTurnHost(model: model).ignoresSafeArea()
                    }
            } else if loadFailed {
                ContentUnavailableView {
                    Label("Our story couldn’t open", systemImage: "book.closed")
                } description: {
                    Text("The story file is unavailable. Please try opening PlayScript again.")
                } actions: {
                    Button("Try again", action: loadStory)
                }
            } else {
                ProgressView().tint(Palette.rose)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: auth.isAuthenticated)
        .task(id: auth.isAuthenticated) { if auth.isAuthenticated && model == nil { loadStory() } }
        .onChange(of: scenePhase) { _, phase in
            model?.setActive(phase == .active)
        }
    }

    private func loadStory() {
        do {
            model = ReadingModel(story: try Story.bundled())
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}
