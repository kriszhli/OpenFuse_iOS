//
//  SimulatorCapture.swift
//  OpenFuse
//
//  Created by Kris Li on 8/20/25.
//

import Foundation
import Photos
import UniformTypeIdentifiers

enum SimulatorCapture {
    enum SimError: Error { case noFiles, loadFailed(String) }

    static func runBurst(outputMode: CameraController.OutputMode,
                         status: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Load all DNGs from bundle/TestDNGs
                let dngDatas = try loadBurstDNGs()
                status("Processing simulated RAW burst x\(dngDatas.count)…")

                let result = try RawProcessor.mergeAndDevelop(dngDatas: dngDatas,
                                                             saveOneDNG: outputMode == .dngPlusJpeg)

                // Try saving to Photos; fall back to Documents if Photos unavailable on simulator
                do {
                    try PhotoLibrary.saveJPEG(data: result.jpegData)
                    if let d = result.savedDNG { try PhotoLibrary.saveDNG(data: d) }
                    DispatchQueue.main.async {
                        status("Saved \(outputMode == .dngPlusJpeg ? "JPEG + DNG" : "JPEG") to Photos")
                    }
                } catch {
                    // Fallback: write to app Documents and print path
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let ts = Int(Date().timeIntervalSince1970)
                    let jpegURL = docs.appendingPathComponent("openfuse_\(ts).jpg")
                    try result.jpegData.write(to: jpegURL)
                    var msg = "Saved JPEG to \(jpegURL.path)"
                    if let d = result.savedDNG {
                        let dngURL = docs.appendingPathComponent("openfuse_\(ts).dng")
                        try d.write(to: dngURL)
                        msg += " and DNG to \(dngURL.path)"
                    }
                    DispatchQueue.main.async { status(msg) }
                }
            } catch {
                DispatchQueue.main.async { status("Sim process error: \(error)") }
            }
        }
    }

    private static func loadBurstDNGs() throws -> [Data] {
        let bundle = Bundle.main
        // Load every .dng inside TestDNGs/ (order by name)
        guard let url = bundle.url(forResource: "TestDNGs", withExtension: nil) else {
            throw SimError.noFiles
        }
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        let dngURLs = contents.filter { $0.pathExtension.lowercased() == "dng" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !dngURLs.isEmpty else { throw SimError.noFiles }
        var datas: [Data] = []
        for u in dngURLs {
            do { datas.append(try Data(contentsOf: u)) }
            catch { throw SimError.loadFailed(u.lastPathComponent) }
        }
        return datas
    }
}
