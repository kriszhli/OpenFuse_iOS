//
//  RawProcessor.swift
//  OpenFuse
//
//  Rewritten for robustness on Simulator and device.
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

        // GPU‑backed CIContext in linear sRGB
        let ciContext = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .useSoftwareRenderer: false
        ])

        // 1) Develop each DNG to a linear CIImage with neutral settings
        let developed = try decodeDNGs(dngDatas)
        guard !developed.isEmpty else { throw ProcessError(message: "No decodable RAW frames") }

        // 2) Align all frames to the first using Vision translation (fast, robust)
        let aligned = alignImagesToFirst(developed)

        // 3) Average aligned frames to reduce noise without halos
        let averaged = averageImages(aligned)

        // 4) Gentle tone mapping (very light shadows lift)
        let toned = applyGentleTone(averaged)

        // 5) Render to JPEG data
        let jpegData = try renderJPEG(toned, context: ciContext, quality: 0.92)

        // Save one DNG (middle frame) if requested
        let savedDNG = saveOneDNG ? dngDatas[dngDatas.count / 2] : nil
        return (jpegData, savedDNG)
    }

    // MARK: - Decode

    private static func decodeDNGs(_ dngDatas: [Data]) throws -> [CIImage] {
        var output: [CIImage] = []
        output.reserveCapacity(dngDatas.count)
        for data in dngDatas {
            guard let raw = CIRAWFilter(imageData: data, options: nil) else {
                throw ProcessError(message: "CIRAWFilter init failed")
            }
            // Keep rendering neutral. Only use well‑supported knobs.
            raw.boostAmount = 0.0
            raw.scaleFactor = 1.0
            if let img = raw.outputImage {
                output.append(img)
            }
        }
        return output
    }

    // MARK: - Align

    private static func alignImagesToFirst(_ images: [CIImage]) -> [CIImage] {
        guard let base = images.first else { return images }
        var aligned: [CIImage] = [base]
        aligned.reserveCapacity(images.count)
        for idx in 1..<images.count {
            let moving = images[idx]
            if let t = translation(from: moving, to: base) {
                aligned.append(moving.transformed(by: t))
            } else {
                aligned.append(moving) // fallback: no transform
            }
        }
        return aligned
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
            // Ignore; return nil to skip transform
        }
        return nil
    }

    // MARK: - Merge

    private static func averageImages(_ images: [CIImage]) -> CIImage {
        guard let first = images.first else { return CIImage() }
        let scale = 1.0 / Double(images.count)
        var acc = scaled(image: first, by: scale)
        for i in 1..<images.count {
            let scaledImg = scaled(image: images[i], by: scale)
            let add = CIFilter(name: "CIAdditionCompositing", parameters: [
                kCIInputImageKey: scaledImg,
                kCIInputBackgroundImageKey: acc
            ])?.outputImage
            acc = add ?? acc
        }
        return acc
    }

    private static func scaled(image: CIImage, by scale: Double) -> CIImage {
        // Use CIColorMatrix to multiply RGB by `scale`. Guard filter creation.
        let params: [String: Any] = [
            kCIInputImageKey: image,
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ]
        return CIFilter(name: "CIColorMatrix", parameters: params)?.outputImage ?? image
    }

    // MARK: - Tone

    private static func applyGentleTone(_ image: CIImage) -> CIImage {
        // Very light shadow lift; if filter fails, return input.
        let params: [String: Any] = [
            kCIInputImageKey: image,
            "inputShadowAmount": 0.2,
            "inputHighlightAmount": 0.0
        ]
        return CIFilter(name: "CIHighlightShadowAdjust", parameters: params)?.outputImage ?? image
    }

    // MARK: - Encode

    private static func renderJPEG(_ image: CIImage, context: CIContext, quality: CGFloat) throws -> Data {
        let extent = image.extent
        guard let cg = context.createCGImage(image, from: extent) else {
            throw ProcessError(message: "CGImage render failed")
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ProcessError(message: "CGImageDestination create failed")
        }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ProcessError(message: "CGImageDestination finalize failed")
        }
        return data as Data
    }
}
