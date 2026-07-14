import SwiftUI

// MARK: - 색/스타일 헬퍼 (UI 전용)

enum SketchStyle {
    static func color(_ i: Int) -> Color {
        guard SketchRules.palette.indices.contains(i) else { return .black }
        let c = SketchRules.palette[i]
        return Color(red: c.r, green: c.g, blue: c.b)
    }
    static var boardColor: Color {
        let c = SketchRules.boardColor
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}

// MARK: - 루트

struct SketchRootView: View {
    @EnvironmentObject var game: GameViewModel
    let state: SketchGameState

    var body: some View {
        if state.phase == .lobby {
            PartyLobbyView(title: "달빛 화실",
                           subtitle: "한 명이 그리고 나머지가 맞히는 그림 놀이",
                           players: state.players,
                           range: SketchRules.playerRange) {
                game.performSketch(.startGame)
            }
        } else {
            SketchGameView(state: state)
        }
    }
}

// MARK: - 게임 화면

struct SketchGameView: View {
    @EnvironmentObject var game: GameViewModel
    let state: SketchGameState
    @State private var showLeaveConfirm = false

    private var isDrawer: Bool { state.drawerID == game.playerID }

    var body: some View {
        VStack(spacing: 12) {
            header

            if let guide = demoGuide {
                demoGuideCard(guide)
            }

            phaseContent
                .frame(maxHeight: .infinity)

            footer
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
                Button("게임 중단하고 대기실로") { game.performSketch(.abortToLobby) }
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
            Button { showLeaveConfirm = true } label: {
                Image(systemName: "xmark").foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            VStack(spacing: 2) {
                if state.phase == .gameOver {
                    Text("게임 종료")
                        .font(.headline).foregroundColor(.white)
                } else {
                    Text("\(state.round) / \(state.totalRounds) 라운드")
                        .font(.headline).foregroundColor(.white)
                    if let drawer = state.drawer {
                        Label(isDrawer ? "내가 화가!" : "화가: \(drawer.name)",
                              systemImage: "paintbrush.pointed.fill")
                            .font(.caption)
                            .foregroundColor(Theme.mint)
                    }
                }
            }
            Spacer()
            if let seconds = state.phaseSeconds, state.phase != .gameOver {
                PhaseTimerView(seconds: seconds, startedAt: state.phaseStartedAt)
            } else {
                Image(systemName: "xmark").opacity(0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: 단계별 화면

    @ViewBuilder
    private var phaseContent: some View {
        switch state.phase {
        case .wordSelect:  SketchWordSelectView(state: state)
        case .drawing:     SketchDrawingView(state: state)
        case .roundResult: SketchRoundResultView(state: state)
        case .gameOver:    SketchGameOverView(state: state)
        case .lobby:       EmptyView()
        }
    }

    // MARK: 하단

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            // 화가/호스트: 라운드 수동 종료
            if state.phase == .drawing, isDrawer || game.isHost {
                Button {
                    game.performSketch(.endRound)
                } label: {
                    Label(isDrawer ? "다 그렸어요" : "라운드 넘기기",
                          systemImage: "flag.checkered")
                        .font(.subheadline.bold())
                        .padding(.vertical, 10).padding(.horizontal, 16)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .foregroundColor(.white)
                }
            }
            // 데모: 봇 진행
            if game.isDemo, [.drawing, .roundResult].contains(state.phase) {
                Button {
                    game.advanceDemo()
                } label: {
                    Label("다음", systemImage: "forward.fill")
                        .font(.subheadline.bold())
                        .padding(.vertical, 10).padding(.horizontal, 18)
                        .background(Capsule().fill(Theme.gold.opacity(0.25)))
                        .foregroundColor(Theme.gold)
                }
            }
        }
    }

    // MARK: 게임방법(데모) 안내

    private var demoGuide: String? {
        guard game.isDemo else { return nil }
        switch state.phase {
        case .wordSelect:
            return "당신이 이번 화가예요! 제시어 3개 중 그리기 쉬운 걸 하나 고르세요."
        case .drawing:
            return "제시어를 그림으로 표현하세요. 글자·숫자는 금지! 다 그렸으면 '다음'을 눌러 봇들의 추측을 지켜보세요."
        case .roundResult:
            return "라운드 결과입니다. 빨리 맞힌 사람일수록 높은 점수, 화가는 맞힌 사람이 많을수록 점수를 얻어요. '다음'으로 최종 순위를 확인하세요."
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
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.gold.opacity(0.12)))
        .padding(.horizontal, 16)
    }
}

// MARK: - 제시어 고르기

struct SketchWordSelectView: View {
    @EnvironmentObject var game: GameViewModel
    let state: SketchGameState

    private var isDrawer: Bool { state.drawerID == game.playerID }

    var body: some View {
        VStack(spacing: 18) {
            if isDrawer {
                Image(systemName: "paintbrush.pointed.fill")
                    .font(.system(size: 40)).foregroundColor(Theme.mint)
                Text("제시어를 고르세요")
                    .font(.title2.bold()).foregroundColor(.white)
                Text("다른 사람에게 보이지 않게! 그리기 쉬운 걸 고르면 유리해요.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 24)

                if let choices = game.sketchPrivate?.wordChoices {
                    VStack(spacing: 10) {
                        ForEach(choices, id: \.self) { word in
                            Button {
                                game.performSketch(.chooseWord(word))
                            } label: {
                                HStack {
                                    Text(SketchRules.category(of: word))
                                        .font(.caption).foregroundColor(.white.opacity(0.5))
                                        .frame(width: 44, alignment: .leading)
                                    Text(word)
                                        .font(.title3.bold()).foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(Theme.mint)
                                }
                                .padding(.vertical, 16).padding(.horizontal, 18)
                                .cardStyle()
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                } else {
                    ProgressView().tint(.white)
                }
            } else {
                Spacer()
                ProgressView().tint(.white)
                Text("\(state.drawer?.name ?? "화가")님이 제시어를 고르는 중…")
                    .font(.subheadline).foregroundColor(.white.opacity(0.75))
                Text("잠시 후 그림이 그려지기 시작해요.")
                    .font(.caption).foregroundColor(.white.opacity(0.5))
                Spacer()
            }
        }
        .padding(.top, 16)
    }
}

// MARK: - 그리기 / 맞히기

struct SketchDrawingView: View {
    @EnvironmentObject var game: GameViewModel
    let state: SketchGameState

    @State private var live: [SketchPoint] = []
    @State private var colorIndex = 0
    @State private var width = SketchRules.brushWidths[1]
    @State private var guessText = ""
    @FocusState private var guessFocused: Bool

    private var isDrawer: Bool { state.drawerID == game.playerID }
    private var iSolved: Bool { state.solvedIDs.contains(game.playerID) }
    private var solvedCount: Int { state.solvedIDs.count }

    var body: some View {
        VStack(spacing: 10) {
            hintHeader

            SketchCanvasView(
                strokes: state.strokes,
                live: live,
                liveColorIndex: colorIndex,
                liveWidth: width,
                isDrawer: isDrawer,
                onChanged: { p in live.append(p) },
                onEnded: {
                    if !live.isEmpty {
                        game.performSketch(.addStroke(
                            SketchStroke(points: live, colorIndex: colorIndex, width: width)))
                        live = []
                    }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)

            chatStrip

            if isDrawer {
                drawerToolbar
            } else {
                guessBar
            }
        }
    }

    // MARK: 힌트 헤더

    private var hintHeader: some View {
        HStack {
            if isDrawer {
                if let word = game.sketchPrivate?.word {
                    HStack(spacing: 6) {
                        Text("제시어").font(.caption).foregroundColor(.white.opacity(0.5))
                        Text(word).font(.headline.bold()).foregroundColor(Theme.gold)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Text(state.category).font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.mint.opacity(0.2)))
                        .foregroundColor(Theme.mint)
                    Text(String(repeating: "○ ", count: max(state.wordLength, 0)))
                        .font(.headline).foregroundColor(.white.opacity(0.85))
                    Text("\(state.wordLength)글자")
                        .font(.caption).foregroundColor(.white.opacity(0.5))
                }
            }
            Spacer()
            Label("\(solvedCount)/\(state.guesserCount) 정답",
                  systemImage: "checkmark.seal.fill")
                .font(.caption).foregroundColor(.green)
        }
        .padding(.horizontal, 18)
    }

    // MARK: 채팅 스트립 (최근 몇 줄)

    private var chatStrip: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.chat) { line in
                        HStack(spacing: 6) {
                            Text(line.name)
                                .font(.caption.bold())
                                .foregroundColor(line.correct ? .green : Theme.mint)
                            Text(line.text)
                                .font(.caption)
                                .foregroundColor(line.correct ? .green : .white.opacity(0.85))
                            Spacer(minLength: 0)
                        }
                        .id(line.id)
                    }
                    if state.chat.isEmpty {
                        Text(isDrawer ? "사람들의 추측이 여기에 표시돼요."
                                      : "그림을 보고 정답을 맞혀보세요!")
                            .font(.caption).foregroundColor(.white.opacity(0.4))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .frame(height: 84)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            .padding(.horizontal, 16)
            .onChange(of: state.chat.count) { _ in
                if let last = state.chat.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    // MARK: 화가 도구

    private var drawerToolbar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SketchRules.palette.indices, id: \.self) { i in
                        Button {
                            colorIndex = i
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(SketchStyle.color(i))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                                if i == SketchRules.eraserIndex {
                                    Image(systemName: "eraser.fill")
                                        .font(.caption2).foregroundColor(.gray)
                                }
                                if colorIndex == i {
                                    Circle().stroke(Theme.gold, lineWidth: 3)
                                        .frame(width: 36, height: 36)
                                }
                            }
                            .frame(width: 38, height: 38)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 14) {
                ForEach(SketchRules.brushWidths, id: \.self) { w in
                    Button { width = w } label: {
                        Circle()
                            .fill(width == w ? Theme.gold : Color.white.opacity(0.25))
                            .frame(width: w + 6, height: w + 6)
                            .frame(width: 32, height: 32)
                    }
                }

                Divider().frame(height: 22).overlay(Color.white.opacity(0.2))

                Button { game.performSketch(.undoStroke) } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundColor(.white).frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .disabled(state.strokes.isEmpty)
                .opacity(state.strokes.isEmpty ? 0.4 : 1)

                Button { game.performSketch(.clearCanvas) } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.white).frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .disabled(state.strokes.isEmpty)
                .opacity(state.strokes.isEmpty ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: 추측 입력

    @ViewBuilder
    private var guessBar: some View {
        if iSolved {
            Label("정답! 다른 사람을 기다리는 중…", systemImage: "checkmark.seal.fill")
                .font(.subheadline).foregroundColor(.green)
                .padding(.bottom, 4)
        } else {
            HStack(spacing: 10) {
                TextField("정답 입력…", text: $guessText)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                    .foregroundColor(.white)
                    .focused($guessFocused)
                    .submitLabel(.send)
                    .onSubmit(submitGuess)

                Button(action: submitGuess) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.black)
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.mint))
                }
                .disabled(guessText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
        }
    }

    private func submitGuess() {
        let t = guessText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        game.performSketch(.guess(t))
        guessText = ""
    }
}

// MARK: - 캔버스

struct SketchCanvasView: View {
    let strokes: [SketchStroke]
    var live: [SketchPoint] = []
    var liveColorIndex: Int = 0
    var liveWidth: Double = 9
    var isDrawer: Bool = false
    var onChanged: ((SketchPoint) -> Void)? = nil
    var onEnded: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { ctx, canvasSize in
                for stroke in strokes { drawStroke(stroke, in: ctx, size: canvasSize) }
                if !live.isEmpty {
                    drawStroke(SketchStroke(points: live,
                                            colorIndex: liveColorIndex,
                                            width: liveWidth),
                               in: ctx, size: canvasSize)
                }
            }
            .background(SketchStyle.boardColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(isDrawer ? drag(size: size) : nil)
        }
    }

    private func drag(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let nx = min(max(v.location.x, 0), size.width) / max(size.width, 1)
                let ny = min(max(v.location.y, 0), size.height) / max(size.height, 1)
                onChanged?(SketchPoint(x: Double(nx), y: Double(ny)))
            }
            .onEnded { _ in onEnded?() }
    }

    private func drawStroke(_ s: SketchStroke, in ctx: GraphicsContext, size: CGSize) {
        guard let first = s.points.first else { return }
        let color = SketchStyle.color(s.colorIndex)
        let start = CGPoint(x: first.x * size.width, y: first.y * size.height)

        if s.points.count == 1 {
            let r = s.width / 2
            let rect = CGRect(x: start.x - r, y: start.y - r, width: s.width, height: s.width)
            ctx.fill(Path(ellipseIn: rect), with: .color(color))
            return
        }

        var path = Path()
        path.move(to: start)
        for pt in s.points.dropFirst() {
            path.addLine(to: CGPoint(x: pt.x * size.width, y: pt.y * size.height))
        }
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: s.width, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - 라운드 결과

struct SketchRoundResultView: View {
    @EnvironmentObject var game: GameViewModel
    let state: SketchGameState

    private var isLast: Bool { state.round >= state.totalRounds }

    var body: some View {
        VStack(spacing: 16) {
            Text("제시어는")
                .font(.subheadline).foregroundColor(.white.opacity(0.6))
            Text(state.revealedWord ?? "-")
                .font(.largeTitle.weight(.heavy)).foregroundColor(Theme.gold)
            if let drawer = state.drawer {
                Text("화가: \(drawer.name)")
                    .font(.caption).foregroundColor(Theme.mint)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(state.players) { p in
                        let gain = state.lastRoundGains[p.id.uuidString] ?? 0
                        let solved = state.solvedIDs.contains(p.id)
                        let isDrawer = p.id == state.drawerID
                        PlayerRow(
                            player: p,
                            isMe: p.id == game.playerID,
                            trailing: gain > 0 ? "+\(gain)" : (isDrawer ? "화가" : (solved ? "정답" : "―"))
                        )
                    }
                }
                .padding(.horizontal, 20)
            }

            if game.isHost {
                Button {
                    game.performSketch(.continueRound)
                } label: {
                    Text(isLast ? "최종 순위 보기" : "다음 라운드")
                }
                .buttonStyle(BigButtonStyle())
                .padding(.horizontal, 20)
            } else {
                Text("호스트가 다음으로 넘기기를 기다리는 중…")
                    .font(.subheadline).foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.top, 16)
    }
}

// MARK: - 게임 종료 / 순위

struct SketchGameOverView: View {
    @EnvironmentObject var game: GameViewModel
    let state: SketchGameState

    private var winners: [String] { state.winnerNames }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 48)).foregroundColor(Theme.gold)
            Text(winners.isEmpty ? "게임 종료" : "\(winners.joined(separator: ", ")) 승리!")
                .font(.largeTitle.weight(.heavy))
                .foregroundColor(Theme.gold)
                .multilineTextAlignment(.center)
            Text("최고 점수 \(state.topScore)점")
                .font(.subheadline).foregroundColor(.white.opacity(0.7))

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(state.ranking.enumerated()), id: \.element.player.id) { idx, entry in
                        HStack(spacing: 12) {
                            Text("\(idx + 1)")
                                .font(.headline.bold())
                                .frame(width: 26)
                                .foregroundColor(idx == 0 ? Theme.gold : .white.opacity(0.7))
                            PlayerRow(player: entry.player,
                                      isMe: entry.player.id == game.playerID,
                                      trailing: "\(entry.score)점")
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            if game.isHost {
                HStack(spacing: 12) {
                    Button { game.performSketch(.playAgain) } label: {
                        Text("같은 멤버로 다시")
                    }
                    .buttonStyle(BigButtonStyle())
                    Button { game.leaveGame() } label: {
                        Text("방 닫기")
                    }
                    .buttonStyle(BigButtonStyle(color: Color.white.opacity(0.12), textColor: .white))
                }
                .padding(.horizontal, 20)
            } else {
                Button { game.leaveGame() } label: {
                    Text("나가기")
                }
                .buttonStyle(BigButtonStyle(color: Color.white.opacity(0.12), textColor: .white))
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 16)
    }
}
