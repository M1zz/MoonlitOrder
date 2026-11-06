import Foundation
import LeeoKit

enum MoonlitOrderSpec: LeeoAppSpec {
    static let appName = "달빛 오락실"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.FeedbackHub", appIdentifier: "com.example.MoonlitOrder")
    // docs/privacy.html · docs/index.html(지원) 을 GitHub Pages 로 내보내는 주소.
    static let legal = LeeoLegalConfig(
        privacyURL: URL(string: "https://m1zz.github.io/MoonlitOrder/privacy.html")!,
        supportURL: URL(string: "https://m1zz.github.io/MoonlitOrder/")!)
    /// App Store 숫자 ID — 설정의 친구에게 소개하기·리뷰 남기기 링크가 쓴다.
    static let appStoreID: String? = "6790137862"
    /// **라이어 게임 · 달빛 화실은 무료, 정체 추리 두 게임(달빛 결사 · 달 없는 밤)은 방장만 Pro.**
    /// 참가자는 어떤 게임이든 무료다. 상품 · 권한 정책은 `MoonlitPro.swift`.
    static let monetization = LeeoMonetization.freemiumSubscription(
        LeeoSubscriptionConfig(
            productIDs: MoonlitProduct.all,
            // 자체 약관이 없으므로 애플 표준 사용권 계약(EULA)을 건다. 구독을 파는 앱의 심사 필수 항목이다.
            termsURL: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!,
            // 잠기는 것은 이 두 게임의 '방 만들기' 뿐이다 (→ GameKind.needsProToHost).
            gate: LeeoGatePolicy(proOnly: [GameViewModel.GameKind.moonlit.hostGateKey,
                                           GameViewModel.GameKind.wolf.hostGateKey]),
            // 개발자 응원 팁. 아무것도 열지 않는다 — LeeoStore 가 상품 · 결제 리스너를 함께 맡는다.
            tipJar: LeeoTipJarConfig(productIDs: MoonlitProduct.tips)))
    // 익명 사용 통계 → FeedbackHub. 없으면 bootstrap 이 스냅샷·app_open 을 건너뛴다.
    static let analytics: any LeeoAnalytics = LeeoUsageAnalytics(spec: MoonlitOrderSpec.self)
}

extension MoonlitOrderSpec {
    /// 개발자 응원하기(팁). 계약의 `tipJar` 로 LeeoStore 가 만든 것이다 (상품이 App Store 에 없으면 설정 줄도, 부탁 카드도 서지 않는다).
    @MainActor static var tipJar: LeeoTipJar { MoonlitPro.shared.store.tipJar! }
}
