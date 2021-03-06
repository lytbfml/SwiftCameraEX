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
    
    private var device: AVCaptureDevice
    
    private let willCapturePhotoAnimation: () -> Void
    
    private let completionHandler: (PhotoCaptureProcessor) -> Void
    
    private var rawPhotoData: Data?
    
    private var jpgPhotoData: Data?
    
    private var photoCount: Int!
    
    var dngMeta: [String : Any]!
    
    var jpgMeta: [String : Any]!
    
    private var currentIso: String
    private var currentExp: String

    
    init(with requestedPhotoSettings: AVCapturePhotoSettings, device: AVCaptureDevice, photoCount: Int, willCapturePhotoAnimation: @escaping () -> Void, completionHandler: @escaping (PhotoCaptureProcessor) -> Void) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.device = device
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.completionHandler = completionHandler
        self.currentExp = String(format: "%.f ", 1.0 / CMTimeGetSeconds(device.exposureDuration))
        self.currentIso = String(Int(device.iso))
        self.photoCount = photoCount
    }
    
    private func didFinish() {
        completionHandler(self)
    }
    
    
    private func createScenUrl(format: String) -> URL {
        let docPath = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0])
        
        let scenPath = docPath.appendingPathComponent(CamViewController.currentScenName + "_" + format + "_" + CamViewController.currentTimestamp)
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
    
    
    private func createImgPath(scenPath: URL, format: String) -> String {
        let count = self.photoCount + 1
        var photoCount: String
        if(count < 10) {
            photoCount = "00" + String(count)
        } else if (count < 100){
            photoCount = "0" + String(count)
        } else{
            photoCount = String(count)
        }
        var imageName: String = CamViewController.deviceID + CamViewController.currentScenName + "_" + format + "-"
        imageName += photoCount + "_I" + currentIso + "_E" + currentExp + "_o"
        
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
    
    private func printSettings(resolvedSettings: AVCaptureResolvedPhotoSettings) {
        
        print("Output Settings - uniqueID: \(resolvedSettings.uniqueID)")
        print("Output Settings - expectedPhotoCount: \(resolvedSettings.expectedPhotoCount)")
        print("Requested Settings - FlashMode: \(requestedPhotoSettings.flashMode.rawValue) (on, off, auto)")
        print("Output Settings - isFlashEnabled: \(resolvedSettings.isFlashEnabled)")
        print("Output Settings - isStillImageStabilizationEnabled: \(resolvedSettings.isStillImageStabilizationEnabled)")
        print("Output Settings - isDualCameraFusionEnabled: \(resolvedSettings.isDualCameraFusionEnabled)")
        print("Output Settings - photoDimensions: \(resolvedSettings.photoDimensions)")
        print("Output Settings - rawPhotoDimensions: \(resolvedSettings.rawPhotoDimensions)")
        print("Output Settings - previewDimensions: \(resolvedSettings.previewDimensions)")
        print("Output Settings - embeddedThumbnailDimensions: \(resolvedSettings.embeddedThumbnailDimensions)")
        print("Output Settings - livePhotoMovieDimensions: \(resolvedSettings.livePhotoMovieDimensions)")
        
        print("Device Settings - isConnected: \(device.isConnected)")
        print("Device Settings - position: \(device.position.rawValue)")
        print("Device Settings - modelID: \(device.modelID)")
        print("Device Settings - localizedName: \(device.localizedName)")
        print("Device Settings - uniqueID: \(device.uniqueID)")
        print("Device Settings - lensAperture: \(device.lensAperture)")
        print("Device Settings - deviceType: \(device.deviceType)")
        print("Device Settings - manufacturer: Apple Inc.")
        
        print("Device Settings - focusMode: \(device.focusMode.rawValue) (locked, autoFocus, continuousAutoFocus)")
        print("Device Settings - focusPointOfInterest: \(device.focusPointOfInterest)")
        print("Device Settings - isAdjustingFocus: \(device.isAdjustingFocus)")
        print("Device Settings - isSmoothAutoFocusEnabled: \(device.isSmoothAutoFocusEnabled)")
        print("Device Settings - autoFocusRangeRestriction: \(device.autoFocusRangeRestriction.rawValue)")
        
        print("Device Settings - isAdjustingExposure: \(device.isAdjustingExposure)")
        print("Device Settings - exposureMode: \(device.exposureMode.rawValue) (locked, autoExpose, continuousAutoExposure, custom)")
        print("Device Settings - exposurePointOfInterest: \(device.exposurePointOfInterest)")
        print("Device Settings - isExposurePointOfInterestSupported: \(device.isExposurePointOfInterestSupported)")
        
        print("Device Settings - hasFlash: \(device.hasFlash)")
        
        print("Device Settings - isLowLightBoostEnabled: \(device.isLowLightBoostEnabled)")
        print("Device Settings - isLowLightBoostSupported: \(device.isLowLightBoostSupported)")
        print("Device Settings - autoEnableLowLightBoostWhenAvailable: \(device.automaticallyEnablesLowLightBoostWhenAvailable)")
        
        print("Device Settings - lensPosition: \(device.lensPosition)")
        print(String(format: "Device Settings - exposureDuration: 1/%.f ", 1.0 / CMTimeGetSeconds(device.exposureDuration)))
        print("Device Settings - exposureDuration: \(device.exposureDuration)")
        print("Device Settings - exposureTargetOffset: \(device.exposureTargetOffset)")
        print("Device Settings - exposureTargetBias: \(device.exposureTargetBias)")
        
        print("Device Settings - whiteBalanceMode: \(device.whiteBalanceMode)")
        
        print("Device Settings - iso: \(device.iso)")
        
        print("Device Settings - autoAdjustVideoHDREnabled: \(device.automaticallyAdjustsVideoHDREnabled)")
        print("Device Settings - isVideoHDREnabled: \(device.isVideoHDREnabled)")
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
        
        let scenPathJpg = createScenUrl(format: "JPG")
        let scenPathDng = createScenUrl(format: "DNG")
        let imageNameJpg = createImgPath(scenPath: scenPathJpg, format: "JPG")
        let imageNameDng = createImgPath(scenPath: scenPathDng, format: "RAW")
        
        let capturedImage = UIImage(data: jpgPhotoData)
        let imageJ: Data = UIImageJPEGRepresentation(capturedImage!, 1.0)!
        
//        let temp = UIImage(data: imageJ)
//        let nums = Int((temp?.size.height)! * (temp?.size.width)! * 3)
//        let pixelData = temp?.cgImage?.dataProvider?.data
//
//        let tempData: UnsafePointer<UInt8> = CFDataGetBytePtr(pixelData)
//        var stringBuilder: String = ""
//        let cgData = temp?.cgImage
//        for i in 0...nums-1 {
//            stringBuilder += String(tempData[i])
//            stringBuilder += "\n"
//        }
//
//        let stringFinal = NSString(string: stringBuilder)
//        do {
//            let fileURL = scenPath.appendingPathComponent("dataTest").appendingPathExtension("TXT")
//            print("\(fileURL.path)")
//
//            try stringFinal.write(to: fileURL, atomically: true, encoding: 4)
//        } catch let error {
//            print("Unable to write txt file. Error \(error)")
//        }
        
        let imgRef = CGImageSourceCreateWithData(imageJ as CFData, nil)!
        let uti: CFString = CGImageSourceGetType(imgRef)!
        print("img ref type: \(uti)")
        let dataWithEXIF: NSMutableData = NSMutableData(data: imageJ)
        let destination: CGImageDestination = CGImageDestinationCreateWithData(dataWithEXIF, uti, 1, nil)!
        CGImageDestinationAddImageFromSource(destination, imgRef, 0, (jpgMeta as CFDictionary))
        CGImageDestinationFinalize(destination)
        
        let jpgUrl = scenPathJpg.appendingPathComponent(imageNameJpg).appendingPathExtension("jpg")
        do {
            try dataWithEXIF.write(to: jpgUrl, options: .atomic)
        } catch let error {
            print("Unable to write JPG file. Error \(error)")
            didFinish()
            return
        }
        
        let dngUrl = scenPathDng.appendingPathComponent(imageNameDng).appendingPathExtension("dng")
        do {
            try rawPhotoData.write(to: dngUrl, options: .atomic)
        } catch let error as NSError {
            print("Unable to write DNG file. Error \(error)")
            didFinish()
            return
        }
        
        //printSettings(resolvedSettings: resolvedSettings)
        
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


