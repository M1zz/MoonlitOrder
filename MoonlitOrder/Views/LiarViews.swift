import SwiftUI

// MARK: - 라이어 게임 루트

struct LiarRootView: View {
    @EnvironmentObject var game: GameViewModel
    let state: LiarGameState

    var body: some View {
        if state.phase == .lobby {
            PartyLobbyView(title: "라이어 게임",
                           subtitle: "모두 같은 제시어, 단 한 명만 모른다",
                           players: state.players,
                           range: LiarRules.playerRange) {
                game.performLiar(.startGame)
            }
        } else {
            LiarGameView(state: state)
        }
    }
}

// MARK: - 게임 화면

struct LiarGameView: View {
    @EnvironmentObject var game: GameViewModel
    let state: LiarGameState
    @State private var showLeaveConfirm = false
    @State private var showGMPanel = false

    private var me: PlayerPublic? { state.player(game.playerID) }

    var body: some View {
        VStack(spacing: 14) {
            header

            if let guide = demoGuide {
                demoGuideCard(guide)
            }

            phaseContent
                .frame(maxHeight: .infinity)

            if game.isDemo, state.phase != .gameOver {
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
        .padding(.bottom, 10)
        .overlay(alignment: .top) {
            if game.connectionLost {
                HStack(spacing: 8) {
                    ProgressView().tint(.white).scaleEffect(0.8)
                    Text("호스트와 연결이 끊겼습니다. 재접속 시도 중…")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.vertical, 8).padding(.horizontal, 14)
                .background(Capsule().fill(Theme.shadow.opacity(0.9)))
                .padding(.top, 4)
            } else if state.phase != .gameOver, !state.disconnectedPlayers.isEmpty {
                ReconnectWaitBanner(disconnected: state.disconnectedPlayers)
            }
        }
        .sheet(isPresented: $showGMPanel) {
            GMPanelView()
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("게임에서 나갈까요?",
                            isPresented: $showLeaveConfirm,
                            titleVisibility: .visible) {
            if game.isHost, state.phase != .gameOver {
                Button("게임 중단하고 대기실로") { game.performLiar(.abortToLobby) }
            }
            Button(game.isHost ? "방 닫기 (전원 종료됨)" : "나가기", role: .destructive) {
                game.leaveGame()
            }
            Button("취소", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            Button { showLeaveConfirm = true } label: {
                Image(systemName: "xmark").foregroundColor(.white.opacity(0.7))
            }
            if game.isHost, !game.isDemo {
                Button { showGMPanel = true } label: {
                    Image(systemName: "crown.fill")
                        .foregroundColor(Theme.gold.opacity(0.85))
                }
                .padding(.leading, 6)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("라이어 게임")
                    .font(.headline)
                    .foregroundColor(.white)
                if !state.category.isEmpty, state.phase != .gameOver {
                    Text("카테고리: \(state.category)")
                        .font(.caption)
                        .foregroundColor(Theme.gold)
                }
            }
            Spacer()
            if let seconds = state.phaseSeconds {
                PhaseTimerView(seconds: seconds, startedAt: state.phaseStartedAt)
            } else {
                Image(systemName: "xmark").opacity(0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch state.phase {
        case .wordReveal: LiarWordRevealView(state: state)
        case .describing: LiarDescribingView(state: state)
        case .voting:     LiarVotingView(state: state)
        case .liarGuess:  LiarGuessView(state: state)
        case .gameOver:   LiarGameOverView(state: state)
        case .lobby:      EmptyView()
        }
    }

    // MARK: 게임방법(데모) 단계 안내

    private var demoGuide: String? {
        guard game.isDemo else { return nil }
        switch state.phase {
        case .wordReveal:
            return "라이어만 빼고 전원이 같은 제시어를 받았어요. 내 제시어를 확인한 뒤 '다음'으로 봇들의 확인을 마치세요."
        case .describing:
            return "순서대로 제시어를 한 마디씩 설명하는 단계입니다. '다음'을 누를 때마다 현재 차례의 발언이 끝납니다."
        case .voting:
            return "누가 설명을 얼버무렸나요? 라이어로 의심되는 사람에게 먼저 투표해보고, '다음'으로 봇들의 표를 확인하세요."
        case .liarGuess:
            return "라이어가 잡혔습니다! 하지만 라이어가 제시어를 맞히면 역전승 — '다음'으로 라이어의 추측을 지켜보세요."
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
}

// MARK: - 내 제시어 카드 (공용)

struct LiarWordCard: View {
    @EnvironmentObject var game: GameViewModel
    var compact = false

    var body: some View {
        Group {
            if let info = game.liarPrivate {
                if info.isLiar {
                    VStack(spacing: compact ? 4 : 10) {
                        if !compact {
                            Image(systemName: "theatermasks.fill")
                                .font(.system(size: 36))
                                .foregroundColor(Theme.shadow)
                        }
                        Text("당신이 라이어입니다!")
                            .font(compact ? .subheadline.bold() : .title3.weight(.heavy))
                            .foregroundColor(Theme.shadow)
                        Text("제시어를 모르지만 아는 척 설명해야 합니다. 들키지 마세요!")
                            .font(compact ? .caption2 : .footnote)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else {
                    VStack(spacing: compact ? 4 : 10) {
                        Text("제시어")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        Text(info.word ?? "")
                            .font(compact ? .title3.weight(.heavy) : .largeTitle.weight(.heavy))
                            .foregroundColor(Theme.gold)
                    }
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .padding(compact ? 12 : 24)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

// MARK: - 제시어 확인

struct LiarWordRevealView: View {
    @EnvironmentObject var game: GameViewModel
    let state: LiarGameState
    @State private var revealed = false

    private var iConfirmed: Bool { state.player(game.playerID)?.hasActed ?? false }
    private var confirmedCount: Int { state.players.filter { $0.hasActed }.count }

    var body: some View {
        VStack(spacing: 20) {
            Text("제시어가 도착했습니다")
                .font(.title2.bold())
                .foregroundColor(.white)

            if revealed {
                LiarWordCard()
                    .padding(.horizontal, 24)

                if iConfirmed {
                    Label("확인 완료! 다른 플레이어를 기다리는 중…", systemImage: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                } else {
                    Button {
                        game.performLiar(.confirmWord)
                    } label: {
                        Text("확인했어요")
                    }
                    .buttonStyle(BigButtonStyle())
                    .padding(.horizontal, 24)
                }
            } else {
                Text("다른 사람에게 화면이 보이지 않게 확인하세요")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.6))
                Button {
                    revealed = true
                } label: {
                    Label("살짝 확인하기", systemImage: "eye.fill")
                }
                .buttonStyle(BigButtonStyle(color: Color.white.opacity(0.12), textColor: .white))
                .padding(.horizontal, 24)
            }

            Text("확인 \(confirmedCount)/\(state.players.count)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.top, 12)
    }
}

// MARK: - 순서대로 설명

struct LiarDescribingView: View {
    @EnvironmentObject var game: GameViewModel
    let state: LiarGameState

    private var isMyTurn: Bool { state.currentSpeakerID == game.playerID }

    var body: some View {
        VStack(spacing: 14) {
            Text("순서대로 제시어를 한 마디씩 설명하세요")
                .font(.headline)
                .foregroundColor(.white)
            Text("너무 자세히 말하면 라이어에게 힌트가 되고,\n너무 애매하면 당신이 의심받아요!")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.6))

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(state.speakingOrder.enumerated()), id: \.element) { i, pid in
                        if let p = state.player(pid) {
                            HStack(spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.caption.bold())
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(
                                        i == state.speakerIndex
                                            ? Theme.gold : Color.white.opacity(0.12)))
                                    .foregroundColor(i == state.speakerIndex ? .black : .white)
                                Text(p.name)
                                    .fontWeight(p.id == game.playerID ? .bold : .regular)
                                    .foregroundColor(.white)
                                if p.id == game.playerID {
                                    Text("나")
                                        .font(.caption2).bold()
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Theme.gold.opacity(0.25)))
                                        .foregroundColor(Theme.gold)
                                }
                                Spacer()
                                if i < state.speakerIndex {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else if i == state.speakerIndex {
                                    Text("발언 중")
                                        .font(.caption.bold())
                                        .foregroundColor(Theme.gold)
                                }
                            }
                            .padding(.vertical, 10).padding(.horizontal, 14)
                            .cardStyle()
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            LiarWordCard(compact: true)
                .padding(.horizontal, 20)

            if isMyTurn {
                Button {
                    game.performLiar(.finishSpeech)
                } label: {
                    Text("발언 완료")
                }
                .buttonStyle(BigButtonStyle())
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - 라이어 투표

struct LiarVotingView: View {
    @EnvironmentObject var game: GameViewModel
    let state: LiarGameState
    @State private var pendingTarget: PlayerPublic?

    private var iVoted: Bool { state.player(game.playerID)?.hasActed ?? false }
    private var votedCount: Int { state.players.filter { $0.hasActed }.count }

    var body: some View {
        VStack(spacing: 14) {
            Text("라이어는 누구일까요?")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("가장 의심스러운 사람에게 투표하세요 · 표가 갈리면 라이어의 승리!")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(state.players.filter { $0.id != game.playerID }) { p in
                        Button {
                            pendingTarget = p
                        } label: {
                            // 투표를 마친 사람에게 체크 표시 (누구에게 던졌는지는 비공개)
                            PlayerRow(player: p, showActed: true)
                        }
                        .disabled(iVoted)
                        .opacity(iVoted ? 0.55 : 1)
                    }
                }
                .padding(.horizontal, 20)
            }

            if iVoted {
                Label("투표 완료! 개표를 기다리는 중…", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }
            Text("투표 \(votedCount)/\(state.players.count)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.top, 12)
        .confirmationDialog(
            "'\(pendingTarget?.name ?? "")'을(를) 라이어로 지목할까요?",
            isPresented: Binding(get: { pendingTarget != nil },
                                 set: { if !$0 { pendingTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("투표 확정", role: .destructive) {
                if let target = pendingTarget {
                    game.performLiar(.vote(targetID: target.id))
                }
                pendingTarget = nil
            }
            Button("취소", role: .cancel) { pendingTarget = nil }
        } message: {
            Text("제출한 표는 바꿀 수 없습니다.")
        }
    }
}

// MARK: - 라이어의 마지막 추측

struct LiarGuessView: View {
    @EnvironmentObject var game: GameViewModel
    let state: LiarGameState
    @State private var pendingWord: String?

    private var amILiar: Bool { game.liarPrivate?.isLiar ?? false }
    private var accusedName: String {
        state.accusedID.flatMap { state.player($0)?.name } ?? "?"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(Theme.gold)
            Text("라이어 검거!")
                .font(.title.weight(.heavy))
                .foregroundColor(.white)
            Text("'\(accusedName)'이(가) 라이어였습니다!\n하지만 제시어를 맞히면 라이어가 역전승합니다.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.8))

            if amILiar {
                Text("제시어를 골라보세요 — 단 한 번의 기회!")
                    .font(.footnote.bold())
                    .foregroundColor(Theme.shadow)

                if let choices = game.liarPrivate?.guessChoices {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                            GridItem(.flexible())], spacing: 10) {
                            ForEach(choices, id: \.self) { word in
                                Button {
                                    pendingWord = word
                                } label: {
                                    Text(word)
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color.white.opacity(0.1))
                                        )
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                } else {
                    ProgressView().tint(.white)
                }
            } else {
                Spacer()
                ProgressView().tint(.white)
                Text("라이어가 제시어를 추측하는 중…")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }
        }
        .padding(.top, 16)
        .confirmationDialog(
            "제시어를 '\(pendingWord ?? "")'(으)로 추측할까요?",
            isPresented: Binding(get: { pendingWord != nil },
                                 set: { if !$0 { pendingWord = nil } }),
            titleVisibility: .visible
        ) {
            Button("이 단어로 확정", role: .destructive) {
                if let word = pendingWord {
                    game.performLiar(.guessWord(word))
                }
                pendingWord = nil
            }
            Button("취소", role: .cancel) { pendingWord = nil }
        } message: {
            Text("단 한 번의 기회입니다!")
        }
    }
}

// MARK: - 결과

struct LiarGameOverView: View {
    @EnvironmentObject var game: GameViewModel
    let state: LiarGameState

    private var liarName: String {
        state.liarID.flatMap { state.player($0)?.name } ?? "?"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: state.liarWins == true ? "theatermasks.fill" : "person.3.fill")
                .font(.system(size: 48))
                .foregroundColor(state.liarWins == true ? Theme.shadow : Theme.moonlit)

            Text(state.liarWins == true ? "라이어 승리!" : "시민 승리!")
                .font(.largeTitle.weight(.heavy))
                .foregroundColor(state.liarWins == true ? Theme.shadow : Theme.moonlit)

            if let reason = state.winReason {
                Text(reason)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 8) {
                resultRow(label: "라이어", value: liarName, color: Theme.shadow)
                resultRow(label: "제시어", value: state.secretWord ?? "?", color: Theme.gold)
                if let guess = state.liarGuess {
                    resultRow(label: "라이어의 추측", value: guess,
                              color: guess == state.secretWord ? Theme.shadow : .white)
                }
            }
            .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 6) {
                    Text("투표 결과")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.6))
                    ForEach(state.players) { p in
                        let targetName = state.lastVotes[p.id.uuidString]
                            .flatMap { UUID(uuidString: $0) }
                            .flatMap { state.player($0)?.name } ?? "-"
                        PlayerRow(player: p,
                                  isMe: p.id == game.playerID,
                                  trailing: "→ \(targetName)")
                    }
                }
                .padding(.horizontal, 20)
            }

            if game.isHost {
                HStack(spacing: 12) {
                    Button { game.performLiar(.playAgain) } label: {
                        Text("같은 멤버로 다시 하기")
                    }
                    .buttonStyle(BigButtonStyle())
                    Button { game.leaveGame() } label: {
                        Text("방 닫기")
                    }
                    .buttonStyle(BigButtonStyle(color: Color.white.opacity(0.12),
                                                textColor: .white))
                }
                .padding(.horizontal, 20)
            } else {
                Button { game.leaveGame() } label: {
                    Text("나가기")
                }
                .buttonStyle(BigButtonStyle(color: Color.white.opacity(0.12),
                                            textColor: .white))
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 16)
    }

    private func resultRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.headline)
                .foregroundColor(color)
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .cardStyle()
    }
}
