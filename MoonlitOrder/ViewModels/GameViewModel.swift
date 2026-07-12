import Foundation
import MultipeerConnectivity
import SwiftUI

/// 호스트/클라이언트 공용 뷰모델.
/// 호스트일 때는 GameEngine을 직접 품고, 클라이언트일 때는 호스트에 메시지를 보낸다.
@MainActor
final class GameViewModel: ObservableObject {

    enum Mode: Equatable {
        case idle           // 홈 화면
        case hosting
        case browsing       // 방 찾는 중
        case connecting     // 초대 후 연결 중
        case playing        // 클라이언트로 게임 참여 중
    }

    // MARK: 공개 상태

    @Published var mode: Mode = .idle
    @Published var playerName: String {
        didSet { UserDefaults.standard.set(playerName, forKey: "moonorder.playerName") }
    }
    @Published var publicState: PublicGameState?
    @Published var privateInfo: PrivateInfo?
    @Published var hosts: [MultipeerService.DiscoveredHost] = []
    @Published var connectionLost = false      // 클라이언트: 재접속 시도 중
    @Published var errorMessage: String?

    /// 기기에 영구 저장되는 플레이어 ID — 재접속의 핵심.
    let playerID: UUID

    private var service: MultipeerService?
    private var engine: GameEngine?
    private var demoDriver: DemoDriver?
    private(set) var isHost = false

    /// 게임방법(데모) 모드 여부 — 봇들이 자동으로 플레이하는 관전용 판
    var isDemo: Bool { demoDriver != nil }

    private var peerForPlayer: [UUID: MCPeerID] = [:]
    private var playerForPeer: [MCPeerID: UUID] = [:]
    private var lastPrivateInfoRequest: Date = .distantPast

    /// 호스트: 상태 브로드캐스트 유실 대비 주기적 재전송.
    /// 데이터/배터리를 아끼기 위해 유실 복구가 감내할 수 있는 선에서 가장 느리게 잡는다.
    private var resyncTimer: Timer?
    private static let resyncInterval: TimeInterval = 10
    /// 클라이언트: 재접속 제한시간 — 초과하면 포기하고 홈으로
    private var reconnectDeadline: Timer?
    private static let reconnectTimeout: TimeInterval = 60

    // MARK: - 초기화

    init() {
        if let saved = UserDefaults.standard.string(forKey: "moonorder.playerID"),
           let uuid = UUID(uuidString: saved) {
            playerID = uuid
        } else {
            let uuid = UUID()
            UserDefaults.standard.set(uuid.uuidString, forKey: "moonorder.playerID")
            playerID = uuid
        }
        playerName = UserDefaults.standard.string(forKey: "moonorder.playerName") ?? ""
    }

    // MARK: - 편의 계산 속성

    var me: PlayerPublic? { publicState?.player(playerID) }
    var isLeader: Bool { publicState?.leaderID == playerID }
    var isOnTeam: Bool { publicState?.proposedTeam.contains(playerID) ?? false }
    var myRole: Role? { privateInfo?.role }

    var trimmedName: String {
        let t = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "플레이어" : t
    }

    // MARK: - 호스트 시작

