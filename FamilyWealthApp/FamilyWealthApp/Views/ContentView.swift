import SwiftData
import SwiftUI

private enum RootTab: Hashable {
    case dashboard
    case assets
    case settings
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var didSeed = false
    @State private var selectedTab: RootTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tag(RootTab.dashboard)
                .tabItem {
                    Label(AppLocalizer.string("tab.dashboard"), systemImage: "chart.pie.fill")
                }

            AssetsView()
                .tag(RootTab.assets)
                .tabItem {
                    Label(AppLocalizer.string("tab.assets"), systemImage: "list.bullet.rectangle.portrait.fill")
                }

            SettingsView()
                .tag(RootTab.settings)
                .tabItem {
                    Label(AppLocalizer.string("tab.me"), systemImage: "person.crop.circle.fill")
                }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            customBottomDock
        }
        .task {
            guard !didSeed else {
                return
            }

            AppSeeder.seedIfNeeded(modelContext: modelContext)
            didSeed = true
        }
    }

    @ViewBuilder
    private var customBottomDock: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.primary.opacity(0.08))

            HStack(spacing: 0) {
                dockItem(
                    title: AppLocalizer.string("tab.dashboard"),
                    systemImage: "chart.pie.fill",
                    tab: .dashboard
                )
                dockItem(
                    title: AppLocalizer.string("tab.assets"),
                    systemImage: "list.bullet.rectangle.portrait.fill",
                    tab: .assets
                )
                dockItem(
                    title: AppLocalizer.string("tab.me"),
                    systemImage: "person.crop.circle.fill",
                    tab: .settings
                )
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private func dockItem(
        title: String,
        systemImage: String,
        tab: RootTab
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Household.self, Member.self, Asset.self, NetWorthSnapshot.self], inMemory: true)
}
