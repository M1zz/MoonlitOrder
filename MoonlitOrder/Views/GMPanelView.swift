import SwiftUI

/// GM(진행자) 제어판 — 호스트 전용 시트.
/// 멈춘 단계의 강제 진행, 참가자 관리(추방), 비공개 정보 열람을 한곳에서 제공한다.
struct GMPanelView: View {
    @EnvironmentObject var game: GameViewModel
    @Environment(\.dismiss) private var dismiss

    // -gmPreview 시연에서는 비공개 정보를 켠 채로 시작한다
    @State private var showSecrets = ProcessInfo.processInfo.arguments.contains("-gmPreview")
    @State private var kickTarget: PlayerPublic?
    @State private var confirmAdvance = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header

                    forceAdvanceSection

                    playerSection

                    secretSection
                }
                .padding(20)
            }
        }
        .confirmationDialog("단계를 강제로 진행할까요?",
                            isPresented: $confirmAdvance,
                            titleVisibility: .visible) {
            Button("강제 진행", role: .destructive) { game.gmForceAdvance() }
            Button("취소", role: .cancel) {}
        } message: {
            Text(game.gmForceAdvanceLabel ?? "")
        }
        .confirmationDialog(kickTarget.map { "\($0.name) 님을 내보낼까요?" } ?? "",
                            isPresented: Binding(get: { kickTarget != nil },
                                                 set: { if !$0 { kickTarget = nil } }),
                            titleVisibility: .visible,
                            presenting: kickTarget) { target in
            Button("내보내기", role: .destructive) { game.kickPlayer(target.id) }
            Button("취소", role: .cancel) {}
        } message: { _ in
            Text("내보낸 뒤에도 진행 중인 게임은 남은 인원으로 계속됩니다.")
        }
    }

    // MARK: 상단

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "crown.fill")
                .font(.title)
                .foregroundColor(Theme.gold)
            Text("GM 진행자 모드")
                .font(.title2.weight(.heavy))
                .foregroundColor(.white)
            Text("진행이 막히면 여기서 게임을 계속 굴릴 수 있어요.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.top, 20)
    }

    // MARK: 진행 제어

    @ViewBuilder
    private var forceAdvanceSection: some View {
        sectionCard(title: "진행 제어", icon: "forward.frame.fill") {
            if let label = game.gmForceAdvanceLabel {
                Text(label)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    confirmAdvance = true
                } label: {
                    Label("단계 강제 진행", systemImage: "forward.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.gold.opacity(0.25)))
                        .foregroundColor(Theme.gold)
                }
            } else {
                Text("지금 단계에서는 강제 진행할 것이 없습니다.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 참가자 관리

    private var playerSection: some View {
        sectionCard(title: "참가자 관리", icon: "person.3.fill") {
            ForEach(game.gmPlayers) { p in
                PlayerRow(player: p,
                          isMe: p.id == game.playerID,
                          showActed: true,
                          trailing: showSecrets ? game.gmSecrets[p.id] : nil,
                          onKick: p.isHost ? nil : { kickTarget = p })
            }
        }
    }

    // MARK: 비공개 정보

    private var secretSection: some View {
        sectionCard(title: "비공개 정보", icon: "eye.fill") {
            Toggle(isOn: $showSecrets.animation()) {
                Text("역할·정답 공개")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
            }
            .tint(Theme.gold)

            Text("확인하면 GM 본인의 공정한 플레이는 어려워집니다. 진행이 꼬였을 때만 사용하세요.")
                .font(.caption2)
                .foregroundColor(Theme.shadow.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)

            if showSecrets, let note = game.gmNote {
                Text(note)
                    .font(.subheadline.bold())
                    .foregroundColor(Theme.gold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.gold.opacity(0.1)))
            }
        }
    }

    // MARK: 헬퍼

    private func sectionCard<Content: View>(title: String, icon: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            Label(title, systemImage: icon)
                .font(.footnote.bold())
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
    }
}
