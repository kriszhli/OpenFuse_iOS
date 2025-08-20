//
//  CameraView.swift
//  OpenFuse
//
//  Created by Kris Li on 8/19/25.
//

import Foundation
import SwiftUI
import AVFoundation


struct CameraView: UIViewRepresentable {
let session: AVCaptureSession


func makeUIView(context: Context) -> Preview {
let v = Preview()
v.videoPreviewLayer.session = session
v.videoPreviewLayer.videoGravity = .resizeAspectFill
return v
}
func updateUIView(_ uiView: Preview, context: Context) {}


final class Preview: UIView {
override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
}
