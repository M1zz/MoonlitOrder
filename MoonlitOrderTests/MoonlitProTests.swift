import XCTest
@testable import MoonlitOrder

/// 달빛 오락실 Pro 의 규칙 — 무엇이 잠기고, 누가 처음부터 Pro 인가.
final class MoonlitProTests: XCTestCase {

    func testOnlyTheTwoHiddenRoleGamesNeedProToHost() {
        XCTAssertTrue(GameViewModel.GameKind.moonlit.needsProToHost)
        XCTAssertTrue(GameViewModel.GameKind.wolf.needsProToHost)
        XCTAssertFalse(GameViewModel.GameKind.liar.needsProToHost)
        XCTAssertFalse(GameViewModel.GameKind.sketch.needsProToHost)
    }

    func testPeopleWhoInstalledBeforeThePaywallKeepPro() {
        XCTAssertTrue(MoonlitProduct.installedBeforePaywall(originalBuild: "1"))
        XCTAssertTrue(MoonlitProduct.installedBeforePaywall(originalBuild: MoonlitProduct.lastFreeBuild))
        XCTAssertFalse(MoonlitProduct.installedBeforePaywall(originalBuild: "6"))
        XCTAssertFalse(MoonlitProduct.installedBeforePaywall(originalBuild: "12"))
        XCTAssertFalse(MoonlitProduct.installedBeforePaywall(originalBuild: ""))
    }

    func testTipsNeverUnlockPro() {
        XCTAssertTrue(Set(MoonlitProduct.tips).isDisjoint(with: MoonlitOrderSpec.paywall?.entitlementIDs ?? []))
        XCTAssertEqual(MoonlitOrderSpec.paywall?.entitlementIDs, Set(MoonlitProduct.all))
    }
}
