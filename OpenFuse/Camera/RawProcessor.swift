//
//  RawProcessor.swift
//  OpenFuse
//
//  Created by Kris Li on 8/19/25.
//

import Foundation
import CoreImage
import Vision
import UniformTypeIdentifiers
import ImageIO
import CoreGraphics

struct RawProcessor {
    struct ProcessError: Error { let message: String }

    /// Merge a burst of DNG data, develop with gentle defaults, and return a JPEG (optionally also one DNG).
    static func mergeAndDevelop(dngDatas: [Data], saveOneDNG: Bool) throws -> (jpegData: Data, savedDNG: Data?) {
        guard !dngDatas.isEmpty else { throw ProcessError(message: "No frames") }

        // GPU-backed CIContext in linear sRGB
        let ciContext = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .useSoftwareRenderer: false
        ])

        // 1) Develop each DNG to a linear CIImage with neutral settings
        var developed: [CIImage] = []
        developed.reserveCapacity(dngDatas.count)

        for data in dngDatas {
            guard let raw = CIRAWFilter(imageData: data, options: nil) else {
                throw ProcessError(message: "CIRAWFilter init failed")
            }
            // Dial back processing for a neutral look
            raw.boostAmount = 0.0
            raw.scaleFactor = 1.0

            // Future-proof adjustments using setValue for keys if supported
            raw.setValue(0.0, forKey: "noiseReductionAmount")
            raw.setValue(0.0, forKey: "luminanceNoiseReductionAmount")
            raw.setValue(0.0, forKey: "sharpness")

            guard let out = raw.outputImage else { continue }
            developed.append(out)
        }

        guard let base = developed.first else { throw ProcessError(message: "No decodable RAW frames") }

        // 2) Align all frames to the first using Vision (translation-only for speed)
        let aligned: [CIImage] = developed.enumerated().map { idx, img in
            if idx == 0 { return img }
            let t = translation(from: img, to: base) ?? .identity
            return img.transformed(by: t)
        }

        // 3) Average the aligned frames in CI (scale each by 1/N, then add)
        let scale = 1.0 / Double(aligned.count)
        var accumulator = colorMatrix(image: aligned[0], scale: scale)
        for i in 1..<aligned.count {
            let scaled = colorMatrix(image: aligned[i], scale: scale)
            guard let added = CIFilter(name: "CIAdditionCompositing", parameters: [
                kCIInputImageKey: scaled, kCIInputBackgroundImageKey: accumulator
            ])?.outputImage else { continue }
            accumulator = added
        }

        // 4) Optional mild tone mapping (very gentle to keep the natural look)
        let tone = CIFilter(name: "CIHighlightShadowAdjust", parameters: [
            kCIInputImageKey: accumulator, "inputShadowAmount": 0.2, "inputHighlightAmount": 0.0
        ])?.outputImage ?? accumulator

        // 5) Render to JPEG data
        let extent = tone.extent
        guard let cg = ciContext.createCGImage(tone, from: extent) else {
            throw ProcessError(message: "CGImage render failed")
        }
        let jpegData = encodeJPEG(cgImage: cg, quality: 0.92)

        // Save one DNG (middle frame) if requested
        let savedDNG = saveOneDNG ? dngDatas[dngDatas.count/2] : nil
        return (jpegData, savedDNG)
    }

    // MARK: - Helpers

    private static func colorMatrix(image: CIImage, scale: Double) -> CIImage {
        CIFilter(name: "CIColorMatrix", parameters: [
            kCIInputImageKey: image,
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])!.outputImage!
    }

    private static func translation(from moving: CIImage, to fixed: CIImage) -> CGAffineTransform? {
        let req = VNTranslationalImageRegistrationRequest(targetedCIImage: moving, options: [:])
        let handler = VNImageRequestHandler(ciImage: fixed, options: [:])
        do {
            try handler.perform([req])
            if let obs = req.results?.first as? VNImageTranslationAlignmentObservation {
                return CGAffineTransform(translationX: CGFloat(obs.alignmentTransform.tx),
                                          y: CGFloat(obs.alignmentTransform.ty))
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func encodeJPEG(cgImage: CGImage, quality: CGFloat) -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return data as Data
    }
}
