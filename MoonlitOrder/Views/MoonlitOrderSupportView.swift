import SwiftUI
import LeeoKit

struct MoonlitOrderSupportView: View {
    /// 메일 앱이 없거나 계정이 없으면 mailto: 를 열 수 없다 — 그때는 주소를 보여 주고 복사할 수 있게 한다.
    @State private var showMailFallback = false

    private var mailURL: URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = MoonlitOrderSpec.developerEmail
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        c.queryItems = [URLQueryItem(name: "subject", value: String(localized: "[달빛 오락실 \(version)] 문의"))]
        return c.url
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LeeoSupportSection<MoonlitOrderSpec>()
                    // 앞으로 만들 기능 — 원본은 MoonlitOrderRoadmap.swift
                    NavigationLink(LeeoRoadmapText.entry) { RoadmapScreen() }
                } header: { Text("지원") }

                Section {
                    Button {
                        guard let url = mailURL else { showMailFallback = true; return }
                        UIApplication.shared.open(url) { opened in
                            if !opened { showMailFallback = true }
                        }
                    } label: {
                        externalRow(String(localized: "메일로 문의하기"), systemImage: "envelope.fill")
                    }

                    // 핸들(@lee25_ios)은 고유명사라 그대로 둔다.
                    Link(destination: URL(string: "https://instagram.com/lee25_ios")!) {
                        externalRow(String(localized: "인스타그램 DM (@lee25_ios)"), systemImage: "paperplane.fill")
                    }
                } header: {
                    Text("개발자에게 연락하기")
                } footer: {
                    Text("버그 제보나 바라는 게임이 있다면 편하게 알려 주세요.")
                }
            }
            .navigationTitle("설정")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .alert("메일 앱을 열 수 없어요", isPresented: $showMailFallback) {
                Button("주소 복사") { UIPasteboard.general.string = MoonlitOrderSpec.developerEmail }
                Button("닫기", role: .cancel) {}
            } message: {
                Text("아래 주소로 메일을 보내 주세요.\n\(MoonlitOrderSpec.developerEmail)")
            }
        }
    }

    private func externalRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
