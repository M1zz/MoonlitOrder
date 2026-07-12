import SwiftUI

struct HomeView: View {
    @EnvironmentObject var game: GameViewModel
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 56))
                    .foregroundColor(Theme.gold)
                Text("달빛 결사")
                    .font(.system(size: 40, weight: .heavy, design: .serif))
                    .foregroundColor(.white)
                Text("숨어든 그림자를 찾아라 — 5~10인 소셜 추리 게임")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("닉네임")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                TextField("이름을 입력하세요", text: $game.playerName)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                    )
                    .foregroundColor(.white)
                    .focused($nameFocused)
                    .submitLabel(.done)
            }
            .padding(.horizontal, 28)

            VStack(spacing: 14) {
                Button {
                    nameFocused = false
                    game.hostGame()
                } label: {
                    Label("방 만들기 (호스트)", systemImage: "house.fill")
                }
                .buttonStyle(BigButtonStyle())

                Button {
                    nameFocused = false
                    game.startBrowsing()
                } label: {
                    Label("게임 참가", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(BigButtonStyle(color: Color.white.opacity(0.12),
                                            textColor: .white))

                Button {
                    nameFocused = false
                    game.startDemo()
                } label: {
                    Label("게임방법", systemImage: "questionmark.circle")
                }
                .buttonStyle(BigButtonStyle(color: Color.white.opacity(0.12),
                                            textColor: .white))
            }
            .padding(.horizontal, 28)

            Spacer()

            Text("같은 Wi-Fi 또는 근거리의 아이폰끼리 자동으로 연결됩니다.\n인터넷 없이도 플레이할 수 있어요.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.45))
                .padding(.bottom, 12)
        }
    }
}

struct BrowseView: View {
    @EnvironmentObject var game: GameViewModel

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    game.leaveGame()
                } label: {
                    Label("뒤로", systemImage: "chevron.left")
                        .foregroundColor(.white)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Text("주변의 방 찾기")
                .font(.title2).bold()
                .foregroundColor(.white)

            if game.mode == .connecting {
                Spacer()
                ProgressView("방에 연결하는 중…")
                    .tint(.white)
                    .foregroundColor(.white)
                Spacer()
            } else if game.hosts.isEmpty {
                Spacer()
                ProgressView()
                    .tint(.white)
                Text("주변에서 방을 찾고 있습니다…\n호스트가 '방 만들기'를 눌렀는지 확인하세요.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(game.hosts) { host in
                            Button {
                                game.join(host: host)
                            } label: {
                                HStack {
                                    Image(systemName: "moon.fill")
                                        .foregroundColor(Theme.gold)
                                    Text("\(host.hostName)의 방")
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                .padding(16)
                                .cardStyle()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                Spacer()
            }
        }
    }
}
