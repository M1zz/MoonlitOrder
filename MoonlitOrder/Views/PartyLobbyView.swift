import SwiftUI

/// 라이어 게임·한밤의 늑대인간 공용 대기실.
/// (달빛 결사는 진영 구성 안내가 있는 전용 LobbyView를 쓴다)
struct PartyLobbyView: View {
    @EnvironmentObject var game: GameViewModel
    let title: String
    let subtitle: String
    let players: [PlayerPublic]
    let range: ClosedRange<Int>
    let onStart: () -> Void
    @State private var kickTarget: PlayerPublic?

    private var countOK: Bool { range.contains(players.count) }

    private func canKick(_ p: PlayerPublic) -> Bool {
        game.isHost && !game.isDemo && !p.isHost
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    game.leaveGame()
                } label: {
                    Label("나가기", systemImage: "xmark")
                        .foregroundColor(.white.opacity(0.8))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title.weight(.heavy))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
                Text("\(players.count)명 참가 중 (\(range.lowerBound)~\(range.upperBound)명)")
                    .font(.caption)
                    .foregroundColor(countOK ? Theme.moonlit : .white.opacity(0.6))
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(players) { p in
                        PlayerRow(player: p, isMe: p.id == game.playerID,
                                  onKick: canKick(p) ? { kickTarget = p } : nil)
                    }
                }
                .padding(.horizontal, 20)
            }

            if game.isDemo {
                Text("게임방법 배우기: 봇들이 입장하고 있어요.\n인원이 모이면 '게임 시작'을 눌러 시작하세요.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.gold)
            }

            if game.isHost {
                Button(action: onStart) {
                    Text(countOK ? "게임 시작" : "최소 \(range.lowerBound)명이 필요합니다")
                }
                .buttonStyle(BigButtonStyle())
                .disabled(!countOK)
                .opacity(countOK ? 1 : 0.5)
                .padding(.horizontal, 20)
            } else {
                Text("호스트가 게임을 시작하기를 기다리는 중…")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 8)
            }
        }
        .padding(.bottom, 16)
        .confirmationDialog(kickTarget.map { "\($0.name) 님을 내보낼까요?" } ?? "",
                            isPresented: Binding(get: { kickTarget != nil },
                                                 set: { if !$0 { kickTarget = nil } }),
                            titleVisibility: .visible,
                            presenting: kickTarget) { target in
            Button("내보내기", role: .destructive) { game.kickPlayer(target.id) }
            Button("취소", role: .cancel) {}
        }
    }
}
