//
//  MoonlitOrderFlags.swift
//  MoonlitOrder
//
//  원격 킬스위치 플래그 — LeeoKit(LeeoRemoteFlags)이 CloudKit RemoteFlags 레코드에서 읽는다.
//
//  ⚠️ rawValue = CloudKit 필드명 계약이다 — 다르면 아무리 꺼도 켜진 채로 도는 조용한 실패. 변경 금지.
//  ⚠️ 조회 실패 = 켬(가용성 우선), 갱신은 6시간 쓰로틀 → 즉시 전파되지 않는다.
//
//  CloudKit Dashboard 설정(1회): 컨테이너 iCloud.com.Ysoup.FeedbackHub, 레코드 타입 RemoteFlags,
//  recordName "flags_com.example.MoonlitOrder", 각 플래그를 Int64(1=켬/0=끔) 필드로 만들고
//  Production 배포. 필드가 없으면 켬으로 동작한다.
//

import Foundation
import LeeoKit

enum MoonlitOrderFlag: String, LeeoRemoteFlag, CaseIterable {
    /// 익명 사용 통계 전송(스냅샷·이벤트). 끄면 다음 실행부터 보내지 않는다.
    case usageReportingEnabled
    /// MetricKit 크래시/행 수집(LeeoDiagnostics). 끄면 다음 실행부터 구독하지 않는다.
    case diagnosticsEnabled

    // 게임별 스위치 — 한 게임의 규칙·동기화에 심각한 버그가 났을 때, 심사 없이 그 게임만
    // 홈에서 '점검 중'으로 돌려 새 판이 열리지 않게 한다. 다른 게임은 그대로 즐길 수 있다.
    case moonlitGameEnabled
    case liarGameEnabled
    case wolfGameEnabled
    case sketchGameEnabled
}

extension GameViewModel.GameKind {
    /// 이 게임을 담당하는 원격 스위치.
    var remoteFlag: MoonlitOrderFlag {
        switch self {
        case .moonlit: return .moonlitGameEnabled
        case .liar:    return .liarGameEnabled
        case .wolf:    return .wolfGameEnabled
        case .sketch:  return .sketchGameEnabled
        }
    }

    /// 원격 스위치로 꺼지지 않았는가. 조회에 실패했거나 필드가 없으면 켬이다.
    var isRemotelyEnabled: Bool {
        LeeoRemoteFlags.isEnabled(remoteFlag)
    }
}
