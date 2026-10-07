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
}
