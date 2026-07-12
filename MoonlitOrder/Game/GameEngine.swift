import Foundation

/// 호스트 기기에서만 동작하는 권위(authoritative) 게임 엔진.
/// 모든 규칙 판정은 여기서만 이루어지고, 결과는 전체 상태로 브로드캐스트된다.
/// 클라이언트는 언제 재접속하더라도 최신 전체 상태 + 본인 비공개 정보만 받으면 복귀할 수 있다.
final class GameEngine {

    struct PlayerInternal {
        let id: UUID
        var name: String
        var isHost: Bool
        var connected: Bool = true
        var role: Role = .knight
        var confirmedRole: Bool = false
        var vote: Bool?
        var missionPlay: Bool?
    }

    enum JoinResult {
        case joined
        case rejoined
        case rejectedFull
        case rejectedInProgress
    }

    // MARK: 상태

    private(set) var players: [PlayerInternal] = []
    private(set) var phase: GamePhase = .lobby {
        didSet { if oldValue != phase { phaseStartedAt = Date() } }
    }
    private var phaseStartedAt = Date()
    private var round = 1
    private var leaderIndex = 0
    private var proposedTeam: [UUID] = []
    private var voteTrack = 0
    private var missionHistory: [MissionRecord] = []
    private var lastVotes: [String: Bool] = [:]
    private var lastVoteApproved = false
    private var winner: Team?
    private var winReason: String?
    private var assassinTargetName: String?
    private var revealedRoles: [String: Role]?

    /// 상태가 바뀔 때마다 호출 → 뷰모델이 로컬 반영 + 전체 브로드캐스트
    var onStateChange: ((PublicGameState) -> Void)?
    /// 특정 플레이어에게 비공개 정보 전송이 필요할 때 호출
    var onPrivateInfo: ((UUID, PrivateInfo) -> Void)?

    private var hostID: UUID? { players.first { $0.isHost }?.id }

    // MARK: - 참가 / 연결 관리

    @discardableResult
    func join(playerID: UUID, name: String, isHost: Bool) -> JoinResult {
        // 같은 playerID로 돌아온 경우 → 재접속 처리
        if let idx = players.firstIndex(where: { $0.id == playerID }) {
            players[idx].connected = true
            pushState()
            if phase != .lobby {
                onPrivateInfo?(playerID, privateInfo(for: players[idx]))
            }
            return .rejoined
        }
        guard phase == .lobby else { return .rejectedInProgress }
        guard players.count < GameRules.playerRange.upperBound else { return .rejectedFull }

        players.append(PlayerInternal(id: playerID,
                                      name: uniqueName(for: name),
                                      isHost: isHost))
        pushState()
        return .joined
    }

    func setConnected(_ playerID: UUID, _ connected: Bool) {
        guard let idx = players.firstIndex(where: { $0.id == playerID }) else { return }
        // 대기실에서 나간 사람은 아예 제거
        if !connected && phase == .lobby && !players[idx].isHost {
            players.remove(at: idx)
        } else {
            players[idx].connected = connected
        }
        pushState()
    }

