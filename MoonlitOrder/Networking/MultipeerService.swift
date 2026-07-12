import Foundation
import MultipeerConnectivity
import os

/// MultipeerConnectivity 래퍼.
/// - 호스트: 광고(advertise)를 게임 내내 유지하고, 세션을 여러 개 운용해
///   MCSession의 세션당 8피어 제한을 넘는 인원(최대 10명)도 수용한다.
/// - 클라이언트: 탐색(browse)을 유지하다가 연결이 끊기면 같은 호스트를
///   자동으로 다시 초대해 재접속한다. (스타 토폴로지: 모든 통신은 호스트 경유)
final class MultipeerService: NSObject {

    static let serviceType = "moonorder"   // Info.plist의 NSBonjourServices와 일치해야 함

    private static let log = Logger(subsystem: "MoonlitOrder", category: "MultipeerService")

    enum PeerRole { case host, client }

    struct DiscoveredHost: Identifiable, Equatable {
        let peer: MCPeerID
        let hostName: String
        let gameName: String?
        var id: String { peer.displayName }

        static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool {
            lhs.peer == rhs.peer && lhs.hostName == rhs.hostName
                && lhs.gameName == rhs.gameName
        }
    }

    let role: PeerRole
    let myPeerID: MCPeerID

    private var sessions: [MCSession] = []
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var isAdvertising = false
    private var isBrowsing = false

    /// 각 피어가 현재 소속된 세션. 재접속으로 피어가 새 세션에 옮겨간 뒤
    /// 구(舊) 세션에서 뒤늦게 도착하는 끊김 이벤트를 걸러내는 기준이 된다.
    private var peerSession: [MCPeerID: MCSession] = [:]

    // 클라이언트 전용
    private(set) var hostPeer: MCPeerID?
    private var desiredHostDisplayName: String?
    private var autoReconnect = false
    private var isInviting = false     // 초대(핸드셰이크) 중복 방지
    private var inviteGeneration = 0   // 이전 초대의 안전 타이머 무효화용
    private var discovered: [MCPeerID: (host: String, game: String?)] = [:]

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
                                                            "game": gameName],
                                            serviceType: MultipeerService.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
        isAdvertising = true
    }

    /// 광고 라디오를 필요할 때만 켠다. 게임 중 전원이 접속해 있으면 꺼서
    /// 배터리를 아끼고, 로비이거나 끊긴 플레이어가 있으면 재접속을 위해 켠다.
    func setAdvertisingEnabled(_ enabled: Bool) {
        guard role == .host, let advertiser, enabled != isAdvertising else { return }
        isAdvertising = enabled
        if enabled {
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

    // MARK: - 클라이언트

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
        desiredHostDisplayName = host.peer.displayName
        autoReconnect = true
        invite(peer: host.peer)
    }

    private func invite(peer: MCPeerID) {
        // 이미 핸드셰이크가 진행 중이면 중복 초대로 그 연결을 끊지 않는다.
        guard !isInviting else { return }
        isInviting = true
        inviteGeneration += 1
        let generation = inviteGeneration
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

    // MARK: - 전송

    func send(_ message: NetMessage, to peer: MCPeerID) {
        guard let data = NetCoder.encode(message) else { return }
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

    func sendToHost(_ message: NetMessage) {
        guard let host = hostPeer else { return }
        send(message, to: host)
    }

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
        }
    }

    // MARK: - 생명주기

    /// 포그라운드 복귀 시 호출. 백그라운드에서 iOS가 정지시킨 광고/탐색을 되살리고,
    /// 끊김 콜백 없이 세션만 죽은 경우 재접속을 강제한다.
    /// 라디오는 실제로 필요한 경우에만 다시 깨운다.
    func refreshAfterForeground() {
        switch role {
        case .host:
            guard isAdvertising else { return }
            advertiser?.stopAdvertisingPeer()
            advertiser?.startAdvertisingPeer()
        case .client:
            // 연결이 살아 있으면 탐색 라디오를 깨울 필요가 없다
            if let host = hostPeer, connectedPeers.contains(host) { return }
            if isBrowsing {
                browser?.stopBrowsingForPeers()
                browser?.startBrowsingForPeers()
            }
            ensureConnected()
        }
    }

    /// 클라이언트: 호스트와의 연결이 실제로 살아 있는지 확인하고, 죽었으면 재접속한다.
    private func ensureConnected() {
        guard role == .client, autoReconnect, let host = hostPeer else { return }
        guard !connectedPeers.contains(host) else { return }
        isInviting = false
        onConnectionLost?()
        attemptReconnect()
    }

    // MARK: - 종료

    func stop() {
        autoReconnect = false
        isInviting = false
        inviteGeneration += 1
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isAdvertising = false
        browser?.stopBrowsingForPeers()
        browser = nil
        isBrowsing = false
        for session in sessions { session.disconnect() }
        sessions.removeAll()
        peerSession.removeAll()
        discovered.removeAll()
        hostPeer = nil
    }

    private func publishHosts() {
        let hosts = discovered
            .map { DiscoveredHost(peer: $0.key,
                                  hostName: $0.value.host,
                                  gameName: $0.value.game) }
            .sorted { $0.hostName < $1.hostName }
        onHostsChanged?(hosts)
    }
}

