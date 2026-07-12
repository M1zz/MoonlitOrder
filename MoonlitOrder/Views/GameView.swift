import SwiftUI

struct GameView: View {
    @EnvironmentObject var game: GameViewModel
    let state: PublicGameState
    @State private var showRoleSheet = false
    @State private var showLeaveConfirm = false

    var body: some View {
        VStack(spacing: 14) {
            header

            if state.phase != .gameOver {
                MissionTrackView(state: state)
                    .padding(.horizontal, 16)
            }

            phaseContent
                .frame(maxHeight: .infinity)

            footer
        }
        .padding(.bottom, 10)
        .overlay(alignment: .top) { disconnectBanner }
        .sheet(isPresented: $showRoleSheet) {
            RoleSheet()
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("게임에서 나갈까요?",
                            isPresented: $showLeaveConfirm,
                            titleVisibility: .visible) {
            if game.isHost, state.phase != .gameOver {
                Button("게임 중단하고 대기실로") {
                    game.abortToLobby()
                }
            }
            Button(game.isHost ? "방 닫기 (전원 종료됨)" : "나가기", role: .destructive) {
                game.leaveGame()
            }
            Button("취소", role: .cancel) {}
        }
    }

    // MARK: 상단

    private var header: some View {
        HStack {
            Button {
                showLeaveConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            if state.phase != .gameOver {
                VStack(spacing: 2) {
                    Text("\(state.round)번째 원정")
                        .font(.headline)
                        .foregroundColor(.white)
                    if let leader = state.leader {
                        Label("리더: \(leader.name)", systemImage: "flag.fill")
                            .font(.caption)
                            .foregroundColor(Theme.moonlit)
                    }
                }
            } else {
                Text("게임 종료")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            Spacer()
            Image(systemName: "xmark").opacity(0)   // 균형용
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: 단계별 화면

    @ViewBuilder
    private var phaseContent: some View {
        switch state.phase {
        case .roleReveal:
            RoleRevealView(state: state)
        case .teamProposal:
            TeamProposalView(state: state)
        case .teamVoting:
            VotingView(state: state)
        case .voteResult:
            VoteResultView(state: state)
        case .mission:
            MissionView(state: state)
        case .missionResult:
            MissionResultView(state: state)
        case .assassination:
            AssassinationView(state: state)
        case .gameOver:
            GameOverView(state: state)
        case .lobby:
            EmptyView()
        }
    }

    // MARK: 하단

    @ViewBuilder
    private var footer: some View {
        if state.phase != .gameOver, game.privateInfo != nil {
            Button {
                showRoleSheet = true
            } label: {
                Label("내 역할 보기", systemImage: "person.text.rectangle")
                    .font(.subheadline.bold())
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: 연결 끊김 안내

    @ViewBuilder
    private var disconnectBanner: some View {
        if game.connectionLost {
            banner(text: "호스트와 연결이 끊겼습니다. 자동으로 재접속을 시도하는 중…",
                   color: Theme.shadow)
        } else if state.phase != .gameOver, !state.disconnectedPlayers.isEmpty {
            let names = state.disconnectedPlayers.map { $0.name }.joined(separator: ", ")
            banner(text: "\(names) 님의 재접속을 기다리는 중입니다. 앱을 다시 열면 자동 복귀됩니다.",
                   color: .orange)
        }
    }

    private func banner(text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            ProgressView().tint(.white).scaleEffect(0.8)
            Text(text)
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Capsule().fill(color.opacity(0.9)))
        .padding(.top, 4)
    }
}

// MARK: - 내 역할 시트

struct RoleSheet: View {
    @EnvironmentObject var game: GameViewModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let info = game.privateInfo {
                VStack(spacing: 18) {
                    Text("다른 사람에게 보이지 않게 확인하세요")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 24)

                    RoleCard(info: info)
                        .padding(.horizontal, 24)

                    Spacer()
                }
            }
        }
    }
}

struct RoleCard: View {
    let info: PrivateInfo

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: info.role.team == .moonlit ? "moon.stars.fill" : "theatermasks.fill")
                .font(.system(size: 44))
                .foregroundColor(Theme.teamColor(info.role.team))

            Text(info.role.displayName)
                .font(.title.weight(.heavy))
                .foregroundColor(.white)

            Text("\(info.role.team.displayName) 진영")
                .font(.subheadline.bold())
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill(Theme.teamColor(info.role.team).opacity(0.2)))
                .foregroundColor(Theme.teamColor(info.role.team))

            Text(info.role.summary)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 6)

            if !info.knownShadowNames.isEmpty {
                VStack(spacing: 6) {
                    Text(info.role == .seer ? "그림자 단원으로 보이는 자들" : "당신의 동료 그림자")
                        .font(.caption.bold())
                        .foregroundColor(Theme.shadow)
                    Text(info.knownShadowNames.joined(separator: " · "))
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.shadow.opacity(0.12))
                )
            }

            Text("목표: \(info.role.objective)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}
