import Foundation

/// 게임방법(데모) 모드: 봇 플레이어들과 함께 사용자가 '다음' 버튼으로
/// 한 단계씩 진행하며 게임 규칙을 익힌다. 자동으로 넘어가지 않는다.
/// 네트워크 없이 로컬 GameEngine 위에서 돌며, 실제 게임과 같은
/// 메시지 경로(engine.handle)만 사용하므로 규칙 판정도 동일하다.
final class DemoDriver {

    private weak var engine: GameEngine?
    private let hostID: UUID
    private let botIDs: [UUID]
    private var pendingActions: [DispatchWorkItem] = []

    private static let botNames = ["달토끼", "밤바람", "은하수", "그믐달", "별지기", "새벽"]

    init(engine: GameEngine, hostID: UUID, botCount: Int = 6) {
        self.engine = engine
        self.hostID = hostID
        self.botIDs = (0..<botCount).map { _ in UUID() }
    }

    /// 봇들이 시차를 두고 대기실에 입장한다. 게임 시작은 사용자가 직접 누른다.
    func start() {
        for (i, id) in botIDs.enumerated() {
            schedule(after: 0.6 + Double(i) * 0.45) { engine in
                engine.join(playerID: id,
                            name: Self.botNames[i % Self.botNames.count],
                            isHost: false)
            }
        }
    }

    func stop() {
        for item in pendingActions { item.cancel() }
        pendingActions.removeAll()
    }

    /// '다음': 현재 단계에서 아직 행동하지 않은 참가자(봇, 필요시 사용자 포함)의
    /// 행동을 실행해 게임을 한 단계 진행시킨다. 사용자가 먼저 직접 행동해도 되고,
    /// 이미 끝난 행동은 엔진의 단계 검사가 걸러내므로 여러 번 눌러도 안전하다.
    func advance(from state: PublicGameState) {
        switch state.phase {
        case .roleReveal:
            for (i, player) in state.players.enumerated() where !player.hasActed {
                schedule(after: Double(i) * 0.15) { engine in
                    engine.handle(.confirmRole(playerID: player.id))
                }
            }

        case .teamProposal:
            guard let leader = state.leaderID else { return }
            let size = state.requiredTeamSize
            schedule(after: 0.2) { engine in
                // 리더는 보통 자신을 포함해 무작위로 지명한다
                var pool = state.players.map(\.id).shuffled()
                pool.removeAll { $0 == leader }
                let team = [leader] + pool.prefix(size - 1)
                engine.handle(.proposeTeam(playerID: leader, members: Array(team)))
            }

        case .teamVoting:
            for (i, player) in state.players.enumerated() where !player.hasActed {
                schedule(after: Double(i) * 0.2) { engine in
                    let approve = Double.random(in: 0..<1) < 0.75
                    engine.handle(.teamVote(playerID: player.id, approve: approve))
                }
            }

        case .voteResult:
            schedule(after: 0.1) { [hostID] engine in
                engine.handle(.hostContinue(playerID: hostID))
            }

        case .mission:
            for (i, memberID) in state.proposedTeam.enumerated() {
                schedule(after: Double(i) * 0.25) { engine in
                    let isShadow = engine.players
                        .first { $0.id == memberID }?.role.team == .shadow
                    let success = isShadow ? Double.random(in: 0..<1) < 0.35 : true
                    engine.handle(.missionAction(playerID: memberID, success: success))
                }
            }

        case .missionResult:
            schedule(after: 0.1) { [hostID] engine in
                engine.handle(.hostContinue(playerID: hostID))
            }

        case .assassination:
            schedule(after: 0.2) { engine in
                guard let assassin = engine.players.first(where: { $0.role == .assassin }),
                      let target = engine.players
                          .filter({ $0.role.team == .moonlit })
                          .randomElement() else { return }
                engine.handle(.assassinate(playerID: assassin.id, targetID: target.id))
            }

        case .lobby, .gameOver:
            break   // 대기실·결과 화면은 기존 버튼으로 사용자가 직접 진행한다
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
