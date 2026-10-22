import XCTest
@testable import MoonlitOrder

/// 호스트 엔진이 판정하는 달빛 결사 한 판의 흐름.
final class GameEngineTests: XCTestCase {

    private var engine: GameEngine!
    private var ids: [UUID] = []
    private var roles: [UUID: Role] = [:]
    private var host: UUID { ids[0] }

    override func setUp() {
        super.setUp()
        engine = GameEngine()
        roles = [:]
        engine.onPrivateInfo = { [unowned self] id, info in self.roles[id] = info.role }
    }

    /// count 명이 들어와 역할 확인까지 마친 상태로 만든다.
    private func startGame(players count: Int) {
        ids = (0..<count).map { _ in UUID() }
        for (i, id) in ids.enumerated() {
            engine.join(playerID: id, name: "P\(i)", isHost: i == 0)
        }
        engine.handle(.startGame(playerID: host))
        XCTAssertEqual(engine.phase, .roleReveal)
        ids.forEach { engine.handle(.confirmRole(playerID: $0)) }
        XCTAssertEqual(engine.phase, .teamProposal)
    }

    private var state: PublicGameState { engine.publicState() }
    private var moonlitIDs: [UUID] { ids.filter { roles[$0]?.team == .moonlit } }
    private var shadowIDs: [UUID] { ids.filter { roles[$0]?.team == .shadow } }

    private func propose(_ members: [UUID]) {
        engine.handle(.proposeTeam(playerID: state.leaderID!, members: members))
    }

    private func voteAll(approve: Bool) {
        ids.forEach { engine.handle(.teamVote(playerID: $0, approve: approve)) }
    }

    /// 원정대를 꾸려 가결시키고, 대원 전원이 success 카드를 낸다.
    private func playMission(team: [UUID], success: Bool) {
        propose(team)
        voteAll(approve: true)
        engine.handle(.hostContinue(playerID: host))
        XCTAssertEqual(engine.phase, .mission)
        team.forEach { engine.handle(.missionAction(playerID: $0, success: success)) }
        XCTAssertEqual(engine.phase, .missionResult)
        engine.handle(.hostContinue(playerID: host))
    }

    // MARK: - 참가

    func testDuplicateNamesAreMadeUnique() {
        engine.join(playerID: UUID(), name: "달님", isHost: true)
        engine.join(playerID: UUID(), name: "달님", isHost: false)
        engine.join(playerID: UUID(), name: "  ", isHost: false)
        XCTAssertEqual(state.players.map(\.name), ["달님", "달님 2", String(localized: "플레이어")])
    }

    func testRejoinKeepsSeatAndLateJoinIsRejected() {
        startGame(players: 5)
        XCTAssertEqual(engine.join(playerID: ids[2], name: "P2", isHost: false), .rejoined)
        XCTAssertEqual(engine.join(playerID: UUID(), name: "늦은 사람", isHost: false), .rejectedInProgress)
        XCTAssertEqual(state.players.count, 5)
    }

    func testOnlyHostCanStartAndNeedsFivePlayers() {
        ids = (0..<4).map { _ in UUID() }
        for (i, id) in ids.enumerated() { engine.join(playerID: id, name: "P\(i)", isHost: i == 0) }
        engine.handle(.startGame(playerID: host))
        XCTAssertEqual(engine.phase, .lobby, "4명으로는 시작하지 않는다")

        let fifth = UUID()
        engine.join(playerID: fifth, name: "P4", isHost: false)
        engine.handle(.startGame(playerID: fifth))
        XCTAssertEqual(engine.phase, .lobby, "호스트가 아니면 시작할 수 없다")
        engine.handle(.startGame(playerID: host))
        XCTAssertEqual(engine.phase, .roleReveal)
    }

    // MARK: - 투표

    func testWrongTeamSizeIsIgnored() {
        startGame(players: 5)
        propose(Array(ids.prefix(3)))   // 1라운드는 2명
        XCTAssertEqual(engine.phase, .teamProposal)
        propose(Array(ids.prefix(2)))
        XCTAssertEqual(engine.phase, .teamVoting)
    }

    func testTiedVoteIsRejected() {
        startGame(players: 6)
        propose(Array(ids.prefix(2)))
        for (i, id) in ids.enumerated() { engine.handle(.teamVote(playerID: id, approve: i < 3)) }
        XCTAssertEqual(engine.phase, .voteResult)
        XCTAssertFalse(state.lastVoteApproved, "3:3 동수는 부결")
        XCTAssertEqual(state.voteTrack, 1)
    }

    func testFiveRejectionsInARowGiveShadowTheWin() {
        startGame(players: 5)
        for _ in 0..<GameRules.maxRejections {
            propose(Array(ids.prefix(2)))
            voteAll(approve: false)
            engine.handle(.hostContinue(playerID: host))
        }
        XCTAssertEqual(engine.phase, .gameOver)
        XCTAssertEqual(state.winner, .shadow)
    }

    // MARK: - 미션 · 승패

    func testMoonlitPlayersCannotPlayFailCards() {
        startGame(players: 5)
        let team = Array(moonlitIDs.prefix(2))
        propose(team)
        voteAll(approve: true)
        engine.handle(.hostContinue(playerID: host))
        team.forEach { engine.handle(.missionAction(playerID: $0, success: false)) }
        XCTAssertEqual(state.missionHistory.last?.succeeded, true)
        XCTAssertEqual(state.missionHistory.last?.failCount, 0)
    }

    func testThreeFailedMissionsGiveShadowTheWin() {
        startGame(players: 5)
        // 1·3라운드 2명, 2라운드 3명 — 그림자 2명을 꼭 넣는다
        let shadows = shadowIDs
        let filler = moonlitIDs
        playMission(team: shadows, success: false)
        playMission(team: shadows + [filler[0]], success: false)
        XCTAssertNotEqual(engine.phase, .gameOver)
        playMission(team: shadows, success: false)
        XCTAssertEqual(engine.phase, .gameOver)
        XCTAssertEqual(state.winner, .shadow)
    }

    /// 달빛 결사만으로 원정 3회를 성공시켜 암살 단계로 간다 (5인: 결사 3명, 원정대 2·3·2명).
    private func reachAssassination() -> (assassin: UUID, seer: UUID, knight: UUID) {
        startGame(players: 5)
        let good = moonlitIDs
        playMission(team: Array(good.prefix(2)), success: true)
        playMission(team: good, success: true)
        playMission(team: Array(good.prefix(2)), success: true)
        XCTAssertEqual(engine.phase, .assassination)
        let assassin = ids.first { roles[$0] == .assassin }!
        let seer = ids.first { roles[$0] == .seer }!
        let knight = ids.first { roles[$0] == .knight }!
        return (assassin, seer, knight)
    }

    func testAssassinFindingSeerStealsTheWin() {
        let p = reachAssassination()
        engine.handle(.assassinate(playerID: p.assassin, targetID: p.seer))
        XCTAssertEqual(engine.phase, .gameOver)
        XCTAssertEqual(state.winner, .shadow)
        XCTAssertEqual(state.revealedRoles?.count, 5, "끝나면 모든 역할을 공개한다")
    }

    func testAssassinMissingSeerGivesMoonlitTheWin() {
        let p = reachAssassination()
        engine.handle(.assassinate(playerID: p.assassin, targetID: p.knight))
        XCTAssertEqual(state.winner, .moonlit)
    }

    func testOnlyAssassinCanAssassinate() {
        let p = reachAssassination()
        engine.handle(.assassinate(playerID: p.knight, targetID: p.seer))
        XCTAssertEqual(engine.phase, .assassination, "암살자가 아니면 무시")
    }
}
