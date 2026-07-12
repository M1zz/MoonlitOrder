import SwiftUI

// MARK: - 역할 확인 단계

struct RoleRevealView: View {
    @EnvironmentObject var game: GameViewModel
    let state: PublicGameState
    @State private var revealed = false

    private var confirmedCount: Int { state.players.filter { $0.hasActed }.count }
    private var iConfirmed: Bool { state.player(game.playerID)?.hasActed ?? false }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("역할이 배정되었습니다")
                    .font(.title3.bold())
                    .foregroundColor(.white)

                if iConfirmed {
                    waitingCard
                } else if revealed {
                    if let info = game.privateInfo {
                        RoleCard(info: info)
                        Button {
                            game.confirmRole()
                        } label: {
                            Text("확인했습니다")
                        }
                        .buttonStyle(BigButtonStyle())
                    } else {
                        VStack(spacing: 12) {
                            ProgressView().tint(.white)
                            Text("역할 정보를 받는 중…")
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .cardStyle()
                    }
                } else {
                    hiddenCard
                }

                Text("역할 확인 \(confirmedCount)/\(state.players.count)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    private var hiddenCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(Theme.gold)
            Text("주변에 보이지 않게 한 뒤\n버튼을 눌러 역할을 확인하세요")
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.85))
            Button {
                withAnimation { revealed = true }
            } label: {
                Text("내 역할 확인하기")
            }
            .buttonStyle(BigButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var waitingCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)
            Text("확인 완료!\n다른 플레이어를 기다리는 중…")
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

// MARK: - 원정대 지명 단계

struct TeamProposalView: View {
    @EnvironmentObject var game: GameViewModel
    let state: PublicGameState
    @State private var selected: Set<UUID> = []

    private var required: Int { state.requiredTeamSize }

