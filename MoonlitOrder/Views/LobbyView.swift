import SwiftUI

struct LobbyView: View {
    @EnvironmentObject var game: GameViewModel
    let state: PublicGameState

    private var countOK: Bool {
        GameRules.playerRange.contains(state.players.count)
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    game.leaveGame()
                } label: {
                    Label("나가기", systemImage: "xmark")
                        .foregroundColor(.white.opacity(0.8))
                }
                Spacer()
                Text(game.isHost ? "내가 만든 방" : "대기실")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                // 좌우 균형용 투명 요소
                Label("나가기", systemImage: "xmark").opacity(0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            VStack(spacing: 4) {
                Image(systemName: "moon.stars.fill")
                    .font(.largeTitle)
                    .foregroundColor(Theme.gold)
                Text("달빛 결사")
                    .font(.title.weight(.heavy))
                    .foregroundColor(.white)
                Text("참가자 \(state.players.count)명 · \(GameRules.playerRange.lowerBound)~\(GameRules.playerRange.upperBound)명 필요")
                    .font(.subheadline)
                    .foregroundColor(countOK ? Theme.moonlit : .white.opacity(0.6))
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(state.players) { p in
                        PlayerRow(player: p, isMe: p.id == game.playerID)
                    }
                }
                .padding(.horizontal, 20)
            }

            if state.players.count >= GameRules.playerRange.lowerBound {
                shadowCountInfo
            }

            if game.isHost {
                Button {
                    game.startGame()
                } label: {
                    Text(countOK ? "게임 시작" : "최소 \(GameRules.playerRange.lowerBound)명이 필요합니다")
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
    }

    private var shadowCountInfo: some View {
        let n = state.players.count
        let shadows = GameRules.shadowCount(for: n)
        return Text("이 인원이면 그림자 진영 \(shadows)명 · 달빛 결사 \(n - shadows)명")
            .font(.caption)
            .foregroundColor(.white.opacity(0.55))
    }
}
