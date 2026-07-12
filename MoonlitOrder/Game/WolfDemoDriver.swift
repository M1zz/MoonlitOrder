import Foundation

/// '달 없는 밤'의 게임방법(데모) 모드. 봇들과 함께 사용자가 '다음' 버튼으로
/// 한 단계씩 진행하며 규칙을 익힌다. 실제 게임과 같은 엔진 경로만 사용한다.
final class WolfDemoDriver {

    private weak var engine: WolfEngine?
    private let hostID: UUID
    private let botIDs: [UUID]
    private var pendingActions: [DispatchWorkItem] = []

    private static let botNames = ["달토끼", "밤바람", "은하수", "그믐달", "별지기"]

    init(engine: WolfEngine, hostID: UUID, botCount: Int = 5) {
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

    /// '다음': 현재 단계에서 아직 행동하지 않은 참가자의 행동을 실행한다.
    func advance(from state: WolfGameState) {
        guard let engine else { return }
        switch state.phase {
        case .night:
            let loneWolf = engine.players.filter { $0.originalRole == .werewolf }.count == 1
            for (i, player) in engine.players.enumerated() where !player.nightDone {
                let role = player.originalRole
                let pid = player.id
                schedule(after: Double(i) * 0.2) { engine in
                    let others = engine.players.map(\.id).filter { $0 != pid }
                    switch role {
                    case .werewolf:
                        let centers = loneWolf ? [Int.random(in: 0..<3)] : []
                        engine.handle(pid, .nightAction(targets: [], centers: centers))
                    case .seer:
                        if Bool.random(), let target = others.randomElement() {
                            engine.handle(pid, .nightAction(targets: [target], centers: []))
                        } else {
                            engine.handle(pid, .nightAction(targets: [], centers: [0, 1]))
                        }
                    case .robber:
                        guard let target = others.randomElement() else { return }
                        engine.handle(pid, .nightAction(targets: [target], centers: []))
                    case .troublemaker:
                        let two = Array(others.shuffled().prefix(2))
                        guard two.count == 2 else { return }
                        engine.handle(pid, .nightAction(targets: two, centers: []))
                    case .villager:
                        engine.handle(pid, .nightAction(targets: [], centers: []))
                    }
                }
            }

        case .day:
            schedule(after: 0.2) { [hostID] engine in
                engine.handle(hostID, .startVoting)
            }

        case .voting:
            for (i, player) in state.players.enumerated() where !player.hasActed {
                schedule(after: Double(i) * 0.25) { engine in
                    let others = state.players.map(\.id).filter { $0 != player.id }
                    guard let target = others.randomElement() else { return }
                    engine.handle(player.id, .vote(targetID: target))
                }
            }

        case .lobby, .gameOver:
            break
        }
    }

    /// 연습에서만 공개하는 '밤사이 일어난 일' 요약.
    /// 실제 게임에서는 절대 볼 수 없는 정보지만, 능력·카드 교환 시스템을
    /// 배우려면 무슨 일이 있었는지 봐야 하므로 데모에서만 보여준다.
    func nightSummary() -> String? {
        guard let engine else { return nil }
        var lines: [String] = []
        for player in engine.players {
            switch player.originalRole {
            case .werewolf:
                lines.append("🔥 도깨비 \(player.name)이(가) 어둠 속에서 눈을 떴습니다.")
            case .seer:
                lines.append("👁 무당 \(player.name)이(가) 남몰래 카드를 확인했습니다.")
            case .robber:
                if let targetID = player.robberTarget,
                   let target = engine.players.first(where: { $0.id == targetID }) {
                    lines.append("🤝 밤손님 \(player.name)이(가) \(target.name)의 카드를 훔쳐 서로 바뀌었습니다!")
                }
            case .troublemaker:
                let names = player.troublemakerTargets.compactMap { id in
                    engine.players.first { $0.id == id }?.name
                }
                if names.count == 2 {
                    lines.append("🔀 장난꾼 \(player.name)이(가) \(names[0])과(와) \(names[1])의 카드를 서로 바꿨습니다!")
                }
            case .villager:
                break
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func schedule(after delay: TimeInterval,
                          _ action: @escaping (WolfEngine) -> Void) {
        let item = DispatchWorkItem { [weak self] in
            guard let engine = self?.engine else { return }
            action(engine)
        }
        pendingActions.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
