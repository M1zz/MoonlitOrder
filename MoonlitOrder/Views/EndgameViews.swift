import SwiftUI

// MARK: - 암살 단계

struct AssassinationView: View {
    @EnvironmentObject var game: GameViewModel
    let state: PublicGameState
    @State private var target: UUID?

    private var amAssassin: Bool { game.myRole == .assassin }

    /// 암살자 입장에서 예언자 후보 = 나와 동료 그림자를 제외한 전원
    private var candidates: [PlayerPublic] {
        let shadowNames = Set(game.privateInfo?.knownShadowNames ?? [])
        return state.players.filter {
            $0.id != game.playerID && !shadowNames.contains($0.name)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "scope")
                .font(.system(size: 48))
                .foregroundColor(Theme.shadow)

            Text("암살의 시간")
                .font(.title.weight(.heavy))
                .foregroundColor(.white)

            Text("달빛 결사가 원정 3회에 성공했습니다.\n하지만 암살자가 예언자를 찾아내면 그림자의 역전승!")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 24)

            if amAssassin {
                Text("예언자라고 생각하는 플레이어를 지목하세요")
                    .font(.caption.bold())
                    .foregroundColor(Theme.shadow)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(candidates) { p in
                            Button {
                                target = p.id
                            } label: {
                                HStack {
                                    Image(systemName: target == p.id
                                          ? "scope" : "circle")
                                        .foregroundColor(target == p.id
                                                         ? Theme.shadow : .white.opacity(0.35))
                                    Text(p.name).foregroundColor(.white)
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 14)
                                .cardStyle()
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Theme.shadow,
                                                lineWidth: target == p.id ? 2 : 0)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Button {
                    if let target {
                        game.assassinate(target)
                    }
                } label: {
                    Text("암살 실행")
                }
                .buttonStyle(BigButtonStyle(color: Theme.shadow, textColor: .white))
                .disabled(target == nil)
                .opacity(target == nil ? 0.5 : 1)
                .padding(.horizontal, 24)
            } else {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView().tint(Theme.shadow)
                    Text("암살자가 마지막 표적을 고르고 있습니다…")
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(24)
                .cardStyle()
                .padding(.horizontal, 24)
                Spacer()
            }
        }
    }
}

// MARK: - 게임 종료

struct GameOverView: View {
    @EnvironmentObject var game: GameViewModel
    let state: PublicGameState

    var body: some View {
        VStack(spacing: 16) {
            if let winner = state.winner {
                Image(systemName: winner == .moonlit ? "moon.stars.fill" : "theatermasks.fill")
                    .font(.system(size: 56))
                    .foregroundColor(Theme.teamColor(winner))

                Text("\(winner.displayName) 승리!")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundColor(Theme.teamColor(winner))

                if let reason = state.winReason {
                    Text(reason)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 24)
                }
            }

            ScrollView {
                VStack(spacing: 6) {
                    Text("역할 공개")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.55))
                    ForEach(state.players) { p in
                        HStack {
                            Text(p.name)
                                .fontWeight(p.id == game.playerID ? .bold : .regular)
                                .foregroundColor(.white)
                            if p.id == game.playerID {
                                Text("나").font(.caption2).bold()
                                    .foregroundColor(Theme.gold)
                            }
                            Spacer()
                            if let role = state.revealedRoles?[p.id.uuidString] {
                                Text(role.displayName)
                                    .font(.subheadline.bold())
                                    .foregroundColor(Theme.teamColor(role.team))
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .cardStyle()
                    }
                }
                .padding(.horizontal, 20)
            }

            if game.isHost {
                Button {
                    game.playAgain()
                } label: {
                    Text("같은 멤버로 다시 하기")
                }
                .buttonStyle(BigButtonStyle())
                .padding(.horizontal, 20)
            } else {
                Text("호스트가 다시 시작할 수 있습니다")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }

            Button {
                game.leaveGame()
            } label: {
                Text("나가기")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.bottom, 4)
        }
    }
}
