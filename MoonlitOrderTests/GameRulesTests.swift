import XCTest
@testable import MoonlitOrder

/// 달빛 결사의 규칙 테이블 — 인원수별 진영 · 원정대 크기 · 실패 카드 수.
final class GameRulesTests: XCTestCase {

    func testRoleCompositionForEveryPlayerCount() {
        for count in GameRules.playerRange {
            let roles = GameRules.makeRoles(for: count)
            XCTAssertEqual(roles.count, count, "\(count)명")
            XCTAssertEqual(roles.filter { $0 == .assassin }.count, 1, "\(count)명: 암살자는 한 명")
            XCTAssertEqual(roles.filter { $0 == .seer }.count, 1, "\(count)명: 예언자는 한 명")
            XCTAssertEqual(roles.filter { $0.team == .shadow }.count,
                           GameRules.shadowCount(for: count), "\(count)명: 그림자 수")
            // 선한 진영이 언제나 다수여야 게임이 성립한다
            XCTAssertGreaterThan(roles.filter { $0.team == .moonlit }.count, count / 2, "\(count)명")
        }
    }

    func testShadowCountBrackets() {
        XCTAssertEqual(GameRules.shadowCount(for: 5), 2)
        XCTAssertEqual(GameRules.shadowCount(for: 6), 2)
        XCTAssertEqual(GameRules.shadowCount(for: 7), 3)
        XCTAssertEqual(GameRules.shadowCount(for: 9), 3)
        XCTAssertEqual(GameRules.shadowCount(for: 10), 4)
        XCTAssertEqual(GameRules.shadowCount(for: 12), 4)
        XCTAssertEqual(GameRules.shadowCount(for: 13), 5)
        XCTAssertEqual(GameRules.shadowCount(for: 15), 5)
    }

    func testTeamSizesFitThePlayers() {
        for count in GameRules.playerRange {
            let sizes = GameRules.teamSizes(for: count)
            XCTAssertEqual(sizes.count, GameRules.missionCount, "\(count)명")
            XCTAssertTrue(sizes.allSatisfy { $0 >= 2 && $0 < count }, "\(count)명: \(sizes)")
        }
    }

    func testTwoFailCardsNeededOnBigTables() {
        XCTAssertEqual(GameRules.failsRequired(for: 5), [1, 1, 1, 1, 1])
        XCTAssertEqual(GameRules.failsRequired(for: 6), [1, 1, 1, 1, 1])
        XCTAssertEqual(GameRules.failsRequired(for: 7), [1, 1, 1, 2, 1])
        XCTAssertEqual(GameRules.failsRequired(for: 11), [1, 1, 1, 2, 2])
    }

    func testOnlyActionPhasesHaveTimers() {
        XCTAssertNil(GameRules.phaseSeconds(for: .lobby))
        XCTAssertNil(GameRules.phaseSeconds(for: .voteResult))
        XCTAssertNil(GameRules.phaseSeconds(for: .missionResult))
        XCTAssertNil(GameRules.phaseSeconds(for: .gameOver))
        XCTAssertNotNil(GameRules.phaseSeconds(for: .teamVoting))
        XCTAssertNotNil(GameRules.phaseSeconds(for: .mission))
    }
}
