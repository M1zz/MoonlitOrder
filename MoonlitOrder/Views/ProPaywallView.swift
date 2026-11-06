//
//  ProPaywallView.swift
//  MoonlitOrder
//
//  무료 · Pro 두 칸 카드와 비교표. 연 구독을 먼저 고르고, 평생은 옆에, 주 · 월은 펼치면 보인다.
//
//  뜨는 곳: 게임 고르기에서 달빛 결사 · 달 없는 밤의 방 만들기 · 단축어로 잠긴 게임 열기(RootView) ·
//          두 게임의 연습을 마친 결과 화면 · 무료 게임을 세 판 호스트한 뒤 결과 화면(→ ProNudgeCard) · 설정.
//
//  ⚠️ 불러온 상품만 단추로 선다. App Store 에 아직 없는 상품은 보이지 않는다.
//  ⚠️ 결제는 `@Environment(\.purchase)` 로 한다(아이패드에서 결제 시트가 엉뚱한 창에 뜨지 않게).
//

import SwiftUI
import StoreKit
import LeeoKit

struct ProPaywallView: View {
    /// 방을 열려다 막힌 게임. 있으면 맨 위에 그 까닭을 한 줄로 말한다.
    var lockedKind: GameViewModel.GameKind? = nil
    /// 설정의 '평생으로 바꾸기' 처럼 평생을 먼저 골라 둘 때.
    var startsWithLifetime = false

