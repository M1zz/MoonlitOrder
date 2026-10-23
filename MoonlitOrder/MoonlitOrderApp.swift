import SwiftUI
import TipKit
import LeeoKit

@main
struct MoonlitOrderApp: App {
    @StateObject private var game = GameViewModel()

    init() {
        // 첫 실행 안내가 생기기 전부터 쓰던 사람에게는 안내를 띄우지 않는다 (뷰모델이 ID 를 만들기 전에 판단).
        MoonlitOrderOnboarding.skipForExistingPlayers()

        // 사용량 기록 · 크래시 진단 · 익명 사용 통계 · 원격 킬스위치. 실패해도 게임은 그대로 돈다.
        // 통계·진단 스위치는 지난 실행에 받아 둔 값으로 판단한다(이번 갱신은 다음 실행부터 반영).
        LeeoKit.bootstrap(
            MoonlitOrderSpec.self,
            flags: MoonlitOrderFlag.self,
            diagnostics: LeeoRemoteFlags.isEnabled(MoonlitOrderFlag.diagnosticsEnabled),
            usageReporting: LeeoRemoteFlags.isEnabled(MoonlitOrderFlag.usageReportingEnabled))

        // 사용 팁 — 화면당 하나씩, TipKit 이 표시 빈도를 관리한다.
        try? Tips.configure([.displayFrequency(.daily)])
        if RootView.isScriptedLaunch { Tips.hideAllTipsForTesting() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .preferredColorScheme(.dark)
                .leeoSatisfactionCheck(MoonlitOrderSpec.self)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var game: GameViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showGMPreview = false
    @State private var showSupport = false
    @AppStorage(MoonlitOrderOnboarding.hasSeenOnboardingKey) private var hasSeenOnboarding = false
    @ObservedObject private var shortcuts = ShortcutRouter.shared

    /// 시연·스크린샷용 실행 인자로 켠 실행인가. 이때는 첫 실행 안내·팁을 띄우지 않는다.
    static var isScriptedLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains { arg in
            arg.hasPrefix("-demo") || arg.hasPrefix("-kickPreview")
                || ["-gmPreview", "-autoHost", "-autoJoin", "-screenshotScene"].contains(arg)
        }
    }

    private var showOnboarding: Binding<Bool> {
        Binding(
            get: { !hasSeenOnboarding && !Self.isScriptedLaunch },
            set: { if !$0 { hasSeenOnboarding = true } })
    }

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

            // 홈 화면에서만 노출되는 설정(지원) 진입점
            if game.mode == .idle {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showSupport = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(10)
                        }
                        .accessibilityLabel("설정")
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showSupport) {
            MoonlitOrderSupportView()
        }
        .fullScreenCover(isPresented: showOnboarding) {
            MoonlitOrderOnboardingView { hasSeenOnboarding = true }
        }
        .onReceive(shortcuts.$pending) { _ in runPendingShortcut() }
        .onChange(of: hasSeenOnboarding) { _ in runPendingShortcut() }
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
            if let scene = GameViewModel.screenshotScene {
                game.startScreenshotScene(scene)
            } else if args.contains("-demoLiar") {
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

    /// 단축어·Siri 로 받은 할 일을 실행한다. 첫 실행 안내를 다 본 뒤 홈 화면에서만 한다 —
    /// 게임 중이면 진행 중인 판을 깨지 않도록 버린다.
    private func runPendingShortcut() {
        guard let action = shortcuts.pending, hasSeenOnboarding || Self.isScriptedLaunch else { return }
        shortcuts.pending = nil
        guard game.mode == .idle else { return }
        showSupport = false

        switch action {
        case .browse:
            game.startBrowsing()
        case .host(let kind), .practice(let kind):
            guard kind.isRemotelyEnabled else {
                game.errorMessage = String(localized: "\(kind.displayName)은(는) 잠시 점검 중이에요. 다른 게임을 골라 주세요.")
                return
            }
            if case .host = action {
                game.hostGame(kind: kind)
            } else {
                game.startDemo(kind: kind)
            }
        }
    }

    /// 실행 인자에서 "-이름 값" 쌍의 값을 읽는다 (시연용)
    private func argValue(_ args: [String], _ name: String) -> String? {
        guard let i = args.firstIndex(of: name), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
}
