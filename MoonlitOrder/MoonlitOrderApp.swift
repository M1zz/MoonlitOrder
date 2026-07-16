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
    @State private var showGMPreview = false

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
                } else if let sketchState = game.sketchState {
                    SketchRootView(state: sketchState)
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
            } else if args.contains("-demoSketchAuto") {
                game.startDemo(kind: .sketch, auto: true)
            } else if args.contains("-demoSketch") {
                game.startDemo(kind: .sketch)
            } else if args.contains("-demo") {
                game.startDemo(kind: .moonlit)
            } else if args.contains("-kickPreviewGame") {
                game.startKickPreview(midGame: true)
            } else if args.contains("-kickPreview") {
                game.startKickPreview(midGame: false)
            } else if args.contains("-gmPreview") {
                // GM 패널 시연: 봇 게임을 열고 패널을 띄운 뒤 강제 진행까지 실행
                game.startKickPreview(midGame: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showGMPreview = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { game.gmForceAdvance() }
            } else if args.contains("-autoHost") {
                // 멀티 기기 시연: 즉시 방을 연다
                if let name = argValue(args, "-playerName") { game.playerName = name }
                game.hostGame(kind: .moonlit)
            } else if args.contains("-autoJoin") {
                // 멀티 기기 시연: 발견되는 첫 방에 자동 참가
                if let name = argValue(args, "-playerName") { game.playerName = name }
                game.autoJoinRoom = true
                game.startBrowsing()
            }
        }
        .sheet(isPresented: $showGMPreview) {
            GMPanelView()
                .presentationDetents([.medium, .large])
        }
    }

    /// 실행 인자에서 "-이름 값" 쌍의 값을 읽는다 (시연용)
    private func argValue(_ args: [String], _ name: String) -> String? {
        guard let i = args.firstIndex(of: name), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
}
