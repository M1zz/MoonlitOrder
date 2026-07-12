import Foundation

/// 라이어 게임의 권위(authoritative) 엔진. 호스트 기기에서만 동작한다.
/// 규칙: 라이어를 제외한 전원이 같은 제시어를 받는다. 순서대로 한 마디씩
/// 설명한 뒤 라이어를 투표로 지목한다. 라이어가 잡히면 라이어에게 단어를
/// 추측할 마지막 기회가 주어지고, 맞히면 라이어가 역전승한다.
final class LiarEngine {

    struct PlayerInternal {
        let id: UUID
        var name: String
        var isHost: Bool
        var connected: Bool = true
        var confirmedWord: Bool = false
        var votedFor: UUID?
    }

    // MARK: 상태

    private(set) var players: [PlayerInternal] = []
    private var phase: LiarPhase = .lobby {
        didSet { if oldValue != phase { phaseStartedAt = Date() } }
    }
    private var phaseStartedAt = Date()
    // 데모(게임방법) 봇이 참조할 수 있도록 읽기만 공개
    private(set) var category = ""
    private(set) var secretWord = ""
    private(set) var liarID: UUID?
    private var speakingOrder: [UUID] = []
    private var speakerIndex = 0
    private var lastVotes: [String: String] = [:]
    private var accusedID: UUID?
    private var liarGuess: String?
    private var liarWins: Bool?
    private var winReason: String?

    var onStateChange: ((LiarGameState) -> Void)?
    var onPrivateInfo: ((UUID, LiarPrivateInfo) -> Void)?

    private var hostID: UUID? { players.first { $0.isHost }?.id }

    // MARK: - 참가 / 연결 (달빛 결사와 동일한 규약)

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
        guard players.count < LiarRules.playerRange.upperBound else { return .rejectedFull }

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

    func handle(_ playerID: UUID, _ action: LiarAction) {
        switch action {
        case .startGame:
            startGame(by: playerID)
        case .confirmWord:
            confirmWord(playerID)
        case .finishSpeech:
            finishSpeech(playerID)
        case .vote(let targetID):
            vote(playerID, for: targetID)
        case .guessWord(let word):
            guessWord(playerID, word: word)
        case .playAgain, .abortToLobby:
            resetToLobby(by: playerID)
        }
    }

    private func startGame(by playerID: UUID) {
        guard phase == .lobby,
              playerID == hostID,
              LiarRules.playerRange.contains(players.count) else { return }

        let drawn = LiarRules.drawWord()
        category = drawn.category
        secretWord = drawn.word
        liarID = players.randomElement()?.id
        speakingOrder = players.map(\.id).shuffled()
        speakerIndex = 0
        lastVotes = [:]
        accusedID = nil
        liarGuess = nil
        liarWins = nil
        winReason = nil
        for i in players.indices {
            players[i].confirmedWord = false
            players[i].votedFor = nil
        }
        phase = .wordReveal

        pushState()
        for p in players {
            onPrivateInfo?(p.id, privateInfo(for: p.id))
        }
    }

    private func confirmWord(_ playerID: UUID) {
        guard phase == .wordReveal,
              let idx = players.firstIndex(where: { $0.id == playerID }) else { return }
        players[idx].confirmedWord = true
        if players.allSatisfy({ $0.confirmedWord }) {
            phase = .describing
        }
        pushState()
    }

    private func finishSpeech(_ playerID: UUID) {
        guard phase == .describing,
              speakingOrder.indices.contains(speakerIndex),
              speakingOrder[speakerIndex] == playerID else { return }
        speakerIndex += 1
        phaseStartedAt = Date()   // 발언자마다 타이머 리셋
        if speakerIndex >= speakingOrder.count {
            phase = .voting
        }
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
        let top = counts.filter { $0.value == maxCount }.map(\.key)

        guard top.count == 1, let accused = top.first else {
            // 표가 갈리면 라이어 검거 실패
            endGame(liarWins: true, reason: "표가 갈려 라이어를 잡지 못했습니다!")
            return
        }
        accusedID = accused
        if accused == liarID {
            phase = .liarGuess
            // 라이어에게 추측 후보를 전달
            if let liarID { onPrivateInfo?(liarID, privateInfo(for: liarID)) }
        } else {
            endGame(liarWins: true, reason: "엉뚱한 사람을 지목했습니다!")
        }
    }

    private func guessWord(_ playerID: UUID, word: String) {
        guard phase == .liarGuess, playerID == liarID else { return }
        liarGuess = word
        if word == secretWord {
            endGame(liarWins: true, reason: "라이어가 제시어를 정확히 맞혔습니다! 라이어의 역전승!")
        } else {
            endGame(liarWins: false, reason: "라이어가 제시어를 맞히지 못했습니다. 시민의 승리!")
        }
    }

    private func endGame(liarWins: Bool, reason: String) {
        self.liarWins = liarWins
        self.winReason = reason
        phase = .gameOver
        pushState()
    }

    private func resetToLobby(by playerID: UUID) {
        guard phase != .lobby, playerID == hostID else { return }
        players.removeAll { !$0.connected && !$0.isHost }
        for i in players.indices {
            players[i].confirmedWord = false
            players[i].votedFor = nil
        }
        phase = .lobby
        category = ""
        secretWord = ""
        liarID = nil
        speakingOrder = []
        speakerIndex = 0
        lastVotes = [:]
        accusedID = nil
        liarGuess = nil
        liarWins = nil
        winReason = nil
        pushState()
    }

    // MARK: - 상태 생성

    private func privateInfo(for playerID: UUID) -> LiarPrivateInfo {
        let isLiar = playerID == liarID
        var info = LiarPrivateInfo(isLiar: isLiar, word: isLiar ? nil : secretWord)
        if isLiar, phase == .liarGuess {
            info.guessChoices = LiarRules.guessChoices(category: category, answer: secretWord)
        }
        return info
    }

    private func hasActed(_ p: PlayerInternal) -> Bool {
        switch phase {
        case .wordReveal: return p.confirmedWord
        case .describing: return !(speakingOrder.dropFirst(speakerIndex).contains(p.id))
        case .voting:     return p.votedFor != nil
        default:          return false
        }
    }

    private func publicState() -> LiarGameState {
        var s = LiarGameState()
        s.phase = phase
        s.players = players.map {
            PlayerPublic(id: $0.id,
                         name: $0.name,
                         isHost: $0.isHost,
                         isConnected: $0.connected,
                         hasActed: hasActed($0))
        }
        s.category = phase == .lobby ? "" : category
        s.speakingOrder = speakingOrder
        s.speakerIndex = speakerIndex
        if phase == .liarGuess || phase == .gameOver {
            s.lastVotes = lastVotes
            s.accusedID = accusedID
        }
        if phase == .gameOver {
            s.liarID = liarID
            s.secretWord = secretWord
            s.liarGuess = liarGuess
        }
        s.liarWins = liarWins
        s.winReason = winReason
        s.phaseSeconds = LiarRules.phaseSeconds(for: phase)
        s.phaseStartedAt = phaseStartedAt
        return s
    }

    private func pushState() {
        onStateChange?(publicState())
    }
}
