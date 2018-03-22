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
    
    private var photoData: Data?
    
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
}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
    
    
    
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapturePhotoAnimation()
    }

    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        if let error = error {
            print("Fail to capture photo: \(error)")
        } else {
            let photoMetadata = photo.metadata
            // Returns corresponting NSCFNumber. It seems to specify the origin of the image
            //                print("Metadata orientation: ",photoMetadata["Orientation"])
            
            // Returns corresponting NSCFNumber. It seems to specify the origin of the image
            print("Metadata orientation with key: ",photoMetadata[String(kCGImagePropertyOrientation)] as Any)
            print("Metadata: ",photoMetadata[String(kCGImagePropertyExifISOSpeedRatings)] as Any)
            
            photoData = photo.fileDataRepresentation()
            
        }
    }
    
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Fail to capture photo: \(error)")
            didFinish()
            return
        }
        
        guard let photoData = photoData else {
            print("No photo data resource")
            didFinish()
            return
        }
        
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    options.uniformTypeIdentifier = self.requestedPhotoSettings.processedFileType.map { $0.rawValue }
                    creationRequest.addResource(with: .photo, data: photoData, options: options)
                    
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























