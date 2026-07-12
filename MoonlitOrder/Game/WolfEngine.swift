import Foundation

/// '달 없는 밤' — 하룻밤 정체 추리 게임의 권위 엔진. 호스트 기기에서만 동작한다.
/// (한국 설화 테마의 오리지널 게임: 도깨비 · 무당 · 밤손님 · 장난꾼 · 마을 사람)
///
/// 규칙 요약:
/// - 인원수+3장의 카드를 섞어 각자 1장씩, 나머지 3장은 중앙에 놓는다.
/// - 밤(단 한 번): 도깨비는 서로 확인(혼자면 중앙 1장 확인), 무당은
///   플레이어 1명 또는 중앙 2장 확인, 밤손님은 카드를 훔쳐 새 카드 확인,
///   장난꾼은 다른 두 명의 카드를 교환한다.
/// - 밤 행동은 각자 폰에서 동시에 입력받되, 판정은 고정 순서
///   (도깨비 → 무당 → 밤손님 → 장난꾼)로 적용한다. 확인 계열 행동은
///   모두 교환 이전의 카드를 보므로 동시 입력과 결과가 동일하다.
/// - 낮: 토론 후 전원이 동시에 1명을 지목한다. 최다 득표자가 추방되고
///   (동률은 전원, 전원이 1표 이하면 아무도 추방되지 않음),
///   추방자 중 최종 카드가 도깨비면 마을 승리. 도깨비가 플레이어 중에
///   없을 때는 아무도 추방되지 않아야 마을이 승리한다.
final class WolfEngine {

    struct PlayerInternal {
        let id: UUID
        var name: String
        var isHost: Bool
        var connected: Bool = true
        var originalRole: WolfRole = .villager   // 밤 행동 기준
        var currentRole: WolfRole = .villager    // 교환 반영된 최종 카드
        var nightDone: Bool = false
        var votedFor: UUID?
        // 판정 대기 중인 밤 선택
        var robberTarget: UUID?
        var troublemakerTargets: [UUID] = []
    }

    // MARK: 상태

    private(set) var players: [PlayerInternal] = []
    private var center: [WolfRole] = []
    private var phase: WolfPhase = .lobby {
        didSet { if oldValue != phase { phaseStartedAt = Date() } }
    }
    private var phaseStartedAt = Date()
    private var lastVotes: [String: String] = [:]
    private var executedIDs: [UUID] = []
    private var villageWins: Bool?
    private var winReason: String?
    private var nightResults: [UUID: String] = [:]

    var onStateChange: ((WolfGameState) -> Void)?
    var onPrivateInfo: ((UUID, WolfPrivateInfo) -> Void)?

    /// 게임방법(데모) 전용: 이 플레이어에게 밤 행동이 있는 역할을 보장한다.
    /// (마을 사람이 걸리면 능력·카드 교환 시스템을 전혀 체험하지 못하므로)
    var guaranteeActionRoleFor: UUID?

    private var hostID: UUID? { players.first { $0.isHost }?.id }

    // MARK: - 참가 / 연결 (달빛 결사와 동일한 규약)

    @discardableResult
    func join(playerID: UUID, name: String, isHost: Bool) -> GameEngine.JoinResult {
        if let idx = players.firstIndex(where: { $0.id == playerID }) {
            players[idx].connected = true
            pushState()
            if phase != .lobby {
                onPrivateInfo?(playerID, privateInfo(for: players[idx]))
            }
            return .rejoined
        }
        guard phase == .lobby else { return .rejectedInProgress }
        guard players.count < WolfRules.playerRange.upperBound else { return .rejectedFull }

        players.append(PlayerInternal(id: playerID,
                                      name: uniqueName(for: name),
                                      isHost: isHost))
        pushState()
        return .joined
    }

    func setConnected(_ playerID: UUID, _ connected: Bool) {
        guard let idx = players.firstIndex(where: { $0.id == playerID }) else { return }
        if !connected && phase == .lobby && !players[idx].isHost {
            players.remove(at: idx)
        } else {
            players[idx].connected = connected
        }
        pushState()
    }

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

    // MARK: - 액션 처리

    func handle(_ playerID: UUID, _ action: WolfAction) {
        switch action {
        case .startGame:
            startGame(by: playerID)
        case .nightAction(let targets, let centers):
            nightAction(playerID, targets: targets, centers: centers)
        case .startVoting:
            startVoting(by: playerID)
        case .vote(let targetID):
            vote(playerID, for: targetID)
        case .playAgain, .abortToLobby:
            resetToLobby(by: playerID)
        }
    }

