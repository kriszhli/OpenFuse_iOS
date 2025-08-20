//
//  CameraController.swift
//  OpenFuse
//

import Foundation
import AVFoundation

final class CameraController: NSObject {

    enum OutputMode { case jpegOnly, dngPlusJpeg }

    // MARK: Public
    let session = AVCaptureSession()
    var onStatus: ((String) -> Void)?

    // MARK: Private
    private let sessionQueue = DispatchQueue(label: "cam.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var inFlightProcessors: [AVCapturePhotoCaptureDelegate] = []

    override init() {
        super.init()
        configureSession()
    }

    // MARK: - Session control
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            self.onStatus?("Session running")
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            self.onStatus?("Session stopped")
        }
    }

    // MARK: - Capture
    func captureBurst(burstCount: Int, outputMode: OutputMode) {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            // RAW pixel format that can be written as DNG
            let rawFormats = self.photoOutput.supportedRawPhotoPixelFormatTypes(for: .dng)
            guard let bayerRAW = rawFormats.first else {
                self.onStatus?("RAW not supported on this device")
                return
            }

            // iOS 16+: enumerate supported maximum photo dimensions from the ACTIVE FORMAT
            let bestDims: CMVideoDimensions? = self.device?
                .activeFormat
                .supportedMaxPhotoDimensions
                .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) })

            self.onStatus?("Capturing RAW burst x\(burstCount)…")
            self.inFlightProcessors.removeAll(keepingCapacity: true)

            for index in 0..<burstCount {
                let settings = AVCapturePhotoSettings(rawPixelFormatType: bayerRAW)

                // Apply the largest supported max dimension if available
                if let bestDims { settings.maxPhotoDimensions = bestDims }

                // Prefer quality over speed (non-deprecated)
                settings.photoQualityPrioritization = .quality

                // Small embedded thumbnail for UX
                settings.embeddedThumbnailPhotoFormat = [
                    AVVideoCodecKey: AVVideoCodecType.jpeg,
                    AVVideoWidthKey: 512,
                    AVVideoHeightKey: 384
                ]

                let proc = PhotoCaptureProcessor(
                    index: index,
                    total: burstCount,
                    outputMode: outputMode
                ) { [weak self] msg in
                    self?.onStatus?(msg)
                    if msg.hasPrefix("Saved ") || msg.contains("Process error") {
                        self?.sessionQueue.async { self?.inFlightProcessors.removeAll() }
                    }
                }

                self.inFlightProcessors.append(proc)
                self.photoOutput.capturePhoto(with: settings, delegate: proc)
            }
        }
    }

    // MARK: - Configuration
    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Input (back wide camera)
        guard
            let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: dev),
            session.canAddInput(input)
        else {
            onStatus?("No camera input available")
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        device = dev

        // Output
        guard session.canAddOutput(photoOutput) else {
            onStatus?("No photo output available")
            session.commitConfiguration()
            return
        }

        // Prefer highest photo quality (current API)
        photoOutput.maxPhotoQualityPrioritization = .quality

        // Avoid multi-camera fusion to keep single-lens stream
        if photoOutput.isVirtualDeviceConstituentPhotoDeliverySupported {
            photoOutput.isVirtualDeviceConstituentPhotoDeliveryEnabled = false
        }

        session.addOutput(photoOutput)
        session.commitConfiguration()
    }
}
