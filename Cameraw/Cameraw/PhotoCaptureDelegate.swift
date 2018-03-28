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
    
    private var photoDataJ: Data?
    
    private var dngFileUrl: URL?

    
    init(with requestedPhotoSettings: AVCapturePhotoSettings,
         willCapturePhotoAnimation: @escaping () -> Void,
         completionHandler: @escaping (PhotoCaptureProcessor) -> Void) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.completionHandler = completionHandler
    }
    
    private func didFinish() {
        if let dngPath = dngFileUrl?.path {
            if FileManager.default.fileExists(atPath: dngPath) {
                do {
                    try FileManager.default.removeItem(atPath: dngPath)
                } catch {
                    print("Could not remove file at url: \(dngPath)")
                }
            } else {
                print("not exist \(dngFileUrl?.path)")
            }
        }
        
        completionHandler(self)
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
//            let photoMetadata = photo.metadata
//            print("Metadata orientation ", photoMetadata[String(kCGImagePropertyOrientation)] as! CFNumber)
//            print("Metadata: ", photoMetadata[String(kCGImagePropertyExifISOSpeedRatings)] as Any)
            print(photo.isRawPhoto)
            
            if(photo.isRawPhoto) {
                rawPhotoData = photo.fileDataRepresentation()
            } else{
                photoDataJ = photo.fileDataRepresentation()
//                let capturedImage = UIImage.init(data: photoDataJ!, scale: 1.0)
//                if let imageD = capturedImage {
//                    let imageJ = UIImageJPEGRepresentation(imageD, 1.0)
//                    UIImageWriteToSavedPhotosAlbum(imageJ, nil, nil, nil)
//                }
            }
        }
    }
    
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Fail to capture photo: \(error)")
            didFinish()
            return
        }
        
        guard let photoData = rawPhotoData else {
            print("No photo data resource")
            didFinish()
            return
        }
        
        guard let photoDataJ = photoDataJ else {
            print("No photo JPEG data resource")
            didFinish()
            return
        }
        
        let dngFileName = NSUUID().uuidString
        let dngFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((dngFileName as NSString).appendingPathExtension("DNG")!)
        dngFileUrl = URL(fileURLWithPath: dngFilePath)
        do {
            try photoData.write(to: dngFileUrl!, options: [])
        } catch let error as NSError {
            print("Unable to write DNG file. Error \(error)")
            didFinish()
            return
        }
        
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    let creationOptions = PHAssetResourceCreationOptions()
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationOptions.uniformTypeIdentifier = self.requestedPhotoSettings.rawFileType.map { $0.rawValue }
                    creationOptions.shouldMoveFile = true
//                    let creationOptions2 = PHAssetResourceCreationOptions()
//                    creationOptions2.uniformTypeIdentifier = self.requestedPhotoSettings.rawFileType.map{$0.rawValue}
                    creationRequest.addResource(with: .photo, data: photoDataJ, options: nil)
                    creationRequest.addResource(with: .alternatePhoto, fileURL: self.dngFileUrl!, options: creationOptions)
                }, completionHandler: { _, error in
                    if let error = error {
                        print("Error occurered while saving photo to photo library: \(error)")
                    }
                    self.didFinish()
                })
            } else {
                self.didFinish()
            }
        }
    }
}


