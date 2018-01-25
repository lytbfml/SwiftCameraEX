//
//  ViewController.swift
//  SwiftCamBasic
//
//  Created by J L Newman on 1/24/18.
//  Copyright © 2018 Yangxiao Wang. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

class ViewController: UIViewController {

    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var captureImageView: UIImageView!
    
    var session: AVCaptureSession?
    var stillImageOutput: AVCapturePhotoOutput?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.checkCameraAuthorization { authorized in
            if authorized {
                // Proceed to set up and use the camera.
            } else {
                print("Permission to use camera denied.")
                
                //Exit the application
                UIControl().sendAction(#selector(NSXPCConnection.suspend),
                                       to: UIApplication.shared, for: nil)
            }
        }
        
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        session = AVCaptureSession()
        session!.sessionPreset = AVCaptureSession.Preset.photo
        
        guard let backCam = AVCaptureDevice.default(for: .video) else {
            fatalError("No vidoe device found")
        }
        
        var error: NSError?
        var input: AVCaptureDeviceInput!
        
        do{
            input = try AVCaptureDeviceInput(device: backCam)
            
        } catch let error1 as NSError {
            error = error1
            input = nil
            print(error!.localizedDescription)
        }
        
        if error == nil && session!.canAddInput(input) {
            session!.addInput(input)
            
            stillImageOutput = AVCapturePhotoOutput()
            
            
            
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func didTakePhoto(_ sender: Any) {
        
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











