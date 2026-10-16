//
//  OnboardingView.swift
//  MoonlitOrder
//
//  첫 실행 안내 — 이 앱은 "근처 아이폰끼리, 인터넷 없이" 노는 앱이라 처음 연 사람이
//  ① 다 같이 앱을 깔아야 하고 ② 한 명이 방을 열어야 하며 ③ 로컬 네트워크 허용이 꼭 필요하다는
//  세 가지를 모르면 "방이 안 보여요"에서 막힌다. 그 세 가지만 짧게 알려 준다.
//

import SwiftUI

enum MoonlitOrderOnboarding {
    /// 첫 실행 안내를 봤는가. RootView 가 이 값으로 안내를 띄운다.
    static let hasSeenOnboardingKey = "hasSeenOnboarding"

    /// 안내가 생기기 전부터 쓰던 사람에게는 띄우지 않는다.
    /// 기기 고유 플레이어 ID 는 앱을 처음 연 순간 만들어지므로, 이미 있으면 써 본 사람이다.
    /// GameViewModel 이 만들어지기 전(App.init)에 불러야 한다.
    static func skipForExistingPlayers(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: hasSeenOnboardingKey) == nil,
              defaults.string(forKey: "moonorder.playerID") != nil else { return }
        defaults.set(true, forKey: hasSeenOnboardingKey)
    }
}

struct MoonlitOrderOnboardingView: View {
    /// 다 보면(또는 건너뛰면) 호출된다.
    let onFinish: () -> Void

    @State private var page = 0

    private struct Page {
        let icon: String
        let color: Color
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(icon: "moon.stars.fill", color: Theme.gold,
             title: "달빛 오락실에 오신 걸 환영해요",
             body: "한자리에 모인 친구들과 아이폰으로 즐기는 파티게임 모음이에요.\n인터넷도, 회원가입도 필요 없어요."),
        Page(icon: "house.fill", color: Theme.moonlit,
             title: "한 명이 방을 만들어요",
             body: "모두 앱을 설치한 뒤, 한 사람이 게임을 골라 '방 만들기'를 눌러요.\n나머지는 '게임 참가'로 그 방에 들어오면 끝!"),
        Page(icon: "antenna.radiowaves.left.and.right", color: Theme.mint,
             title: "가까이 모여 연결을 허용해 주세요",
             body: "같은 Wi-Fi나 블루투스 거리 안에서 서로를 찾아요.\n처음에 뜨는 '로컬 네트워크' 접근 요청은 꼭 허용해 주세요."),
        Page(icon: "person.2.wave.2", color: Theme.shadow,
             title: "규칙이 낯설다면 연습부터",
             body: "게임마다 '게임방법 (봇과 연습)'이 있어요.\n혼자서 봇들과 한 판을 해 보며 규칙을 익힐 수 있어요."),
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if !isLastPage {
                        Button("건너뛰기", action: onFinish)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .frame(height: 44)
                .padding(.horizontal, 20)

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in
                        pageView(pages[i]).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button {
                    if isLastPage {
                        onFinish()
                    } else {
                        withAnimation { page += 1 }
                    }
                } label: {
                    Text(isLastPage ? "시작하기" : "다음")
                }
                .buttonStyle(BigButtonStyle(color: Theme.gold, textColor: .black))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func pageView(_ p: Page) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: p.icon)
                .font(.system(size: 64))
                .foregroundColor(p.color)
                .accessibilityHidden(true)
            Text(p.title)
                .font(.title2.weight(.heavy))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
            Text(p.body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