    @ObservedObject private var pro = MoonlitPro.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @State private var selectedID = MoonlitProduct.yearly
    @State private var showsShortTerms = false
    @State private var introEligible = false
    @State private var restoreFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if pro.hasPro {
                    ownedCard
                } else {
                    freeCard
                    proCard
                }
                comparison
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(14)
            }
            .accessibilityLabel("닫기")
        }
        .preferredColorScheme(.dark)
        .task {
            if startsWithLifetime { selectedID = MoonlitProduct.lifetime }
            await pro.store.loadProducts()
            introEligible = await pro.product(MoonlitProduct.yearly)?.subscription?.isEligibleForIntroOffer ?? false
        }
        .onChange(of: pro.hasPro) { _, has in
            if has { Task { await pro.refreshSubscription() } }
        }
        .alert("이 Apple 계정에서 구매한 기록을 찾지 못했어요.", isPresented: $restoreFailed) {
            Button("확인", role: .cancel) {}
        }
    }

    // MARK: - 머리

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 44))
                .foregroundColor(Theme.gold)
                .accessibilityHidden(true)
            Text("달빛 오락실 Pro")
                .font(.title.weight(.heavy))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("방장 한 명이면 모두가 함께 놀아요. 연 구독이나 평생 중에 고르세요.")
                .font(.body)
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let lockedKind, !pro.hasPro {
                Text("\(lockedKind.displayName) 방은 Pro 방장이 열어요. 참가는 언제나 무료예요.")
                    .font(.body.weight(.semibold))
                    .foregroundColor(Theme.gold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
    }

    // MARK: - 칸 카드

    private var freeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("무료")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Spacer()
                Text("지금 쓰는 중")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.6))
            }
            Text("라이어 게임과 달빛 화실로 오늘 밤 바로 놀아 보세요. 남의 방에는 어떤 게임이든 무료로.")
                .font(.body)
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private var proCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Pro")
                .font(.title3.bold())
                .foregroundColor(Theme.gold)
            Text("정체 추리 게임 두 개를 내가 방장으로 열어요.")
                .font(.body)
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if pro.store.products.isEmpty {
                loadingState
            } else {
                terms
                buyButton
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.gold.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1.5))
        )
    }

    private var ownedCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundColor(Theme.gold)
                .accessibilityHidden(true)
            Text("Pro를 쓰고 있어요. 고마워요!")
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            if pro.isGrandfathered {
                Text("처음부터 함께해 줘서 고마워요. 평생 Pro예요.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var loadingState: some View {
        if pro.store.isLoadingProducts {
            ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 44)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let error = pro.store.lastError {
                    Text(error)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("다시 불러오기") { Task { await pro.store.loadProducts() } }
                    .font(.body.weight(.semibold))
                    .foregroundColor(Theme.gold)
                    .frame(minHeight: 44)
            }
        }
    }

    // MARK: - 기간 고르기

    @ViewBuilder
    private var terms: some View {
        VStack(spacing: 8) {
            termRow(MoonlitProduct.yearly, title: LeeoLadderText.yearly, format: LeeoLadderText.perYearFormat,
                    note: introNote)
            termRow(MoonlitProduct.lifetime, title: LeeoLadderText.lifetime, format: "%@", note: lifetimeNote)
            if showsShortTerms {
                termRow(MoonlitProduct.monthly, title: String(localized: "월 구독"),
                        format: String(localized: "%@ / 월", comment: "Paywall: monthly price. %@ = price"), note: nil)
                termRow(MoonlitProduct.weekly, title: String(localized: "주 구독"),
                        format: String(localized: "%@ / 주", comment: "Paywall: weekly price. %@ = price"), note: nil)
            } else if pro.product(MoonlitProduct.monthly) != nil || pro.product(MoonlitProduct.weekly) != nil {
                Button {
                    withAnimation { showsShortTerms = true }
                } label: {
                    Label("주 · 월 구독도 보기", systemImage: "chevron.down")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.75))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
    }

    /// 처음 구독하는 사람에게만 보이는 첫 해 값.
    private var introNote: String? {
        guard introEligible, let offer = pro.product(MoonlitProduct.yearly)?.subscription?.introductoryOffer,
              offer.paymentMode == .payUpFront || offer.paymentMode == .payAsYouGo else { return nil }
        return String(format: LeeoLadderText.introFormat, offer.displayPrice)
    }

    /// 평생이 연 구독 몇 년치인가.
    private var lifetimeNote: String? {
        guard let yearly = pro.product(MoonlitProduct.yearly)?.price,
              let lifetime = pro.product(MoonlitProduct.lifetime)?.price, yearly > 0 else { return nil }
        let years = Int(NSDecimalNumber(decimal: lifetime / yearly).doubleValue.rounded(.down))
        return years >= 2 ? String(format: LeeoLadderText.lifetimeWorthFormat, years) : nil
    }

    @ViewBuilder
    private func termRow(_ id: String, title: String, format: String, note: String?) -> some View {
        if let product = pro.product(id) {
            let selected = selectedID == id
            Button {
                selectedID = id
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(selected ? Theme.gold : .white.opacity(0.5))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                        if let note {
                            Text(note)
                                .font(.body)
                                .foregroundColor(Theme.gold)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(String(format: format, product.displayPrice))
                        .font(.body)
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .multilineTextAlignment(.trailing)
                }
                .padding(12)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? Theme.gold.opacity(0.14) : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Theme.gold : .clear, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        }
    }

    private var buyButton: some View {
        let product = pro.product(selectedID) ?? pro.product(MoonlitProduct.yearly) ?? pro.store.products.first
        let busy = pro.store.purchasingProductID != nil
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                guard let product else { return }
                Task { await buy(product) }
            } label: {
                if busy {
                    ProgressView().tint(.black)
                } else {
                    Text("Pro 열기")
                }
            }
            .buttonStyle(BigButtonStyle())
            .disabled(product == nil || busy)

            if let error = pro.store.lastError {
                Text(error)
                    .font(.body)
                    .foregroundColor(Theme.shadow)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func buy(_ product: Product) async {
        let bought = await pro.store.purchase(product) { try await purchase($0) }
        if bought {
            await pro.refreshSubscription()
            dismiss()
        }
    }

    // MARK: - 비교표

    private var comparison: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 12) {
            GridRow {
                Text("기능").gridColumnAlignment(.leading)
                Text("무료").gridColumnAlignment(.center)
                Text(verbatim: "Pro").gridColumnAlignment(.center)
            }
            .font(.body.bold())
            .foregroundColor(.white.opacity(0.7))
            .accessibilityHidden(true)
            Divider().overlay(Color.white.opacity(0.2)).gridCellColumns(3)
            row("라이어 게임 · 달빛 화실 방 만들기", free: true, pro: true)
            row("달빛 결사 · 달 없는 밤 방 만들기", free: false, pro: true)
            row("다른 사람 방에 참가", both: "네 게임 모두")
            row("봇과 연습", free: true, pro: true)
            row("끊겨도 이어서 · 진행자 도구", free: true, pro: true)
            row("새로 더해지는 게임", free: false, pro: true)
        }
        .padding(16)
        .cardStyle()
    }

    private func row(_ feature: LocalizedStringKey, free: Bool, pro: Bool) -> some View {
        GridRow {
            Text(feature)
                .font(.body)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            mark(free)
            mark(pro)
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ feature: LocalizedStringKey, both: LocalizedStringKey) -> some View {
        GridRow {
            Text(feature)
                .font(.body)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(both).font(.body).foregroundColor(.white.opacity(0.85)).multilineTextAlignment(.center)
            Text(both).font(.body).foregroundColor(.white.opacity(0.85)).multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private func mark(_ included: Bool) -> some View {
        Image(systemName: included ? "checkmark" : "minus")
            .font(.body.bold())
            .foregroundColor(included ? Theme.gold : .white.opacity(0.35))
            .frame(minWidth: 44)
            .accessibilityLabel(included ? Text("포함") : Text("없음"))
    }

    // MARK: - 아래

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await pro.store.restore()
                    await pro.refreshSubscription()
                    if !pro.hasPro { restoreFailed = true }
                }
            } label: {
                Text("구매 복원")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(minHeight: 44)
            }
            .disabled(pro.store.isRestoring)

            Text("구독은 기간이 끝나기 24시간 전까지 해지하지 않으면 같은 값으로 자동 갱신돼요. App Store 계정 설정에서 언제든 해지할 수 있어요. 평생은 한 번만 결제해요.")
                .font(.body)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 20) {
                if let terms = MoonlitOrderSpec.monetization.subscriptionTermsURL {
                    Link("이용약관", destination: terms)
                }
                Link("개인정보 처리방침", destination: MoonlitOrderSpec.legal.privacyURL)
            }
            .font(.body)
            .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - 결과 화면의 한 줄

/// 결과 화면에 서는 Pro 권유 카드. 모달이 아니다 — 결과 목록 안에 한 장.
struct ProNudgeCard: View {
    enum Moment {
        /// 달빛 결사 · 달 없는 밤 연습을 마쳤다.
        case practiceDone(GameViewModel.GameKind)
        /// 무료 게임을 세 판 넘게 방장으로 열었다.
        case hostedFreeGames
    }

    let moment: Moment
    @State private var showsPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(message)
                .font(.body)
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Button("Pro 알아보기") { showsPaywall = true }
                .font(.body.weight(.semibold))
                .foregroundColor(Theme.gold)
                .frame(minHeight: 44)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.gold.opacity(0.12)))
        .padding(.top, 8)
        .sheet(isPresented: $showsPaywall) {
            ProPaywallView(lockedKind: lockedKind)
        }
    }

    private var lockedKind: GameViewModel.GameKind? {
        if case .practiceDone(let kind) = moment { return kind }
        return nil
    }

    private var title: String {
        switch moment {
        case .practiceDone: return String(localized: "이제 친구들과 열어 보세요")
        case .hostedFreeGames: return String(localized: "다음 모임엔 정체 추리 게임도 열어 보세요")
        }
    }

    private var message: String {
        switch moment {
        case .practiceDone(let kind):
            return String(localized: "규칙을 다 익혔어요. 다음 모임에서 \(kind.displayName) 방을 내가 열어 보세요. 한 사람만 Pro면 모두가 함께해요.")
        case .hostedFreeGames:
            return String(localized: "달빛 결사와 달 없는 밤은 판이 길고 깊어요. 한 사람만 Pro면 모두가 함께해요.")
        }
    }
}

