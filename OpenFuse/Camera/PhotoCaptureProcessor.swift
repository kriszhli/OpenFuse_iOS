//
//  PhotoCaptureProcessor.swift
//  OpenFuse
//
//  Created by Kris Li on 8/19/25.
//

import Foundation
import AVFoundation


final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
private let index: Int
private let total: Int
private let outputMode: CameraController.OutputMode
private let status: (String) -> Void


// Static accumulation shared across the burst
private static var pendingDNGs: [Data] = []
private static var expectedCount: Int = 0
private static var outputMode: CameraController.OutputMode = .jpegOnly
private static let sync = DispatchQueue(label: "burst.sync")


init(index: Int, total: Int, outputMode: CameraController.OutputMode, status: @escaping (String)->Void) {
self.index = index
self.total = total
self.outputMode = outputMode
self.status = status
super.init()
Self.sync.sync {
if Self.expectedCount == 0 {
Self.expectedCount = total
Self.outputMode = outputMode
Self.pendingDNGs.removeAll()
}
}
}


func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto) {
guard photo.isRawPhoto else { return } // We only requested RAW
if let dng = photo.fileDataRepresentation() {
Self.sync.sync { Self.pendingDNGs.append(dng) }
}
}


func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
if let error { status("Capture error: \(error.localizedDescription)") }
Self.sync.async {
guard Self.pendingDNGs.count >= Self.expectedCount else { return }
let dngs = Self.pendingDNGs
Self.pendingDNGs.removeAll()
Self.expectedCount = 0
let mode = Self.outputMode
DispatchQueue.global(qos: .userInitiated).async {
do {
let result = try RawProcessor.mergeAndDevelop(dngDatas: dngs, saveOneDNG: mode == .dngPlusJpeg)
try PhotoLibrary.saveJPEG(data: result.jpegData)
if let dng = result.savedDNG { try PhotoLibrary.saveDNG(data: dng) }
DispatchQueue.main.async { self.status("Saved \(mode == .dngPlusJpeg ? "JPEG + DNG" : "JPEG") to Photos") }
} catch {
DispatchQueue.main.async { self.status("Process error: \(error.localizedDescription)") }
}
}
}
}
}
