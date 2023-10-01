//
//  NosturApp.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI

@main
struct NosturApp: App {
    var body: some Scene {
        WindowGroup {
            // Not sure why the preview canvas is loading this on every other view so wrap in condition:
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
                AppView()
            }
        }
    }
}

