import Foundation
import MultipeerConnectivity
import os

/// MultipeerConnectivity 래퍼 — 릴레이 트리 토폴로지.
///
/// MCSession은 세션 안의 모든 피어가 서로 물리 링크를 유지하는 메시라서,
/// 한 세션에 6명 이상이 모이면 라디오 부하로 급격히 불안정해진다.
/// 그래서 호스트 직결 인원을 제한하고, 그 이후 참가자는 이미 접속한
/// 클라이언트(릴레이)의 자식으로 붙어 트리를 이룬다:
///
///   호스트 ── 직결 클라이언트 (최대 5)
///                └─ 릴레이의 자식 (릴레이당 최대 2, 깊이 제한 없음)
///
/// 라우팅 규칙은 방향 기반이라 단순하다.
/// - 위(자식 → 부모): 모든 게임 액션. 릴레이는 그대로 부모에게 흘려보내며
///   playerID ↔ 자식 피어 매핑을 학습한다.
/// - 아래(부모 → 자식): 상태 브로드캐스트는 전 자식에게 재전파,
///   .toPlayer 봉투는 해당 플레이어가 붙은 가지로만 흘려보낸다.
/// - 자식이 끊기면 릴레이가 호스트에게 .playerGone을 올린다.
///
/// 클라이언트는 연결이 끊기면 같은 방(roomID)을 광고하는 아무 지점
/// (호스트든 릴레이든)에 다시 붙는다. 상태 복원은 playerID 기반이라
/// 어디에 붙어도 동일하게 동작한다.
final class MultipeerService: NSObject {

    static let serviceType = "moonorder"   // Info.plist의 NSBonjourServices와 일치해야 함

    private static let log = Logger(subsystem: "MoonlitOrder", category: "MultipeerService")

    /// 호스트가 직접 받는 원격 피어 수. 세션 메시 부하가 급증하기 전 선에서 자른다.
    static let hostDirectMax = intArg("-hostDirectMax", default: 5)
    /// 릴레이 하나가 받는 자식 수
    static let relayChildMax = intArg("-relayChildMax", default: 2)