// MARK: - MCSessionDelegate

extension MultipeerService: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch state {
            case .connected:
                self.peerSession[peerID] = session
                self.isInviting = false
                self.inviteGeneration += 1   // 대기 중인 초대 안전 타이머 무효화
                if self.role == .client { self.pauseBrowsing() }
                self.onPeerConnected?(peerID)
            case .notConnected:
                // 피어가 재접속으로 새 세션에 이미 옮겨간 경우,
                // 구 세션에서 뒤늦게 온 끊김 이벤트는 무시한다.
                if let current = self.peerSession[peerID], current !== session { return }
                self.peerSession[peerID] = nil
                self.isInviting = false
                if self.role == .client {
                    if peerID == self.hostPeer {
                        self.onConnectionLost?()
                        self.attemptReconnect()
                    }
                } else {
                    self.onPeerDisconnected?(peerID)
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    /// 연결이 끊긴 클라이언트가 같은 호스트를 다시 초대한다.
    /// 브라우저는 계속 켜져 있으므로, 호스트가 아직 보이면 즉시,
    /// 안 보이면 foundPeer 콜백에서 다시 시도된다.
    private func attemptReconnect() {
        guard autoReconnect, role == .client else { return }
        startBrowsing()
        if let want = desiredHostDisplayName,
           let peer = discovered.keys.first(where: { $0.displayName == want }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.autoReconnect else { return }
                guard !(self.sessions.first?.connectedPeers.contains(peer) ?? false) else { return }
                self.hostPeer = peer
                self.invite(peer: peer)
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = NetCoder.decode(data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onMessage?(message, peerID)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate (호스트)

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // 재접속하는 피어의 이전 연결이 세션에 남아 있으면 먼저 정리한다.
        // (구 연결이 남으면 죽은 세션으로 전송되거나, 뒤늦은 끊김 이벤트가
        //  재접속 완료 상태를 덮어쓰는 레이스가 생긴다)
        for session in sessions where session.connectedPeers.contains(peerID) {
            session.cancelConnectPeer(peerID)
        }
        // 정원 검사는 게임 엔진(join 처리)에서 하고, 여기서는 일단 수락한다.
        invitationHandler(true, sessionWithCapacity())
    }
}

// MARK: - MCNearbyServiceBrowserDelegate (클라이언트)

extension MultipeerService: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let game = (info?["game"]).flatMap { $0.isEmpty ? nil : $0 }
            self.discovered[peerID] = (host: info?["host"] ?? peerID.displayName,
                                       game: game)
            self.publishHosts()

            // 재접속 대상 호스트가 다시 나타나면 자동으로 초대
            if self.autoReconnect,
               peerID.displayName == self.desiredHostDisplayName,
               !(self.connectedPeers.contains(peerID)) {
                self.hostPeer = peerID
                self.invite(peer: peerID)
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
