//
//  MoonlitOrderRoadmap.swift
//  MoonlitOrder
//
//  **앞으로 만들 것**의 원본. 설정 ▸ 앞으로 만들 기능(`LeeoRoadmapView`)이 이 목록을 그대로 보여 준다.
//
//  ⚠️ 개발하다 "이건 다음에" 가 생기면 **여기에 한 줄을 더한다.** 코드의 TODO 주석으로만 남기지 않는다.
//     - 새 항목: `.planned`. 손대기 시작하면 `.building`. 내보내면 `.shipped("1.2.0")`.
//     - id 는 한 번 정하면 바꾸지 않는다(문구는 바꿔도 된다).
//     - 문구는 사용자 말로 쓴다(내부 이름 · 기술 용어 금지). 지금은 한국어 앱이라 키가 곧 문구다 —
//       다른 언어를 열면 이 키들도 함께 번역한다.
//     - 사용자에게 보일 만한 것만 적는다. 리팩터링 · 시험 · 빌드 설정은 `.sprintcommander/tasks.json` 의 몫이다.
//

import SwiftUI
import LeeoKit

extension MoonlitOrderSpec {
    static var roadmap: [LeeoRoadmapItem] {[
        // MARK: 만들고 있어요
        .init(id: "a11y.voiceover", status: .building,
              title: NSLocalizedString("VoiceOver로 더 편하게", comment: "Roadmap item: VoiceOver"),
              detail: NSLocalizedString("화면 읽기 기능이 역할 카드와 투표 단추를 빠짐없이, 알맞은 순서로 읽어 줘요.", comment: "Roadmap item detail: VoiceOver")),
        .init(id: "a11y.largetext", status: .building,
              title: NSLocalizedString("큰 글씨에 맞춘 화면", comment: "Roadmap item: larger text"),
              detail: NSLocalizedString("글자 크기를 키워도 잘리지 않고 보기 좋게 다시 배치돼요.", comment: "Roadmap item detail: larger text")),
        .init(id: "a11y.contrast", status: .building,
              title: NSLocalizedString("보기 편한 색과 대비", comment: "Roadmap item: color and contrast"),
              detail: NSLocalizedString("대비를 높이거나 색을 구별하기 어려워도 진영과 결과를 알아볼 수 있어요.", comment: "Roadmap item detail: color and contrast")),
        .init(id: "a11y.motion", status: .building,
              title: NSLocalizedString("움직임 줄이기", comment: "Roadmap item: reduce motion"),
              detail: NSLocalizedString("움직임 줄이기를 켜면 화면 효과가 차분해져요.", comment: "Roadmap item detail: reduce motion")),
        // MARK: 다음에 만들어요
        .init(id: "lang.english", status: .planned,
              title: NSLocalizedString("영어 지원", comment: "Roadmap item: English"),
              detail: NSLocalizedString("외국인 친구와도 함께 하도록 앱을 영어로도 쓸 수 있어요.", comment: "Roadmap item detail: English")),
        .init(id: "lang.more", status: .planned,
              title: NSLocalizedString("더 많은 언어", comment: "Roadmap item: more languages"),
              detail: NSLocalizedString("더 많은 나라 말로 앱을 쓸 수 있게 해요.", comment: "Roadmap item detail: more languages")),
        .init(id: "whatsnew", status: .planned,
              title: NSLocalizedString("업데이트 소식", comment: "Roadmap item: what's new"),
              detail: NSLocalizedString("업데이트 뒤 처음 열 때 무엇이 새로 생겼는지 알려 줘요.", comment: "Roadmap item detail: what's new")),
        .init(id: "haptics", status: .planned,
              title: NSLocalizedString("손끝으로 느끼는 반응", comment: "Roadmap item: haptics"),
              detail: NSLocalizedString("역할을 받거나 투표가 끝나면 가볍게 떨려서 알려 줘요.", comment: "Roadmap item detail: haptics")),
        .init(id: "widgets", status: .planned,
              title: NSLocalizedString("홈 화면 위젯", comment: "Roadmap item: widgets"),
              detail: NSLocalizedString("홈 화면에서 바로 게임 방을 열 수 있어요.", comment: "Roadmap item detail: widgets")),
        .init(id: "notifications", status: .planned,
              title: NSLocalizedString("내 차례 알림", comment: "Roadmap item: notifications"),
              detail: NSLocalizedString("화면을 꺼 두어도 내 차례가 오면 알림으로 알려 줘요.", comment: "Roadmap item detail: notifications")),
        .init(id: "fold", status: .planned,
              title: NSLocalizedString("펼치는 아이폰 화면", comment: "Roadmap item: foldable iPhone"),
              detail: NSLocalizedString("펼치는 아이폰에서 넓은 화면을 두 쪽으로 나눠 써요.", comment: "Roadmap item detail: foldable iPhone")),
    ]}
}

// MARK: - 화면

/// 설정 ▸ 앞으로 만들 기능. "이런 기능이 있으면 좋겠어요" 는 피드백 창을 연다.
struct RoadmapScreen: View {
    @State private var showFeedback = false

    var body: some View {
        LeeoRoadmapView<MoonlitOrderSpec>(onSuggest: { showFeedback = true })
            .sheet(isPresented: $showFeedback) {
                NavigationStack {
                    LeeoFeedbackView<MoonlitOrderSpec>()
                }
            }
    }
}
