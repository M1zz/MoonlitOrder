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

    enum GameKind: String {
        case moonlit   // 달빛 결사 (오리지널)
        case liar      // 라이어 게임 (민속 파티게임 — 관용 명칭)
        case wolf      // 달 없는 밤 (한국 설화 테마 오리지널)

        var displayName: String {
            switch self {
            case .moonlit: return "달빛 결사"
            case .liar:    return "라이어 게임"
            case .wolf:    return "달 없는 밤"
            }
        }
    }

    // MARK: 공개 상태

    @Published var mode: Mode = .idle
    @Published var playerName: String {
        didSet { UserDefaults.standard.set(playerName, forKey: "moonorder.playerName") }
    }
    @Published var publicState: PublicGameState?
    @Published var privateInfo: PrivateInfo?
    @Published var liarState: LiarGameState?
    @Published var liarPrivate: LiarPrivateInfo?
    @Published var wolfState: WolfGameState?
    @Published var wolfPrivate: WolfPrivateInfo?
    @Published var hosts: [MultipeerService.DiscoveredHost] = []
    @Published var connectionLost = false      // 클라이언트: 재접속 시도 중
    @Published var errorMessage: String?
    @Published var showDemoIntro = false       // 게임방법: 목적·승리조건 안내 화면

    /// 기기에 영구 저장되는 플레이어 ID — 재접속의 핵심.
    let playerID: UUID

    private var service: MultipeerService?
    private var engine: GameEngine?
    private var liarEngine: LiarEngine?
    private var wolfEngine: WolfEngine?
    private var demoDriver: DemoDriver?
    private var liarDemoDriver: LiarDemoDriver?
    private var wolfDemoDriver: WolfDemoDriver?
    private(set) var isHost = false
    private(set) var gameKind: GameKind = .moonlit
    private(set) var browseFilter: GameKind?

    /// 게임방법(데모) 모드 여부 — 봇들과 함께 단계별로 배우는 판
    var isDemo: Bool {
        demoDriver != nil || liarDemoDriver != nil || wolfDemoDriver != nil
    }

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

    func hostGame(kind: GameKind = .moonlit) {
        cleanup()
        isHost = true
        gameKind = kind
        UIApplication.shared.isIdleTimerDisabled = true

        switch kind {
        case .moonlit: setupMoonlitEngine()
        case .liar:    setupLiarEngine()
        case .wolf:    setupWolfEngine()
        }

        let service = MultipeerService(role: .host,
                                       displayName: "\(trimmedName)#\(shortID)")
        self.service = service
        wireHostCallbacks(service)
        service.startHosting(hostName: trimmedName, gameName: kind.displayName)

        switch kind {
        case .moonlit: engine?.join(playerID: playerID, name: trimmedName, isHost: true)
        case .liar:    liarEngine?.join(playerID: playerID, name: trimmedName, isHost: true)
        case .wolf:    wolfEngine?.join(playerID: playerID, name: trimmedName, isHost: true)
        }
        startResyncTimer()
        mode = .hosting
    }

    private func setupMoonlitEngine() {
        let engine = GameEngine()
        self.engine = engine

        engine.onStateChange = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                self.publicState = state
                self.prunePeerMappings(keeping: state.players.map(\.id))
                self.service?.broadcast(.state(state))
                self.updateAdvertising(lobby: state.phase == .lobby,
                                       playerCount: state.players.count,
                                       maxPlayers: GameRules.playerRange.upperBound,
                                       anyDisconnected: !state.disconnectedPlayers.isEmpty)
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
    }

    private func setupLiarEngine() {
        let engine = LiarEngine()
        liarEngine = engine

        engine.onStateChange = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                self.liarState = state
                self.prunePeerMappings(keeping: state.players.map(\.id))
                self.service?.broadcast(.liarState(state))
                self.updateAdvertising(lobby: state.phase == .lobby,
                                       playerCount: state.players.count,
                                       maxPlayers: LiarRules.playerRange.upperBound,
                                       anyDisconnected: !state.disconnectedPlayers.isEmpty)
            }
        }
        engine.onPrivateInfo = { [weak self] pid, info in
            guard let self else { return }
            Task { @MainActor in
                if pid == self.playerID {
                    self.liarPrivate = info
                } else if let peer = self.peerForPlayer[pid] {
                    self.service?.send(.liarPrivate(info), to: peer)
                }
            }
        }
    }

    private func setupWolfEngine() {
        let engine = WolfEngine()
        wolfEngine = engine

        engine.onStateChange = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                self.wolfState = state
                self.prunePeerMappings(keeping: state.players.map(\.id))
                self.service?.broadcast(.wolfState(state))
                self.updateAdvertising(lobby: state.phase == .lobby,
                                       playerCount: state.players.count,
                                       maxPlayers: WolfRules.playerRange.upperBound,
                                       anyDisconnected: !state.disconnectedPlayers.isEmpty)
            }
        }
        engine.onPrivateInfo = { [weak self] pid, info in
            guard let self else { return }
            Task { @MainActor in
                if pid == self.playerID {
                    self.wolfPrivate = info
                } else if let peer = self.peerForPlayer[pid] {
                    self.service?.send(.wolfPrivate(info), to: peer)
                }
            }
        }
    }

    /// 상태 브로드캐스트가 전송 실패로 유실돼도 복구되도록 주기적으로 최신 전체
    /// 상태를 재전송한다. (전체 상태 스냅샷 설계라 중복 수신은 무해하다)
    private func startResyncTimer() {
        resyncTimer?.invalidate()
        resyncTimer = Timer.scheduledTimer(withTimeInterval: Self.resyncInterval,
                                           repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let service = self.service,
                      !service.connectedPeers.isEmpty,
                      let message = self.activeStateMessage else { return }
                service.broadcast(message)
            }
        }
    }

    /// 현재 진행 중인 게임의 전체 상태 브로드캐스트 메시지
    private var activeStateMessage: NetMessage? {
        switch gameKind {
        case .moonlit: return publicState.map { NetMessage.state($0) }
        case .liar:    return liarState.map { NetMessage.liarState($0) }
        case .wolf:    return wolfState.map { NetMessage.wolfState($0) }
        }
    }

    /// 게임 중 전원이 접속해 있거나 로비가 가득 찼으면 광고 라디오를 꺼서 배터리를 아낀다.
    private func updateAdvertising(lobby: Bool, playerCount: Int,
                                   maxPlayers: Int, anyDisconnected: Bool) {
        service?.setAdvertisingEnabled((lobby && playerCount < maxPlayers) || anyDisconnected)
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
                    // 활성 엔진은 하나뿐이므로 모두 호출해도 안전하다
                    self.engine?.setConnected(pid, false)
                    self.liarEngine?.setConnected(pid, false)
                    self.wolfEngine?.setConnected(pid, false)
                }
            }
        }
    }

    private func hostReceived(_ message: NetMessage, from peer: MCPeerID) {
        switch message {
        case .join(let pid, let name):
            let result: GameEngine.JoinResult
            switch gameKind {
            case .moonlit:
                guard let engine else { return }
                result = engine.join(playerID: pid, name: name, isHost: false)
            case .liar:
                guard let liarEngine else { return }
                result = liarEngine.join(playerID: pid, name: name, isHost: false)
            case .wolf:
                guard let wolfEngine else { return }
                result = wolfEngine.join(playerID: pid, name: name, isHost: false)
            }
            switch result {
            case .joined, .rejoined:
                // 참가가 확정된 피어만 매핑에 기록 (거절된 피어가 맵을 오염시키지 않도록)
                if let old = peerForPlayer[pid] { playerForPeer.removeValue(forKey: old) }
                peerForPlayer[pid] = peer
                playerForPeer[peer] = pid
            case .rejectedFull:
                service?.send(.rejected(reason: "정원이 가득 찼습니다. (최대 10명)"), to: peer)
                service?.disconnectPeer(peer)
            case .rejectedInProgress:
                service?.send(.rejected(reason: "이미 게임이 진행 중인 방입니다."), to: peer)
                service?.disconnectPeer(peer)
            }
        case .liarAction(let pid, let action):
            liarEngine?.handle(pid, action)
        case .wolfAction(let pid, let action):
            wolfEngine?.handle(pid, action)
        default:
            engine?.handle(message)
        }
    }

    // MARK: - 게임방법 (데모 모드)

    /// 봇들과 함께 한 단계씩 배우는 데모 판을 연다. 네트워크 없이 로컬에서 돌며,
    /// 사용자는 자기 차례의 행동을 직접 해보고 '다음'으로 봇들을 진행시킨다.
    func startDemo(kind: GameKind = .moonlit) {
        cleanup()
        isHost = true
        gameKind = kind
        showDemoIntro = true   // 먼저 게임 목적·승리 조건을 보여준다
        UIApplication.shared.isIdleTimerDisabled = true

        // 서비스가 없으므로 브로드캐스트/광고는 자연스럽게 무시된다
        switch kind {
        case .moonlit:
            setupMoonlitEngine()
            engine?.join(playerID: playerID, name: trimmedName, isHost: true)
            if let engine {
                let driver = DemoDriver(engine: engine, hostID: playerID)
                demoDriver = driver
                driver.start()
            }
        case .liar:
            setupLiarEngine()
            liarEngine?.join(playerID: playerID, name: trimmedName, isHost: true)
            if let liarEngine {
                let driver = LiarDemoDriver(engine: liarEngine, hostID: playerID)
                liarDemoDriver = driver
                driver.start()
            }
        case .wolf:
            setupWolfEngine()
            wolfEngine?.join(playerID: playerID, name: trimmedName, isHost: true)
            if let wolfEngine {
                let driver = WolfDemoDriver(engine: wolfEngine, hostID: playerID)
                wolfDemoDriver = driver
                driver.start()
            }
        }
        mode = .hosting
    }

    /// 데모: '다음' — 현재 단계에서 남은 참가자(봇)의 행동을 실행해 한 단계 진행한다.
    func advanceDemo() {
        switch gameKind {
        case .moonlit:
            if let state = publicState { demoDriver?.advance(from: state) }
        case .liar:
            if let state = liarState { liarDemoDriver?.advance(from: state) }
        case .wolf:
            if let state = wolfState { wolfDemoDriver?.advance(from: state) }
        }
    }

    // MARK: - 클라이언트 참가

    /// 방 찾기. filter를 주면 해당 게임의 방만 목록에 보인다.
    func startBrowsing(filter: GameKind? = nil) {
        cleanup()
        isHost = false
        browseFilter = filter

        let service = MultipeerService(role: .client,
                                       displayName: "\(trimmedName)#\(shortID)")
        self.service = service

        service.onHostsChanged = { [weak self] hosts in
            guard let self else { return }
            Task { @MainActor in
                if let filter = self.browseFilter {
                    self.hosts = hosts.filter { $0.gameName == filter.displayName }
                } else {
                    self.hosts = hosts
                }
            }
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
        case .liarState(let state):
            gameKind = .liar
            if state != liarState { liarState = state }
            if connectionLost { connectionLost = false }
            cancelReconnectDeadline()
            if mode == .connecting { mode = .playing }
            if state.phase != .lobby, liarPrivate == nil,
               Date().timeIntervalSince(lastPrivateInfoRequest) > 3 {
                lastPrivateInfoRequest = Date()
                service?.sendToHost(.join(playerID: playerID, name: trimmedName))
            }
        case .liarPrivate(let info):
            if info != liarPrivate { liarPrivate = info }
        case .wolfState(let state):
            gameKind = .wolf
            if state != wolfState { wolfState = state }
            if connectionLost { connectionLost = false }
            cancelReconnectDeadline()
            if mode == .connecting { mode = .playing }
            if state.phase != .lobby, wolfPrivate == nil,
               Date().timeIntervalSince(lastPrivateInfoRequest) > 3 {
                lastPrivateInfoRequest = Date()
                service?.sendToHost(.join(playerID: playerID, name: trimmedName))
            }
        case .wolfPrivate(let info):
            if info != wolfPrivate { wolfPrivate = info }
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

    /// 라이어 게임 액션 (호스트는 엔진에 직접, 클라이언트는 호스트로 전송)
    func performLiar(_ action: LiarAction) {
        if isHost {
            liarEngine?.handle(playerID, action)
        } else {
            service?.sendToHost(.liarAction(playerID: playerID, action: action))
        }
    }

    /// 한밤의 늑대인간 액션
    func performWolf(_ action: WolfAction) {
        if isHost {
            wolfEngine?.handle(playerID, action)
        } else {
            service?.sendToHost(.wolfAction(playerID: playerID, action: action))
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
        liarDemoDriver?.stop()
        liarDemoDriver = nil
        wolfDemoDriver?.stop()
        wolfDemoDriver = nil
        browseFilter = nil
        showDemoIntro = false
        service?.stop()
        service = nil
        engine?.onStateChange = nil
        engine?.onPrivateInfo = nil
        engine = nil
        liarEngine?.onStateChange = nil
        liarEngine?.onPrivateInfo = nil
        liarEngine = nil
        wolfEngine?.onStateChange = nil
        wolfEngine?.onPrivateInfo = nil
        wolfEngine = nil
        publicState = nil
        privateInfo = nil
        liarState = nil
        liarPrivate = nil
        wolfState = nil
        wolfPrivate = nil
        gameKind = .moonlit
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
