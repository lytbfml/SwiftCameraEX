//
//  CameraController.swift
//  Cameraw
//
//  Created by J L Newman on 4/12/18.
//  Copyright © 2018 Yangxiao Wang. All rights reserved.
//

import UIKit
import AVFoundation

class CameraController: NSObject {
    
    var captureSession: AVCaptureSession?
    
    var captureDevice: AVCaptureDevice?
    
    var videoDeviceInput: AVCaptureDeviceInput?
    
    var photoOutput: AVCapturePhotoOutput?
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var flashMode = AVCaptureDevice.FlashMode.off
}


extension CameraController {
    func configureCamera(completionHandler: @escaping (Error?) -> Void ) {
        
    }
    
    
}



