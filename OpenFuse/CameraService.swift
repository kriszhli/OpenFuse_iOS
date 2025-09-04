//
//  CameraService.swift
//  OpenFuse
//
//  Created by Kris Li on 8/21/25.
//

@preconcurrency import AVFoundation
import UIKit

enum CameraServiceError: Error {
    case setupFailed
    case captureFailed
    case deviceNotFound
}

actor CameraService {
    private var currentInput: AVCaptureDeviceInput?

    func configureSession(session: AVCaptureSession, position: AVCaptureDevice.Position) async throws {
        // Configure on the actor's executor (off main thread by default)
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Clear previous inputs/outputs if reconfiguring
        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }

        // Input
        guard let device = bestDevice(position: position) else {
            session.commitConfiguration()
            throw CameraServiceError.deviceNotFound
        }

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraServiceError.setupFailed
        }
        session.addInput(input)
        self.currentInput = input

        // Output
        let photoOutput = AVCapturePhotoOutput()

        // Prefer the largest max photo dimensions available (iOS 16+), but only if the SDK provides the symbol.
        if #available(iOS 16.0, *) {
            // Use selector checks to avoid compile-time references on older SDKs.
            let supportedSelector = NSSelectorFromString("supportedMaxPhotoDimensions")
            let setMaxSelector = NSSelectorFromString("setMaxPhotoDimensions:")
            if photoOutput.responds(to: supportedSelector),
               photoOutput.responds(to: setMaxSelector),
               let dimsArray = photoOutput.value(forKey: "supportedMaxPhotoDimensions") as? [CMVideoDimensions],
               !dimsArray.isEmpty {
                var bestDims: CMVideoDimensions = dimsArray[0]
                var bestArea: Int32 = bestDims.width &* bestDims.height
                for dims in dimsArray {
                    let area = dims.width &* dims.height
                    if area > bestArea {
                        bestArea = area
                        bestDims = dims
                    }
                }
                // Set via KVC to avoid compile-time symbol usage
                photoOutput.setValue(bestDims, forKey: "maxPhotoDimensions")
            }
        }

        // Prefer quality over speed when possible
        if #available(iOS 17.0, *) {
            if photoOutput.isContentAwareDistortionCorrectionSupported {
                photoOutput.isContentAwareDistortionCorrectionEnabled = true
            }
        }
        if #available(iOS 14.1, *) {
            if photoOutput.isVirtualDeviceConstituentPhotoDeliverySupported {
                photoOutput.isVirtualDeviceConstituentPhotoDeliveryEnabled = false
            }
        }

        // Quality prioritization (iOS 13+ when compiled with an SDK that includes it)
        if #available(iOS 13.0, *) {
            let selector = NSSelectorFromString("setPhotoQualityPrioritization:")
            if photoOutput.responds(to: selector) {
                // 2 corresponds to AVCapturePhotoQualityPrioritization.quality
                photoOutput.setValue(2, forKey: "photoQualityPrioritization")
            } else {
                // Fallback for iOS 13–15 only: enable high resolution capture when available
                if #available(iOS 16.0, *) {
                    // Do nothing; use maxPhotoDimensions above on iOS 16+
                } else {
                    if photoOutput.responds(to: NSSelectorFromString("setHighResolutionCaptureEnabled:")) {
                        photoOutput.isHighResolutionCaptureEnabled = true
                    }
                }
            }
        } else {
            // iOS 12 and earlier: enable high resolution capture when available
            if photoOutput.responds(to: NSSelectorFromString("setHighResolutionCaptureEnabled:")) {
                photoOutput.isHighResolutionCaptureEnabled = true
            }
        }

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            throw CameraServiceError.setupFailed
        }
        session.addOutput(photoOutput)

        session.commitConfiguration()

        // Check if configuration was successful
        if session.inputs.isEmpty || session.outputs.isEmpty {
            throw CameraServiceError.setupFailed
        }
    }

    /// Start the capture session on the actor's executor to avoid blocking the main thread.
    func startSession(_ session: AVCaptureSession) {
        guard !session.isRunning else { return }
        session.startRunning()
    }

    /// Stop the capture session on the actor's executor to avoid blocking the main thread.
    func stopSession(_ session: AVCaptureSession) {
        guard session.isRunning else { return }
        session.stopRunning()
    }

    private func bestDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Prefer the built-in wide-angle camera for photos
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        return AVCaptureDevice.default(for: .video)
    }

    func flipCamera(on session: AVCaptureSession) async throws {
        let newPosition: AVCaptureDevice.Position = (currentInput?.device.position == .back) ? .front : .back
        try await configureSession(session: session, position: newPosition)
        startSession(session)
    }

    func capturePhoto(on session: AVCaptureSession, flash: Bool) async throws -> Data {
        guard let photoOutput = session.outputs.compactMap({ $0 as? AVCapturePhotoOutput }).first else {
            throw CameraServiceError.captureFailed
        }

        // Create settings
        let settings = AVCapturePhotoSettings()
        if let device = currentInput?.device, device.isFlashAvailable {
            settings.flashMode = flash ? .on : .off
        }
        // Quality prioritization is configured on the output above when possible.

        // Await delegate callback
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let delegate = PhotoCaptureDelegate { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            // Retain delegate until callback
            PhotoCaptureDelegateStore.shared.retain(delegate)
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

// MARK: - Delegate plumbing

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, Error>) -> Void

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error = error {
            completion(.failure(error))
        } else if let data = photo.fileDataRepresentation() {
            completion(.success(data))
        } else {
            completion(.failure(CameraServiceError.captureFailed))
        }
        PhotoCaptureDelegateStore.shared.release(self)
    }
}

private final class PhotoCaptureDelegateStore {
    static let shared = PhotoCaptureDelegateStore()
    private let queue = DispatchQueue(label: "photo.delegate.store")
    private var storage: [ObjectIdentifier: AnyObject] = [:]

    func retain(_ delegate: AnyObject) {
        let id = ObjectIdentifier(delegate)
        queue.sync { storage[id] = delegate }
    }

    func release(_ delegate: AnyObject) {
        let id = ObjectIdentifier(delegate)
        queue.sync { storage[id] = nil }
    }
}
