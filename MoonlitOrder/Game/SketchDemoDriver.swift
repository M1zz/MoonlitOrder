import Foundation

/// 달빛 화실의 게임방법(데모) 모드. 봇들과 함께 사용자가 '다음' 버튼으로
/// 한 단계씩 진행하며 규칙을 익힌다. 사용자가 화가를 맡아 직접 그려보고,
/// '다음'을 누르면 봇들이 채팅으로 추측(오답 몇 개 뒤 정답)하는 흐름을 보여준다.
final class SketchDemoDriver {

    private weak var engine: SketchEngine?
    private let hostID: UUID
    private let botIDs: [UUID]
    private var pendingActions: [DispatchWorkItem] = []

    private let auto: Bool

    private static let botNames = ["달토끼", "밤바람", "은하수", "그믐달", "별지기"]
    private static let wrongGuesses = ["강아지?", "음… 자동차", "혹시 곰?", "모르겠다 ㅋㅋ", "사과?"]

    init(engine: SketchEngine, hostID: UUID, botCount: Int = 4, auto: Bool = false) {
        self.engine = engine
        self.hostID = hostID
        self.auto = auto
        self.botIDs = (0..<botCount).map { _ in UUID() }
        // 데모는 한 라운드(사용자가 화가)만, 사용자가 첫 화가가 되도록 보장
        engine.guaranteeFirstDrawer = hostID
        engine.forcedTotalRounds = 1
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
        if auto { scheduleAutoPlay() }
    }

    /// 검증/자동 시연용: 탭 없이 전체 흐름을 자동 진행한다.
    private func scheduleAutoPlay() {
        let host = hostID
        let bots = botIDs
        let base = 0.6 + Double(botIDs.count) * 0.45 + 0.6

        schedule(after: base) { e in e.handle(host, .startGame) }
        schedule(after: base + 0.8) { e in
            if let word = e.wordChoices.first { e.handle(host, .chooseWord(word)) }
        }
        // 샘플 그림(웃는 얼굴)을 한 획씩 그린다
        let strokes = Self.sampleDrawing()
        for (i, s) in strokes.enumerated() {
            schedule(after: base + 1.4 + Double(i) * 0.5) { e in
                e.handle(host, .addStroke(s))
            }
        }
        // 봇들이 추측: 첫 봇은 오답 뒤 정답, 나머지는 정답
        let guessStart = base + 1.4 + Double(strokes.count) * 0.5 + 0.8
        for (i, bot) in bots.enumerated() {
            if i == 0 {
                schedule(after: guessStart) { e in
                    e.handle(bot, .guess(Self.wrongGuesses.randomElement() ?? "음…"))
                }
                schedule(after: guessStart + 0.6) { e in e.handle(bot, .guess(e.secretWord)) }
            } else {
                schedule(after: guessStart + 0.6 + Double(i) * 0.5) { e in
                    e.handle(bot, .guess(e.secretWord))
                }
            }
        }
        // 결과 → 최종 순위
        let done = guessStart + 0.6 + Double(bots.count) * 0.5 + 1.0
        schedule(after: done) { e in e.handle(host, .continueRound) }
    }

    /// 정규화 좌표(0…1) 기준 간단한 웃는 얼굴
    private static func sampleDrawing() -> [SketchStroke] {
        func arc(cx: Double, cy: Double, r: Double,
                 from: Double, to: Double, seg: Int = 28) -> [SketchPoint] {
            (0...seg).map { i in
                let a = from + (to - from) * Double(i) / Double(seg)
                return SketchPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            }
        }
        let twoPi = 2 * Double.pi
        let face  = SketchStroke(points: arc(cx: 0.5, cy: 0.46, r: 0.30, from: 0, to: twoPi),
                                 colorIndex: 0, width: 9)
        let eyeL  = SketchStroke(points: arc(cx: 0.40, cy: 0.38, r: 0.035, from: 0, to: twoPi),
                                 colorIndex: 0, width: 9)
        let eyeR  = SketchStroke(points: arc(cx: 0.60, cy: 0.38, r: 0.035, from: 0, to: twoPi),
                                 colorIndex: 0, width: 9)
        let smile = SketchStroke(points: arc(cx: 0.5, cy: 0.50, r: 0.16,
                                             from: Double.pi * 0.15, to: Double.pi * 0.85),
                                 colorIndex: 1, width: 9)
        return [face, eyeL, eyeR, smile]
    }

    func stop() {
        for item in pendingActions { item.cancel() }
        pendingActions.removeAll()
    }

    /// '다음': 현재 단계에서 봇들의 행동을 실행해 게임을 진행시킨다.
    func advance(from state: SketchGameState) {
        guard engine != nil else { return }
        switch state.phase {
        case .wordSelect:
            // 사용자가 화가다. 아직 제시어를 안 골랐으면 안내만 (사용자가 직접 고름).
            break

        case .drawing:
            // 봇들이 채팅으로 추측한다: 오답 몇 개 → 정답으로 맞힘
            let guessers = state.players.filter { $0.id != state.drawerID }
            let solved = Set(state.solvedIDs)
            let pending = guessers.filter { !solved.contains($0.id) }
            for (i, bot) in pending.enumerated() {
                // 앞의 한두 명은 오답을 먼저 던지고, 그다음 정답
                if i == 0 {
                    schedule(after: 0.3) { engine in
                        engine.handle(bot.id, .guess(Self.wrongGuesses.randomElement() ?? "음…"))
                    }
                    schedule(after: 1.0) { engine in
                        engine.handle(bot.id, .guess(engine.secretWord))
                    }
                } else {
                    schedule(after: 1.4 + Double(i) * 0.5) { engine in
                        engine.handle(bot.id, .guess(engine.secretWord))
                    }
                }
            }

        case .roundResult:
            // 다음으로 → 라운드가 1개뿐이므로 게임 종료로 진행
            schedule(after: 0.2) { [hostID] engine in
                engine.handle(hostID, .continueRound)
            }

        case .lobby, .gameOver:
            break
        }
    }

    private func schedule(after delay: TimeInterval,
                          _ action: @escaping (SketchEngine) -> Void) {
        let item = DispatchWorkItem { [weak self] in
            guard let engine = self?.engine else { return }
            action(engine)
        }
        pendingActions.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
