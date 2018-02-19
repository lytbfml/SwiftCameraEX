//
//  ViewController.swift
//  Cameraw
//
//  Created by J L Newman on 1/29/18.
//  Copyright © 2018 Yangxiao Wang. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

class CamViewController: UIViewController {
    
    
    var count = 0;
    
    
    // View Controller Life Cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        photoButton.isEnabled = false
        previewView.session = session
        
        photoButton.layer.shadowColor = UIColor.black.cgColor
        photoButton.layer.shadowOffset = CGSize(width: 0.0, height: 2.0)
        photoButton.layer.masksToBounds = false
        photoButton.layer.shadowRadius = 1.0
        photoButton.layer.shadowOpacity = 0.5
        photoButton.layer.cornerRadius = photoButton.frame.width / 2
        photoButton.clipsToBounds = true

        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                // The user has previously granted access to the camera.
                break
            case .notDetermined:
                sessionQueue.suspend()
                AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                    if !granted {
                        self.setupResult = .notAuthorized
                    }
                    self.sessionQueue.resume()
                })
            default:
                // The user has previously denied access.
                setupResult = .notAuthorized
        }
        sessionQueue.async {
            self.configureSession()
            //MARK: TODO
            self.setExposureDurationAndISO(time: 0.02, isoVal: 100)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session running if setup succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "AVCam doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        
        super.viewWillDisappear(animated)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: Session Management
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private let session = AVCaptureSession()
    
    private var isSessionRunning = false
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue")
    
    private var setupResult: SessionSetupResult = .success
    
    var videoDeviceInput: AVCaptureDeviceInput!
    
    @IBOutlet weak var previewView: PreviewView!
    
    // Call this on the session queue.
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        // AVCaptureSession.Preset.photo
        session.sessionPreset = .photo
        
        // Add video input
        let defaultVideoDevice = defaultDevice()
        guard let videoInput = try? AVCaptureDeviceInput(device: defaultVideoDevice) else {
            print("Unable to obtain video input for default camera.")
            return
        }
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
            self.videoDeviceInput = videoInput
            
//            DispatchQueue.main.async {
//                /*
//                 Why are we dispatching this to the main queue?
//                 Because AVCaptureVideoPreviewLayer is the backing layer for PreviewView and UIView
//                 can only be manipulated on the main thread.
//                 Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
//                 on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
//
//                 Use the status bar orientation as the initial video orientation. Subsequent orientation changes are
//                 handled by CameraViewController.viewWillTransition(to:with:).
//                 */
//                let statusBarOrientation = UIApplication.shared.statusBarOrientation
//                var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
//                if statusBarOrientation != .unknown {
//                    if let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: statusBarOrientation) {
//                        initialVideoOrientation = videoOrientation
//                    }
//                }
//                self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
//            }
        } else {
            print("Could not add video device input to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add photo output.
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            
            photoOutput.isHighResolutionCaptureEnabled = true
            
            print("configureSession - isDepthDataDeliveryEnabled: \(photoOutput.isDepthDataDeliveryEnabled)")
            print("configureSession - Max Bracketed: \(photoOutput.maxBracketedCapturePhotoCount)")
            
        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    func defaultDevice() -> AVCaptureDevice {
        if let device = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInDualCamera,
                                                for: AVMediaType.video,
                                                position: AVCaptureDevice.Position.back) {
            print("defaultDevice - using dual cam")
            return device // use dual camera on supported devices
        } else if let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: .back) {
            print("defaultDevice - using wide angle cam")
            return device // use default back facing camera otherwise
        } else {
            fatalError("All supported devices are expected to have at least one of the queried capture devices.")
        }
    }
    
    // Device Configuration
    
    @IBOutlet weak var isoLabel: UILabel!
    @IBOutlet weak var expLabel: UILabel!
    
    
    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, at devicePoint: CGPoint, monitorSubjectAreaChange: Bool) {
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                /*
                 Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                 Call set(Focus/Exposure)Mode() to apply the new point of interest.
                 */
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
                
                let exp = device.exposureDuration
                let iso = device.iso
                let expValInt = Int(1 / CMTimeGetSeconds(device.exposureDuration))
                print("focus - ISO: \(iso)")
                print("focus - ExpVal: \(expValInt)")
                print("focus - expCMTime: \(exp)\n")
                DispatchQueue.main.async {
                    self.isoLabel.text = String(iso)
                    self.expLabel.text = "1/" + String(expValInt)
                    self.isoLabel.isHidden = false
                    self.expLabel.isHidden = false
                }
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    private let photoOutput = AVCapturePhotoOutput()
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    @IBOutlet weak var isoIn: UITextField!
    @IBOutlet weak var expIn: UITextField!
    
    @IBOutlet weak var photoButton: UIButton!
    @IBAction func capturePhoto(_ photoButton: UIButton) {
        self.takePhoto()
    }
    
    private func takePhoto()
    {
        sessionQueue.async {
            
            let device = self.videoDeviceInput.device
            
            self.printISOnEXP(dev: device);
            
            // Photo settings for RAW capture.
            let rawFormatType = kCVPixelFormatType_14Bayer_RGGB
            
            // At this point the array should not be empty (session has been configured).
            guard self.photoOutput.availableRawPhotoPixelFormatTypes.contains(NSNumber(value: rawFormatType).uint32Value) else {
                print("No available RAW pixel formats")
                return
            }
            //guard let availableRawFormat = self.photoOutput.availableRawPhotoPixelFormatTypes.first else { return }
            
            let photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormatType)
            
            // MARK: Flash mode
            photoSettings.flashMode = .off
            photoSettings.isAutoStillImageStabilizationEnabled = false
            photoSettings.isHighResolutionPhotoEnabled = true
            
            print("takePhoto - photoSettings.isAutoStillImageStabilizationEnabled: \(photoSettings.isAutoStillImageStabilizationEnabled)")
            print("takePhoto - device.exposureMode: \(device.exposureMode.rawValue)\n")
            
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
                DispatchQueue.main.async {
                    self.previewView.videoPreviewLayer.opacity = 0
                    UIView.animate(withDuration: 0.25) {
                        self.previewView.videoPreviewLayer.opacity = 1
                    }
                }
            }, completionHandler: { photoCaptureProcessor in
                // When the capture is complete, remove a reference to the photo capture delegate so it can be deallocated.
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                    
                    //MARK: repeat capture
                    self.count = self.count+1;
                    if(self.count < 5)
                    {
                        self.takePhoto();
                    }
                }
            })
            
            /*
             The Photo Output keeps a weak reference to the photo capture delegate so
             we store it in an array to maintain a strong reference to this object
             until the capture is completed.
             */
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)

        }
    }
    
    
    private var keyValueObservations = [NSKeyValueObservation]()
    
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
//            let isLivePhotoCaptureSupported = self.photoOutput.isLivePhotoCaptureSupported
//            let isLivePhotoCaptureEnabled = self.photoOutput.isLivePhotoCaptureEnabled
//            let isDepthDeliveryDataSupported = self.photoOutput.isDepthDataDeliverySupported
//            let isDepthDeliveryDataEnabled = self.photoOutput.isDepthDataDeliveryEnabled
            
            DispatchQueue.main.async {
                self.photoButton.isEnabled = isSessionRunning
                
            }
        }
        keyValueObservations.append(keyValueObservation)
        
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: session)
        
        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }
    
    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        
        print("Capture session runtime error: \(error)")
        
        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
