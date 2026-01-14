//
//  UnfollowersApp.swift
//  Unfollowers
//
//  Created by Muhammed Hakan Celik on 19.12.2025.
//

import SwiftUI

@main
struct UnfollowersApp: App {
    @StateObject private var languageManager = LanguageManager()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: languageManager.currentLanguage.rawValue))
                .id(languageManager.currentLanguage.rawValue)
                .environmentObject(languageManager)
        }
    }
}