    var body: some View {
        VStack(spacing: 14) {
            if game.isLeader {
                Text("당신이 리더입니다!")
                    .font(.title3.bold())
                    .foregroundColor(Theme.gold)
                Text("이번 원정에 보낼 \(required)명을 선택하세요 (\(selected.count)/\(required))")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(state.players) { p in
                            Button {
                                toggle(p.id)
                            } label: {
                                HStack {
                                    Image(systemName: selected.contains(p.id)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selected.contains(p.id)
                                                         ? Theme.gold : .white.opacity(0.35))
                                    Text(p.name)
                                        .foregroundColor(.white)
                                    if p.id == game.playerID {
                                        Text("나").font(.caption2).bold()
                                            .foregroundColor(Theme.gold)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 14)
                                .cardStyle()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Button {
                    game.proposeTeam(Array(selected))
                    selected = []
                } label: {
                    Text("원정대 확정 → 전원 투표")
                }
                .buttonStyle(BigButtonStyle())
                .disabled(selected.count != required)
                .opacity(selected.count == required ? 1 : 0.5)
                .padding(.horizontal, 20)
            } else {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 44))
                        .foregroundColor(Theme.moonlit)
                    Text("리더 \(state.leader?.name ?? "?") 님이\n원정대 \(required)명을 고르는 중…")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                    Text("누구를 보낼지 자유롭게 토론하세요!")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(24)
                .cardStyle()
                .padding(.horizontal, 24)
                Spacer()
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) {
            selected.remove(id)
        } else if selected.count < required {
            selected.insert(id)
        }
    }
}

// MARK: - 찬반 투표 단계

struct VotingView: View {
    @EnvironmentObject var game: GameViewModel
    let state: PublicGameState

    private var iVoted: Bool { state.player(game.playerID)?.hasActed ?? false }
    private var votedCount: Int { state.players.filter { $0.hasActed }.count }

    var body: some View {
        VStack(spacing: 16) {
            Text("원정대 찬반 투표")
                .font(.title3.bold())
                .foregroundColor(.white)

            teamChips

            if iVoted {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    Text("투표 완료 — 결과를 기다리는 중 (\(votedCount)/\(state.players.count))")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(20)
                .cardStyle()
                .padding(.horizontal, 24)
            } else {
                Text("이 원정대 구성에 동의하시나요?\n(모두의 표가 공개됩니다 · 동수면 부결)")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.6))

                HStack(spacing: 14) {
                    Button {
                        game.vote(approve: true)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "hand.thumbsup.fill").font(.title)
                            Text("찬성")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                    }
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.moonlit.opacity(0.85)))
                    .foregroundColor(.black)

                    Button {
                        game.vote(approve: false)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "hand.thumbsdown.fill").font(.title)
                            Text("반대")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                    }
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.shadow.opacity(0.85)))
                    .foregroundColor(.white)
                }
                .font(.headline)
                .padding(.horizontal, 24)
            }

            votersProgress
        }
    }

    private var teamChips: some View {
        let names = state.proposedTeam.compactMap { state.player($0)?.name }
        return VStack(spacing: 6) {
            Text("리더 \(state.leader?.name ?? "?")의 선택")
                .font(.caption)
                .foregroundColor(.white.opacity(0.55))
            Text(names.joined(separator: " · "))
                .font(.headline)
                .foregroundColor(Theme.gold)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .cardStyle()
        .padding(.horizontal, 24)
    }

    private var votersProgress: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(state.players) { p in
                    PlayerRow(player: p,
                              isMe: p.id == game.playerID,
                              isLeader: p.id == state.leaderID,
                              showActed: true)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - 투표 결과 단계

struct VoteResultView: View {
    @EnvironmentObject var game: GameViewModel
    let state: PublicGameState

    var body: some View {
        VStack(spacing: 16) {
            Text(state.lastVoteApproved ? "가결! 원정을 떠납니다" : "부결되었습니다")
                .font(.title2.weight(.heavy))
                .foregroundColor(state.lastVoteApproved ? Theme.moonlit : Theme.shadow)

            if !state.lastVoteApproved {
                Text("리더가 다음 사람에게 넘어갑니다 · 연속 부결 \(state.voteTrack)/\(GameRules.maxRejections)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
                if state.voteTrack >= GameRules.maxRejections - 1 {
                    Text("⚠️ 한 번 더 부결되면 그림자 진영이 승리합니다!")
                        .font(.caption.bold())
                        .foregroundColor(Theme.shadow)
                }
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(state.players) { p in
                        PlayerRow(player: p,
                                  isMe: p.id == game.playerID,
                                  isLeader: p.id == state.leaderID,
                                  trailing: voteText(p.id))
                    }
                }
                .padding(.horizontal, 20)
            }

            if game.isHost {
                Button {
                    game.hostContinue()
                } label: {
                    Text("다음으로")
                }
                .buttonStyle(BigButtonStyle())
                .padding(.horizontal, 20)
            } else {
                Text("호스트가 진행하기를 기다리는 중…")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private func voteText(_ id: UUID) -> String {
        guard let vote = state.lastVotes[id.uuidString] else { return "-" }
        return vote ? "찬성 👍" : "반대 👎"
    }
}

// MARK: - 미션 수행 단계

struct MissionView: View {
    @EnvironmentObject var game: GameViewModel
    let state: PublicGameState
    @State private var choice: Bool?

    private var iSubmitted: Bool { state.player(game.playerID)?.hasActed ?? false }
    private var amGood: Bool { game.myRole?.team == .moonlit }
    private var teamMembers: [PlayerPublic] {
        state.players.filter { state.proposedTeam.contains($0.id) }
    }
    private var submittedCount: Int { teamMembers.filter { $0.hasActed }.count }

    var body: some View {
        VStack(spacing: 16) {
            Text("\(state.round)번째 원정 진행 중")
                .font(.title3.bold())
                .foregroundColor(.white)

            Text("원정대: \(teamMembers.map { $0.name }.joined(separator: " · "))")
                .font(.subheadline)
                .foregroundColor(Theme.gold)

            if game.isOnTeam {
                if iSubmitted {
                    waitingCard
                } else {
                    missionCards
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.6))
                    Text("원정대가 임무를 수행하는 중…\n(\(submittedCount)/\(teamMembers.count) 제출)")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(24)
                .cardStyle()
                .padding(.horizontal, 24)
            }

            if state.requiredFails > 1 {
                Text("이번 원정은 실패 카드가 \(state.requiredFails)장 나와야 실패합니다")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
    }

    private var missionCards: some View {
        VStack(spacing: 14) {
            Text("카드를 선택하세요 (아무도 누가 냈는지 알 수 없습니다)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))

            HStack(spacing: 14) {
                missionCard(success: true)
                missionCard(success: false)
            }
            .padding(.horizontal, 24)

            if !amGood {
                Text("당신은 그림자 — 실패 카드로 원정을 망칠 수 있습니다")
                    .font(.caption)
                    .foregroundColor(Theme.shadow.opacity(0.9))
            }

            Button {
                if let choice {
                    game.playMission(success: choice)
                }
            } label: {
                Text("카드 제출")
            }
            .buttonStyle(BigButtonStyle())
            .disabled(choice == nil)
            .opacity(choice == nil ? 0.5 : 1)
            .padding(.horizontal, 24)
        }
    }

    private func missionCard(success: Bool) -> some View {
        let disabled = !success && amGood
        return Button {
            if !disabled { choice = success }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: success ? "checkmark.shield.fill" : "xmark.shield.fill")
                    .font(.system(size: 36))
                Text(success ? "성공" : "실패")
                    .font(.headline)
                if disabled {
                    Text("결사단은\n성공만 가능")
                        .font(.system(size: 9))
                        .multilineTextAlignment(.center)
                        .opacity(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(success ? Theme.moonlit.opacity(0.85) : Theme.shadow.opacity(0.85))
                    .opacity(disabled ? 0.3 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.gold, lineWidth: choice == success ? 3 : 0)
            )
            .foregroundColor(success ? .black : .white)
        }
        .disabled(disabled)
    }

    private var waitingCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 40))
                .foregroundColor(Theme.gold)
            Text("카드 제출 완료\n다른 대원을 기다리는 중… (\(submittedCount)/\(teamMembers.count))")
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(24)
        .cardStyle()
        .padding(.horizontal, 24)
    }
}

// MARK: - 미션 결과 단계

struct MissionResultView: View {
    @EnvironmentObject var game: GameViewModel
    let state: PublicGameState

    private var record: MissionRecord? {
        state.missionHistory.last
    }

    var body: some View {
        VStack(spacing: 18) {
            if let record {
                Image(systemName: record.succeeded ? "sun.max.fill" : "cloud.bolt.fill")
                    .font(.system(size: 56))
                    .foregroundColor(record.succeeded ? Theme.gold : Theme.shadow)

                Text(record.succeeded ? "원정 성공!" : "원정 실패…")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundColor(record.succeeded ? Theme.moonlit : Theme.shadow)

                VStack(spacing: 8) {
                    Text("성공 카드 \(record.teamNames.count - record.failCount)장 · 실패 카드 \(record.failCount)장")
                        .font(.headline)
                        .foregroundColor(.white)
                    if record.failCount > 0 && record.succeeded {
                        Text("실패 카드가 나왔지만 이번 원정은 \(state.requiredFails)장이 필요해 버텨냈습니다!")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Text("원정대: \(record.teamNames.joined(separator: " · "))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.55))
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .cardStyle()
                .padding(.horizontal, 24)

                Text("성공 \(state.successCount) : \(state.failureCount) 실패 — 먼저 3승을 가져가면 승리")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }

            if game.isHost {
                Button {
                    game.hostContinue()
                } label: {
                    Text("다음으로")
                }
                .buttonStyle(BigButtonStyle())
                .padding(.horizontal, 24)
            } else {
                Text("호스트가 진행하기를 기다리는 중…")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}
