//
//  FoldPanes.swift
//  MoonlitOrder
//
//  아이폰 듀오를 폈을 때 결과 쪽(가로면 오른쪽, 세로면 위)에 무엇이 서는가.
//  자리 셈 · 시트 가드는 LeeoKit Fold 모듈이 하고, 여기는 이 앱의 짝만 정한다.
//
//  - 접혀 있거나 보통 아이폰이면 이 판은 그려지지 않는다. 지금 화면 그대로다.
//  - 첫 화면: 왼쪽(아래)에서 게임을 고르면 오른쪽(위)에 그 게임의 소개와 방 만들기 · 참가 · 연습이 선다.
//    접혀 있을 때 시트로 뜨던 `GameMenuView` 를 그대로 쓴다.
//  - 방에 들어가면 오른쪽(위)은 그 방의 현황: 참가자와 연결 상태, 달빛 결사면 원정 트랙,
//    달빛 화실이면 점수. 손은 고르는 쪽에서 투표 · 지명을 하고 눈은 현황을 본다.
//    역할 · 제시어 같은 비밀은 이 판에 두지 않는다(펼친 화면은 옆 사람에게도 보인다).
//

import SwiftUI
import LeeoKit

/// 펼친 화면의 결과 쪽 판.
struct FoldResultPane: View {
    @EnvironmentObject var game: GameViewModel
    /// 첫 화면에서 고른 게임. 아직 안 골랐으면 맨 위의 달빛 결사.
    let menuKind: GameViewModel.GameKind

    var body: some View {
        switch game.mode {
        case .idle, .browsing, .connecting:
            GameMenuView(kind: game.browseFilter ?? menuKind)
        case .hosting, .playing:
            RoomStatusPane()
        }
    }
}

/// 방의 현황. 누가 있고 누가 끊겼는지, 그리고 그 게임의 진행판.
private struct RoomStatusPane: View {
    @EnvironmentObject var game: GameViewModel

    private var players: [PlayerPublic] {
        game.liarState?.players ?? game.wolfState?.players
            ?? game.sketchState?.players ?? game.publicState?.players ?? []
    }

    /// 지금 방이 달빛 결사일 때만 그 상태.
    private var moonlit: PublicGameState? {
        game.liarState == nil && game.wolfState == nil && game.sketchState == nil ? game.publicState : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(game.gameKind.displayName)
                    .font(.title2.weight(.heavy))
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 20)

                // 달빛 결사: 원정 트랙은 이 판으로 옮겨 온다(고르는 쪽에서는 빠진다 → GameView)
                if let state = moonlit, state.phase != .lobby, state.phase != .gameOver {
                    MissionTrackView(state: state)
                }

                VStack(spacing: 8) {
                    ForEach(players) { p in
                        PlayerRow(player: p,
                                  isMe: p.id == game.playerID,
                                  isLeader: moonlit.map { $0.phase != .lobby && $0.leaderID == p.id } ?? false,
                                  trailing: score(of: p))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// 달빛 화실의 누적 점수. 다른 게임은 점수가 없다.
    private func score(of player: PlayerPublic) -> String? {
        guard let sketch = game.sketchState else { return nil }
        return "\(sketch.scores[player.id.uuidString] ?? 0)"
    }
}
