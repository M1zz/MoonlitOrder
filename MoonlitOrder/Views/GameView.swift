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

            if let guide = demoGuide {
                demoGuideCard(guide)
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
            if let seconds = state.phaseSeconds, state.phase != .gameOver {
                PhaseTimerView(seconds: seconds, startedAt: state.phaseStartedAt)
            } else {
                Image(systemName: "xmark").opacity(0)   // 균형용
            }
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
        if state.phase != .gameOver {
            HStack(spacing: 12) {
                if game.privateInfo != nil {
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
                // 결과 화면에는 큰 '다음으로' 버튼이 있으므로 '다음'은 행동 단계에서만 보인다
                if game.isDemo, ![.voteResult, .missionResult].contains(state.phase) {
                    Button {
                        game.advanceDemo()
                    } label: {
                        Label("다음", systemImage: "forward.fill")
                            .font(.subheadline.bold())
                            .padding(.vertical, 10)
                            .padding(.horizontal, 18)
                            .background(Capsule().fill(Theme.gold.opacity(0.25)))
                            .foregroundColor(Theme.gold)
                    }
                }
            }
        }
    }

    // MARK: 게임방법(데모) 단계 안내

    private var demoGuide: String? {
        guard game.isDemo else { return nil }
        switch state.phase {
        case .roleReveal:
            return "각자 자신의 역할을 남몰래 확인하는 단계입니다. 역할을 확인한 뒤 '다음'을 누르면 봇들도 확인을 마칩니다."
        case .teamProposal:
            return "리더가 이번 원정을 떠날 원정대를 지명합니다. '다음'을 누르면 리더가 팀을 고릅니다. (내가 리더라면 직접 골라보세요!)"
        case .teamVoting:
            return "전원이 원정대 구성에 찬성/반대를 투표합니다. 동수면 부결! 먼저 투표해보고 '다음'으로 봇들의 표를 확인하세요."
        case .voteResult:
            return "투표 결과입니다. 원정대가 5회 연속 부결되면 그림자 진영이 승리하니 무작정 반대만 할 수는 없어요."
        case .mission:
            return "원정대원만 성공/실패 카드를 냅니다. 달빛 결사는 성공만 낼 수 있고, 그림자만 몰래 실패를 낼 수 있어요. '다음'으로 원정대의 카드 제출을 지켜보세요."
        case .missionResult:
            return "실패 카드가 기준 수 이상이면 원정 실패! 어느 진영이든 먼저 3승을 가져가면 게임이 끝납니다."
        case .assassination:
            return "미션 3회가 성공해도 마지막 반전이 남아 있습니다 — 암살자가 예언자를 정확히 지목하면 그림자가 역전승합니다."
        default:
            return nil
        }
    }

    private func demoGuideCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(Theme.gold)
            Text(text)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Theme.gold.opacity(0.12))
        )
        .padding(.horizontal, 16)
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

// MARK: - 단계 타이머

/// 현재 단계의 남은 시간을 보여주는 카운트다운.
/// 호스트가 정한 단계 시작 시각 기준이라 모든 기기가 같은 시간을 본다.
/// 시간이 다 되어도 행동을 강제하지는 않는다 (재촉용).
struct PhaseTimerView: View {
    let seconds: Int
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(startedAt))
            let remaining = max(0, seconds - elapsed)
            let urgent = remaining <= 10
            Label(remaining > 0 ? "\(remaining)" : "시간 초과",
                  systemImage: "timer")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundColor(urgent ? Theme.shadow : .white.opacity(0.85))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    Capsule().fill((urgent ? Theme.shadow : Color.white).opacity(0.15))
                )
        }
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
