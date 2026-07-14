import Foundation

/// 달빛 화실의 권위(authoritative) 엔진. 호스트 기기에서만 동작한다.
/// 규칙: 매 라운드 한 명(화가)이 제시어를 그리고, 나머지는 채팅으로 맞힌다.
/// 빠르게 맞힐수록 높은 점수를 얻고, 화가는 맞힌 사람이 많을수록 점수를 얻는다.
/// 모든 참가자가 한 번씩 화가를 맡으면 게임이 끝나고 최고 점수자가 승리한다.
final class SketchEngine {

    struct PlayerInternal {
        let id: UUID
        var name: String
        var isHost: Bool
        var connected: Bool = true
    }

    // MARK: 상태

    private(set) var players: [PlayerInternal] = []
    private var phase: SketchPhase = .lobby {
        didSet { if oldValue != phase { phaseStartedAt = Date() } }
    }
    private var phaseStartedAt = Date()

    private var round = 1
    private var totalRounds = 0
    private var drawOrder: [UUID] = []
    private var drawerIndex = 0

    // 데모 드라이버가 참조할 수 있도록 읽기만 공개
    private(set) var secretWord = ""
    private var category = ""
    private(set) var wordChoices: [String] = []
    private var strokes: [SketchStroke] = []
    private var chat: [SketchChat] = []
    private var solvedOrder: [UUID] = []        // 맞힌 순서
    private var scores: [UUID: Int] = [:]
    private var lastRoundGains: [UUID: Int] = [:]

    /// 데모: 이 사람이 첫 화가가 되도록 보장 (사용자가 그리기를 체험)
    var guaranteeFirstDrawer: UUID?
    /// 데모: 한 라운드만 진행
    var forcedTotalRounds: Int?

    var onStateChange: ((SketchGameState) -> Void)?
    var onPrivateInfo: ((UUID, SketchPrivateInfo) -> Void)?

    private var hostID: UUID? { players.first { $0.isHost }?.id }
    private var currentDrawerID: UUID? {
        drawOrder.indices.contains(drawerIndex) ? drawOrder[drawerIndex] : nil
    }

    // MARK: - 참가 / 연결 (다른 게임과 동일한 규약)

