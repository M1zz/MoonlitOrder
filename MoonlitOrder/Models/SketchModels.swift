import Foundation

// MARK: - 달빛 화실 진행 단계

enum SketchPhase: String, Codable, Equatable {
    case lobby          // 대기실
    case wordSelect     // 화가가 제시어 3개 중 하나를 고르는 중
    case drawing        // 화가가 그리고 나머지는 채팅으로 맞히는 중
    case roundResult    // 라운드 결과 (제시어 공개 · 점수)
    case gameOver       // 최종 순위
}

// MARK: - 그림 한 획 (정규화 좌표 0…1 기준 — 모든 기기가 같은 그림을 본다)

struct SketchPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct SketchStroke: Codable, Equatable {
    var points: [SketchPoint]
    var colorIndex: Int
    var width: Double
}

// MARK: - 추측/채팅 로그 한 줄

struct SketchChat: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var text: String
    var correct: Bool          // 정답을 맞힌 순간의 시스템 메시지면 true
}

// MARK: - 공개 상태 (전원 브로드캐스트)

struct SketchGameState: Codable, Equatable {
    var phase: SketchPhase = .lobby
    var players: [PlayerPublic] = []
    var round: Int = 1
    var totalRounds: Int = 0
    var drawerID: UUID?
    var drawOrder: [UUID] = []

    var category: String = ""          // 제시어 힌트: 카테고리
    var wordLength: Int = 0            // 제시어 힌트: 글자 수
    var strokes: [SketchStroke] = []
    var chat: [SketchChat] = []
    var solvedIDs: [UUID] = []          // 이번 라운드에 정답을 맞힌 사람들

    var scores: [String: Int] = [:]     // playerID.uuidString → 누적 점수
    var lastRoundGains: [String: Int] = [:]
    var revealedWord: String?           // roundResult / gameOver 에서만 채워짐

    // 단계 타이머 (호스트 기준 — 재촉용 소프트 타이머)
    var phaseSeconds: Int?
    var phaseStartedAt: Date = Date()

    // MARK: 계산 속성

    func player(_ id: UUID) -> PlayerPublic? { players.first { $0.id == id } }
    var drawer: PlayerPublic? { drawerID.flatMap { player($0) } }
    var disconnectedPlayers: [PlayerPublic] { players.filter { !$0.isConnected } }

    /// 이번 라운드에 아직 정답을 못 맞힌 추측자(화가 제외) 수
    var remainingGuessers: Int {
        players.filter { $0.id != drawerID && !solvedIDs.contains($0.id) }.count
    }

    var guesserCount: Int { max(0, players.count - 1) }

    /// 순위표 (점수 내림차순)
    var ranking: [(player: PlayerPublic, score: Int)] {
        players.map { ($0, scores[$0.id.uuidString] ?? 0) }
            .sorted { $0.1 > $1.1 }
    }

    var topScore: Int { scores.values.max() ?? 0 }
    var winnerNames: [String] {
        guard topScore > 0 else { return [] }
        return players
            .filter { (scores[$0.id.uuidString] ?? 0) == topScore }
            .map(\.name)
    }
}

// MARK: - 비공개 정보 (개별 전송)

struct SketchPrivateInfo: Codable, Equatable {
    var isDrawer: Bool
    var word: String?              // 화가에게만 (그리는 중)
    var wordChoices: [String]?     // 화가에게만 (제시어 고르는 중)
}

// MARK: - 클라이언트 → 호스트 액션

enum SketchAction: Codable {
    case startGame
    case chooseWord(String)
    case addStroke(SketchStroke)
    case undoStroke
    case clearCanvas
    case guess(String)
    case endRound            // 화가 또는 호스트: 이번 라운드를 끝낸다
    case continueRound       // 호스트: 다음 라운드(또는 종료)로
    case playAgain
    case abortToLobby
}

// MARK: - 규칙 / 단어 은행 / 팔레트

