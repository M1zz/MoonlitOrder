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
        case sketch    // 달빛 화실 (그림 맞추기 — 오리지널 테마)

        var displayName: String {
            switch self {
            case .moonlit: return "달빛 결사"
            case .liar:    return "라이어 게임"
            case .wolf:    return "달 없는 밤"
            case .sketch:  return "달빛 화실"
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
    @Published var sketchState: SketchGameState?
    @Published var sketchPrivate: SketchPrivateInfo?
    @Published var hosts: [MultipeerService.DiscoveredHost] = []
    @Published var connectionLost = false      // 클라이언트: 재접속 시도 중
    @Published var errorMessage: String?
    @Published var showDemoIntro = false       // 게임방법: 목적·승리조건 안내 화면

    /// 시연용(-autoJoin): 방이 발견되면 자동으로 참가한다
    var autoJoinRoom = false

    // MARK: - 마지막 방 기억 (끊겨도 다시 들어와 이어서 플레이)

    struct LastRoom: Equatable {
        let roomID: String
        let hostName: String
        let gameName: String
    }

    /// 마지막으로 참가했던 방. 앱을 껐다 켜도 홈 화면에서 바로 재참가할 수 있다.
    @Published private(set) var lastRoom: LastRoom?
    /// 재참가 대상 방 — 목록에서 발견되는 즉시 자동 참가한다
    private var pendingRejoinRoomID: String?

    private func loadLastRoom() {
        let d = UserDefaults.standard
        guard let id = d.string(forKey: "moonorder.lastRoom.id"),
              let host = d.string(forKey: "moonorder.lastRoom.host") else { return }
        lastRoom = LastRoom(roomID: id, hostName: host,
                            gameName: d.string(forKey: "moonorder.lastRoom.game") ?? "")
    }

    private func saveLastRoom(_ room: LastRoom) {
        lastRoom = room
        let d = UserDefaults.standard
        d.set(room.roomID, forKey: "moonorder.lastRoom.id")
        d.set(room.hostName, forKey: "moonorder.lastRoom.host")
        d.set(room.gameName, forKey: "moonorder.lastRoom.game")
    }

    func forgetLastRoom() {
        lastRoom = nil
        let d = UserDefaults.standard
        d.removeObject(forKey: "moonorder.lastRoom.id")
        d.removeObject(forKey: "moonorder.lastRoom.host")
        d.removeObject(forKey: "moonorder.lastRoom.game")
    }

    /// 홈 화면의 '이어서 하기': 기억해 둔 방을 찾아 자동으로 다시 참가한다.
    func rejoinLastRoom() {
        guard let room = lastRoom else { return }
        startBrowsing()
        pendingRejoinRoomID = room.roomID
    }

    /// 기기에 영구 저장되는 플레이어 ID — 재접속의 핵심.
    let playerID: UUID

    private var service: MultipeerService?
    private var engine: GameEngine?
    private var liarEngine: LiarEngine?
    private var wolfEngine: WolfEngine?
    private var sketchEngine: SketchEngine?
    private var demoDriver: DemoDriver?
    private var liarDemoDriver: LiarDemoDriver?
    private var wolfDemoDriver: WolfDemoDriver?
    private var sketchDemoDriver: SketchDemoDriver?
    private(set) var isHost = false
    private(set) var gameKind: GameKind = .moonlit
    private(set) var browseFilter: GameKind?

    /// 게임방법(데모) 모드 여부 — 봇들과 함께 단계별로 배우는 판
    var isDemo: Bool {
        demoDriver != nil || liarDemoDriver != nil
            || wolfDemoDriver != nil || sketchDemoDriver != nil
    }

    /// 플레이어가 어느 직결 피어를 통해 들어왔는지. 릴레이 뒤의 플레이어는
    /// 릴레이 피어로 매핑되므로 피어 하나에 여러 플레이어가 붙을 수 있다.
    private var peerForPlayer: [UUID: MCPeerID] = [:]
    private var playersForPeer: [MCPeerID: Set<UUID>] = [:]
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
        loadLastRoom()
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
        case .sketch:  setupSketchEngine()
        }

        let service = MultipeerService(role: .host,
                                       displayName: "\(trimmedName)#\(shortID)")
        service.myPlayerID = playerID
        self.service = service
        wireHostCallbacks(service)
        service.startHosting(hostName: trimmedName, gameName: kind.displayName)

        switch kind {
        case .moonlit: engine?.join(playerID: playerID, name: trimmedName, isHost: true)
        case .liar:    liarEngine?.join(playerID: playerID, name: trimmedName, isHost: true)
        case .wolf:    wolfEngine?.join(playerID: playerID, name: trimmedName, isHost: true)
        case .sketch:  sketchEngine?.join(playerID: playerID, name: trimmedName, isHost: true)
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
                } else {
                    self.sendToPlayer(pid, .privateInfo(info))
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
                } else {
                    self.sendToPlayer(pid, .liarPrivate(info))
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
                } else {
                    self.sendToPlayer(pid, .wolfPrivate(info))
                }
            }
        }
    }

    private func setupSketchEngine() {
        let engine = SketchEngine()
        sketchEngine = engine

        engine.onStateChange = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                self.sketchState = state
                self.prunePeerMappings(keeping: state.players.map(\.id))
                self.service?.broadcast(.sketchState(state))
                self.updateAdvertising(lobby: state.phase == .lobby,
                                       playerCount: state.players.count,
                                       maxPlayers: SketchRules.playerRange.upperBound,
                                       anyDisconnected: !state.disconnectedPlayers.isEmpty)
            }
        }
        engine.onPrivateInfo = { [weak self] pid, info in
            guard let self else { return }
            Task { @MainActor in
                if pid == self.playerID {
                    self.sketchPrivate = info
                } else {
                    self.sendToPlayer(pid, .sketchPrivate(info))
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
        case .sketch:  return sketchState.map { NetMessage.sketchState($0) }
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
            playersForPeer[peer]?.remove(pid)
            if playersForPeer[peer]?.isEmpty == true {
                playersForPeer.removeValue(forKey: peer)
            }
        }
    }

    /// 참가가 확정된 플레이어의 유입 경로를 기록한다.
    /// (릴레이를 통해 온 플레이어는 릴레이 피어로 매핑된다)
    private func recordRoute(playerID pid: UUID, via peer: MCPeerID) {
        if let old = peerForPlayer[pid], old != peer {
            playersForPeer[old]?.remove(pid)
            if playersForPeer[old]?.isEmpty == true {
                playersForPeer.removeValue(forKey: old)
            }
        }
        peerForPlayer[pid] = peer
        playersForPeer[peer, default: []].insert(pid)
    }

    /// 호스트 → 특정 플레이어 전송. 릴레이 뒤에 있어도 봉투가 트리를 따라 전달된다.
    private func sendToPlayer(_ pid: UUID, _ message: NetMessage) {
        guard let peer = peerForPlayer[pid] else { return }
        service?.send(.toPlayer(playerID: pid, message: message), to: peer)
    }

    private func wireHostCallbacks(_ service: MultipeerService) {
        service.onMessage = { [weak self] message, peer in
            guard let self else { return }
            Task { @MainActor in self.hostReceived(message, from: peer) }
        }
        service.onPeerDisconnected = { [weak self] peer in
            guard let self else { return }
            Task { @MainActor in
                // 릴레이 피어가 끊기면 그 뒤의 플레이어들도 함께 끊긴 것으로 처리
                for pid in self.playersForPeer[peer] ?? [] {
                    // 활성 엔진은 하나뿐이므로 모두 호출해도 안전하다
                    self.engine?.setConnected(pid, false)
                    self.liarEngine?.setConnected(pid, false)
                    self.wolfEngine?.setConnected(pid, false)
                    self.sketchEngine?.setConnected(pid, false)
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
            case .sketch:
                guard let sketchEngine else { return }
                result = sketchEngine.join(playerID: pid, name: name, isHost: false)
            }
            switch result {
            case .joined, .rejoined:
                // 참가가 확정된 피어만 매핑에 기록 (거절된 피어가 맵을 오염시키지 않도록)
                recordRoute(playerID: pid, via: peer)
            case .rejectedFull:
                service?.send(.toPlayer(playerID: pid,
                                        message: .rejected(reason: "정원이 가득 찼습니다. (최대 \(activeMaxPlayers)명)")),
                              to: peer)
                disconnectIfDirect(pid, peer: peer)
            case .rejectedInProgress:
                service?.send(.toPlayer(playerID: pid,
                                        message: .rejected(reason: "이미 게임이 진행 중인 방입니다.")),
                              to: peer)
                disconnectIfDirect(pid, peer: peer)
            }
        case .playerGone(let pid):
            // 릴레이가 보고한 자식 끊김. 그 사이 다른 경로로 재접속했다면
            // (현재 경로가 보고한 릴레이가 아니라면) 낡은 보고이므로 무시한다.
            guard peerForPlayer[pid] == peer else { break }
            engine?.setConnected(pid, false)
            liarEngine?.setConnected(pid, false)
            wolfEngine?.setConnected(pid, false)
            sketchEngine?.setConnected(pid, false)
        case .liarAction(let pid, let action):
            liarEngine?.handle(pid, action)
        case .wolfAction(let pid, let action):
            wolfEngine?.handle(pid, action)
        case .sketchAction(let pid, let action):
            sketchEngine?.handle(pid, action)
        default:
            engine?.handle(message)
        }
    }

    /// 현재 게임의 최대 정원
    private var activeMaxPlayers: Int {
        switch gameKind {
        case .moonlit: return GameRules.playerRange.upperBound
        case .liar:    return LiarRules.playerRange.upperBound
        case .wolf:    return WolfRules.playerRange.upperBound
        case .sketch:  return SketchRules.playerRange.upperBound
        }
    }

    /// 피어가 그 플레이어 하나만 나르는 직결 연결일 때만 물리 연결을 끊는다.
    /// (릴레이 피어를 끊으면 뒤에 붙은 다른 플레이어까지 같이 끊기므로)
    private func disconnectIfDirect(_ pid: UUID, peer: MCPeerID) {
        let carried = playersForPeer[peer] ?? []
        if carried.isEmpty || carried == [pid] {
            service?.disconnectPeer(peer)
        }
    }

    /// 추방 UI 확인용: 가짜 플레이어들이 있는 방을 연다. (시뮬레이터 시연 전용)
    /// midGame이면 게임을 시작하고 한 명을 끊긴 상태로 만들어 재접속 대기 배너를 띄운다.
    func startKickPreview(midGame: Bool) {
        hostGame(kind: .moonlit)
        guard let engine else { return }
        let bots = ["난희", "무명", "달수", "별이"].map { (id: UUID(), name: $0) }
        for bot in bots { engine.join(playerID: bot.id, name: bot.name, isHost: false) }
        guard midGame else { return }
        engine.handle(.startGame(playerID: playerID))
        for bot in bots { engine.handle(.confirmRole(playerID: bot.id)) }
        engine.setConnected(bots[0].id, false)
        // 잠시 후 자동으로 추방해 추방 동작까지 시연한다
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.kickPlayer(bots[0].id)
        }
    }

    // MARK: - 게임방법 (데모 모드)

    /// 봇들과 함께 한 단계씩 배우는 데모 판을 연다. 네트워크 없이 로컬에서 돌며,
    /// 사용자는 자기 차례의 행동을 직접 해보고 '다음'으로 봇들을 진행시킨다.
    func startDemo(kind: GameKind = .moonlit, auto: Bool = false) {
        cleanup()
        isHost = true
        gameKind = kind
        showDemoIntro = !auto  // 먼저 게임 목적·승리 조건을 보여준다 (자동 시연은 건너뜀)
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
            // 마을 사람이 걸리면 능력을 체험하지 못하므로 행동 역할을 보장
            wolfEngine?.guaranteeActionRoleFor = playerID
            wolfEngine?.join(playerID: playerID, name: trimmedName, isHost: true)
            if let wolfEngine {
                let driver = WolfDemoDriver(engine: wolfEngine, hostID: playerID)
                wolfDemoDriver = driver
                driver.start()
            }
        case .sketch:
            setupSketchEngine()
            if let sketchEngine {
                // 드라이버가 사용자를 첫 화가로 지정하므로 join 전에 생성한다
                let driver = SketchDemoDriver(engine: sketchEngine, hostID: playerID, auto: auto)
                sketchDemoDriver = driver
                sketchEngine.join(playerID: playerID, name: trimmedName, isHost: true)
                driver.start()
            }
        }
        mode = .hosting
    }

    /// 데모(달 없는 밤) 전용: 연습에서만 공개하는 '밤사이 일어난 일' 요약
    func demoNightSummary() -> String? {
        wolfDemoDriver?.nightSummary()
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
        case .sketch:
            if let state = sketchState { sketchDemoDriver?.advance(from: state) }
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
        service.myPlayerID = playerID
        self.service = service

        service.onHostsChanged = { [weak self] hosts in
            guard let self else { return }
            Task { @MainActor in
                if let filter = self.browseFilter {
                    self.hosts = hosts.filter { $0.gameName == filter.displayName }
                } else {
                    self.hosts = hosts
                }
                // 이어서 하기: 기억해 둔 방이 다시 보이면 즉시 재참가
                if let want = self.pendingRejoinRoomID, self.mode == .browsing,
                   let room = self.hosts.first(where: { $0.id == want }) {
                    self.pendingRejoinRoomID = nil
                    self.join(host: room)
                } else if self.autoJoinRoom, self.mode == .browsing,
                          let first = self.hosts.first {
                    self.join(host: first)
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
        // 세션이 끊기거나 앱을 껐다 켜도 이어서 할 수 있게 방을 기억한다
        saveLastRoom(LastRoom(roomID: host.roomID,
                              hostName: host.hostName,
                              gameName: host.gameName ?? ""))
        service.join(host: host)
    }

    /// 클라이언트: 방에 자리가 있거나 재접속 대기자가 있으면 이 기기도
    /// 릴레이(추가 접속 지점)가 되어 준다. 상태를 받을 때마다 갱신한다.
    private func updateRelayAvailability(lobby: Bool, playerCount: Int,
                                         maxPlayers: Int, anyDisconnected: Bool) {
        service?.setRelayAvailable((lobby && playerCount < maxPlayers) || anyDisconnected)
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
            updateRelayAvailability(lobby: state.phase == .lobby,
                                    playerCount: state.players.count,
                                    maxPlayers: GameRules.playerRange.upperBound,
                                    anyDisconnected: !state.disconnectedPlayers.isEmpty)
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
            updateRelayAvailability(lobby: state.phase == .lobby,
                                    playerCount: state.players.count,
                                    maxPlayers: LiarRules.playerRange.upperBound,
                                    anyDisconnected: !state.disconnectedPlayers.isEmpty)
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
            updateRelayAvailability(lobby: state.phase == .lobby,
                                    playerCount: state.players.count,
                                    maxPlayers: WolfRules.playerRange.upperBound,
                                    anyDisconnected: !state.disconnectedPlayers.isEmpty)
        case .wolfPrivate(let info):
            if info != wolfPrivate { wolfPrivate = info }
        case .sketchState(let state):
            gameKind = .sketch
            if state != sketchState { sketchState = state }
            if connectionLost { connectionLost = false }
            cancelReconnectDeadline()
            if mode == .connecting { mode = .playing }
            if state.phase != .lobby, sketchPrivate == nil,
               Date().timeIntervalSince(lastPrivateInfoRequest) > 3 {
                lastPrivateInfoRequest = Date()
                service?.sendToHost(.join(playerID: playerID, name: trimmedName))
            }
            updateRelayAvailability(lobby: state.phase == .lobby,
                                    playerCount: state.players.count,
                                    maxPlayers: SketchRules.playerRange.upperBound,
                                    anyDisconnected: !state.disconnectedPlayers.isEmpty)
        case .sketchPrivate(let info):
            if info != sketchPrivate { sketchPrivate = info }
        case .rejected(let reason):
            errorMessage = reason
            leaveGame()
        case .kicked:
            errorMessage = "방장이 회원님을 내보냈습니다."
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

    /// 달빛 화실 액션
    func performSketch(_ action: SketchAction) {
        if isHost {
            sketchEngine?.handle(playerID, action)
        } else {
            service?.sendToHost(.sketchAction(playerID: playerID, action: action))
        }
    }

    // MARK: - GM(진행자) 제어 — 호스트 전용, 활성 엔진에서 직접 읽는다

    /// 현재 게임의 참가자 목록 (GM 패널용)
    var gmPlayers: [PlayerPublic] {
        publicState?.players ?? liarState?.players
            ?? wolfState?.players ?? sketchState?.players ?? []
    }

    /// 플레이어별 비공개 정보 (역할·라이어 여부 등)
    var gmSecrets: [UUID: String] {
        guard isHost else { return [:] }
        return engine?.gmSecrets() ?? liarEngine?.gmSecrets()
            ?? wolfEngine?.gmSecrets() ?? sketchEngine?.gmSecrets() ?? [:]
    }

    /// 판 전체 비밀 요약 (제시어·중앙 카드 등)
    var gmNote: String? {
        guard isHost else { return nil }
        return engine?.gmNote() ?? liarEngine?.gmNote()
            ?? wolfEngine?.gmNote() ?? sketchEngine?.gmNote()
    }

    /// 강제 진행이 수행할 일 설명. nil이면 현재 단계에서 강제 진행 불가.
    var gmForceAdvanceLabel: String? {
        guard isHost else { return nil }
        return engine?.gmForceAdvanceLabel() ?? liarEngine?.gmForceAdvanceLabel()
            ?? wolfEngine?.gmForceAdvanceLabel() ?? sketchEngine?.gmForceAdvanceLabel()
    }

    /// GM 강제 진행: 미응답자를 기본 처리하고 현재 단계를 끝낸다.
    func gmForceAdvance() {
        guard isHost else { return }
        // 활성 엔진은 하나뿐이므로 모두 호출해도 안전하다
        engine?.forceAdvance(by: playerID)
        liarEngine?.forceAdvance(by: playerID)
        wolfEngine?.forceAdvance(by: playerID)
        sketchEngine?.forceAdvance(by: playerID)
    }

    /// 호스트: 플레이어 추방. 엔진에서 제거하고, 아직 연결돼 있으면
    /// 추방 통지를 보낸 뒤 세션을 끊는다. (끊긴 채 방치된 사람 정리가 주 용도)
    func kickPlayer(_ targetID: UUID) {
        guard isHost, targetID != playerID else { return }
        if let peer = peerForPlayer[targetID] {
            sendToPlayer(targetID, .kicked)
            disconnectIfDirect(targetID, peer: peer)
        }
        // 활성 엔진은 하나뿐이므로 모두 호출해도 안전하다
        engine?.removePlayer(targetID, by: playerID)
        liarEngine?.removePlayer(targetID, by: playerID)
        wolfEngine?.removePlayer(targetID, by: playerID)
        sketchEngine?.removePlayer(targetID, by: playerID)
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
                self.errorMessage = "호스트에 다시 연결하지 못했습니다. 홈의 '이어서 하기'로 다시 참가할 수 있습니다."
                self.leaveGame(forgetRoom: false)   // 방을 기억해 두어 이어서 할 수 있게
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

    /// 게임에서 나간다. 재접속 제한시간 초과처럼 '의도치 않은' 퇴장은
    /// forgetRoom=false로 방 기억을 남겨 홈에서 이어서 참가할 수 있게 한다.
    func leaveGame(forgetRoom: Bool = true) {
        if forgetRoom, !isHost { forgetLastRoom() }
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
        sketchDemoDriver?.stop()
        sketchDemoDriver = nil
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
        sketchEngine?.onStateChange = nil
        sketchEngine?.onPrivateInfo = nil
        sketchEngine = nil
        publicState = nil
        privateInfo = nil
        liarState = nil
        liarPrivate = nil
        wolfState = nil
        wolfPrivate = nil
        sketchState = nil
        sketchPrivate = nil
        gameKind = .moonlit
        hosts = []
        connectionLost = false
        peerForPlayer = [:]
        playersForPeer = [:]
        pendingRejoinRoomID = nil
        isHost = false
    }

    /// MCPeerID displayName 충돌 방지용 짧은 식별자
    private var shortID: String {
        String(playerID.uuidString.prefix(4))
    }
}
