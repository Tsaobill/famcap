import SwiftData
import SwiftUI

@main
struct FamilyWealthAppApp: App {
    @AppStorage("appLanguageCode") private var appLanguageCode = AppLanguage.system.rawValue

    private let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Household.self,
            Member.self,
            Asset.self,
            NetWorthSnapshot.self,
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, selectedLanguage.locale)
        }
        .modelContainer(sharedModelContainer)
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageCode) ?? .system
    }
}
