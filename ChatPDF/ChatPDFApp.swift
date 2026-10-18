//
//  ChatPDFApp.swift
//  ChatPDF
//
//  Created by Sharan Thakur on 01/05/26.
//

import SwiftUI

@main
struct ChatPDFApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1100, height: 720)
        .commands { ChatPDFCommands() }
    }
}
