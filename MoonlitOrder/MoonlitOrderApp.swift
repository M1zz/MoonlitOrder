import SwiftUI

@main
struct MoonlitOrderApp: App {
    @StateObject private var game = GameViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var game: GameViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            switch game.mode {
            case .idle:
                HomeView()
            case .browsing, .connecting:
                BrowseView()
            case .hosting, .playing:
                if game.showDemoIntro {
                    DemoIntroView()
                } else if let liarState = game.liarState {
                    LiarRootView(state: liarState)
                } else if let wolfState = game.wolfState {
                    WolfRootView(state: wolfState)
                } else if let state = game.publicState {
                    if state.phase == .lobby {
                        LobbyView(state: state)
                    } else {
                        GameView(state: state)
                    }
                } else {
                    ProgressView("연결 중…")
                        .tint(.white)
                }
            }
        }
        .alert("알림", isPresented: Binding(
            get: { game.errorMessage != nil },
            set: { if !$0 { game.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { game.errorMessage = nil }
        } message: {
            Text(game.errorMessage ?? "")
        }
        .onChange(of: scenePhase) { newPhase in
            game.handleScenePhase(newPhase)
        }
        .onAppear {
            // 실행 인자로 게임방법(데모) 판을 바로 연다 (시뮬레이터 시연용)
            guard game.mode == .idle else { return }
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-demoLiar") {
                game.startDemo(kind: .liar)
            } else if args.contains("-demoWolf") {
                game.startDemo(kind: .wolf)
            } else if args.contains("-demo") {
                game.startDemo(kind: .moonlit)
            }
        }
    }
}
