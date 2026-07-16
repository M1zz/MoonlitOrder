import Foundation

// MARK: - 진영

enum Team: String, Codable, Equatable {
    case moonlit = "moonlit"   // 달빛 결사 (선한 진영)
    case shadow  = "shadow"    // 그림자 (배신자 진영)

    var displayName: String {
        switch self {
        case .moonlit: return "달빛 결사"
        case .shadow:  return "그림자"
        }
    }
}

// MARK: - 역할 (모든 명칭은 오리지널)

enum Role: String, Codable, CaseIterable, Equatable {
    case seer     = "seer"      // 예언자: 그림자 단원들을 알고 시작
    case knight   = "knight"    // 결사단원: 일반 선 역할
    case assassin = "assassin"  // 암살자: 게임 마지막에 예언자를 지목할 기회
    case shadow   = "shadow"    // 그림자 단원: 서로를 알고 시작

    var team: Team {
        switch self {
        case .seer, .knight:      return .moonlit
        case .assassin, .shadow:  return .shadow
        }
    }

    var displayName: String {
        switch self {
        case .seer:     return "예언자"
        case .knight:   return "결사단원"
        case .assassin: return "암살자"
        case .shadow:   return "그림자 단원"
        }
    }

    var summary: String {
        switch self {
        case .seer:
            return "당신은 그림자 단원이 누구인지 알고 있습니다. 하지만 정체가 드러나면 마지막에 암살당할 수 있으니, 티 내지 말고 은밀하게 원정대를 이끌어야 합니다."
        case .knight:
            return "당신은 달빛 결사의 충직한 단원입니다. 토론과 투표 기록을 근거로 그림자 단원을 찾아내고, 미션 3회를 성공시키세요."
        case .assassin:
            return "당신은 그림자의 칼끝입니다. 동료 그림자 단원들을 알고 있으며, 결사가 미션 3회를 성공하더라도 예언자를 정확히 지목하면 역전승합니다."
        case .shadow:
            return "당신은 어둠 속에 숨은 배신자입니다. 동료 그림자를 알고 있습니다. 정체를 숨기고 원정대에 잠입해 미션을 실패시키세요."
        }
    }

    var objective: String {
        switch team {
        case .moonlit: return "미션 3회 성공 (단, 예언자가 암살당하면 패배)"
        case .shadow:  return "미션 3회 실패 · 원정대 5회 연속 부결 · 예언자 암살"
        }
    }
}

// MARK: - 게임 진행 단계

enum GamePhase: String, Codable, Equatable {
    case lobby          // 대기실
    case roleReveal     // 역할 확인
    case teamProposal   // 리더가 원정대 지명
    case teamVoting     // 전원 찬반 투표
    case voteResult     // 투표 결과 공개
    case mission        // 원정대원이 성공/실패 카드 제출
    case missionResult  // 미션 결과 공개
    case assassination  // 암살자의 마지막 기회
    case gameOver       // 게임 종료
}

// MARK: - 공개 정보 (모든 플레이어에게 브로드캐스트)

struct PlayerPublic: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var isHost: Bool
    var isConnected: Bool
    var hasActed: Bool     // 현재 단계에서 행동을 마쳤는지 (역할확인/투표/카드제출)
}

struct MissionRecord: Codable, Equatable {
    var round: Int
    var succeeded: Bool
    var failCount: Int
    var teamNames: [String]
}

struct PublicGameState: Codable, Equatable {
    var phase: GamePhase = .lobby
    var players: [PlayerPublic] = []
    var round: Int = 1                     // 1...5
    var leaderID: UUID?
    var proposedTeam: [UUID] = []
    var voteTrack: Int = 0                 // 연속 부결 횟수 (0...4)
    var missionHistory: [MissionRecord] = []
    var lastVotes: [String: Bool] = [:]    // playerID.uuidString → 찬성 여부 (결과 공개 시)
    var lastVoteApproved: Bool = false
    var teamSizes: [Int] = []
    var failsRequired: [Int] = []
    var winner: Team?
    var winReason: String?
    var assassinTargetName: String?
    var revealedRoles: [String: Role]?     // playerID.uuidString → 역할 (게임 종료 시)

