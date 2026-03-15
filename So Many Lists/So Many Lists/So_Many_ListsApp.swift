//
//  So_Many_ListsApp.swift
//  So Many Lists
//
//  Created by Kevin Flathers on 3/12/26.
//

import SwiftUI
import SwiftData

@main
struct So_Many_ListsApp: App {
    @StateObject private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ListDocument.self,
            ListSectionModel.self,
            ListEntry.self,
            StarterSetDocument.self,
            StarterSetSectionModel.self,
            StarterSetEntryModel.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    appState.handle(url: url)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
