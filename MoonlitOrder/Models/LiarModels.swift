import Foundation

// MARK: - 라이어 게임 진행 단계

enum LiarPhase: String, Codable, Equatable {
    case lobby          // 대기실
    case wordReveal     // 제시어 확인 (라이어는 자신이 라이어임을 확인)
    case describing     // 돌아가며 한 마디씩 설명
    case voting         // 라이어 지목 투표
    case liarGuess      // 라이어가 잡혔을 때 마지막 단어 추측 기회
    case gameOver       // 결과
}

// MARK: - 공개 상태 (전원 브로드캐스트)

struct LiarGameState: Codable, Equatable {
    var phase: LiarPhase = .lobby
    var players: [PlayerPublic] = []
    var category: String = ""
    var speakingOrder: [UUID] = []
    var speakerIndex: Int = 0
    var lastVotes: [String: String] = [:]   // voterID → targetID (결과 공개 시)
    var accusedID: UUID?                    // 최다 득표자
    var liarID: UUID?                       // 게임 종료 시 공개
    var secretWord: String?                 // 게임 종료 시 공개
    var liarGuess: String?                  // 라이어가 추측한 단어
    var liarWins: Bool?
    var winReason: String?

    // 단계 타이머 (호스트 기준)
    var phaseSeconds: Int?
    var phaseStartedAt: Date = Date()

    var currentSpeakerID: UUID? {
        speakingOrder.indices.contains(speakerIndex) ? speakingOrder[speakerIndex] : nil
    }

    func player(_ id: UUID) -> PlayerPublic? { players.first { $0.id == id } }
    var disconnectedPlayers: [PlayerPublic] { players.filter { !$0.isConnected } }
}

// MARK: - 비공개 정보 (개별 전송)

struct LiarPrivateInfo: Codable, Equatable {
    var isLiar: Bool
    var word: String?             // 시민에게만
    var guessChoices: [String]?   // 라이어 추측 단계에서만
}

// MARK: - 클라이언트 → 호스트 액션

enum LiarAction: Codable {
    case startGame
    case confirmWord
    case finishSpeech
    case vote(targetID: UUID)
    case guessWord(String)
    case playAgain
    case abortToLobby
}

// MARK: - 규칙 / 단어 은행

enum LiarRules {
    static let playerRange = 3...15
    static let guessChoiceCount = 12

    static func phaseSeconds(for phase: LiarPhase) -> Int? {
        switch phase {
        case .wordReveal: return 30
        case .describing: return 30    // 발언자 1명당 (발언자가 바뀌면 리셋)
        case .voting:     return 45
        case .liarGuess:  return 60
        case .lobby, .gameOver: return nil
        }
    }

    /// 카테고리 → 단어 목록 (라이어의 추측 후보도 여기서 뽑는다)
    static let wordBank: [String: [String]] = [
        "음식": ["김치찌개", "삼겹살", "떡볶이", "치킨", "피자", "초밥", "라면", "비빔밥",
               "냉면", "갈비탕", "파스타", "햄버거", "김밥", "순대", "족발", "샐러드"],
        "동물": ["코끼리", "기린", "펭귄", "호랑이", "판다", "고슴도치", "캥거루", "부엉이",
               "돌고래", "문어", "다람쥐", "악어", "낙타", "수달", "앵무새", "두더지"],
        "장소": ["놀이공원", "도서관", "찜질방", "영화관", "편의점", "지하철역", "미용실", "병원",
               "학교", "캠핑장", "수영장", "공항", "시장", "카페", "노래방", "헬스장"],
        "직업": ["소방관", "의사", "요리사", "프로그래머", "유튜버", "선생님", "경찰관", "농부",
               "파일럿", "미용사", "가수", "운동선수", "사진작가", "변호사", "어부", "바리스타"],
        "물건": ["우산", "선풍기", "냉장고", "칫솔", "베개", "리모컨", "텀블러", "이어폰",
               "가위", "담요", "거울", "시계", "충전기", "슬리퍼", "마스크", "지갑"],
        "스포츠": ["축구", "야구", "농구", "배드민턴", "수영", "볼링", "태권도", "골프",
                "탁구", "스키", "클라이밍", "요가", "복싱", "양궁", "펜싱", "마라톤"],
    ]

    /// 무작위 카테고리와 제시어를 뽑는다.
    static func drawWord() -> (category: String, word: String) {
        let category = wordBank.keys.randomElement() ?? "음식"
        let word = wordBank[category]?.randomElement() ?? "김치찌개"
        return (category, word)
    }

    /// 라이어에게 보여줄 추측 후보 (정답 포함, 같은 카테고리에서)
    static func guessChoices(category: String, answer: String) -> [String] {
        var pool = (wordBank[category] ?? []).filter { $0 != answer }.shuffled()
        pool = Array(pool.prefix(guessChoiceCount - 1))
        pool.append(answer)
        return pool.shuffled()
    }
}
