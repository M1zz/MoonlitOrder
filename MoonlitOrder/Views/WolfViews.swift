import SwiftUI

// MARK: - '달 없는 밤' 루트

struct WolfRootView: View {
    @EnvironmentObject var game: GameViewModel
    let state: WolfGameState

    var body: some View {
        if state.phase == .lobby {
            PartyLobbyView(title: "달 없는 밤",
                           subtitle: "도깨비가 숨어든 하룻밤, 단 한 번의 투표",
                           players: state.players,
                           range: WolfRules.playerRange) {
                game.performWolf(.startGame)
            }
        } else {
            WolfGameView(state: state)
        }
    }
}

// MARK: - 게임 화면

struct WolfGameView: View {
    @EnvironmentObject var game: GameViewModel
    let state: WolfGameState
    @State private var showLeaveConfirm = false

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
            }
        }
        .confirmationDialog("게임에서 나갈까요?",
                            isPresented: $showLeaveConfirm,
                            titleVisibility: .visible) {
            if game.isHost, state.phase != .gameOver {
                Button("게임 중단하고 대기실로") { game.performWolf(.abortToLobby) }
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
            Spacer()
            VStack(spacing: 2) {
                Text("달 없는 밤")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(phaseTitle)
                    .font(.caption)
                    .foregroundColor(Theme.gold)
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

    private var phaseTitle: String {
        switch state.phase {
        case .night:    return "🌙 밤 — 비밀 행동"
        case .day:      return "☀️ 낮 — 토론"
        case .voting:   return "🗳️ 처형 투표"
        case .gameOver: return "결과"
        case .lobby:    return ""
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch state.phase {
        case .night:    WolfNightView(state: state)
        case .day:      WolfDayView(state: state)
        case .voting:   WolfVotingView(state: state)
        case .gameOver: WolfGameOverView(state: state)
        case .lobby:    EmptyView()
        }
    }

    // MARK: 게임방법(데모) 단계 안내

    private var demoGuide: String? {
        guard game.isDemo else { return nil }
        switch state.phase {
        case .night:
            return "밤에는 각자 몰래 행동해요. 내 역할을 확인하고 행동을 마친 뒤, '다음'으로 봇들의 밤 행동을 진행하세요."
        case .day:
            return "밤사이 밤손님과 장난꾼이 카드를 바꿨을 수 있어요! 실제 게임에선 여기서 토론합니다. '다음'을 누르면 투표가 시작됩니다."
        case .voting:
            return "도깨비로 의심되는 사람을 먼저 지목해보고, '다음'으로 봇들의 표를 확인하세요. 최다 득표자가 추방됩니다."
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

// MARK: - 내 역할 카드 (공용)

struct WolfRoleCard: View {
    let info: WolfPrivateInfo
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 6 : 12) {
            Image(systemName: info.role.iconName)
                .font(.system(size: compact ? 24 : 40))
                .foregroundColor(info.role.isWolfTeam ? Theme.shadow : Theme.moonlit)
            Text(info.role.displayName)
                .font(compact ? .headline : .title.weight(.heavy))
                .foregroundColor(.white)
            if !compact {
                Text(info.role.summary)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.8))
            }
            if !info.packmateNames.isEmpty {
                Text("동료 도깨비: \(info.packmateNames.joined(separator: " · "))")
                    .font(.footnote.bold())
                    .foregroundColor(Theme.shadow)
            }
            if let result = info.nightResult {
                Text(result)
                    .font(.footnote.bold())
                    .foregroundColor(Theme.gold)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(compact ? 12 : 20)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

// MARK: - 밤

struct WolfNightView: View {
    @EnvironmentObject var game: GameViewModel
    let state: WolfGameState
    @State private var revealed = false
    @State private var seerMode: Int = 0          // 0: 플레이어, 1: 중앙 2장
    @State private var selected: [UUID] = []
    @State private var centerChoice: Int?         // 외톨이 도깨비의 중앙 카드 선택

    private var iActed: Bool { state.player(game.playerID)?.hasActed ?? false }
    private var actedCount: Int { state.players.filter { $0.hasActed }.count }
    private var others: [PlayerPublic] { state.players.filter { $0.id != game.playerID } }

    var body: some View {
        VStack(spacing: 14) {
            if !revealed {
                Spacer()
                Text("🌙")
                    .font(.system(size: 56))
                Text("밤이 되었습니다")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("다른 사람에게 화면이 보이지 않게 역할을 확인하세요")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.6))
                Button {
                    revealed = true
                } label: {
                    Label("내 역할 확인하기", systemImage: "eye.fill")
                }
                .buttonStyle(BigButtonStyle())
                .padding(.horizontal, 24)
                Spacer()
            } else if let info = game.wolfPrivate {
                ScrollView {
                    VStack(spacing: 14) {
                        WolfRoleCard(info: info)
                            .padding(.horizontal, 20)

                        if iActed {
                            Label("행동 완료! 다른 플레이어를 기다리는 중… \(actedCount)/\(state.players.count)",
                                  systemImage: "checkmark.seal.fill")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        } else {
                            nightActionArea(info: info)
                        }
                    }
                    .padding(.top, 4)
                }
            } else {
                ProgressView().tint(.white)
            }
        }
    }

    @ViewBuilder
    private func nightActionArea(info: WolfPrivateInfo) -> some View {
        switch info.role {
        case .villager:
            confirmButton(title: "확인했어요")

        case .werewolf:
            if info.isLoneWolf {
                VStack(spacing: 8) {
                    Text("당신은 유일한 도깨비! 중앙 카드 1장을 볼 수 있습니다")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { i in
                            Button {
                                centerChoice = i
                            } label: {
                                VStack {
                                    Image(systemName: "questionmark.square.fill")
                                        .font(.title)
                                    Text("중앙 \(i + 1)")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.1)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Theme.gold,
                                                lineWidth: centerChoice == i ? 2 : 0)
                                )
                                .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    if let choice = centerChoice {
                        confirmButton(title: "중앙 \(choice + 1)번 카드 확인하기") {
                            game.performWolf(.nightAction(targets: [], centers: [choice]))
                        }
                    }
                }
            } else {
                confirmButton(title: "동료를 확인했어요")
            }

        case .seer:
            VStack(spacing: 10) {
                Picker("", selection: $seerMode) {
                    Text("플레이어 1명 보기").tag(0)
                    Text("중앙 2장 보기").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                if seerMode == 0 {
                    playerPicker(limit: 1)
                    if let target = selected.first {
                        confirmButton(title: "'\(name(of: target))'의 카드 보기") {
                            game.performWolf(.nightAction(targets: [target], centers: []))
                        }
                    }
                } else {
                    confirmButton(title: "중앙 카드 2장 확인") {
                        game.performWolf(.nightAction(targets: [], centers: [0, 1]))
                    }
                }
            }

        case .robber:
            VStack(spacing: 8) {
                Text("카드를 훔칠 상대를 고르세요")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                playerPicker(limit: 1)
                if let target = selected.first {
                    confirmButton(title: "'\(name(of: target))'의 카드 훔치기") {
                        game.performWolf(.nightAction(targets: [target], centers: []))
                    }
                }
            }

        case .troublemaker:
            VStack(spacing: 8) {
                Text("카드를 서로 바꿀 두 사람을 고르세요 (\(selected.count)/2)")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                playerPicker(limit: 2)
                if selected.count == 2 {
                    confirmButton(title: "이 둘의 카드를 바꾸기") {
                        game.performWolf(.nightAction(targets: selected, centers: []))
                    }
                }
            }
        }
    }

    private func name(of id: UUID) -> String {
        state.player(id)?.name ?? "?"
    }

    private func confirmButton(title: String, action: (() -> Void)? = nil) -> some View {
        Button {
            if let action {
                action()
            } else {
                game.performWolf(.nightAction(targets: [], centers: []))
            }
        } label: {
            Text(title)
        }
        .buttonStyle(BigButtonStyle())
        .padding(.horizontal, 20)
    }

    /// 대상 선택만 담당한다. 제출은 별도의 확인 버튼에서 이루어진다 (오터치 방지).
    private func playerPicker(limit: Int) -> some View {
        VStack(spacing: 8) {
            ForEach(others) { p in
                Button {
                    if selected.contains(p.id) {
                        selected.removeAll { $0 == p.id }
                    } else {
                        selected.append(p.id)
                        if selected.count > limit { selected.removeFirst() }
                    }
                } label: {
                    HStack {
                        Image(systemName: selected.contains(p.id)
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selected.contains(p.id) ? Theme.gold : .white.opacity(0.4))
                        Text(p.name)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .cardStyle()
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - 낮 (토론)

struct WolfDayView: View {
    @EnvironmentObject var game: GameViewModel
    let state: WolfGameState

    var body: some View {
        VStack(spacing: 16) {
            Text("☀️")
                .font(.system(size: 48))
            Text("아침이 밝았습니다")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("밤사이 카드가 바뀌었을 수도 있습니다!\n토론으로 도깨비(현재 카드 기준)를 찾아내세요.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.75))

            if let info = game.wolfPrivate {
                WolfRoleCard(info: info, compact: true)
                    .padding(.horizontal, 20)
                Text("(밤이 시작될 때 당신의 역할 기준입니다)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.45))
            }

            if game.isDemo, let summary = game.demoNightSummary() {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("밤사이 일어난 일 (연습에서만 공개)", systemImage: "moon.zzz.fill")
                            .font(.footnote.bold())
                            .foregroundColor(Theme.gold)
                        Text(summary)
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("실제 게임에서는 아무것도 공개되지 않아요. 그래서 토론이 중요합니다!")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                    .padding(.horizontal, 20)
                }
            }

            Spacer()

            if game.isHost {
                Button {
                    game.performWolf(.startVoting)
                } label: {
                    Label("토론 끝! 투표 시작", systemImage: "hand.point.up.left.fill")
                }
                .buttonStyle(BigButtonStyle())
                .padding(.horizontal, 20)
            } else {
                Text("호스트가 투표를 시작하기를 기다리는 중…")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.top, 16)
    }
}

// MARK: - 투표

struct WolfVotingView: View {
    @EnvironmentObject var game: GameViewModel
    let state: WolfGameState
    @State private var pendingTarget: PlayerPublic?

    private var iVoted: Bool { state.player(game.playerID)?.hasActed ?? false }
    private var votedCount: Int { state.players.filter { $0.hasActed }.count }

    var body: some View {
        VStack(spacing: 14) {
            Text("도깨비라고 생각하는 사람을 지목하세요")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
            Text("최다 득표자가 추방됩니다 · 동률이면 모두 · 전원이 1표 이하면 아무도 추방되지 않아요")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.6))

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(state.players.filter { $0.id != game.playerID }) { p in
                        Button {
                            pendingTarget = p
                        } label: {
                            PlayerRow(player: p)
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
            "'\(pendingTarget?.name ?? "")'을(를) 추방 투표할까요?",
            isPresented: Binding(get: { pendingTarget != nil },
                                 set: { if !$0 { pendingTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("투표 확정", role: .destructive) {
                if let target = pendingTarget {
                    game.performWolf(.vote(targetID: target.id))
                }
                pendingTarget = nil
            }
            Button("취소", role: .cancel) { pendingTarget = nil }
        } message: {
            Text("제출한 표는 바꿀 수 없습니다.")
        }
    }
}

// MARK: - 결과

struct WolfGameOverView: View {
    @EnvironmentObject var game: GameViewModel
    let state: WolfGameState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: state.villageWins == true ? "sun.max.fill" : "flame.fill")
                .font(.system(size: 44))
                .foregroundColor(state.villageWins == true ? Theme.moonlit : Theme.shadow)

            Text(state.villageWins == true ? "마을의 승리!" : "도깨비의 승리!")
                .font(.title.weight(.heavy))
                .foregroundColor(state.villageWins == true ? Theme.moonlit : Theme.shadow)

            if let reason = state.winReason {
                Text(reason)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 24)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(state.players) { p in
                        roleRevealRow(p)
                    }
                    if let center = state.revealedCenter {
                        Text("중앙 카드: \(center.map { $0.displayName }.joined(separator: " · "))")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 20)
            }

            if game.isHost {
                HStack(spacing: 12) {
                    Button { game.performWolf(.playAgain) } label: {
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
        .padding(.top, 14)
    }

    private func roleRevealRow(_ p: PlayerPublic) -> some View {
        let original = state.originalRoles?[p.id.uuidString]
        let final = state.revealedRoles?[p.id.uuidString]
        let executed = state.executedIDs.contains(p.id)
        let votes = state.lastVotes.values.filter { $0 == p.id.uuidString }.count
        let roleText: String = {
            guard let final else { return "?" }
            if let original, original != final {
                return "\(original.displayName) → \(final.displayName)"
            }
            return final.displayName
        }()

        return HStack(spacing: 8) {
            Text(executed ? "💀" : "•")
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
            Text(roleText)
                .font(.subheadline.bold())
                .foregroundColor(final?.isWolfTeam == true ? Theme.shadow : Theme.moonlit)
            Text("\(votes)표")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .cardStyle()
    }
}
