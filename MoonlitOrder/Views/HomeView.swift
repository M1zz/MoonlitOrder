import SwiftUI

extension GameViewModel.GameKind: Identifiable {
    var id: String { rawValue }
}

struct HomeView: View {
    @EnvironmentObject var game: GameViewModel
    @FocusState private var nameFocused: Bool
    @State private var selectedGame: GameViewModel.GameKind?

    private func gameCard(icon: String, color: Color, title: String,
                          desc: String, action: @escaping () -> Void) -> some View {
        Button {
            nameFocused = false
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .cardStyle()
        }
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Theme.gold)
                Text("달빛 오락실")
                    .font(.system(size: 36, weight: .heavy, design: .serif))
                    .foregroundColor(.white)
                Text("가까운 친구들과 즐기는 파티게임 3종")
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

            VStack(spacing: 10) {
                HStack {
                    Text("게임을 골라보세요")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                }

                gameCard(icon: "moon.stars.fill", color: Theme.gold,
                         title: "달빛 결사",
                         desc: "5~10인 · 숨어든 그림자를 찾는 정체 추리") {
                    selectedGame = .moonlit
                }
                gameCard(icon: "theatermasks.fill", color: Theme.moonlit,
                         title: "라이어 게임",
                         desc: "3~10인 · 제시어를 모르는 한 명을 찾아라") {
                    selectedGame = .liar
                }
                gameCard(icon: "flame.fill", color: Theme.shadow,
                         title: "달 없는 밤",
                         desc: "3~10인 · 도깨비가 숨어든 하룻밤 추리") {
                    selectedGame = .wolf
                }

                Button {
                    nameFocused = false
                    game.startBrowsing()
                } label: {
                    Label("주변의 모든 방 찾기", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 28)

            Spacer()

            Text("같은 Wi-Fi 또는 근거리의 아이폰끼리 자동으로 연결됩니다.\n인터넷 없이도 플레이할 수 있어요.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.45))
                .padding(.bottom, 12)
        }
        .sheet(item: $selectedGame) { kind in
            GameMenuView(kind: kind)
                .presentationDetents([.medium])
        }
    }
}

// MARK: - 게임별 메뉴 (방 만들기 / 참가 / 게임방법)

struct GameMenuView: View {
    @EnvironmentObject var game: GameViewModel
    @Environment(\.dismiss) private var dismiss
    let kind: GameViewModel.GameKind

    private var icon: String {
        switch kind {
        case .moonlit: return "moon.stars.fill"
        case .liar:    return "theatermasks.fill"
        case .wolf:    return "flame.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .moonlit: return Theme.gold
        case .liar:    return Theme.moonlit
        case .wolf:    return Theme.shadow
        }
    }

    private var summary: String {
        switch kind {
        case .moonlit:
            return "원정대에 숨어든 그림자 진영을 찾아내는 5~10인 정체 추리 게임. 미션 3회를 먼저 성공(또는 실패)시키는 진영이 승리합니다."
        case .liar:
            return "라이어만 빼고 모두 같은 제시어를 받는 3~10인 눈치 게임. 한 마디씩 설명한 뒤 라이어를 찾아내세요. 라이어는 잡혀도 제시어를 맞히면 역전승!"
        case .wolf:
            return "도깨비가 숨어든 하룻밤의 3~10인 추리 게임. 밤사이 카드가 뒤바뀌고, 단 한 번의 투표로 승패가 갈립니다."
        }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundColor(color)
                    .padding(.top, 28)
                Text(kind.displayName)
                    .font(.title.weight(.heavy))
                    .foregroundColor(.white)
                Text(summary)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 28)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        dismiss()
                        game.hostGame(kind: kind)
                    } label: {
                        Label("방 만들기 (호스트)", systemImage: "house.fill")
                    }
                    .buttonStyle(BigButtonStyle(color: color,
                                                textColor: kind == .moonlit ? .black : .white))

                    Button {
                        dismiss()
                        game.startBrowsing(filter: kind)
                    } label: {
                        Label("게임 참가", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(BigButtonStyle(color: Color.white.opacity(0.12),
                                                textColor: .white))

                    Button {
                        dismiss()
                        game.startDemo(kind: kind)
                    } label: {
                        Label("게임방법 (봇과 연습)", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(BigButtonStyle(color: Color.white.opacity(0.12),
                                                textColor: .white))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
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

            Text(game.browseFilter.map { "\($0.displayName) 방 찾기" } ?? "주변의 방 찾기")
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
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(host.hostName)의 방")
                                            .foregroundColor(.white)
                                        if let gameName = host.gameName {
                                            Text(gameName)
                                                .font(.caption)
                                                .foregroundColor(Theme.moonlit)
                                        }
                                    }
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
