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
        String(localized: "음식"): [String(localized: "김치찌개"), String(localized: "삼겹살"), String(localized: "떡볶이"), String(localized: "치킨"), String(localized: "피자"), String(localized: "초밥"), String(localized: "라면"), String(localized: "비빔밥"),
               String(localized: "냉면"), String(localized: "갈비탕"), String(localized: "파스타"), String(localized: "햄버거"), String(localized: "김밥"), String(localized: "순대"), String(localized: "족발"), String(localized: "샐러드")],
        String(localized: "동물"): [String(localized: "코끼리"), String(localized: "기린"), String(localized: "펭귄"), String(localized: "호랑이"), String(localized: "판다"), String(localized: "고슴도치"), String(localized: "캥거루"), String(localized: "부엉이"),
               String(localized: "돌고래"), String(localized: "문어"), String(localized: "다람쥐"), String(localized: "악어"), String(localized: "낙타"), String(localized: "수달"), String(localized: "앵무새"), String(localized: "두더지")],
        String(localized: "장소"): [String(localized: "놀이공원"), String(localized: "도서관"), String(localized: "찜질방"), String(localized: "영화관"), String(localized: "편의점"), String(localized: "지하철역"), String(localized: "미용실"), String(localized: "병원"),
               String(localized: "학교"), String(localized: "캠핑장"), String(localized: "수영장"), String(localized: "공항"), String(localized: "시장"), String(localized: "카페"), String(localized: "노래방"), String(localized: "헬스장")],
        String(localized: "직업"): [String(localized: "소방관"), String(localized: "의사"), String(localized: "요리사"), String(localized: "프로그래머"), String(localized: "유튜버"), String(localized: "선생님"), String(localized: "경찰관"), String(localized: "농부"),
               String(localized: "파일럿"), String(localized: "미용사"), String(localized: "가수"), String(localized: "운동선수"), String(localized: "사진작가"), String(localized: "변호사"), String(localized: "어부"), String(localized: "바리스타")],
        String(localized: "물건"): [String(localized: "우산"), String(localized: "선풍기"), String(localized: "냉장고"), String(localized: "칫솔"), String(localized: "베개"), String(localized: "리모컨"), String(localized: "텀블러"), String(localized: "이어폰"),
               String(localized: "가위"), String(localized: "담요"), String(localized: "거울"), String(localized: "시계"), String(localized: "충전기"), String(localized: "슬리퍼"), String(localized: "마스크"), String(localized: "지갑")],
        String(localized: "스포츠"): [String(localized: "축구"), String(localized: "야구"), String(localized: "농구"), String(localized: "배드민턴"), String(localized: "수영"), String(localized: "볼링"), String(localized: "태권도"), String(localized: "골프"),
                String(localized: "탁구"), String(localized: "스키"), String(localized: "클라이밍"), String(localized: "요가"), String(localized: "복싱"), String(localized: "양궁"), String(localized: "펜싱"), String(localized: "마라톤")],
    ]

    /// 무작위 카테고리와 제시어를 뽑는다.
    static func drawWord() -> (category: String, word: String) {
        let category = wordBank.keys.randomElement() ?? String(localized: "음식")
        let word = wordBank[category]?.randomElement() ?? String(localized: "김치찌개")
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
