//
//  MoonlitOrderShortcuts.swift
//  MoonlitOrder
//
//  단축어·Siri·Spotlight 에서 앱의 핵심 동작을 바로 연다.
//   • "○○ 방 만들기" — 친구들이 모였을 때 호스트가 가장 먼저 하는 일
//   • "주변 방 찾기" — 참가하는 사람이 가장 먼저 하는 일
//   • "○○ 연습하기" — 혼자서 봇과 규칙 익히기
//
//  인텐트는 앱을 연 뒤 ShortcutRouter 에 할 일을 남기고, RootView 가 홈 화면일 때 실행한다.
//  게임 중에는 진행 중인 판을 깨지 않도록 무시한다.
//

import AppIntents
import Foundation

// MARK: - 게임 종류 (단축어 매개변수)

enum PartyGameAppEnum: String, AppEnum {
    case moonlit, liar, wolf, sketch

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "게임" }

    static var caseDisplayRepresentations: [PartyGameAppEnum: DisplayRepresentation] {
        [
            .moonlit: DisplayRepresentation(title: "달빛 결사", image: .init(systemName: "moon.stars.fill")),
            .liar:    DisplayRepresentation(title: "라이어 게임", image: .init(systemName: "theatermasks.fill")),
            .wolf:    DisplayRepresentation(title: "달 없는 밤", image: .init(systemName: "flame.fill")),
            .sketch:  DisplayRepresentation(title: "달빛 화실", image: .init(systemName: "paintbrush.pointed.fill")),
        ]
    }

    var kind: GameViewModel.GameKind {
        switch self {
        case .moonlit: return .moonlit
        case .liar:    return .liar
        case .wolf:    return .wolf
        case .sketch:  return .sketch
        }
    }
}

// MARK: - 앱 안으로 할 일 전달

/// 인텐트 → 화면. 인텐트는 앱 프로세스 안에서 돌지만 뷰모델을 직접 쥐고 있지 않으므로
/// 할 일을 여기 남기면 RootView 가 받아 실행한다.
@MainActor
final class ShortcutRouter: ObservableObject {
    enum Action: Equatable {
        case host(GameViewModel.GameKind)
        case browse
        case practice(GameViewModel.GameKind)
    }

    static let shared = ShortcutRouter()

    @Published var pending: Action?
}

// MARK: - 인텐트

struct HostRoomIntent: AppIntent {
    static var title: LocalizedStringResource = "방 만들기"
    static var description = IntentDescription("고른 게임의 방을 열어 친구들이 들어올 수 있게 해요.")
    static var openAppWhenRun = true

    @Parameter(title: "게임", default: .moonlit)
    var game: PartyGameAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$game) 방 만들기")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutRouter.shared.pending = .host(game.kind)
        return .result()
    }
}

struct BrowseRoomsIntent: AppIntent {
    static var title: LocalizedStringResource = "주변 방 찾기"
    static var description = IntentDescription("근처 친구가 만든 방을 찾아 참가해요.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutRouter.shared.pending = .browse
        return .result()
    }
}

struct PracticeGameIntent: AppIntent {
    static var title: LocalizedStringResource = "봇과 연습하기"
    static var description = IntentDescription("혼자서 봇들과 한 판을 해 보며 규칙을 익혀요.")
    static var openAppWhenRun = true

    @Parameter(title: "게임", default: .moonlit)
    var game: PartyGameAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$game) 연습하기")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutRouter.shared.pending = .practice(game.kind)
        return .result()
    }
}

// MARK: - 단축어 앱·Siri 에 올리는 목록

struct MoonlitOrderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: HostRoomIntent(),
            phrases: [
                "\(.applicationName)에서 \(\.$game) 방 만들기",
                "\(.applicationName) \(\.$game) 방 만들어 줘",
                "\(.applicationName)에서 방 만들기",
            ],
            shortTitle: "방 만들기",
            systemImageName: "house.fill"
        )
        AppShortcut(
            intent: BrowseRoomsIntent(),
            phrases: [
                "\(.applicationName)에서 주변 방 찾기",
                "\(.applicationName) 방 찾아 줘",
                "\(.applicationName) 게임 참가",
            ],
            shortTitle: "주변 방 찾기",
            systemImageName: "antenna.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: PracticeGameIntent(),
            phrases: [
                "\(.applicationName)에서 \(\.$game) 연습하기",
                "\(.applicationName) 연습하기",
            ],
            shortTitle: "봇과 연습하기",
            systemImageName: "person.2.wave.2"
        )
    }
}
