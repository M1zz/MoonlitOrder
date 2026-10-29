import SwiftUI

/// 앱 전체 색/스타일. 다크 판타지 무드의 오리지널 테마.
enum Theme {
    static let background = LinearGradient(
        colors: [Color(red: 0.06, green: 0.07, blue: 0.15),
                 Color(red: 0.13, green: 0.09, blue: 0.24)],
        startPoint: .top, endPoint: .bottom)

    static let card = Color.white.opacity(0.07)
    static let cardStroke = Color.white.opacity(0.12)

    static let moonlit = Color(red: 0.45, green: 0.75, blue: 1.0)   // 달빛(선) — 청색
    static let shadow  = Color(red: 0.95, green: 0.35, blue: 0.42)  // 그림자(악) — 적색
    static let gold    = Color(red: 0.95, green: 0.78, blue: 0.35)
    static let mint    = Color(red: 0.35, green: 0.82, blue: 0.72)   // 달빛 화실 — 민트

    static func teamColor(_ team: Team) -> Color {
        team == .moonlit ? moonlit : shadow
    }
}

// MARK: - 공용 컴포넌트

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Theme.cardStroke, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardBackground()) }
}

struct BigButtonStyle: ButtonStyle {
    var color: Color = Theme.gold
    var textColor: Color = .black

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color)
            )
            .foregroundColor(textColor)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct PlayerRow: View {
    let player: PlayerPublic
    var isMe: Bool = false
    var isLeader: Bool = false
    var showActed: Bool = false
    var trailing: String? = nil
    var onKick: (() -> Void)? = nil   // 호스트 전용: 내보내기

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(player.isConnected ? Color.green : Color.red)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)   // 끊기면 '연결 끊김' 글자가 함께 뜬다

            Text(player.name)
                .fontWeight(isMe ? .bold : .regular)
                .foregroundColor(.white)

            if player.isHost {
                Image(systemName: "house.fill")
                    .font(.caption)
                    .foregroundColor(Theme.gold)
                    .accessibilityLabel("방장")
            }
            if isLeader {
                Image(systemName: "flag.fill")
                    .font(.caption)
                    .foregroundColor(Theme.moonlit)
                    .accessibilityLabel("리더")
            }
            if isMe {
                Text("나")
                    .font(.caption2).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.gold.opacity(0.25)))
                    .foregroundColor(Theme.gold)
            }

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.subheadline).bold()
                    .foregroundColor(.white.opacity(0.9))
            } else if showActed {
                Image(systemName: player.hasActed ? "checkmark.circle.fill" : "hourglass")
                    .foregroundColor(player.hasActed ? .green : .white.opacity(0.6))
                    .accessibilityLabel(player.hasActed ? String(localized: "완료") : String(localized: "기다리는 중"))
            }

            if !player.isConnected {
                Text("연결 끊김")
                    .font(.caption2)
                    .foregroundColor(.red.opacity(0.9))
            }

            if let onKick {
                Button(action: onKick) {
                    Image(systemName: "person.fill.xmark")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.9))
                        .padding(6)
                        .background(Circle().fill(Color.red.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "\(player.name) 내보내기"))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .cardStyle()
        // 한 사람을 한 줄로 읽는다. 내보내기 단추는 따로 누를 수 있게 남긴다.
        .accessibilityElement(children: onKick == nil ? .combine : .contain)
    }
}