    func hostGame() {
        cleanup()
        isHost = true
        UIApplication.shared.isIdleTimerDisabled = true

        let engine = GameEngine()
        self.engine = engine

        engine.onStateChange = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                self.publicState = state
                self.prunePeerMappings(keeping: state.players.map(\.id))
                self.service?.broadcast(.state(state))
                self.updateAdvertising(for: state)
            }
        }
        engine.onPrivateInfo = { [weak self] pid, info in
            guard let self else { return }
            Task { @MainActor in
                if pid == self.playerID {
                    self.privateInfo = info
                } else if let peer = self.peerForPlayer[pid] {
                    self.service?.send(.privateInfo(info), to: peer)
                }
            }
        }

        let service = MultipeerService(role: .host,
                                       displayName: "\(trimmedName)#\(shortID)")
        self.service = service
        wireHostCallbacks(service)
        service.startHosting(hostName: trimmedName)

        engine.join(playerID: playerID, name: trimmedName, isHost: true)
        startResyncTimer()
        mode = .hosting
    }

    /// 상태 브로드캐스트가 전송 실패로 유실돼도 복구되도록 주기적으로 최신 전체
    /// 상태를 재전송한다. (전체 상태 스냅샷 설계라 중복 수신은 무해하다)
    private func startResyncTimer() {
        resyncTimer?.invalidate()
        resyncTimer = Timer.scheduledTimer(withTimeInterval: Self.resyncInterval,
                                           repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let state = self.publicState,
                      let service = self.service,
                      !service.connectedPeers.isEmpty else { return }
                service.broadcast(.state(state))
            }
        }
    }

    /// 게임 중 전원이 접속해 있거나 로비가 가득 찼으면 광고 라디오를 꺼서 배터리를 아낀다.
    private func updateAdvertising(for state: PublicGameState) {
        let lobbyHasRoom = state.phase == .lobby
            && state.players.count < GameRules.playerRange.upperBound
        let waitingForReconnect = state.players.contains { !$0.isConnected }
        service?.setAdvertisingEnabled(lobbyHasRoom || waitingForReconnect)
    }

    /// 엔진에서 제거된 플레이어의 피어 매핑을 정리한다.
    private func prunePeerMappings(keeping ids: [UUID]) {
        let keep = Set(ids)
        for (pid, peer) in peerForPlayer where !keep.contains(pid) {
            peerForPlayer.removeValue(forKey: pid)
            playerForPeer.removeValue(forKey: peer)
        }
    }

    private func wireHostCallbacks(_ service: MultipeerService) {
        service.onMessage = { [weak self] message, peer in
            guard let self else { return }
            Task { @MainActor in self.hostReceived(message, from: peer) }
        }
        service.onPeerDisconnected = { [weak self] peer in
            guard let self else { return }
            Task { @MainActor in
                if let pid = self.playerForPeer[peer] {
                    self.engine?.setConnected(pid, false)
                }
            }
        }
    }

    private func hostReceived(_ message: NetMessage, from peer: MCPeerID) {
        guard let engine else { return }
        switch message {
        case .join(let pid, let name):
            let result = engine.join(playerID: pid, name: name, isHost: false)
            switch result {
            case .joined, .rejoined:
                // 참가가 확정된 피어만 매핑에 기록 (거절된 피어가 맵을 오염시키지 않도록)
                if let old = peerForPlayer[pid] { playerForPeer.removeValue(forKey: old) }
                peerForPlayer[pid] = peer
                playerForPeer[peer] = pid
            case .rejectedFull:
                service?.send(.rejected(reason: "정원이 가득 찼습니다. (최대 \(GameRules.playerRange.upperBound)명)"), to: peer)
                service?.disconnectPeer(peer)
            case .rejectedInProgress:
                service?.send(.rejected(reason: "이미 게임이 진행 중인 방입니다."), to: peer)
                service?.disconnectPeer(peer)
            }
        default:
            engine.handle(message)
        }
    }

    // MARK: - 게임방법 (데모 모드)

    /// 봇 6명이 자동으로 플레이하는 데모 판을 연다. 네트워크 없이 로컬에서 돌며,
    /// 사용자는 관전하거나 자기 차례의 행동(투표 등)을 직접 해볼 수도 있다.
    func startDemo() {
        cleanup()
        isHost = true
        UIApplication.shared.isIdleTimerDisabled = true

        let engine = GameEngine()
        self.engine = engine

        engine.onStateChange = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                self.publicState = state
                self.demoDriver?.react(to: state)
            }
        }
        engine.onPrivateInfo = { [weak self] pid, info in
            guard let self else { return }
            Task { @MainActor in
                if pid == self.playerID { self.privateInfo = info }
            }
        }

        engine.join(playerID: playerID, name: trimmedName, isHost: true)
        let driver = DemoDriver(engine: engine, hostID: playerID)
        demoDriver = driver
        mode = .hosting
        driver.start()
    }

    /// 데모: 현재 단계를 즉시 진행시켜 다음 단계로 넘어간다.
    func skipDemoPhase() {
        guard let state = publicState else { return }
        demoDriver?.skip(state: state)
    }

    // MARK: - 클라이언트 참가

    func startBrowsing() {
        cleanup()
        isHost = false

        let service = MultipeerService(role: .client,
                                       displayName: "\(trimmedName)#\(shortID)")
        self.service = service

        service.onHostsChanged = { [weak self] hosts in
            guard let self else { return }
            Task { @MainActor in self.hosts = hosts }
        }
        service.onPeerConnected = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // 연결(또는 재연결)되면 같은 playerID로 참가 요청 → 상태 복원
                self.service?.sendToHost(.join(playerID: self.playerID, name: self.trimmedName))
                self.connectionLost = false
                self.cancelReconnectDeadline()
                if self.mode == .connecting { self.mode = .playing }
            }
        }
        service.onConnectionLost = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if self.mode == .playing {
                    self.connectionLost = true
                    self.startReconnectDeadline()
                }
            }
        }
        service.onMessage = { [weak self] message, _ in
            guard let self else { return }
            Task { @MainActor in self.clientReceived(message) }
        }

        service.startBrowsing()
        mode = .browsing
    }

    func join(host: MultipeerService.DiscoveredHost) {
        guard let service else { return }
        mode = .connecting
        UIApplication.shared.isIdleTimerDisabled = true
        service.join(host: host)
    }

    private func clientReceived(_ message: NetMessage) {
        switch message {
        case .state(let state):
            // 주기적 재동기화로 같은 상태가 반복 수신되므로, 바뀐 경우에만
            // 반영해 불필요한 전체 뷰 재렌더링(배터리 소모)을 막는다.
            if state != publicState { publicState = state }
            if connectionLost { connectionLost = false }
            cancelReconnectDeadline()
            if mode == .connecting { mode = .playing }
            // 게임이 진행 중인데 내 역할 정보가 없다면(전송 유실 등)
            // join을 다시 보내 재접속 경로로 비공개 정보를 다시 받는다.
            if state.phase != .lobby, privateInfo == nil,
               Date().timeIntervalSince(lastPrivateInfoRequest) > 3 {
                lastPrivateInfoRequest = Date()
                service?.sendToHost(.join(playerID: playerID, name: trimmedName))
            }
        case .privateInfo(let info):
            if info != privateInfo { privateInfo = info }
        case .rejected(let reason):
            errorMessage = reason
            leaveGame()
        case .hostEnded:
            errorMessage = "호스트가 방을 닫았습니다."
            leaveGame()
        default:
            break
        }
    }

    // MARK: - 게임 액션 (호스트는 엔진에 직접, 클라이언트는 호스트로 전송)

    private func perform(_ message: NetMessage) {
        if isHost {
            engine?.handle(message)
        } else {
            service?.sendToHost(message)
        }
    }

    func startGame()                  { perform(.startGame(playerID: playerID)) }
    func confirmRole()                { perform(.confirmRole(playerID: playerID)) }
    func proposeTeam(_ ids: [UUID])   { perform(.proposeTeam(playerID: playerID, members: ids)) }
    func vote(approve: Bool)          { perform(.teamVote(playerID: playerID, approve: approve)) }
    func playMission(success: Bool)   { perform(.missionAction(playerID: playerID, success: success)) }
    func assassinate(_ target: UUID)  { perform(.assassinate(playerID: playerID, targetID: target)) }
    func hostContinue()               { perform(.hostContinue(playerID: playerID)) }
    func playAgain()                  { perform(.playAgain(playerID: playerID)) }
    func abortToLobby()               { perform(.abortToLobby(playerID: playerID)) }

    // MARK: - 재접속 제한시간 / 앱 생명주기

    /// 재접속이 이 시간 안에 이뤄지지 않으면 (호스트 종료·크래시 등) 포기하고 홈으로 나간다.
    private func startReconnectDeadline() {
        reconnectDeadline?.invalidate()
        reconnectDeadline = Timer.scheduledTimer(withTimeInterval: Self.reconnectTimeout,
                                                 repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.connectionLost else { return }
                self.errorMessage = "호스트에 다시 연결하지 못했습니다. 방 목록에서 다시 참가해주세요."
                self.leaveGame()
            }
        }
    }

    private func cancelReconnectDeadline() {
        reconnectDeadline?.invalidate()
        reconnectDeadline = nil
    }

    /// 포그라운드 복귀 시 백그라운드에서 끊긴 광고/탐색/연결을 되살린다.
    func handleScenePhase(_ phase: ScenePhase) {
        guard phase == .active, mode != .idle else { return }
        service?.refreshAfterForeground()
        // 백그라운드 동안 타이머가 멈춰 있었으므로 제한시간을 새로 시작한다
        if connectionLost { startReconnectDeadline() }
    }

    // MARK: - 나가기 / 정리

    func leaveGame() {
        if isHost, let service {
            // hostEnded가 전송될 시간을 준 뒤 세션을 닫는다.
            // (즉시 disconnect하면 마지막 메시지가 유실되어 클라이언트가
            //  '재접속 시도 중' 배너에 갇힌다)
            service.broadcast(.hostEnded)
            self.service = nil   // cleanup()이 즉시 stop하지 않도록 분리
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                service.stop()
            }
        }
        cleanup()
        mode = .idle
    }

    private func cleanup() {
        UIApplication.shared.isIdleTimerDisabled = false
        resyncTimer?.invalidate()
        resyncTimer = nil
        cancelReconnectDeadline()
        demoDriver?.stop()
        demoDriver = nil
        service?.stop()
        service = nil
        engine?.onStateChange = nil
        engine?.onPrivateInfo = nil
        engine = nil
        publicState = nil
        privateInfo = nil
        hosts = []
        connectionLost = false
        peerForPlayer = [:]
        playerForPeer = [:]
        isHost = false
    }

    /// MCPeerID displayName 충돌 방지용 짧은 식별자
    private var shortID: String {
        String(playerID.uuidString.prefix(4))
    }
}
