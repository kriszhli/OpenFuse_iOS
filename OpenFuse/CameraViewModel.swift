//
//  CameraViewModel.swift
//  OpenFuse
//
//  Created by Kris Li on 8/21/25.
//

import AVFoundation
import Photos
import SwiftUI
import UIKit

@MainActor
final class CameraViewModel: ObservableObject {
    // Public for UI
    let session = AVCaptureSession()
    @Published var isFlashOn: Bool = false
    @Published var didSave: Bool = false
    @Published var showPermissionAlert: Bool = false
    @Published var isConfiguring: Bool = false
    @Published var errorMessage: String?

    private let service = CameraService()
    private var isConfigured = false

    var supportsCamera: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    func configure() async {
        guard !isConfiguring else { return }
        
        isConfiguring = true
        errorMessage = nil
        
        // Simulator doesn't have camera hardware
        guard supportsCamera else {
            await MainActor.run {
                isConfiguring = false
                errorMessage = "Camera not available on Simulator."
            }
            return
        }
        
        switch await checkPermissions() {
        case true:
            do {
                try await service.configureSession(session: session, position: .back)
                await service.startSession(session)
                await MainActor.run {
                    isConfigured = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Camera setup failed: \(error.localizedDescription)"
                }
                print("Session configuration failed: \(error)")
            }
        case false:
            await MainActor.run {
                showPermissionAlert = true
            }
        }
        
        await MainActor.run {
            isConfiguring = false
        }
    }

    func toggleFlash() {
        isFlashOn.toggle()
    }

    func flipCamera() async {
        guard supportsCamera else { return }
        await MainActor.run {
            isConfiguring = true
        }
        
        do {
            try await service.flipCamera(on: session)
        } catch {
            await MainActor.run {
                errorMessage = "Failed to flip camera: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isConfiguring = false
        }
    }

    func capturePhoto() async {
        guard supportsCamera else {
            await MainActor.run { errorMessage = "Camera not available on Simulator." }
            return
        }
        do {
            let data = try await service.capturePhoto(on: session, flash: isFlashOn)
            try await saveToPhotos(imageData: data)
            await MainActor.run {
                didSave = true
            }
        } catch {
            await MainActor.run {
                errorMessage = "Photo capture failed: \(error.localizedDescription)"
            }
            print("Capture error: \(error)")
        }
    }

    // MARK: - App Lifecycle Management
    
    func pauseSession() {
        Task { await service.stopSession(session) }
    }

    func resumeSession() {
        guard isConfigured else { return }
        Task { await service.startSession(session) }
    }

    // MARK: - Permissions

    private func checkPermissions() async -> Bool {
        // Camera
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        var cameraOK = camStatus == .authorized
        if camStatus == .notDetermined {
            cameraOK = await AVCaptureDevice.requestAccess(for: .video)
        }

        // Photo Library (Add Only)
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        var photoOK = photoStatus == .authorized || photoStatus == .limited
        if photoStatus == .notDetermined {
            let s = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            photoOK = s == .authorized || s == .limited
        }

        return cameraOK && photoOK
    }

    // MARK: - Save

    private func saveToPhotos(imageData: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: imageData, options: nil)
        }
    }

    // MARK: - Settings

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