// MARK: - 설정 ▸ 구독 관리

struct ProSettingsSection: View {
    @ObservedObject private var pro = MoonlitPro.shared
    @State private var showsPaywall = false
    @State private var showsLifetimePaywall = false
    @State private var showsGraduation = false
    @State private var showsManage = false
    @State private var restoreFailed = false

    var body: some View {
        if pro.isSelling || pro.hasPro {
            Section {
                Button { showsPaywall = true } label: {
                    HStack {
                        Label("달빛 오락실 Pro", systemImage: "moon.stars.fill")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(pro.hasPro ? String(localized: "쓰는 중") : String(localized: "알아보기"))
                            .foregroundStyle(.secondary)
                    }
                }
                if pro.subscription != nil {
                    Button(LeeoLadderText.manageSubscription) { showsManage = true }
                }
                // 늘 보인다. 구독 중이면 졸업 평생가, 아니면 평생을 골라 둔 페이월.
                if !pro.ownsLifetime {
                    Button(LeeoLadderText.switchToLifetimeEntry) {
                        if pro.subscription != nil, pro.product(MoonlitProduct.graduate) != nil {
                            showsGraduation = true
                        } else {
                            showsLifetimePaywall = true
                        }
                    }
                }
                Button("구매 복원") {
                    Task {
                        await pro.store.restore()
                        await pro.refreshSubscription()
                        if !pro.hasPro { restoreFailed = true }
                    }
                }
                .disabled(pro.store.isRestoring)
            } header: {
                Text("구독 관리")
            }
            .sheet(isPresented: $showsPaywall) { ProPaywallView() }
            .sheet(isPresented: $showsLifetimePaywall) { ProPaywallView(startsWithLifetime: true) }
            .sheet(isPresented: $showsGraduation) { ProGraduationSheet() }
            .manageSubscriptionsSheet(isPresented: $showsManage)
            .alert("이 Apple 계정에서 구매한 기록을 찾지 못했어요.", isPresented: $restoreFailed) {
                Button("확인", role: .cancel) {}
            }
        }
    }
}

// MARK: - 구독 졸업

/// 구독 중인 사람에게 졸업 평생가. 사면 LeeoKit 화면이 구독 해지 화면으로 바로 안내한다.
struct ProGraduationSheet: View {
    @ObservedObject private var pro = MoonlitPro.shared

    var body: some View {
        LeeoGraduationOfferView(graduate: pro.product(MoonlitProduct.graduate)) {
            await pro.store.refreshEntitlements()
            await pro.refreshSubscription()
        }
        .leeoStyle(LeeoStyle(accent: Theme.gold))
        .preferredColorScheme(.dark)
    }
}
