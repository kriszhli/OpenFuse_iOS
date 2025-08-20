//
//  PhotoLibrary.swift
//  OpenFuse
//
//  Created by Kris Li on 8/19/25.
//

import Foundation
import Photos
import UniformTypeIdentifiers


enum PhotoLibrary {
  static func saveJPEG(data: Data) throws {
    try PHPhotoLibrary.shared().performChangesAndWait {
      let req = PHAssetCreationRequest.forAsset()
      let opts = PHAssetResourceCreationOptions()
      opts.uniformTypeIdentifier = UTType.jpeg.identifier
      req.addResource(with: .photo, data: data, options: opts)
    }
  }


  static func saveDNG(data: Data) throws {
    try PHPhotoLibrary.shared().performChangesAndWait {
      let req = PHAssetCreationRequest.forAsset()
      let opts = PHAssetResourceCreationOptions()
      opts.uniformTypeIdentifier = UTType.dng.identifier
      req.addResource(with: .photo, data: data, options: opts)
    }
  }
}
