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
    static let monetization = LeeoMonetization.free
    // 익명 사용 통계 → FeedbackHub. 없으면 bootstrap 이 스냅샷·app_open 을 건너뛴다.
    static let analytics: any LeeoAnalytics = LeeoUsageAnalytics(spec: MoonlitOrderSpec.self)
}
