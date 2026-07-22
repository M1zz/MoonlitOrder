import SwiftUI
import LeeoKit

struct MoonlitOrderSupportView: View {
    var body: some View {
        NavigationStack {
            List {
                Section { LeeoSupportSection<MoonlitOrderSpec>() } header: { Text("지원") }
            }
            .navigationTitle("설정")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
