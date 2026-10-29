//
//  TipAskMoments.swift
//  MoonlitOrder
//
//  "계속 만들 수 있게 힘을 보태 주세요" 카드. 친구들과 **한 판을 끝까지 마친 직후** 결과 화면에 선다.
//
//  누구에게: 모두(무료 앱이라 페이월이 없다).
//  언제: 이 앱으로 친구들과 즐긴 판 수가 숫자로 보이는 순간. 방금 판이 끝나 숫자가 막 하나 늘어난 때다.
//  얼마나 드물게: LeeoKit 의 규칙(`LeeoTipAskPolicy`). 물으면 60일 쉬고, 낸 사람은 180일, '다음에' 세 번이면 끝.
//
//  ⚠️ 모달이 아니다. 결과 목록 맨 위에 한 장 선다.
//

import SwiftUI
import LeeoKit

enum MoonlitOrderTipMoments {
    /// 끝까지 마친 판 수. 큰 것부터.
    static let games = [100, 30, 10]

    private static let finishedGamesKey = "moonorder.finishedGames"

    /// 친구들과 끝까지 마친 판 수(연습 판 제외).
    static var finishedGames: Int { UserDefaults.standard.integer(forKey: finishedGamesKey) }

    /// 한 판이 결과 화면에 닿았다. 연습(데모) 판은 세지 않는다.
    static func recordFinishedGame() {
        UserDefaults.standard.set(finishedGames + 1, forKey: finishedGamesKey)
    }

    /// 넘어선 순간, **인상적인 것부터**.
    static func reached(finishedGames count: Int) -> [LeeoTipMoment] {
        games.filter { count >= $0 }.map { threshold in
            LeeoTipMoment(id: "games.\(threshold)",
                          message: String(localized: "친구들과 \(count)판을 끝까지 함께했어요",
                                          comment: "Tip ask card: how many party games this person finished with friends"))
        }
    }

    static var reachedNow: [LeeoTipMoment] { reached(finishedGames: finishedGames) }
}

/// 네 게임의 결과 화면이 함께 쓰는 부탁 자리.
struct GameOverTipAsk: View {
    @EnvironmentObject var game: GameViewModel

    var body: some View {
        if !game.isDemo {
            LeeoTipAskSlot<MoonlitOrderSpec>(tipJar: MoonlitOrderSpec.tipJar,
                                             reached: MoonlitOrderTipMoments.reachedNow)
        }
    }
}
