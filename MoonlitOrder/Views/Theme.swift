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

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(player.isConnected ? Color.green : Color.red)
                .frame(width: 9, height: 9)

            Text(player.name)
                .fontWeight(isMe ? .bold : .regular)
                .foregroundColor(.white)

            if player.isHost {
                Image(systemName: "house.fill")
                    .font(.caption)
                    .foregroundColor(Theme.gold)
            }
            if isLeader {
                Image(systemName: "flag.fill")
                    .font(.caption)
                    .foregroundColor(Theme.moonlit)
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
                    .foregroundColor(player.hasActed ? .green : .white.opacity(0.4))
            }

            if !player.isConnected {
                Text("연결 끊김")
                    .font(.caption2)
                    .foregroundColor(.red.opacity(0.9))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .cardStyle()
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
                }
            }
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
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
    }

    private func circleColor(record: MissionRecord?) -> Color {
        guard let record else { return Color.white.opacity(0.12) }
        return record.succeeded ? Theme.moonlit.opacity(0.85) : Theme.shadow.opacity(0.85)
    }
}