//                        self.resumeButton.isHidden = false
                    }
                }
            }
        } else {
//            resumeButton.isHidden = false
        }
    }
    
    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        /*
         In some scenarios we want to enable the user to resume the session running.
         For example, if music playback is initiated via control center while
         using AVCam, then the user can let AVCam resume
         the session running, which will stop music playback. Note that stopping
         music playback in control center will not automatically resume the session
         running. Also note that it is not always possible to resume, see `resumeInterruptedSession(_:)`.
         */
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
        }
    }
    
    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool
    {
//        let allowedCharacters = CharacterSet.decimalDigits
//        let characterSet = CharacterSet(charactersIn: string)
//        return allowedCharacters.isSuperset(of: characterSet)
        
        let characterSet = CharacterSet(charactersIn: string)
        let boolIsNumber = CharacterSet.decimalDigits.isSuperset(of: characterSet)
        if boolIsNumber == true {
            return true
        } else {
            if string == "." {
                let countdots = textField.text!.components(separatedBy: ".").count - 1
                if countdots == 0 {
                    return true
                } else {
                    if countdots > 0 && string == "." {
                        return false
                    } else {
                        return true
                    }
                }
            } else {
                return false
            }
        }
    }
    
    
    //--------------------------------------------Helper Method-----------------------------------------------------
    
    
    private func setExposureDurationAndISO(time: Float64, isoVal: Float) {
        do {
            try self.videoDeviceInput.device.lockForConfiguration()
            self.videoDeviceInput.device.setExposureModeCustom(duration: CMTimeMakeWithSeconds(time, 1000*1000*1000), iso: isoVal, completionHandler: nil)
            self.videoDeviceInput.device.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    private func setExposureDuration(time: Float64) {
        do {
            try self.videoDeviceInput.device.lockForConfiguration()
            self.videoDeviceInput.device.setExposureModeCustom(duration: CMTimeMakeWithSeconds(time, 1000*1000*1000), iso: AVCaptureDevice.currentISO, completionHandler: nil)
            self.videoDeviceInput.device.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    private func setISO(isoVal: Float) {
        do {
            try self.videoDeviceInput.device.lockForConfiguration()
            self.videoDeviceInput.device.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: isoVal, completionHandler: nil)
            self.videoDeviceInput.device.unlockForConfiguration()
        } catch let error {
            NSLog("Could not lock device for configuration: \(error)")
        }
    }
    
    private func printISOnEXP(dev: AVCaptureDevice)
    {
        let exp = dev.exposureDuration
        let iso = dev.iso
        let expValInt = Int(1 / CMTimeGetSeconds(dev.exposureDuration))
        print("takePhoto - ISO: \(iso)")
        print("takePhoto - ExpVal: \(expValInt)")
        print("takePhoto - expCMTime: \(exp)\n")
    }
    
}











