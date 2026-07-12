import Foundation

/// 게임방법(데모) 모드: 봇 플레이어들이 자동으로 한 판을 플레이해
/// 게임의 전체 흐름을 보여준다. 네트워크 없이 로컬 GameEngine 위에서 돌며,
/// 실제 게임과 같은 메시지 경로(engine.handle)만 사용하므로 규칙 판정도 동일하다.
final class DemoDriver {

    private weak var engine: GameEngine?
    private let hostID: UUID
    private let botIDs: [UUID]

    /// 같은 국면에 행동을 중복 예약하지 않기 위한 기록
    private var handledSignatures: Set<String> = []
    private var pendingActions: [DispatchWorkItem] = []

    private static let botNames = ["달토끼", "밤바람", "은하수", "그믐달", "별지기", "새벽"]

    init(engine: GameEngine, hostID: UUID, botCount: Int = 6) {
        self.engine = engine
        self.hostID = hostID
        self.botIDs = (0..<botCount).map { _ in UUID() }
    }

    /// 봇들이 시차를 두고 입장한 뒤 게임을 자동 시작한다.
    func start() {
        for (i, id) in botIDs.enumerated() {
            schedule(after: 0.6 + Double(i) * 0.45) { engine in
                engine.join(playerID: id,
                            name: Self.botNames[i % Self.botNames.count],
                            isHost: false)
            }
        }
        let allJoined = 0.6 + Double(botIDs.count) * 0.45
        schedule(after: allJoined + 1.2) { [hostID] engine in
            engine.handle(.startGame(playerID: hostID))
        }
    }

    func stop() {
        for item in pendingActions { item.cancel() }
        pendingActions.removeAll()
    }

    /// '넘어가기': 현재 국면에 예약된 행동을 취소하고 즉시 실행해 다음 단계로 넘긴다.
    func skip(state: PublicGameState) {
        stop()
        handledSignatures.remove(signature(for: state))
        react(to: state, fast: true)
    }

    private func signature(for state: PublicGameState) -> String {
        [state.phase.rawValue,
         "\(state.round)",
         "\(state.voteTrack)",
         state.leaderID?.uuidString ?? ""].joined(separator: "-")
    }

    /// 상태가 바뀔 때마다 호출된다. 현재 국면에 필요한 행동들을
    /// 사람이 따라 읽을 수 있는 속도로 예약한다. (fast면 즉시 실행)
    func react(to state: PublicGameState, fast: Bool = false) {
        let signature = signature(for: state)
        guard !handledSignatures.contains(signature) else { return }
        handledSignatures.insert(signature)
        let speed = fast ? 0.03 : 1.0

        switch state.phase {
        case .lobby:
            // 새 판(다시 하기)을 위해 이전 판의 기록을 비운다
            handledSignatures = [signature]

        case .roleReveal:
            for (i, player) in state.players.enumerated() where !player.hasActed {
                schedule(after: (1.2 + Double(i) * 0.5) * speed) { engine in
                    engine.handle(.confirmRole(playerID: player.id))
                }
            }

        case .teamProposal:
            guard let leader = state.leaderID else { return }
            let size = state.requiredTeamSize
            schedule(after: 2.2 * speed) { engine in
                // 리더는 보통 자신을 포함해 무작위로 지명한다
                var pool = state.players.map(\.id).shuffled()
                pool.removeAll { $0 == leader }
                let team = [leader] + pool.prefix(size - 1)
                engine.handle(.proposeTeam(playerID: leader, members: Array(team)))
            }

        case .teamVoting:
            for (i, player) in state.players.enumerated() where !player.hasActed {
                schedule(after: (1.0 + Double(i) * 0.4) * speed) { engine in
                    let approve = Double.random(in: 0..<1) < 0.75
                    engine.handle(.teamVote(playerID: player.id, approve: approve))
                }
            }

        case .voteResult:
            schedule(after: 3.0 * speed) { [hostID] engine in
                engine.handle(.hostContinue(playerID: hostID))
            }

        case .mission:
            for (i, memberID) in state.proposedTeam.enumerated() {
                schedule(after: (1.5 + Double(i) * 0.5) * speed) { engine in
                    let isShadow = engine.players
                        .first { $0.id == memberID }?.role.team == .shadow
                    let success = isShadow ? Double.random(in: 0..<1) < 0.35 : true
                    engine.handle(.missionAction(playerID: memberID, success: success))
                }
            }

        case .missionResult:
            schedule(after: 3.5 * speed) { [hostID] engine in
                engine.handle(.hostContinue(playerID: hostID))
            }

        case .assassination:
            schedule(after: 4.0 * speed) { engine in
                guard let assassin = engine.players.first(where: { $0.role == .assassin }),
                      let target = engine.players
                          .filter({ $0.role.team == .moonlit })
                          .randomElement() else { return }
                engine.handle(.assassinate(playerID: assassin.id, targetID: target.id))
            }

        case .gameOver:
            break   // 결과 화면은 사용자가 직접 닫거나 다시 시작한다
        }
    }

    /// 데모가 종료(stop)되면 예약된 행동은 실행되지 않는다.
    private func schedule(after delay: TimeInterval,
                          _ action: @escaping (GameEngine) -> Void) {
        let item = DispatchWorkItem { [weak self] in
            guard let engine = self?.engine else { return }
            action(engine)
        }
        pendingActions.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