/// 게임 중 연결이 끊긴 플레이어의 재접속을 기다리는 배너.
/// 호스트에게는 돌아오지 않는 플레이어를 추방하는 버튼을 함께 보여준다.
struct ReconnectWaitBanner: View {
    @EnvironmentObject var game: GameViewModel
    let disconnected: [PlayerPublic]
    @State private var kickTarget: PlayerPublic?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // 주황 띠 위 흰 글씨는 대비가 모자라 검정으로 쓴다
                ProgressView().tint(.black).scaleEffect(0.8)
                Text("\(disconnected.map { $0.name }.joined(separator: ", ")) 님의 재접속을 기다리는 중입니다.")
                    .font(.caption)
                    .foregroundColor(.black)
            }
            if game.isHost {
                HStack(spacing: 8) {
                    ForEach(disconnected) { p in
                        Button {
                            kickTarget = p
                        } label: {
                            Label("\(p.name) 내보내기", systemImage: "person.fill.xmark")
                                .font(.caption2.bold())
                                .padding(.vertical, 5)
                                .padding(.horizontal, 10)
                                .background(Capsule().fill(Color.black.opacity(0.12)))
                                .foregroundColor(.black)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.orange.opacity(0.9)))
        .padding(.top, 4)
        .padding(.horizontal, 16)
        .confirmationDialog(kickTarget.map { String(localized: "\($0.name) 님을 내보낼까요?") } ?? "",
                            isPresented: Binding(get: { kickTarget != nil },
                                                 set: { if !$0 { kickTarget = nil } }),
                            titleVisibility: .visible,
                            presenting: kickTarget) { target in
            Button("내보내기", role: .destructive) { game.kickPlayer(target.id) }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("내보낸 뒤에도 진행 중인 게임은 남은 인원으로 계속됩니다.")
        }
    }
}

/// 화면 상단 미션 트랙: 5개 원 + 부결 카운터
struct MissionTrackView: View {
    let state: PublicGameState

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ForEach(0..<GameRules.missionCount, id: \.self) { i in
                    missionCircle(index: i)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(missionLabel(index: i))
                }
            }
            // 원은 크기가 정해진 요약판이라 아주 큰 글씨에서는 더 키우지 않는다 (같은 내용이 단계 화면에 글로 나온다)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            HStack(spacing: 6) {
                Text("부결")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                ForEach(0..<GameRules.maxRejections, id: \.self) { i in
                    Circle()
                        .fill(i < state.voteTrack ? Theme.shadow : Color.white.opacity(0.15))
                        .frame(width: 7, height: 7)
                }
                Text("\(state.voteTrack)/\(GameRules.maxRejections)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    @ViewBuilder
    private func missionCircle(index: Int) -> some View {
        let record = state.missionHistory.first { $0.round == index + 1 }
        let isCurrent = state.round == index + 1 && record == nil
        let size: CGFloat = 44

        ZStack {
            Circle()
                .fill(circleColor(record: record))
                .frame(width: size, height: size)
            if isCurrent {
                Circle()
                    .stroke(Theme.gold, lineWidth: 2)
                    .frame(width: size + 6, height: size + 6)
            }
            if let record {
                Image(systemName: record.succeeded ? "checkmark" : "xmark")
                    .font(.headline)
                    .foregroundColor(.white)
            } else {
                VStack(spacing: 0) {
                    Text("\(state.teamSizes.indices.contains(index) ? state.teamSizes[index] : 0)")
                        .font(.subheadline).bold()
                        .foregroundColor(.white)
                    if state.failsRequired.indices.contains(index),
                       state.failsRequired[index] > 1 {
                        Text("실패2")
                            .font(.caption2)
                            .minimumScaleFactor(0.5)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
    }

    /// VoiceOver 가 읽는 원정 한 칸: 몇 번째인지, 결과 또는 인원·실패 조건
    private func missionLabel(index: Int) -> String {
        let round = index + 1
        let record = state.missionHistory.first { $0.round == round }
        var parts: [String] = []
        if let record {
            parts.append(String(localized: "\(round)번째 원정"))
            parts.append(record.succeeded ? String(localized: "원정 성공!") : String(localized: "원정 실패…"))
        } else {
            parts.append(state.round == round ? String(localized: "\(round)번째 원정 진행 중")
                                              : String(localized: "\(round)번째 원정"))
            if state.teamSizes.indices.contains(index) {
                parts.append(String(localized: "원정대 \(state.teamSizes[index])명"))
            }
            if state.failsRequired.indices.contains(index), state.failsRequired[index] > 1 {
                parts.append(String(localized: "이번 원정은 실패 카드가 \(state.failsRequired[index])장 나와야 실패합니다"))
            }
        }
        return parts.joined(separator: ", ")
    }

    private func circleColor(record: MissionRecord?) -> Color {
        guard let record else { return Color.white.opacity(0.12) }
        return record.succeeded ? Theme.moonlit.opacity(0.85) : Theme.shadow.opacity(0.85)
    }
}