    private static func intArg(_ name: String, default def: Int) -> Int {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: name), a.indices.contains(i + 1),
              let v = Int(a[i + 1]) else { return def }
        return v
    }

    enum PeerRole { case host, client }

    struct DiscoveredHost: Identifiable, Equatable {
        let peer: MCPeerID          // 실제로 초대를 보낼 접속 지점 (호스트 또는 릴레이)
        let hostName: String
        let gameName: String?
        let roomID: String          // 방 식별자 (호스트 피어 displayName)
        let isRelay: Bool
        var id: String { roomID }

        static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool {
            lhs.peer == rhs.peer && lhs.hostName == rhs.hostName
                && lhs.gameName == rhs.gameName && lhs.roomID == rhs.roomID
        }
    }

    let role: PeerRole
    let myPeerID: MCPeerID
    /// 내 플레이어 ID — .toPlayer 봉투에서 내 몫을 골라내는 기준
    var myPlayerID: UUID?

    private var sessions: [MCSession] = []
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var advertisingDesired = false   // 뷰모델이 원하는 광고 상태 (정원 판단)
    private var advertiserActive = false     // 라디오 실제 상태
    private var isBrowsing = false

    /// 각 피어가 현재 소속된 세션. 재접속으로 피어가 새 세션에 옮겨간 뒤
    /// 구(舊) 세션에서 뒤늦게 도착하는 끊김 이벤트를 걸러내는 기준이 된다.
    private var peerSession: [MCPeerID: MCSession] = [:]

    // 클라이언트 전용 — 부모(위쪽) 연결
    private(set) var hostPeer: MCPeerID?
    private var desiredRoomID: String?
    private var autoReconnect = false
    private var isInviting = false     // 초대(핸드셰이크) 중복 방지
    private var inviteGeneration = 0   // 이전 초대의 안전 타이머 무효화용
    private var discovered: [MCPeerID: (host: String, game: String?, room: String, isRelay: Bool)] = [:]

    // 클라이언트 전용 — 릴레이(아래쪽) 상태
    private var joinedRoom: (host: String, game: String, roomID: String)?
    private var childSession: MCSession?
    private var childPeers: Set<MCPeerID> = []
    private var childForPlayer: [UUID: MCPeerID] = [:]
    private var playersForChild: [MCPeerID: Set<UUID>] = [:]
    private var relayDesired = false   // 방에 자리가 있어 릴레이 광고가 필요한지 (뷰모델이 갱신)

    // 콜백 (모두 메인 스레드에서 호출됨)
    var onMessage: ((NetMessage, MCPeerID) -> Void)?
    var onPeerConnected: ((MCPeerID) -> Void)?
    var onPeerDisconnected: ((MCPeerID) -> Void)?
    var onHostsChanged: (([DiscoveredHost]) -> Void)?
    var onConnectionLost: (() -> Void)?    // 클라이언트: 호스트와 연결 끊김 (자동 재접속 시도 중)

    // MARK: - 초기화

    init(role: PeerRole, displayName: String) {
        self.role = role
        self.myPeerID = MultipeerService.persistentPeerID(displayName: displayName)
        super.init()
    }

    /// MCPeerID를 보관해 재실행/재접속 시에도 같은 피어 정체성을 유지한다.
    private static func persistentPeerID(displayName: String) -> MCPeerID {
        let key = "moonorder.peerID.\(displayName)"
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data),
           saved.displayName == displayName {
            return saved
        }
        let peerID = MCPeerID(displayName: displayName)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: peerID,
                                                        requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return peerID
    }

    private func makeSession() -> MCSession {
        let session = MCSession(peer: myPeerID,
                                securityIdentity: nil,
                                encryptionPreference: .required)
        session.delegate = self
        sessions.append(session)
        return session
    }

    // MARK: - 호스트

    func startHosting(hostName: String, gameName: String = "") {
        _ = makeSession()
        let adv = MCNearbyServiceAdvertiser(peer: myPeerID,
                                            discoveryInfo: ["host": hostName,
                                                            "game": gameName,
                                                            "room": myPeerID.displayName],
                                            serviceType: MultipeerService.serviceType)
        adv.delegate = self
        advertiser = adv
        advertisingDesired = true
        applyAdvertising()
    }

    /// 광고 라디오를 필요할 때만 켠다 (배터리·라디오 부하 절약).
    /// 호스트: 뷰모델이 정원 기준으로 켜고 끄되, 직결 정원이 차면 강제로 끈다.
    func setAdvertisingEnabled(_ enabled: Bool) {
        guard role == .host else { return }
        advertisingDesired = enabled
        applyAdvertising()
    }

    /// 직결 원격 피어 수 (호스트)
    var directPeerCount: Int {
        sessions.reduce(0) { $0 + $1.connectedPeers.count }
    }

    /// 광고 라디오 실제 상태를 갱신한다. 연결 수가 바뀔 때마다 다시 평가된다.
    private func applyAdvertising() {
        guard let advertiser else { return }
        let capacityLeft: Bool
        switch role {
        case .host:   capacityLeft = directPeerCount < MultipeerService.hostDirectMax
        case .client: capacityLeft = childPeers.count < MultipeerService.relayChildMax
        }
        let wanted = (role == .host ? advertisingDesired : relayDesired && hostConnected)
            && capacityLeft
        guard wanted != advertiserActive else { return }
        advertiserActive = wanted
        if wanted {
            advertiser.startAdvertisingPeer()
        } else {
            advertiser.stopAdvertisingPeer()
        }
    }

    /// 여유가 있는 세션을 고른다. (세션당 로컬 포함 8피어 = 원격 7피어 제한)
    private func sessionWithCapacity() -> MCSession {
        if let s = sessions.first(where: { $0.connectedPeers.count < 7 }) {
            return s
        }
        return makeSession()
    }

    // MARK: - 클라이언트 (부모 연결)

    func startBrowsing() {
        if browser == nil {
            let b = MCNearbyServiceBrowser(peer: myPeerID,
                                           serviceType: MultipeerService.serviceType)
            b.delegate = self
            browser = b
        }
        guard !isBrowsing else { return }
        isBrowsing = true
        browser?.startBrowsingForPeers()
    }

    /// 연결이 유지되는 동안에는 탐색 라디오를 멈춰 배터리를 아낀다.
    /// 끊기면 attemptReconnect → startBrowsing()으로 다시 켜진다.
    private func pauseBrowsing() {
        guard isBrowsing else { return }
        isBrowsing = false
        browser?.stopBrowsingForPeers()
        // 탐색 중지 후에는 lostPeer가 오지 않아 목록이 낡으므로 비운다
        discovered.removeAll()
        publishHosts()
    }

    func join(host: DiscoveredHost) {
        hostPeer = host.peer
        desiredRoomID = host.roomID
        joinedRoom = (host: host.hostName, game: host.gameName ?? "", roomID: host.roomID)
        autoReconnect = true
        invite(peer: host.peer)
    }

    private var hostConnected: Bool {
        guard let hostPeer else { return false }
        return connectedPeers.contains(hostPeer)
    }

    private func invite(peer: MCPeerID) {
        // 이미 핸드셰이크가 진행 중이면 중복 초대로 그 연결을 끊지 않는다.
        guard !isInviting else { return }
        isInviting = true
        inviteGeneration += 1
        let generation = inviteGeneration
        // 부모 연결이 바뀌는 동안 자식들은 데리고 갈 수 없다 — 정리하면
        // 자식들이 스스로 다른 접속 지점(호스트/다른 릴레이)에 재접속한다.
        teardownRelay()
        // 끊어진 MCSession의 재사용은 불안정하므로 초대할 때마다 새 세션을 쓴다.
        for s in sessions {
            s.delegate = nil
            s.disconnect()
        }
        sessions.removeAll()
        peerSession.removeAll()
        let session = makeSession()
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 20)
        // 초대 타임아웃 콜백이 유실되는 경우를 대비한 안전장치.
        // 그 사이 연결에 성공했거나 새 초대가 시작됐으면(세대 불일치) 건드리지 않는다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self, self.inviteGeneration == generation else { return }
            self.isInviting = false
        }
    }

    // MARK: - 클라이언트 (릴레이: 아래쪽 자식 관리)

    /// 방에 자리가 있는 동안 이 기기도 접속 지점이 되어 준다.
    /// 뷰모델이 상태 브로드캐스트를 받을 때마다 방 정원 기준으로 갱신한다.
    func setRelayAvailable(_ available: Bool) {
        guard role == .client else { return }
        relayDesired = available
        if advertiser == nil, let room = joinedRoom {
            let adv = MCNearbyServiceAdvertiser(peer: myPeerID,
                                                discoveryInfo: ["host": room.host,
                                                                "game": room.game,
                                                                "room": room.roomID,
                                                                "relay": "1"],
                                                serviceType: MultipeerService.serviceType)
            adv.delegate = self
            advertiser = adv
        }
        applyAdvertising()
    }

    /// 릴레이 역할 종료 — 자식 연결과 광고를 정리한다.
    private func teardownRelay() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        advertiserActive = false
        relayDesired = false
        childSession?.delegate = nil
        childSession?.disconnect()
        childSession = nil
        childPeers.removeAll()
        childForPlayer.removeAll()
        playersForChild.removeAll()
    }

    private func childSessionCreatingIfNeeded() -> MCSession {
        if let childSession { return childSession }
        let session = MCSession(peer: myPeerID,
                                securityIdentity: nil,
                                encryptionPreference: .required)
        session.delegate = self
        childSession = session
        return session
    }

    // MARK: - 전송

    func send(_ message: NetMessage, to peer: MCPeerID) {
        guard let data = NetCoder.encode(message) else { return }
        sendRaw(data, to: peer)
    }

    private func sendRaw(_ data: Data, to peer: MCPeerID) {
        // 자식 피어면 자식 세션으로
        if childPeers.contains(peer), let childSession,
           childSession.connectedPeers.contains(peer) {
            do {
                try childSession.send(data, toPeers: [peer], with: .reliable)
            } catch {
                Self.log.error("자식 송신 실패: \(peer.displayName) — \(error.localizedDescription)")
            }
            return
        }
        // 재접속 직후에는 구 세션에 피어가 잠시 남아 있을 수 있으므로
        // 피어의 현재 세션(peerSession)을 우선해 죽은 세션으로의 전송을 피한다.
        let current = peerSession[peer].flatMap { $0.connectedPeers.contains(peer) ? $0 : nil }
        guard let session = current ?? sessions.first(where: { $0.connectedPeers.contains(peer) }) else {
            Self.log.warning("송신 실패(미연결 피어): \(peer.displayName)")
            return
        }
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            Self.log.error("송신 실패: \(peer.displayName) — \(error.localizedDescription)")
        }
    }

    /// 호스트: 직결 피어 전체에 전송. (릴레이가 자기 자식에게 재전파한다)
    func broadcast(_ message: NetMessage) {
        guard let data = NetCoder.encode(message) else { return }
        for session in sessions where !session.connectedPeers.isEmpty {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                Self.log.error("브로드캐스트 실패: \(error.localizedDescription)")
            }
        }
    }

    /// 자식들에게 원본 데이터를 재전파한다 (릴레이의 하향 흐름)
    private func forwardToChildren(_ data: Data) {
        guard let childSession, !childSession.connectedPeers.isEmpty else { return }
        do {
            try childSession.send(data, toPeers: childSession.connectedPeers, with: .reliable)
        } catch {
            Self.log.error("하향 중계 실패: \(error.localizedDescription)")
        }
    }

    func sendToHost(_ message: NetMessage) {
        guard let host = hostPeer else { return }
        send(message, to: host)
    }

    /// 부모 방향 피어들 (자식 세션 제외)
    var connectedPeers: [MCPeerID] {
        sessions.flatMap { $0.connectedPeers }
    }

    /// 거절 메시지 등이 전달될 시간을 준 뒤 해당 피어의 연결을 끊는다.
    /// (거절된 피어가 세션에 남아 게임 상태 브로드캐스트를 계속 받는 것을 방지)
    func disconnectPeer(_ peer: MCPeerID, after delay: TimeInterval = 0.6) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            for session in self.sessions where session.connectedPeers.contains(peer) {
                session.cancelConnectPeer(peer)
            }
            if let child = self.childSession, child.connectedPeers.contains(peer) {
                child.cancelConnectPeer(peer)
            }
        }
    }

    // MARK: - 생명주기

    /// 포그라운드 복귀 시 호출. 백그라운드에서 iOS가 정지시킨 광고/탐색을 되살리고,
    /// 끊김 콜백 없이 세션만 죽은 경우 재접속을 강제한다.
    func refreshAfterForeground() {
        switch role {
        case .host:
            guard advertiserActive else { return }
            advertiser?.stopAdvertisingPeer()
            advertiser?.startAdvertisingPeer()
        case .client:
            if advertiserActive {
                advertiser?.stopAdvertisingPeer()
                advertiser?.startAdvertisingPeer()
            }
            // 연결이 살아 있으면 탐색 라디오를 깨울 필요가 없다
            if hostConnected { return }
            if isBrowsing {
                browser?.stopBrowsingForPeers()
                browser?.startBrowsingForPeers()
            }
            ensureConnected()
        }
    }

    /// 클라이언트: 부모와의 연결이 실제로 살아 있는지 확인하고, 죽었으면 재접속한다.
    private func ensureConnected() {
        guard role == .client, autoReconnect, hostPeer != nil else { return }
        guard !hostConnected else { return }
        isInviting = false
        onConnectionLost?()
        attemptReconnect()
    }

    // MARK: - 종료

    func stop() {
        autoReconnect = false
        isInviting = false
        inviteGeneration += 1
        teardownRelay()
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        advertisingDesired = false
        advertiserActive = false
        browser?.stopBrowsingForPeers()
        browser = nil
        isBrowsing = false
        for session in sessions { session.disconnect() }
        sessions.removeAll()
        peerSession.removeAll()
        discovered.removeAll()
        hostPeer = nil
        joinedRoom = nil
    }

    /// 같은 방(roomID)의 광고가 여럿(호스트 + 릴레이들)일 수 있으므로
    /// 방 단위로 묶어 하나만 노출한다. 호스트 직결 항목을 우선한다.
    private func publishHosts() {
        var byRoom: [String: DiscoveredHost] = [:]
        for (peer, info) in discovered {
            let entry = DiscoveredHost(peer: peer,
                                       hostName: info.host,
                                       gameName: info.game,
                                       roomID: info.room,
                                       isRelay: info.isRelay)
            if let existing = byRoom[info.room] {
                if existing.isRelay && !entry.isRelay {
                    byRoom[info.room] = entry
                }
            } else {
                byRoom[info.room] = entry
            }
        }
        onHostsChanged?(byRoom.values.sorted { $0.hostName < $1.hostName })
    }
}