    /// 이름 중복 방지 (비공개 정보가 이름 기반이므로 반드시 유일해야 함)
    private func uniqueName(for name: String) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = base.isEmpty ? "플레이어" : base
        var result = candidate
        var n = 2
        while players.contains(where: { $0.name == result }) {
            result = "\(candidate) \(n)"
            n += 1
        }
        return result
    }

    // MARK: - 메시지 처리

    func handle(_ message: NetMessage) {
        switch message {
        case .startGame(let pid):
            startGame(by: pid)
        case .confirmRole(let pid):
            confirmRole(pid)
        case .proposeTeam(let pid, let members):
            proposeTeam(by: pid, members: members)
        case .teamVote(let pid, let approve):
            recordVote(pid, approve: approve)
        case .missionAction(let pid, let success):
            recordMission(pid, success: success)
        case .assassinate(let pid, let targetID):
            assassinate(by: pid, targetID: targetID)
        case .hostContinue(let pid):
            hostContinue(by: pid)
        case .playAgain(let pid):
            resetToLobby(by: pid)
        case .abortToLobby(let pid):
            resetToLobby(by: pid)
        default:
            break
        }
    }

    // MARK: - 게임 시작

    private func startGame(by playerID: UUID) {
        guard phase == .lobby,
              playerID == hostID,
              GameRules.playerRange.contains(players.count) else { return }

        let roles = GameRules.makeRoles(for: players.count)
        for i in players.indices {
            players[i].role = roles[i]
            players[i].confirmedRole = false
            players[i].vote = nil
            players[i].missionPlay = nil
        }
        round = 1
        voteTrack = 0
        proposedTeam = []
        missionHistory = []
        lastVotes = [:]
        lastVoteApproved = false
        winner = nil
        winReason = nil
        assassinTargetName = nil
        revealedRoles = nil
        leaderIndex = Int.random(in: 0..<players.count)
        phase = .roleReveal

        pushState()
        for p in players {
            onPrivateInfo?(p.id, privateInfo(for: p))
        }
    }

    private func confirmRole(_ playerID: UUID) {
        guard phase == .roleReveal,
              let idx = players.firstIndex(where: { $0.id == playerID }) else { return }
        players[idx].confirmedRole = true
        if players.allSatisfy({ $0.confirmedRole }) {
            phase = .teamProposal
        }
        pushState()
    }

    // MARK: - 원정대 지명 / 투표

    private func proposeTeam(by playerID: UUID, members: [UUID]) {
        guard phase == .teamProposal,
              playerID == currentLeaderID else { return }
        let unique = Array(Set(members))
        guard unique.count == GameRules.teamSizes(for: players.count)[round - 1],
              unique.allSatisfy({ id in players.contains { $0.id == id } }) else { return }

        proposedTeam = unique
        for i in players.indices { players[i].vote = nil }
        phase = .teamVoting
        pushState()
    }

    private func recordVote(_ playerID: UUID, approve: Bool) {
        guard phase == .teamVoting,
              let idx = players.firstIndex(where: { $0.id == playerID }),
              players[idx].vote == nil else { return }
        players[idx].vote = approve

        if players.allSatisfy({ $0.vote != nil }) {
            lastVotes = Dictionary(uniqueKeysWithValues:
                players.map { ($0.id.uuidString, $0.vote ?? false) })
            let approves = players.filter { $0.vote == true }.count
            lastVoteApproved = approves * 2 > players.count   // 동수는 부결
            if !lastVoteApproved { voteTrack += 1 }
            phase = .voteResult
        }
        pushState()
    }

    // MARK: - 미션

    private func recordMission(_ playerID: UUID, success: Bool) {
        guard phase == .mission,
              proposedTeam.contains(playerID),
              let idx = players.firstIndex(where: { $0.id == playerID }),
              players[idx].missionPlay == nil else { return }

        // 달빛 결사 진영은 실패 카드를 낼 수 없다 (규칙 강제)
        let play = players[idx].role.team == .moonlit ? true : success
        players[idx].missionPlay = play

        let team = players.filter { proposedTeam.contains($0.id) }
        if team.allSatisfy({ $0.missionPlay != nil }) {
            let fails = team.filter { $0.missionPlay == false }.count
            let needed = GameRules.failsRequired(for: players.count)[round - 1]
            let succeeded = fails < needed
            missionHistory.append(MissionRecord(round: round,
                                                succeeded: succeeded,
                                                failCount: fails,
                                                teamNames: team.map { $0.name }.sorted()))
            phase = .missionResult
        }
        pushState()
    }

    // MARK: - 결과 화면에서 다음으로 (호스트가 진행을 통제)

    private func hostContinue(by playerID: UUID) {
        guard playerID == hostID else { return }
        switch phase {
        case .voteResult:
            continueFromVoteResult()
        case .missionResult:
            continueFromMissionResult()
        default:
            return
        }
        pushState()
    }

    private func continueFromVoteResult() {
        if lastVoteApproved {
            voteTrack = 0
            for i in players.indices { players[i].missionPlay = nil }
            phase = .mission
        } else if voteTrack >= GameRules.maxRejections {
            endGame(winner: .shadow,
                    reason: "원정대 구성이 \(GameRules.maxRejections)회 연속 부결되어 그림자 진영이 승리했습니다.")
        } else {
            advanceLeader()
            proposedTeam = []
            phase = .teamProposal
        }
    }

    private func continueFromMissionResult() {
        let successes = missionHistory.filter { $0.succeeded }.count
        let failures = missionHistory.count - successes
        if failures >= 3 {
            endGame(winner: .shadow, reason: "미션이 3회 실패하여 그림자 진영이 승리했습니다.")
        } else if successes >= 3 {
            phase = .assassination
        } else {
            round += 1
            advanceLeader()
            proposedTeam = []
            phase = .teamProposal
        }
    }

    // MARK: - 암살

    private func assassinate(by playerID: UUID, targetID: UUID) {
        guard phase == .assassination,
              let killer = players.first(where: { $0.id == playerID }),
              killer.role == .assassin,
              let target = players.first(where: { $0.id == targetID }),
              target.id != killer.id else { return }

        assassinTargetName = target.name
        if target.role == .seer {
            endGame(winner: .shadow,
                    reason: "암살자가 예언자 '\(target.name)'을(를) 정확히 찾아냈습니다. 그림자 진영의 역전승!")
        } else {
            endGame(winner: .moonlit,
                    reason: "암살자의 칼끝이 빗나갔습니다. '\(target.name)'은(는) 예언자가 아니었습니다. 달빛 결사의 승리!")
        }
        pushState()
    }

    // MARK: - 종료 / 재시작

    private func endGame(winner: Team, reason: String) {
        self.winner = winner
        self.winReason = reason
        revealedRoles = Dictionary(uniqueKeysWithValues:
            players.map { ($0.id.uuidString, $0.role) })
        phase = .gameOver
    }

    /// 게임 종료 후 재시작 또는 진행 중 중단 → 대기실로 (호스트 전용).
    /// 플레이어가 영영 돌아오지 않아 게임이 멈춘 경우의 탈출구이기도 하다.
    private func resetToLobby(by playerID: UUID) {
        guard phase != .lobby, playerID == hostID else { return }
        // 연결이 끊긴 채 종료된 플레이어는 정리하고 대기실로
        players.removeAll { !$0.connected && !$0.isHost }
        phase = .lobby
        winner = nil
        winReason = nil
        revealedRoles = nil
        assassinTargetName = nil
        missionHistory = []
        lastVotes = [:]
        proposedTeam = []
        voteTrack = 0
        round = 1
        pushState()
    }

    // MARK: - 헬퍼

    private var currentLeaderID: UUID? {
        guard !players.isEmpty else { return nil }
        return players[leaderIndex % players.count].id
    }

    private func advanceLeader() {
        guard !players.isEmpty else { return }
        leaderIndex = (leaderIndex + 1) % players.count
    }

    private func privateInfo(for player: PlayerInternal) -> PrivateInfo {
        var info = PrivateInfo(role: player.role)
        switch player.role {
        case .seer:
            info.knownShadowNames = players
                .filter { $0.role.team == .shadow }
                .map { $0.name }.sorted()
        case .shadow, .assassin:
            info.knownShadowNames = players
                .filter { $0.role.team == .shadow && $0.id != player.id }
                .map { $0.name }.sorted()
        case .knight:
            break
        }
        return info
    }

    private func hasActed(_ p: PlayerInternal) -> Bool {
        switch phase {
        case .roleReveal:  return p.confirmedRole
        case .teamVoting:  return p.vote != nil
        case .mission:     return proposedTeam.contains(p.id) && p.missionPlay != nil
        default:           return false
        }
    }

    func publicState() -> PublicGameState {
        var s = PublicGameState()
        s.phase = phase
        s.players = players.map {
            PlayerPublic(id: $0.id,
                         name: $0.name,
                         isHost: $0.isHost,
                         isConnected: $0.connected,
                         hasActed: hasActed($0))
        }
        s.round = round
        s.leaderID = currentLeaderID
        s.proposedTeam = proposedTeam
        s.voteTrack = voteTrack
        s.missionHistory = missionHistory
        s.lastVotes = phase == .voteResult ? lastVotes : [:]
        s.lastVoteApproved = lastVoteApproved
        s.teamSizes = GameRules.teamSizes(for: max(players.count, GameRules.playerRange.lowerBound))
        s.failsRequired = GameRules.failsRequired(for: max(players.count, GameRules.playerRange.lowerBound))
        s.winner = winner
        s.winReason = winReason
        s.assassinTargetName = assassinTargetName
        s.revealedRoles = revealedRoles
        s.phaseSeconds = GameRules.phaseSeconds(for: phase)
        s.phaseStartedAt = phaseStartedAt
        return s
    }

    private func pushState() {
        onStateChange?(publicState())
    }
}
