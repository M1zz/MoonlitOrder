//
//  MoonlitPro.swift
//  MoonlitOrder
//
//  달빛 오락실 Pro — **방장 한 명이 정체 추리 게임 두 개(달빛 결사 · 달 없는 밤)의 방을 여는 권한**.
//
//   · 무료: 라이어 게임 · 달빛 화실 방 만들기, 남의 방 참가(네 게임 모두), 봇과 연습, 진행자 도구.
//   · Pro: 무료의 모든 것 + 달빛 결사 · 달 없는 밤 방 만들기 + 앞으로 더해지는 게임.
//   · 참가자는 어떤 게임이든 무료다. 잠금은 `GameViewModel.hostGame(kind:)` 한 곳뿐이다.
//
//  속은 전부 `LeeoStore`다(상품 로드 · 구매 · 복원 · 다른 기기 · 가족 공유 · 환불 · 만료 · 팁).
//  이 파일은 상품 ID 와 이 앱의 정책 세 가지만 둔다 —
//   ① 결제를 들이기 전에 받은 사람은 평생 Pro (`AppTransaction.originalAppVersion`),
//   ② App Store 에서 Pro 상품을 한 번도 못 본 기기는 잠그지 않는다(상품이 서기 전에 빌드가 나가도 막히는 사람이 없게),
//   ③ 구독 중인 사람에게 6개월째 · 갱신 7일 전 구독 졸업 평생가(`LeeoGraduation`).
//

import Foundation
import Combine
import StoreKit
import LeeoKit

// MARK: - 상품

/// ⚠️ App Store Connect · `Products.storekit` 과 글자 하나까지 같아야 한다.
///    주 · 월 · 연 구독은 구독 그룹 하나("달빛 오락실 Pro")에 둔다.
enum MoonlitProduct {
    private static let prefix = "com.example.MoonlitOrder"

    static let weekly   = prefix + ".pro.weekly"
    static let monthly  = prefix + ".pro.monthly"
    /// 처음 구독하는 사람은 첫 해 반값(App Store 첫 구독 할인).
    static let yearly   = prefix + ".pro.yearly"
    /// Pro 평생 (비소모성).
    static let lifetime = prefix + ".pro"
    /// 구독 졸업 Pro 평생 (비소모성) — 구독 중인 사람에게만 보인다.
    static let graduate = prefix + ".pro.graduate"

    /// 개발자 응원 팁. **아무것도 열지 않는다** — `all` 에 넣지 않는다.
    static let tips = [prefix + ".tip.small", prefix + ".tip.medium", prefix + ".tip.large"]

    /// 페이월이 불러오고 Pro 로 인정하는 상품.
    static let all = [yearly, lifetime, monthly, weekly, graduate]
    static let subscriptions: Set<String> = [weekly, monthly, yearly]
    static let lifetimes: Set<String> = [lifetime, graduate]

    /// 결제를 들이기 직전에 나간 마지막 빌드(1.0.3 빌드 5). 이 빌드 이하로 처음 받은 사람은 평생 Pro 다.
    /// ⚠️ 한 번 나가면 바꾸지 않는다. 올리면 그 사이에 받은 사람에게 공짜 Pro 가 생기고, 내리면 쓰던 사람이 잠긴다.
    static let lastFreeBuild = "5"

    /// 이 빌드(`originalAppVersion` = 처음 받은 빌드 번호)로 처음 받은 사람이 결제 전부터 쓰던 사람인가.
    static func installedBeforePaywall(originalBuild: String) -> Bool {
        guard !originalBuild.isEmpty else { return false }
        return originalBuild.compare(lastFreeBuild, options: .numeric) != .orderedDescending
    }
}

extension GameViewModel.GameKind {
    /// 계약(`MoonlitOrderSpec.gate`)에 적는 열쇠말.
    var hostGateKey: String { "host.\(rawValue)" }

    /// 방을 열 때 Pro 가 있어야 하는 게임인가. 참가 · 연습은 묻지 않는다.
    var needsProToHost: Bool { MoonlitOrderSpec.gate.proOnly.contains(hostGateKey) }
}

// MARK: - 권한

@MainActor
final class MoonlitPro: ObservableObject {
    static let shared = MoonlitPro()

    let store: LeeoStore

    /// 지금 살아 있는 구독. 있으면 설정에 '구독 관리 열기' 가 서고 졸업 제안의 대상이 된다.
    @Published private(set) var subscription: LeeoGraduation.Subscription?

    private var observations: Set<AnyCancellable> = []
    private static let sellingKey = "moonorder.pro.selling"

    private init() {
        guard let config = MoonlitOrderSpec.paywall else {
            preconditionFailure("계약에 페이월이 없다. MoonlitOrderSpec.monetization 을 확인할 것")
        }
        store = LeeoStore(config: config, unlockOverride: {
            #if DEBUG
            // 시연 · 스크린샷 실행 인자는 달빛 결사 방을 곧바로 연다.
            if RootView.isScriptedLaunch { return true }
            #endif
            return nil
        }, grandfather: {
            guard case .verified(let app)? = try? await AppTransaction.shared,
                  app.environment == .production else { return false }
            return MoonlitProduct.installedBeforePaywall(originalBuild: app.originalAppVersion)
        })

        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observations)
        // Pro 상품을 한 번이라도 불러왔으면 그 뒤로는 판다고 본다(네트워크 오류로 잠깐 못 불러와도 다시 연다고 하지 않는다).
        store.$products
            .filter { !$0.isEmpty }
            .sink { _ in UserDefaults.standard.set(true, forKey: Self.sellingKey) }
            .store(in: &observations)
    }

    var hasPro: Bool { store.hasPro }

    /// 결제를 들이기 전부터 쓰던 사람이라 Pro 인가.
    var isGrandfathered: Bool { store.isGrandfathered }

    /// 이 기기가 App Store 에서 Pro 상품을 본 적이 있는가. 없으면 아직 팔지 않는 것이다 — 잠그지 않는다.
    var isSelling: Bool { !store.products.isEmpty || UserDefaults.standard.bool(forKey: Self.sellingKey) }

    /// 이 게임의 방을 내가 열 수 있는가.
    func canHost(_ kind: GameViewModel.GameKind) -> Bool {
        !kind.needsProToHost || hasPro || !isSelling
    }

    /// Pro 를 권할 사람인가 (팔고 있고, 아직 없다).
    var shouldOfferPro: Bool { isSelling && !hasPro }

    /// 끝나지 않는 Pro 를 가졌는가 (평생 · 졸업 · 결제 전부터 쓰던 사람).
    var ownsLifetime: Bool {
        isGrandfathered || !store.purchasedProductIDs.isDisjoint(with: MoonlitProduct.lifetimes)
    }

    func product(_ id: String) -> Product? { store.products.first { $0.id == id } }

    // MARK: - 맞추기

    /// 영수증 · 상품 · 구독을 다시 읽는다. 앱을 켤 때 부른다.
    func refresh() async {
        await store.refreshEntitlements()
        await store.loadProducts()
        await refreshSubscription()
    }

    func refreshSubscription() async {
        subscription = await LeeoGraduation.currentSubscription(among: MoonlitProduct.subscriptions)
    }

    /// 구독 졸업 평생가를 보일 때인가 (6개월째 · 갱신 7일 전, 창마다 한 번).
    var graduationIsDue: Bool {
        guard let subscription, !ownsLifetime, product(MoonlitProduct.graduate) != nil else { return false }
        return LeeoGraduation.isDue(subscription, lastOffered: LeeoGraduation.lastOffered())
    }
}
