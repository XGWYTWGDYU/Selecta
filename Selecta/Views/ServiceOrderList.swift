import SwiftUI

struct ServiceOrderList: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        List {
            ForEach(preferences.enabledProviders) { provider in
                HStack(spacing: 8) {
                    Image(provider.rawValue).resizable().scaledToFit().frame(width: 18, height: 18)
                    Text(provider.rawValue)
                    Spacer()
                    Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                }
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .onMove { preferences.moveEnabledServices(from: $0, to: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(height: CGFloat(preferences.enabledProviders.count) * 34 + 8)
    }
}
