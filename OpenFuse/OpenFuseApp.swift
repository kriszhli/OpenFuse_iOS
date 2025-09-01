//
//  OpenFuseApp.swift
//  OpenFuse
//
//  Created by Kris Li on 8/19/25.
//

import SwiftUI
import UIKit

@main
struct OpenFuseApp: App {
    @StateObject private var cameraViewModel = CameraViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cameraViewModel)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    cameraViewModel.pauseSession()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    cameraViewModel.resumeSession()
                }
        }
    }
}
