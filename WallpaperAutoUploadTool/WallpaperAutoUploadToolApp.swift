//
//  WallpaperAutoUploadToolApp.swift
//  WallpaperAutoUploadTool
//
//  Created by boyyang on 2026/9/22.
//

import SwiftUI
import SwiftData

@main
struct WallpaperAutoUploadToolApp: App {
    @State private var settings = AppSettings()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UploadRecord.self,
            UploadRecordItem.self,
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
                .environment(settings)
        }
        .modelContainer(sharedModelContainer)
    }
}
