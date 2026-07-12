import Foundation

/// 라이어 게임의 게임방법(데모) 모드. 봇들과 함께 사용자가 '다음' 버튼으로
/// 한 단계씩 진행하며 규칙을 익힌다. 실제 게임과 같은 엔진 경로만 사용한다.
final class LiarDemoDriver {

    private weak var engine: LiarEngine?
    private let hostID: UUID
    private let botIDs: [UUID]
    private var pendingActions: [DispatchWorkItem] = []

    private static let botNames = ["달토끼", "밤바람", "은하수", "그믐달", "별지기"]

    init(engine: LiarEngine, hostID: UUID, botCount: Int = 5) {
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

    /// '다음': 현재 단계에서 남은 행동을 실행해 게임을 진행시킨다.
    /// 설명 단계에서는 한 번에 한 명씩 발언을 마친다 (배우기 좋은 속도).
    func advance(from state: LiarGameState) {
        guard let engine else { return }
        switch state.phase {
        case .wordReveal:
            for (i, player) in state.players.enumerated() where !player.hasActed {
                schedule(after: Double(i) * 0.15) { engine in
                    engine.handle(player.id, .confirmWord)
                }
            }

        case .describing:
            if let current = state.currentSpeakerID {
                schedule(after: 0.2) { engine in
                    engine.handle(current, .finishSpeech)
                }
            }

        case .voting:
            let liarID = engine.liarID
            for (i, player) in state.players.enumerated() where !player.hasActed {
                schedule(after: Double(i) * 0.25) { engine in
                    let others = state.players.map(\.id).filter { $0 != player.id }
                    let target: UUID
                    if let liarID, liarID != player.id,
                       Double.random(in: 0..<1) < 0.6 {
                        target = liarID   // 봇들은 눈치가 좋은 편
                    } else {
                        target = others.randomElement() ?? player.id
                    }
                    engine.handle(player.id, .vote(targetID: target))
                }
            }

        case .liarGuess:
            schedule(after: 0.5) { engine in
                guard let liarID = engine.liarID else { return }
                // 절반 확률로 정답을 맞혀 역전승 연출
                let word: String
                if Double.random(in: 0..<1) < 0.5 {
                    word = engine.secretWord
                } else {
                    word = (LiarRules.wordBank[engine.category] ?? [])
                        .filter { $0 != engine.secretWord }
                        .randomElement() ?? engine.secretWord
                }
                engine.handle(liarID, .guessWord(word))
            }

        case .lobby, .gameOver:
            break
        }
    }

    private func schedule(after delay: TimeInterval,
                          _ action: @escaping (LiarEngine) -> Void) {
        let item = DispatchWorkItem { [weak self] in
            guard let engine = self?.engine else { return }
            action(engine)
        }
        pendingActions.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
