//
//  CameraPreview.swift
//  OpenFuse
//
//  Created by Kris Li on 8/21/25.
//

import AVFoundation
import UIKit
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        // Show the full camera image (no cropping), may letterbox/pillarbox
        v.videoPreviewLayer.videoGravity = .resizeAspect
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Only update if the session has actually changed
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
        // Ensure gravity remains correct if UIKit reuses view
        if uiView.videoPreviewLayer.videoGravity != .resizeAspect {
            uiView.videoPreviewLayer.videoGravity = .resizeAspect
        }
    }
}

// Backed by AVCaptureVideoPreviewLayer for best performance
final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Ensure the video preview layer fills the view bounds
        videoPreviewLayer.frame = bounds
    }
}

