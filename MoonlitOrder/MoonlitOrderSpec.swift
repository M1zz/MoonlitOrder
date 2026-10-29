import Foundation
import LeeoKit

enum MoonlitOrderSpec: LeeoAppSpec {
    static let appName = "달빛 오락실"
    static let developerEmail = "mizzking75@gmail.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.FeedbackHub", appIdentifier: "com.example.MoonlitOrder")
    // docs/privacy.html · docs/index.html(지원) 을 GitHub Pages 로 내보내는 주소.
    static let legal = LeeoLegalConfig(
        privacyURL: URL(string: "https://m1zz.github.io/MoonlitOrder/privacy.html")!,
        supportURL: URL(string: "https://m1zz.github.io/MoonlitOrder/")!)
    /// App Store 숫자 ID — 설정의 친구에게 소개하기·리뷰 남기기 링크가 쓴다.
    static let appStoreID: String? = "6790137862"
    static let monetization = LeeoMonetization.free
    // 익명 사용 통계 → FeedbackHub. 없으면 bootstrap 이 스냅샷·app_open 을 건너뛴다.
    static let analytics: any LeeoAnalytics = LeeoUsageAnalytics(spec: MoonlitOrderSpec.self)
}

extension MoonlitOrderSpec {
    /// 개발자 응원하기(팁). 무료 앱이라 LeeoStore 없이 혼자 돈다 — 앱을 열 때 `startStandalone()` 을 한 번 부른다.
    /// 상품이 App Store 에 없으면 설정 줄도, 부탁 카드도 서지 않는다.
    @MainActor static let tipJar = LeeoTipJar(config: LeeoTipJarConfig(productIDs: [
        "com.example.MoonlitOrder.tip.small",
        "com.example.MoonlitOrder.tip.medium",
        "com.example.MoonlitOrder.tip.large",
    ]))
}
