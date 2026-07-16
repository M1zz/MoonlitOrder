import Foundation

// MARK: - 역할

/// '달 없는 밤' — 한국 설화 테마의 오리지널 하룻밤 정체 추리 게임 역할.
enum WolfRole: String, Codable, Equatable, CaseIterable {
    case werewolf      // 도깨비 (숨어든 존재)
    case seer          // 무당 (진실을 보는 자)
    case robber        // 밤손님 (카드를 훔치는 자)
    case troublemaker  // 장난꾼 (카드를 뒤바꾸는 자)
    case villager      // 마을 사람

    var displayName: String {
        switch self {
        case .werewolf:     return "도깨비"
        case .seer:         return "무당"
        case .robber:       return "밤손님"
        case .troublemaker: return "장난꾼"
        case .villager:     return "마을 사람"
        }
    }

    var isWolfTeam: Bool { self == .werewolf }

    var summary: String {
        switch self {
        case .werewolf:
            return "동료 도깨비를 확인합니다. 당신이 유일한 도깨비라면 중앙 카드 1장을 볼 수 있습니다. 날이 밝으면 사람인 척 정체를 숨기세요."
        case .seer:
            return "신통력으로 다른 플레이어 1명의 카드 또는 중앙 카드 2장을 볼 수 있습니다."
        case .robber:
            return "다른 플레이어 1명과 카드를 몰래 바꾸고, 새로 가져온 카드를 확인합니다. 이후 당신의 편은 새 카드를 따릅니다."
        case .troublemaker:
            return "장난기가 발동! 다른 두 플레이어의 카드를 서로 바꿉니다. 무엇이었는지는 볼 수 없습니다."
        case .villager:
            return "밤에는 할 일이 없습니다. 낮의 추리와 토론으로 숨어든 도깨비를 찾아내세요."
        }
    }

    var iconName: String {
        switch self {
        case .werewolf:     return "flame.fill"        // 도깨비불
        case .seer:         return "eye.fill"
        case .robber:       return "hand.raised.fill"
        case .troublemaker: return "shuffle"
        case .villager:     return "person.fill"
        }
    }
}

// MARK: - 진행 단계

enum WolfPhase: String, Codable, Equatable {
    case lobby     // 대기실
    case night     // 밤 — 각자 비밀 행동
    case day       // 낮 — 토론
    case voting    // 처형 투표 (단 한 번)
    case gameOver  // 결과 (모든 카드 공개)
}

// MARK: - 공개 상태

struct WolfGameState: Codable, Equatable {
    var phase: WolfPhase = .lobby
    var players: [PlayerPublic] = []
    var lastVotes: [String: String] = [:]     // voterID → targetID (결과 공개 시)
    var executedIDs: [UUID] = []              // 처형된 플레이어들
    var villageWins: Bool?
    var winReason: String?
    var revealedRoles: [String: WolfRole]?    // 최종 카드 (게임 종료 시)
    var originalRoles: [String: WolfRole]?    // 밤이 시작될 때의 카드 (게임 종료 시)
    var revealedCenter: [WolfRole]?           // 중앙 3장 (게임 종료 시)

    // 단계 타이머 (호스트 기준)
    var phaseSeconds: Int?
    var phaseStartedAt: Date = Date()

    func player(_ id: UUID) -> PlayerPublic? { players.first { $0.id == id } }
    var disconnectedPlayers: [PlayerPublic] { players.filter { !$0.isConnected } }
}

// MARK: - 비공개 정보

struct WolfPrivateInfo: Codable, Equatable {
    var role: WolfRole                 // 밤 행동 기준(원래) 역할
    var packmateNames: [String] = []   // 늑대인간: 동료 늑대들
    var isLoneWolf: Bool = false       // 유일한 늑대 → 중앙 1장 확인 가능
    var nightResult: String?           // 밤에 알게 된 정보 서술
}

// MARK: - 클라이언트 → 호스트 액션

enum WolfAction: Codable {
    case startGame
    /// 밤 행동. 역할에 따라 해석된다:
    /// 도깨비(외톨이): centers 1개 / 무당: targets 1개 또는 centers 2개 /
    /// 밤손님: targets 1개 / 장난꾼: targets 2개 / 그 외: 모두 비움(확인만)
    case nightAction(targets: [UUID], centers: [Int])
    case startVoting            // 호스트: 토론 종료 → 투표
    case vote(targetID: UUID)
    case playAgain
    case abortToLobby
}

// MARK: - 규칙

enum WolfRules {
    static let playerRange = 3...15
    static let centerCount = 3

    static func phaseSeconds(for phase: WolfPhase) -> Int? {
        switch phase {
        case .night:  return 90
        case .day:    return 180
        case .voting: return 45
        case .lobby, .gameOver: return nil
        }
    }

    /// 인원수+3장의 카드 구성: 도깨비 2(11인 이상은 3), 무당, 밤손님, 장난꾼 + 나머지 마을 사람
    static func makeDeck(for playerCount: Int) -> [WolfRole] {
        var deck: [WolfRole] = [.werewolf, .werewolf, .seer, .robber, .troublemaker]
        if playerCount >= 11 { deck.append(.werewolf) }   // 대인원에선 도깨비도 늘린다
        let villagers = playerCount + centerCount - deck.count
        deck += Array(repeating: .villager, count: max(0, villagers))
        return deck.shuffled()
    }
}