    private func startGame(by playerID: UUID) {
        guard phase == .lobby,
              playerID == hostID,
              WolfRules.playerRange.contains(players.count) else { return }

        var deck = WolfRules.makeDeck(for: players.count)
        for i in players.indices {
            let role = deck.removeFirst()
            players[i].originalRole = role
            players[i].currentRole = role
            players[i].nightDone = false
            players[i].votedFor = nil
            players[i].robberTarget = nil
            players[i].troublemakerTargets = []
        }
        center = deck   // 남은 3장

        // 데모: 사용자가 마을 사람이면 밤 행동이 있는 역할과 카드를 바꿔준다
        if let favored = guaranteeActionRoleFor,
           let fIdx = players.firstIndex(where: { $0.id == favored }),
           players[fIdx].originalRole == .villager {
            if let donor = players.indices.first(where: {
                players[$0].originalRole != .villager && players[$0].id != favored
            }) {
                let role = players[donor].originalRole
                players[donor].originalRole = .villager
                players[donor].currentRole = .villager
                players[fIdx].originalRole = role
                players[fIdx].currentRole = role
            } else if let cIdx = center.firstIndex(where: { $0 != .villager }) {
                let role = center[cIdx]
                center[cIdx] = .villager
                players[fIdx].originalRole = role
                players[fIdx].currentRole = role
            }
        }

        lastVotes = [:]
        executedIDs = []
        villageWins = nil
        winReason = nil
        nightResults = [:]
        phase = .night

        pushState()
        for p in players {
            onPrivateInfo?(p.id, privateInfo(for: p))
        }
    }

    // MARK: - 밤

    private var wolves: [PlayerInternal] { players.filter { $0.originalRole == .werewolf } }

    private func nightAction(_ playerID: UUID, targets: [UUID], centers: [Int]) {
        guard phase == .night,
              let idx = players.firstIndex(where: { $0.id == playerID }),
              !players[idx].nightDone else { return }
        let player = players[idx]
        let validCenters = centers.allSatisfy { center.indices.contains($0) }
        let others = targets.filter { $0 != playerID }
        let named: (UUID) -> String = { [players] id in
            players.first { $0.id == id }?.name ?? "?"
        }

        switch player.originalRole {
        case .werewolf:
            if wolves.count == 1 {
                // 외톨이 도깨비: 중앙 1장 확인
                guard centers.count == 1, validCenters, let i = centers.first else { return }
                nightResults[playerID] = "중앙 \(i + 1)번 카드는 '\(center[i].displayName)'입니다."
            } else {
                nightResults[playerID] = nil   // 동료 정보는 packmates로 이미 전달됨
            }

        case .seer:
            if others.count == 1, targets.count == 1, centers.isEmpty,
               let target = players.first(where: { $0.id == others[0] }) {
                nightResults[playerID] = "\(target.name)의 카드는 '\(target.originalRole.displayName)'입니다."
            } else if centers.count == 2, validCenters, targets.isEmpty,
                      centers[0] != centers[1] {
                let seen = centers.map { "'\(center[$0].displayName)'" }.joined(separator: ", ")
                nightResults[playerID] = "중앙 카드 2장: \(seen)"
            } else {
                return
            }

        case .robber:
            guard others.count == 1, targets.count == 1, centers.isEmpty,
                  let target = players.first(where: { $0.id == others[0] }) else { return }
            players[idx].robberTarget = target.id
            nightResults[playerID] =
                "\(target.name)의 카드를 훔쳤습니다. 당신은 이제 '\(target.originalRole.displayName)'입니다."

        case .troublemaker:
            guard others.count == 2, targets.count == 2, centers.isEmpty,
                  others[0] != others[1],
                  players.contains(where: { $0.id == others[0] }),
                  players.contains(where: { $0.id == others[1] }) else { return }
            players[idx].troublemakerTargets = others
            nightResults[playerID] = "\(named(others[0]))과(와) \(named(others[1]))의 카드를 서로 바꿨습니다."

        case .villager:
            nightResults[playerID] = nil
        }

        players[idx].nightDone = true
        onPrivateInfo?(playerID, privateInfo(for: players[idx]))

        if players.allSatisfy({ $0.nightDone }) {
            resolveNight()
            phase = .day
        }
        pushState()
    }

    /// 공식 순서(강도 → 말썽꾸러기)로 카드 교환을 적용한다.
    /// (늑대·예언자·강도의 '확인'은 모두 교환 전 카드 기준이므로 이미 처리됨)
    private func resolveNight() {
        if let robberIdx = players.firstIndex(where: { $0.robberTarget != nil }),
           let targetID = players[robberIdx].robberTarget,
           let targetIdx = players.firstIndex(where: { $0.id == targetID }) {
            let stolen = players[targetIdx].currentRole
            players[targetIdx].currentRole = players[robberIdx].currentRole
            players[robberIdx].currentRole = stolen
        }
        if let tmIdx = players.firstIndex(where: { $0.troublemakerTargets.count == 2 }) {
            let ts = players[tmIdx].troublemakerTargets
            if let a = players.firstIndex(where: { $0.id == ts[0] }),
               let b = players.firstIndex(where: { $0.id == ts[1] }) {
                let tmp = players[a].currentRole
                players[a].currentRole = players[b].currentRole
                players[b].currentRole = tmp
            }
        }
    }

