import SwiftUI

/// 게임방법(데모) 시작 시 가장 먼저 보여주는 게임 목적 · 승리 조건 안내.
/// '연습 시작하기'를 누르면 봇들과 함께하는 단계별 연습으로 넘어간다.
struct DemoIntroView: View {
    @EnvironmentObject var game: GameViewModel

    private var kind: GameViewModel.GameKind { game.gameKind }

    private var icon: String {
        switch kind {
        case .moonlit: return "moon.stars.fill"
        case .liar:    return "theatermasks.fill"
        case .wolf:    return "flame.fill"
        case .sketch:  return "paintbrush.pointed.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .moonlit: return Theme.gold
        case .liar:    return Theme.moonlit
        case .wolf:    return Theme.shadow
        case .sketch:  return Theme.mint
        }
    }

    private var objective: String {
        switch kind {
        case .moonlit:
            return "모든 플레이어는 달빛 결사(선) 또는 그림자(악) 진영에 몰래 배정됩니다. 원정 미션을 최대 5번 진행하는 동안, 대화와 투표 기록만으로 누가 그림자인지 추리해야 합니다."
        case .liar:
            return "라이어 한 명만 빼고 전원이 같은 제시어를 받습니다. 돌아가며 제시어를 한 마디씩 설명하며 서로가 진짜인지 확인하세요. 라이어는 제시어를 모른 채 아는 척 연기해야 합니다."
        case .wolf:
            return "마을에 도깨비가 숨어들었습니다! 밤에 각자 비밀 행동으로 정보를 얻거나 카드를 몰래 뒤바꾸고, 낮에 토론한 뒤 단 한 번의 투표로 추방할 사람을 정합니다. 밤사이 카드가 바뀔 수 있어 승패는 '최종 카드' 기준입니다."
        case .sketch:
            return "매 라운드 한 명이 '화가'가 되어 제시어를 그림으로만 표현합니다. 나머지는 그림을 보고 채팅으로 정답을 맞혀요. 글자나 숫자는 쓸 수 없습니다. 모든 참가자가 한 번씩 화가를 맡으면 게임이 끝납니다."
        }
    }

    private var winConditions: [(team: String, color: Color, text: String)] {
        switch kind {
        case .moonlit:
            return [
                ("달빛 결사 (선)", Theme.moonlit,
                 "미션 3회 성공. 단, 마지막에 암살자가 예언자를 정확히 지목하면 역전패하니 예언자는 끝까지 정체를 숨겨야 해요."),
                ("그림자 (악)", Theme.shadow,
                 "미션 3회 실패 · 원정대 5회 연속 부결 · 예언자 암살 성공 — 셋 중 하나면 승리."),
            ]
        case .liar:
            return [
                ("시민", Theme.moonlit,
                 "투표로 라이어를 정확히 지목하고, 라이어가 제시어 추측에 실패하면 승리."),
                ("라이어", Theme.shadow,
                 "표가 갈리거나 엉뚱한 사람이 지목되면 승리. 잡히더라도 제시어를 맞히면 역전승!"),
            ]
        case .wolf:
            return [
                ("마을", Theme.moonlit,
                 "도깨비(최종 카드 기준)를 추방하면 승리. 도깨비가 모두 중앙 카드에 있다면, 아무도 추방하지 않아야 승리."),
                ("도깨비", Theme.shadow,
                 "도깨비가 한 명도 추방되지 않으면 승리 — 애꿎은 사람이 추방돼도 이겨요."),
            ]
        case .sketch:
            return [
                ("맞히는 사람", Theme.mint,
                 "그림을 보고 제시어를 빨리 맞힐수록 높은 점수! 정답을 맞히면 점수를 얻습니다."),
                ("화가", Theme.gold,
                 "내가 그린 그림을 많은 사람이 맞힐수록 점수를 얻어요. 누구나 알아볼 수 있게 그리는 게 관건!"),
            ]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: icon)
                        .font(.system(size: 44))
                        .foregroundColor(color)
                        .padding(.top, 28)
                    Text("게임방법")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.5))
                    Text(kind.displayName)
                        .font(.title.weight(.heavy))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("게임의 목적", systemImage: "target")
                            .font(.headline)
                            .foregroundColor(Theme.gold)
                        Text(objective)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                    .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 12) {
                        Label("승리 조건", systemImage: "trophy.fill")
                            .font(.headline)
                            .foregroundColor(Theme.gold)
                        ForEach(winConditions, id: \.team) { condition in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(condition.team)
                                    .font(.subheadline.bold())
                                    .foregroundColor(condition.color)
                                Text(condition.text)
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                    .padding(.horizontal, 20)

                    Text("이제 봇들과 함께 한 단계씩 직접 해보며 익혀볼 거예요.\n각 단계마다 안내가 표시되고, '다음' 버튼으로 진행합니다.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 16)
            }

            VStack(spacing: 10) {
                Button {
                    game.showDemoIntro = false
                } label: {
                    Text("연습 시작하기")
                }
                .buttonStyle(BigButtonStyle())

                Button {
                    game.leaveGame()
                } label: {
                    Text("홈으로")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}
