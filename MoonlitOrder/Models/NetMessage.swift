import Foundation
import os

/// 호스트 ↔ 클라이언트 사이에 오가는 모든 메시지.
/// JSON(Codable)으로 인코딩되어 MultipeerConnectivity로 전송된다.
enum NetMessage: Codable {

    // MARK: 클라이언트 → 호스트

    /// 게임 참가 요청. playerID는 기기에 영구 저장되는 UUID라서
    /// 연결이 끊겼다가 다시 들어와도 같은 플레이어로 복귀한다.
    case join(playerID: UUID, name: String)
    case startGame(playerID: UUID)
    case confirmRole(playerID: UUID)
    case proposeTeam(playerID: UUID, members: [UUID])
    case teamVote(playerID: UUID, approve: Bool)
    case missionAction(playerID: UUID, success: Bool)
    case assassinate(playerID: UUID, targetID: UUID)
    case hostContinue(playerID: UUID)     // 결과 화면에서 다음 단계로 (호스트 전용)
    case playAgain(playerID: UUID)        // 같은 멤버로 재시작 (호스트 전용)
    case abortToLobby(playerID: UUID)     // 게임을 중단하고 대기실로 (호스트 전용)

    // MARK: 라이어 게임 / 한밤의 늑대인간 (클라이언트 → 호스트)

    case liarAction(playerID: UUID, action: LiarAction)
    case wolfAction(playerID: UUID, action: WolfAction)
    case sketchAction(playerID: UUID, action: SketchAction)

    // MARK: 호스트 → 클라이언트

    case state(PublicGameState)           // 항상 전체 상태를 전송 → 재접속 시에도 즉시 동기화
    case privateInfo(PrivateInfo)         // 본인 역할 등 비공개 정보 (개별 전송)
    case liarState(LiarGameState)
    case liarPrivate(LiarPrivateInfo)
    case wolfState(WolfGameState)
    case wolfPrivate(WolfPrivateInfo)
    case sketchState(SketchGameState)
    case sketchPrivate(SketchPrivateInfo)
    case rejected(reason: String)         // 참가 거절
    case hostEnded                        // 호스트가 방을 닫음
}

enum NetCoder {
    private static let log = Logger(subsystem: "MoonlitOrder", category: "NetCoder")

    static func encode(_ message: NetMessage) -> Data? {
        do {
            return try JSONEncoder().encode(message)
        } catch {
            log.error("인코딩 실패: \(error.localizedDescription)")
            return nil
        }
    }

    static func decode(_ data: Data) -> NetMessage? {
        do {
            return try JSONDecoder().decode(NetMessage.self, from: data)
        } catch {
            // 앱 버전 간 메시지 포맷이 다르면 여기서 조용히 유실되므로 반드시 기록한다.
            log.error("디코딩 실패(버전 불일치 가능성): \(error.localizedDescription)")
            return nil
        }
    }
}