    // MARK: - 낮 / 투표

    private func startVoting(by playerID: UUID) {
        guard phase == .day, playerID == hostID else { return }
        phase = .voting
        pushState()
    }

    private func vote(_ playerID: UUID, for targetID: UUID) {
        guard phase == .voting,
              playerID != targetID,
              players.contains(where: { $0.id == targetID }),
              let idx = players.firstIndex(where: { $0.id == playerID }),
              players[idx].votedFor == nil else { return }
        players[idx].votedFor = targetID

        if players.allSatisfy({ $0.votedFor != nil }) {
            tallyVotes()
        }
        pushState()
    }

    private func tallyVotes() {
        lastVotes = Dictionary(uniqueKeysWithValues: players.compactMap { p in
            p.votedFor.map { (p.id.uuidString, $0.uuidString) }
        })
        var counts: [UUID: Int] = [:]
        for p in players {
            if let t = p.votedFor { counts[t, default: 0] += 1 }
        }
        let maxCount = counts.values.max() ?? 0
        // 아무도 2표 이상을 받지 않으면 아무도 처형되지 않는다
        executedIDs = maxCount >= 2
            ? counts.filter { $0.value == maxCount }.map(\.key)
            : []

        let wolvesAmongPlayers = players.contains { $0.currentRole.isWolfTeam }
        let executedWolf = players.contains {
            executedIDs.contains($0.id) && $0.currentRole.isWolfTeam
        }

        if executedWolf {
            villageWins = true
            winReason = "도깨비가 추방되었습니다. 마을의 승리!"
        } else if !wolvesAmongPlayers && executedIDs.isEmpty {
            villageWins = true
            winReason = "도깨비는 모두 중앙에 있었고, 아무도 추방되지 않았습니다. 마을의 승리!"
        } else if executedIDs.isEmpty {
            villageWins = false
            winReason = "아무도 추방되지 않았지만 도깨비가 숨어 있었습니다. 도깨비의 승리!"
        } else {
            villageWins = false
            winReason = "애꿎은 사람이 추방되었습니다. 도깨비의 승리!"
        }
        phase = .gameOver
    }

    private func resetToLobby(by playerID: UUID) {
        guard phase != .lobby, playerID == hostID else { return }
        players.removeAll { !$0.connected && !$0.isHost }
        for i in players.indices {
            players[i].originalRole = .villager
            players[i].currentRole = .villager
            players[i].nightDone = false
            players[i].votedFor = nil
            players[i].robberTarget = nil
            players[i].troublemakerTargets = []
        }
        center = []
        lastVotes = [:]
        executedIDs = []
        villageWins = nil
        winReason = nil
        nightResults = [:]
        phase = .lobby
        pushState()
    }

    // MARK: - 상태 생성

    private func privateInfo(for player: PlayerInternal) -> WolfPrivateInfo {
        var info = WolfPrivateInfo(role: player.originalRole)
        if player.originalRole == .werewolf {
            info.packmateNames = wolves.filter { $0.id != player.id }.map(\.name).sorted()
            info.isLoneWolf = wolves.count == 1
        }
        info.nightResult = nightResults[player.id]
        return info
    }

    private func hasActed(_ p: PlayerInternal) -> Bool {
        switch phase {
        case .night:  return p.nightDone
        case .voting: return p.votedFor != nil
        default:      return false
        }
    }

    private func publicState() -> WolfGameState {
        var s = WolfGameState()
        s.phase = phase
        s.players = players.map {
            PlayerPublic(id: $0.id,
                         name: $0.name,
                         isHost: $0.isHost,
                         isConnected: $0.connected,
                         hasActed: hasActed($0))
        }
        if phase == .gameOver {
            s.lastVotes = lastVotes
            s.executedIDs = executedIDs
            s.revealedRoles = Dictionary(uniqueKeysWithValues:
                players.map { ($0.id.uuidString, $0.currentRole) })
            s.originalRoles = Dictionary(uniqueKeysWithValues:
                players.map { ($0.id.uuidString, $0.originalRole) })
            s.revealedCenter = center
        }
        s.villageWins = villageWins
        s.winReason = winReason
        s.phaseSeconds = WolfRules.phaseSeconds(for: phase)
        s.phaseStartedAt = phaseStartedAt
        return s
    }

    private func pushState() {
        onStateChange?(publicState())
    }
}
