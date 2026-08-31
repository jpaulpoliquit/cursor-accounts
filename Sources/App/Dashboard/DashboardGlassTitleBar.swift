import CursorBarDomain
import SwiftUI

/// Tabs for the system toolbar. Do not wrap these in a painted header strip.
struct DashboardProfileTabBar: View {
    @Binding var selection: DashboardTab

    var body: some View {
        Picker("Section", selection: $selection) {
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                Text(tab.title)
                    .tag(tab)
                    .accessibilityLabel(tab.accessibilityLabel)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.regular)
        .frame(minWidth: 220)
        .accessibilityLabel("Dashboard section")
    }
}