    @discardableResult
    func join(playerID: UUID, name: String, isHost: Bool) -> GameEngine.JoinResult {
        if let idx = players.firstIndex(where: { $0.id == playerID }) {
            players[idx].connected = true
            pushState()
            if phase != .lobby {
                onPrivateInfo?(playerID, privateInfo(for: playerID))
            }
            return .rejoined
        }
        guard phase == .lobby else { return .rejectedInProgress }
        guard players.count < SketchRules.playerRange.upperBound else { return .rejectedFull }

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

    func handle(_ playerID: UUID, _ action: SketchAction) {
        switch action {
        case .startGame:          startGame(by: playerID)
        case .chooseWord(let w):  chooseWord(playerID, word: w)
        case .addStroke(let s):   addStroke(playerID, stroke: s)
        case .undoStroke:         undoStroke(playerID)
        case .clearCanvas:        clearCanvas(playerID)
        case .guess(let text):    guess(playerID, text: text)
        case .endRound:           endRound(by: playerID)
        case .continueRound:      continueRound(by: playerID)
        case .playAgain, .abortToLobby: resetToLobby(by: playerID)
        }
    }

    private func startGame(by playerID: UUID) {
        guard phase == .lobby,
              playerID == hostID,
              SketchRules.playerRange.contains(players.count) else { return }

        scores = [:]
        for p in players { scores[p.id] = 0 }
        drawOrder = players.map(\.id).shuffled()
        // 데모: 사용자가 첫 화가가 되도록 맨 앞으로
        if let first = guaranteeFirstDrawer,
           let idx = drawOrder.firstIndex(of: first) {
            drawOrder.remove(at: idx)
            drawOrder.insert(first, at: 0)
        }
        drawerIndex = 0
        totalRounds = forcedTotalRounds ?? players.count
        round = 1
        beginRound()
    }

    private func beginRound() {
        strokes = []
        chat = []
        solvedOrder = []
        lastRoundGains = [:]
        secretWord = ""
        category = ""
        let choices = SketchRules.drawChoices()
        wordChoices = choices.map(\.word)
        phase = .wordSelect

        pushState()
        // 화가에게 제시어 후보를, 나머지에게 빈 정보를 보낸다
        for p in players { onPrivateInfo?(p.id, privateInfo(for: p.id)) }
    }

    private func chooseWord(_ playerID: UUID, word: String) {
        guard phase == .wordSelect,
              playerID == currentDrawerID,
              wordChoices.contains(word) else { return }
        secretWord = word
        category = SketchRules.category(of: word)
        phase = .drawing
        pushState()
        for p in players { onPrivateInfo?(p.id, privateInfo(for: p.id)) }
    }

    private func addStroke(_ playerID: UUID, stroke: SketchStroke) {
        guard phase == .drawing, playerID == currentDrawerID,
              !stroke.points.isEmpty else { return }
        strokes.append(stroke)
        pushState()
    }

    private func undoStroke(_ playerID: UUID) {
        guard phase == .drawing, playerID == currentDrawerID,
              !strokes.isEmpty else { return }
        strokes.removeLast()
        pushState()
    }

    private func clearCanvas(_ playerID: UUID) {
        guard phase == .drawing, playerID == currentDrawerID,
              !strokes.isEmpty else { return }
        strokes = []
        pushState()
    }

    private func guess(_ playerID: UUID, text: String) {
        guard phase == .drawing,
              playerID != currentDrawerID,
              !solvedOrder.contains(playerID),
              let p = players.first(where: { $0.id == playerID }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if SketchRules.normalize(trimmed) == SketchRules.normalize(secretWord) {
            // 정답 — 단어를 노출하지 않고 시스템 메시지만 남긴다
            solvedOrder.append(playerID)
            let rank = solvedOrder.count
            lastRoundGains[playerID, default: 0] += SketchRules.guesserPoints(rank: rank)
            appendChat(SketchChat(name: p.name, text: "정답을 맞혔어요! 🎉", correct: true))
            // 모든 추측자가 맞히면 라운드 종료
            let guessers = players.filter { $0.id != currentDrawerID }
            if guessers.allSatisfy({ solvedOrder.contains($0.id) }) {
                finishRound()
                return
            }
        } else {
            appendChat(SketchChat(name: p.name, text: trimmed, correct: false))
        }
        pushState()
    }

    private func appendChat(_ line: SketchChat) {
        chat.append(line)
        if chat.count > SketchRules.maxChatLines {
            chat.removeFirst(chat.count - SketchRules.maxChatLines)
        }
    }

    /// 화가 또는 호스트가 라운드를 수동 종료
    private func endRound(by playerID: UUID) {
        guard phase == .drawing || phase == .wordSelect,
              playerID == currentDrawerID || playerID == hostID else { return }
        finishRound()
    }

    private func finishRound() {
        // 점수 정산: 추측자 점수는 guess()에서 이미 적립됨. 화가 점수만 여기서.
        if let drawer = currentDrawerID {
            lastRoundGains[drawer, default: 0] += SketchRules.drawerPoints(solvedCount: solvedOrder.count)
        }
        for (id, gain) in lastRoundGains { scores[id, default: 0] += gain }
        phase = .roundResult
        pushState()
    }

    /// 호스트가 다음 라운드(또는 종료)로 진행
    private func continueRound(by playerID: UUID) {
        guard phase == .roundResult, playerID == hostID else { return }
        if round >= totalRounds {
            phase = .gameOver
            pushState()
        } else {
            round += 1
            drawerIndex += 1
            beginRound()
        }
    }

    private func resetToLobby(by playerID: UUID) {
        guard phase != .lobby, playerID == hostID else { return }
        players.removeAll { !$0.connected && !$0.isHost }
        phase = .lobby
        round = 1
        totalRounds = 0
        drawOrder = []
        drawerIndex = 0
        secretWord = ""
        category = ""
        wordChoices = []
        strokes = []
        chat = []
        solvedOrder = []
        scores = [:]
        lastRoundGains = [:]
        pushState()
    }

    // MARK: - 상태 생성

    private func privateInfo(for playerID: UUID) -> SketchPrivateInfo {
        let isDrawer = playerID == currentDrawerID
        var info = SketchPrivateInfo(isDrawer: isDrawer)
        if isDrawer {
            if phase == .wordSelect { info.wordChoices = wordChoices }
            if phase == .drawing || phase == .roundResult { info.word = secretWord }
        }
        return info
    }

    private func hasActed(_ p: PlayerInternal) -> Bool {
        switch phase {
        case .drawing: return p.id != currentDrawerID && solvedOrder.contains(p.id)
        default:       return false
        }
    }

    private func publicState() -> SketchGameState {
        var s = SketchGameState()
        s.phase = phase
        s.players = players.map {
            PlayerPublic(id: $0.id,
                         name: $0.name,
                         isHost: $0.isHost,
                         isConnected: $0.connected,
                         hasActed: hasActed($0))
        }
        s.round = round
        s.totalRounds = totalRounds
        s.drawerID = phase == .lobby ? nil : currentDrawerID
        s.drawOrder = drawOrder
        s.category = (phase == .drawing || phase == .roundResult) ? category : ""
        s.wordLength = (phase == .drawing) ? secretWord.count : 0
        s.strokes = strokes
        s.chat = chat
        s.solvedIDs = solvedOrder
        s.scores = Dictionary(uniqueKeysWithValues: scores.map { ($0.key.uuidString, $0.value) })
        if phase == .roundResult || phase == .gameOver {
            s.lastRoundGains = Dictionary(uniqueKeysWithValues:
                lastRoundGains.map { ($0.key.uuidString, $0.value) })
        }
        if phase == .roundResult { s.revealedWord = secretWord }
        s.phaseSeconds = SketchRules.phaseSeconds(for: phase)
        s.phaseStartedAt = phaseStartedAt
        return s
    }

    private func pushState() {
        onStateChange?(publicState())
    }
}