    // 단계 타이머 (호스트 기준 — 모든 기기가 같은 시간을 본다)
    var phaseSeconds: Int?                 // 현재 단계 제한시간, nil이면 타이머 없음
    var phaseStartedAt: Date = Date()      // 현재 단계 시작 시각

    // MARK: 계산 속성

    var requiredTeamSize: Int {
        let idx = round - 1
        return teamSizes.indices.contains(idx) ? teamSizes[idx] : 0
    }

    var requiredFails: Int {
        let idx = round - 1
        return failsRequired.indices.contains(idx) ? failsRequired[idx] : 1
    }

    var successCount: Int { missionHistory.filter { $0.succeeded }.count }
    var failureCount: Int { missionHistory.filter { !$0.succeeded }.count }

    var leader: PlayerPublic? { players.first { $0.id == leaderID } }

    func player(_ id: UUID) -> PlayerPublic? { players.first { $0.id == id } }

    var disconnectedPlayers: [PlayerPublic] { players.filter { !$0.isConnected } }
}

// MARK: - 비공개 정보 (각 플레이어에게 개별 전송)

struct PrivateInfo: Codable, Equatable {
    var role: Role
    var knownShadowNames: [String] = []   // 예언자·그림자 진영만 채워짐
}

// MARK: - 게임 규칙 테이블

enum GameRules {
    static let playerRange = 5...15
    static let missionCount = 5
    static let maxRejections = 5

    /// 인원수별 그림자 진영 수 (전체의 1/3 안팎을 유지)
    static func shadowCount(for playerCount: Int) -> Int {
        switch playerCount {
        case ...6:    return 2
        case 7...9:   return 3
        case 10...12: return 4
        default:      return 5
        }
    }

    /// 라운드별 원정대 인원수
    static func teamSizes(for playerCount: Int) -> [Int] {
        switch playerCount {
        case 5:        return [2, 3, 2, 3, 3]
        case 6:        return [2, 3, 4, 3, 4]
        case 7:        return [2, 3, 3, 4, 4]
        case 8...10:   return [3, 4, 4, 5, 5]
        case 11...12:  return [4, 5, 5, 6, 6]
        default:       return [4, 5, 6, 7, 7]
        }
    }

    /// 라운드별 미션 실패에 필요한 실패 카드 수
    /// (7인 이상은 4라운드에 2장, 11인 이상은 원정대가 커지므로 5라운드도 2장)
    static func failsRequired(for playerCount: Int) -> [Int] {
        var fails = [1, 1, 1, 1, 1]
        if playerCount >= 7 { fails[3] = 2 }
        if playerCount >= 11 { fails[4] = 2 }
        return fails
    }

    /// 단계별 제한시간(초). 결과 화면·로비·종료 화면은 타이머가 없다.
    /// 시간이 다 되어도 행동을 강제하지는 않는다 (재촉용 소프트 타이머).
    static func phaseSeconds(for phase: GamePhase) -> Int? {
        switch phase {
        case .roleReveal:    return 45
        case .teamProposal:  return 90
        case .teamVoting:    return 30
        case .mission:       return 30
        case .assassination: return 90
        case .lobby, .voteResult, .missionResult, .gameOver:
            return nil
        }
    }

    /// 역할 목록 생성 (셔플됨)
    static func makeRoles(for playerCount: Int) -> [Role] {
        let shadows = shadowCount(for: playerCount)
        var roles: [Role] = [.assassin]
        roles += Array(repeating: Role.shadow, count: shadows - 1)
        roles += [.seer]
        roles += Array(repeating: Role.knight, count: playerCount - shadows - 1)
        return roles.shuffled()
    }
}