enum SketchRules {
    static let playerRange = 3...10
    static let wordChoiceCount = 3
    static let maxChatLines = 40

    static func phaseSeconds(for phase: SketchPhase) -> Int? {
        switch phase {
        case .wordSelect: return 20
        case .drawing:    return 90
        case .lobby, .roundResult, .gameOver: return nil
        }
    }

    // MARK: 색 팔레트 (마지막 색은 배경색 = 지우개)

    /// 그림판 배경(종이) 색 — 지우개가 이 색으로 덧그린다.
    static let boardColor = (r: 0.98, g: 0.97, b: 0.93)

    /// (r,g,b) 0…1. 인덱스가 스트로크에 저장된다.
    static let palette: [(r: Double, g: Double, b: Double)] = [
        (0.10, 0.10, 0.12),   // 0 먹색(검정)
        (0.92, 0.26, 0.30),   // 1 빨강
        (0.96, 0.55, 0.15),   // 2 주황
        (0.98, 0.80, 0.20),   // 3 노랑
        (0.30, 0.72, 0.40),   // 4 초록
        (0.25, 0.55, 0.92),   // 5 파랑
        (0.60, 0.40, 0.85),   // 6 보라
        (0.55, 0.38, 0.24),   // 7 갈색
        boardColor,           // 8 지우개(종이색)
    ]
    static var eraserIndex: Int { palette.count - 1 }

    static let brushWidths: [Double] = [4, 9, 18]

    // MARK: 단어 은행 (그리기 좋은 명사 위주)

    static let wordBank: [String: [String]] = [
        "동물": ["코끼리", "기린", "펭귄", "토끼", "고양이", "강아지", "사자", "곰",
               "돌고래", "문어", "달팽이", "뱀", "부엉이", "거북이", "나비", "물고기"],
        "음식": ["피자", "햄버거", "아이스크림", "케이크", "바나나", "수박", "달걀후라이",
               "라면", "김밥", "도넛", "사과", "핫도그", "포도", "당근"],
        "사물": ["우산", "안경", "시계", "가위", "자전거", "의자", "열쇠", "전구",
               "풍선", "양초", "선물상자", "빗자루", "망치", "연필", "컵"],
        "탈것": ["자동차", "비행기", "배", "기차", "로켓", "헬리콥터", "잠수함", "열기구"],
        "자연": ["나무", "꽃", "태양", "구름", "무지개", "산", "별", "눈사람",
               "번개", "화산", "섬", "달"],
        "캐릭터": ["로봇", "유령", "왕관", "해적", "천사", "마법사", "공룡", "외계인",
                "인어", "산타"],
    ]

    /// 화가에게 보여줄 제시어 후보 (서로 다른 3개, 각각 카테고리 포함)
    static func drawChoices() -> [(word: String, category: String)] {
        var picks: [(String, String)] = []
        var usedWords = Set<String>()
        let categories = Array(wordBank.keys)
        var attempts = 0
        while picks.count < wordChoiceCount, attempts < 100 {
            attempts += 1
            guard let category = categories.randomElement(),
                  let word = wordBank[category]?.randomElement(),
                  !usedWords.contains(word) else { continue }
            usedWords.insert(word)
            picks.append((word, category))
        }
        return picks
    }

    static func category(of word: String) -> String {
        wordBank.first { $0.value.contains(word) }?.key ?? ""
    }

    /// 추측 정답 판정용 정규화 (공백 제거 · 소문자 · 트림)
    static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    // MARK: 점수

    /// rank번째로 맞힌 추측자의 획득 점수 (빠를수록 높음)
    static func guesserPoints(rank: Int) -> Int {
        max(50, 100 - (rank - 1) * 15)
    }

    /// 화가 점수 — 맞힌 사람이 많을수록(그림이 명확할수록) 보상, 최대 90
    static func drawerPoints(solvedCount: Int) -> Int {
        min(90, 30 * solvedCount)
    }
}
