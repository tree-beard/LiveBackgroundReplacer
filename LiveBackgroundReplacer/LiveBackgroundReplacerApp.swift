//
//  LiveBackgroundReplacerApp.swift
//  LiveBackgroundReplacer
//
//  Created by David Arakelyan on 21.08.2024.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct LiveBackgroundReplacerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
