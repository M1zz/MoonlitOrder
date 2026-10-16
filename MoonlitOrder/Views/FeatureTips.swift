//
//  FeatureTips.swift
//  MoonlitOrder
//
//  "이런 것도 있어요"를 필요한 사람에게만 알려주는 TipKit 팁.
//
//  원칙 — 팁은 광고가 아니라 도움이어야 한다:
//   • 이미 그 기능을 써 봤으면 뜨지 않는다(`hasPracticed` 로 스스로 사라진다).
//   • 한 화면에 하나씩. 표시 빈도는 TipKit 이 관리한다(MoonlitOrderApp 의 Tips.configure).
//

import SwiftUI
import TipKit

/// 게임 메뉴에서 "봇과 연습"을 알려준다. 친구들 앞에서 규칙을 몰라 헤매기 쉬운데,
/// 이 앱에는 혼자서 봇들과 한 단계씩 해 보는 연습 판이 있다는 걸 모르는 사람이 많다.
struct PracticeTip: Tip {
    /// 어떤 게임이든 연습 판을 한 번 열어 봤으면 다시 뜨지 않는다.
    @Parameter static var hasPracticed: Bool = false

    var title: Text { Text("처음이라면 봇과 먼저 연습해 보세요") }
    var message: Text? { Text("혼자서도 봇들과 한 판을 끝까지 해 보며 규칙을 익힐 수 있어요.") }
    var image: Image? { Image(systemName: "person.2.wave.2") }

    var rules: [Rule] {
        #Rule(Self.$hasPracticed) { $0 == false }
    }
}

enum FeatureTips {
    /// 연습 판을 실제로 열었다 — 연습 팁을 더는 띄우지 않는다.
    static func markPracticed() {
        PracticeTip.hasPracticed = true
    }
}
