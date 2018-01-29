//
//  ViewController.swift
//  SwiftCamBasic
//
//  Created by Yangxiao Wang on 1/24/18.
//  Copyright © 2018 Yangxiao Wang. All rights reserved.
//

import UIKit
import AVFoundation
import Photos
import os.log


class ViewController: UIViewController {

    @IBOutlet weak var previewView: UIView!
    
    private let captureSession = AVCaptureSession()
    private var capturePhotoOutput: AVCapturePhotoOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    var photoSampleBuffer: CMSampleBuffer?
    var previewPhotoSampleBuffer: CMSampleBuffer?
    var rawSampleBuffer: CMSampleBuffer?
    var rawPreviewPhotoSampleBuffer: CMSampleBuffer?
    
    // Capture raw image
//    let photoSettingsRaw = AVCapturePhotoSettings(rawPixelFormatType: rawFormatType)
    
    
    private let sessionQueue = DispatchQueue(label: "session queue") // Communicate with the session and other session objects on this queue.
    
    var isCaptureSessionConfigured = false // Instance proprerty on this view controller class
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        self.previewLayer?.videoGravity = AVLayerVideoGravity.resizeAspect
        self.previewView.layer.addSublayer(self.previewLayer!)
        self.previewLayer?.frame = previewView.bounds
        
        
        
        print("view did load")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("view will appear")
        
        if self.isCaptureSessionConfigured {
            if !(self.captureSession.isRunning) {
                self.captureSession.startRunning()
                print("configured and is not running")
            }
        } else {
            print("not configured")

            // First time: request camera access, configure capture session and start it.
            self.checkCameraAuthorization({ authorized in
                guard authorized else {
                    print("Permission to use camera denied.")
                    return
                }
                
                self.configureCaptureSession({ success in
                    guard success else { return }
                    self.isCaptureSessionConfigured = true
                    
                    self.captureSession.startRunning()
//                        DispatchQueue.main.async {
//                            self.previewView.updateVideoOrientationForDeviceOrientation()
//                        }
                })
            })
        }
        
        
        

    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }


    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
    @IBOutlet weak var photoButton: UIButton!
    
    private func capturePhoto() {
        
        guard let capturePhotoOutput = self.capturePhotoOutput else { return }

        
        // Photo settings for RAW capture.
        let rawFormatType = kCVPixelFormatType_14Bayer_RGGB
        // At this point the array should not be empty (session has been configured).
        guard capturePhotoOutput.availableRawPhotoPixelFormatTypes.contains(NSNumber(value: rawFormatType).uint32Value) else {
            print("No available RAW pixel formats")
            return
        }
        guard let availableRawFormat = capturePhotoOutput.availableRawPhotoPixelFormatTypes.first else { return }
        
        print(availableRawFormat)
        print(rawFormatType)
        
        
        let photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormatType)
        
        photoSettings.flashMode = .off
        photoSettings.isAutoStillImageStabilizationEnabled = false
        photoSettings.isHighResolutionPhotoEnabled = true

        capturePhotoOutput.capturePhoto(with: photoSettings, delegate: self)
        
    }
    
    @IBAction func snapPhoto(_ sender: Any) {
        capturePhoto()
    }
    
    
    func configureCaptureSession(_ completionHandler: ((_ success: Bool) -> Void)) {
        var success = false
        defer { completionHandler(success) } // Ensure all exit paths call completion handler.
        
        // Get video input for the default camera.
        let videoCaptureDevice = defaultDevice()
        guard let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice) else {
            print("Unable to obtain video input for default camera.")
            return
        }
        
        // Create and configure the photo output.
        let capturePhotoOutput = AVCapturePhotoOutput()
        capturePhotoOutput.isHighResolutionCaptureEnabled = true
        capturePhotoOutput.isLivePhotoCaptureEnabled = capturePhotoOutput.isLivePhotoCaptureSupported
        
        // Make sure inputs and output can be added to session.
        guard self.captureSession.canAddInput(videoInput) else { return }
        guard self.captureSession.canAddOutput(capturePhotoOutput) else { return }
        
        // Configure the session.
        self.captureSession.beginConfiguration()
        self.captureSession.sessionPreset = AVCaptureSession.Preset.photo
        self.captureSession.addInput(videoInput)
        self.captureSession.addOutput(capturePhotoOutput)
        self.captureSession.commitConfiguration()
        
        self.capturePhotoOutput = capturePhotoOutput
        
        success = true
    }
    
    func defaultDevice() -> AVCaptureDevice {
        if let device = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInDualCamera,
                                                for: AVMediaType.video,
                                                position: AVCaptureDevice.Position.back) {
            print("dual cam")
            return device // use dual camera on supported devices
        } else if let device = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera,
                                                       for: AVMediaType.video,
                                                       position: .back) {
            print("wide angle cam")
            return device // use default back facing camera otherwise
        } else {
            fatalError("All supported devices are expected to have at least one of the queried capture devices.")
        }
    }
    
    func checkCameraAuthorization(_ completionHandler: @escaping ((_ authorized: Bool) -> Void)) {
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized:
            //The user has previously granted access to the camera.
            completionHandler(true)

        case .notDetermined:
            // The user has not yet been presented with the option to grant video access so request access.
            AVCaptureDevice.requestAccess(for: AVMediaType.video, completionHandler: { success in completionHandler(success) })
            
        case .restricted:
            // The user doesn't have the authority to request access e.g. parental restriction
            completionHandler(false)
            
        case .denied:
            // The user has previously denied access.
            completionHandler(false)
            
        }
    }
    
    
    func checkPhotoLibraryAuthorization(_ completionHandler: @escaping ((_ authorized: Bool) -> Void)) {
        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized:
            // The user has previously granted access to the photo library.
            print("PHAuthorizationStatus.Authorized")
            completionHandler(true)
            
        case .notDetermined:
            // The user has not yet been presented with the option to grant photo library access so request access.
            print("PHAuthorizationStatus.NotDetermined")
            PHPhotoLibrary.requestAuthorization({ status in
                completionHandler((status == .authorized))
            })
            
        case .denied:
            // The user has previously denied access.
            print("PHAuthorizationStatus.Denied")
            completionHandler(false)
            
        case .restricted:
            // The user doesn't have the authority to request access e.g. parental restriction.
            print("PHAuthorizationStatus.Restricted")
            completionHandler(false)
        }
    }
    
 
}


extension ViewController : AVCapturePhotoCaptureDelegate {
    
    func photoOutput(_ output: AVCapturePhotoOutput,
                didFinishProcessingPhoto photo: AVCapturePhoto,
                error: Error?) {
        guard error == nil else {
            print("Fail to capture photo: \(String(describing: error))")
            return
        }
        guard let dngData = photo.fileDataRepresentation() else {
            print("Fail to convert pixel buffer")
            return
        }
        
        let capturedImage = UIImage.init(data: dngData , scale: 1.0)
        
        if let image = capturedImage {
            // Save our captured image to photos album
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
        
    }
}