// MARK: - MCSessionDelegate

extension MultipeerService: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if session === self.childSession {
                self.childPeerChanged(peerID, state: state)
                return
            }
            switch state {
            case .connected:
                self.peerSession[peerID] = session
                self.isInviting = false
                self.inviteGeneration += 1   // 대기 중인 초대 안전 타이머 무효화
                if self.role == .client { self.pauseBrowsing() }
                self.applyAdvertising()      // 호스트: 직결 정원 재평가
                self.onPeerConnected?(peerID)
            case .notConnected:
                // 피어가 재접속으로 새 세션에 이미 옮겨간 경우,
                // 구 세션에서 뒤늦게 온 끊김 이벤트는 무시한다.
                if let current = self.peerSession[peerID], current !== session { return }
                self.peerSession[peerID] = nil
                self.isInviting = false
                if self.role == .client {
                    if peerID == self.hostPeer {
                        // 부모가 사라지면 중계도 불가능 — 자식들을 놓아주어
                        // 다른 접속 지점에 재접속하게 한다.
                        self.teardownRelay()
                        self.onConnectionLost?()
                        self.attemptReconnect()
                    }
                } else {
                    self.applyAdvertising()  // 자리가 났으니 광고 재개 검토
                    self.onPeerDisconnected?(peerID)
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    /// 릴레이의 자식 연결 상태 변화
    private func childPeerChanged(_ peerID: MCPeerID, state: MCSessionState) {
        switch state {
        case .connected:
            childPeers.insert(peerID)
            Self.log.info("릴레이: 자식 연결됨 \(peerID.displayName)")
            applyAdvertising()   // 자식 정원 재평가
        case .notConnected:
            childPeers.remove(peerID)
            // 이 자식으로 붙어 있던 플레이어들의 끊김을 호스트에 보고한다.
            // (플레이어가 다른 지점으로 이미 재접속했다면 호스트가 무시한다)
            if let pids = playersForChild[peerID] {
                for pid in pids {
                    sendToHost(.playerGone(playerID: pid))
                    childForPlayer[pid] = nil
                }
                playersForChild[peerID] = nil
            }
            applyAdvertising()
        default:
            break
        }
    }

    /// 연결이 끊긴 클라이언트가 같은 방을 다시 찾아 초대한다.
    /// 호스트든 릴레이든 같은 roomID를 광고하는 지점이면 어디든 좋다.
    private func attemptReconnect() {
        guard autoReconnect, role == .client else { return }
        startBrowsing()
        guard let room = desiredRoomID else { return }
        let candidates = discovered.filter { $0.value.room == room }
        // 호스트 직결 광고를 우선하고, 없으면 릴레이에 붙는다
        guard let target = candidates.first(where: { !$0.value.isRelay })?.key
                ?? candidates.keys.first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.autoReconnect else { return }
            guard !self.hostConnected else { return }
            self.hostPeer = target
            self.invite(peer: target)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = NetCoder.decode(data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.route(message, raw: data, from: peerID)
        }
    }

    /// 수신 메시지의 방향을 판정해 중계·전달한다. (메인 스레드)
    private func route(_ message: NetMessage, raw data: Data, from peerID: MCPeerID) {
        guard role == .client else {
            onMessage?(message, peerID)   // 호스트: 항상 최종 수신자
            return
        }
        if childPeers.contains(peerID) {
            // 상향(자식 → 호스트): 매핑을 학습하고 그대로 올려보낸다
            if let pid = message.senderPlayerID {
                if let old = childForPlayer[pid], old != peerID {
                    playersForChild[old]?.remove(pid)
                }
                childForPlayer[pid] = peerID
                playersForChild[peerID, default: []].insert(pid)
            }
            if let host = hostPeer {
                sendRaw(data, to: host)
            }
            return
        }
        // 하향(부모 → 나 그리고/또는 자식들)
        switch message {
        case .toPlayer(let pid, let inner):
            if pid == myPlayerID {
                onMessage?(inner, peerID)
            } else if let child = childForPlayer[pid] {
                sendRaw(data, to: child)     // 봉투째 자식 가지로 (자식이 또 릴레이일 수 있다)
            }
        default:
            forwardToChildren(data)          // 브로드캐스트는 아래로 재전파
            onMessage?(message, peerID)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate (호스트 · 릴레이)

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        switch role {
        case .host:
            // 재접속하는 피어의 이전 연결이 세션에 남아 있으면 먼저 정리한다.
            // (구 연결이 남으면 죽은 세션으로 전송되거나, 뒤늦은 끊김 이벤트가
            //  재접속 완료 상태를 덮어쓰는 레이스가 생긴다)
            for session in sessions where session.connectedPeers.contains(peerID) {
                session.cancelConnectPeer(peerID)
            }
            guard directPeerCount < MultipeerService.hostDirectMax else {
                invitationHandler(false, nil)   // 직결 정원 초과 → 릴레이로 붙게 한다
                return
            }
            // 정원 검사는 게임 엔진(join 처리)에서 하고, 여기서는 일단 수락한다.
            invitationHandler(true, sessionWithCapacity())
        case .client:
            // 릴레이: 부모 연결이 살아 있고 자식 자리가 있을 때만 받는다
            guard hostConnected,
                  childPeers.count < MultipeerService.relayChildMax else {
                invitationHandler(false, nil)
                return
            }
            if let child = childSession, child.connectedPeers.contains(peerID) {
                child.cancelConnectPeer(peerID)
            }
            invitationHandler(true, childSessionCreatingIfNeeded())
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate (클라이언트)

extension MultipeerService: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard peerID != self.myPeerID else { return }
            let game = (info?["game"]).flatMap { $0.isEmpty ? nil : $0 }
            let room = info?["room"] ?? peerID.displayName
            self.discovered[peerID] = (host: info?["host"] ?? peerID.displayName,
                                       game: game,
                                       room: room,
                                       isRelay: info?["relay"] == "1")
            self.publishHosts()

            // 재접속 대상 방이 다시 보이면 자동으로 초대
            if self.autoReconnect,
               room == self.desiredRoomID,
               !self.hostConnected {
                self.attemptReconnect()
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.discovered.removeValue(forKey: peerID)
            self.publishHosts()
        }
    }
}
