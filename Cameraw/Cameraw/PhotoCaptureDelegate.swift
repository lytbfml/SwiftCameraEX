//
//  PhotoCaptureDelegate.swift
//  Cameraw
//
//  Created by Yangxiao Wang on 2/7/18.
//  Copyright © 2018 Yangxiao Wang. All rights reserved.
//

import AVFoundation
import Photos

class PhotoCaptureProcessor: NSObject {
    
    private(set) var requestedPhotoSettings: AVCapturePhotoSettings
    
    private let willCapturePhotoAnimation: () -> Void
    
    private let completionHandler: (PhotoCaptureProcessor) -> Void
    
    private var rawPhotoData: Data?
    
    private var jpgPhotoData: Data?
    
    var dngMeta: [String : Any]!
    
    var jpgMeta: [String : Any]!

    
    init(with requestedPhotoSettings: AVCapturePhotoSettings,
         willCapturePhotoAnimation: @escaping () -> Void,
         completionHandler: @escaping (PhotoCaptureProcessor) -> Void) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.completionHandler = completionHandler
    }
    
    private func didFinish() {
        
        completionHandler(self)
    }
    
    private func createScenUrl() -> URL {
        let docPath = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0])
        
        let scenPath = docPath.appendingPathComponent("Scen_" + String(CamViewController.settingCount))
        if (!FileManager.default.fileExists(atPath: scenPath.path)) {
            print("Creating dir \(scenPath.path)")
            do {
                try FileManager.default.createDirectory(atPath: scenPath.path, withIntermediateDirectories: true, attributes: nil)
            } catch let error {
                print("Unable to create directory \(error)")
            }
        }
        return scenPath
    }
    
    private func createImgPath(scenPath: URL) -> String {
        let date : Date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'_'HH_mm_ss"
        dateFormatter.timeZone = TimeZone(abbreviation: "CDT")
        let imageName = dateFormatter.string(from: date)
        
        return imageName
    }
    
    private func exifEdit(metadataAttachments: [String: Any]) -> [String: Any] {
        var tempData = metadataAttachments
        if var exifData = tempData[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exifData[kCGImagePropertyExifUserComment as String] = "<whatever you want to write>"
            
            tempData[kCGImagePropertyExifDictionary as String] = exifData as Dictionary
        }
        return tempData
    }
}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
    
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapturePhotoAnimation()
    }

    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        if let error = error {
            print("Fail to capture photo: \(error)")
        } else {
            if(photo.isRawPhoto) {
                dngMeta = exifEdit(metadataAttachments: photo.metadata as Dictionary)
                rawPhotoData = photo.fileDataRepresentation(withReplacementMetadata: dngMeta, replacementEmbeddedThumbnailPhotoFormat: photo.embeddedThumbnailPhotoFormat, replacementEmbeddedThumbnailPixelBuffer: nil, replacementDepthData: photo.depthData)
                
            } else{
                jpgMeta = exifEdit(metadataAttachments: photo.metadata as Dictionary)
                jpgPhotoData = photo.fileDataRepresentation(withReplacementMetadata: jpgMeta, replacementEmbeddedThumbnailPhotoFormat: photo.embeddedThumbnailPhotoFormat, replacementEmbeddedThumbnailPixelBuffer: nil, replacementDepthData: photo.depthData)
            }
        }
    }
    
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Fail to capture photo: \(error)")
            didFinish()
            return
        }
        
        guard let rawPhotoData = rawPhotoData else {
            print("No photo data resource")
            didFinish()
            return
        }
        
        guard let jpgPhotoData = jpgPhotoData else {
            print("No photo JPEG data resource")
            didFinish()
            return
        }
        
        let scenPath = createScenUrl()
        let imageName = createImgPath(scenPath: scenPath)
        
        print("ScenPath: \(scenPath)")
        
        let capturedImage = UIImage(data: jpgPhotoData)
        let imageJ: Data = UIImageJPEGRepresentation(capturedImage!, 1.0)!
        
        let imgRef = CGImageSourceCreateWithData(imageJ as CFData, nil)!
        let uti: CFString = CGImageSourceGetType(imgRef)!
        print("img ref type: \(uti)")
        let dataWithEXIF: NSMutableData = NSMutableData(data: imageJ)
        let destination: CGImageDestination = CGImageDestinationCreateWithData(dataWithEXIF, uti, 1, nil)!
        CGImageDestinationAddImageFromSource(destination, imgRef, 0, (jpgMeta as CFDictionary))
        CGImageDestinationFinalize(destination)
        
        let jpgUrl = scenPath.appendingPathComponent(imageName).appendingPathExtension("JPG")
        do {
            try dataWithEXIF.write(to: jpgUrl, options: .atomic)
        } catch let error {
            print("Unable to write JPG file. Error \(error)")
            didFinish()
            return
        }
        
        let dngUrl = scenPath.appendingPathComponent(imageName).appendingPathExtension("DNG")
        do {
            try rawPhotoData.write(to: dngUrl, options: .atomic)
        } catch let error as NSError {
            print("Unable to write DNG file. Error \(error)")
            didFinish()
            return
        }
        
        if (FileManager.default.fileExists(atPath: jpgUrl.path) && FileManager.default.fileExists(atPath: dngUrl.path)) {
            print("success saving file")
            didFinish()
        }
        
        
//        PHPhotoLibrary.requestAuthorization { status in
//            if status == .authorized {
//                PHPhotoLibrary.shared().performChanges({
//                    let creationOptions = PHAssetResourceCreationOptions()
//                    let creationRequest = PHAssetCreationRequest.forAsset()
//                    creationOptions.uniformTypeIdentifier = self.requestedPhotoSettings.rawFileType.map { $0.rawValue }
//                    creationOptions.shouldMoveFile = true
//                    creationRequest.addResource(with: .photo, fileURL: jpgUrl, options: nil)
//
//                    //creationRequest.addResource(with: .alternatePhoto, fileURL: self.dngFileUrl!, options: creationOptions)
//                }, completionHandler: { _, error in
//                    if let error = error {
//                        print("Error occurered while saving photo to photo library: \(error)")
//                    }
//                    self.didFinish()
//                })
//            } else {
//                self.didFinish()
//            }
//        }
    }
}


