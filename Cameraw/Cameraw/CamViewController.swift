//
//  ViewController.swift
//  Cameraw
//
//  Created by Yangxiao Wang on 1/29/18.
//  Copyright © 2018 Yangxiao Wang. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

class CamViewController: UIViewController {
    
    static var count = 0
    static var settingCount = 0;
    
    private let photoOutput = AVCapturePhotoOutput()
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    private var keyValueObservations = [NSKeyValueObservation]()
    
    @objc var captureDevice: AVCaptureDevice?
    
    @IBOutlet weak var isoLabel: UILabel!
    @IBOutlet weak var expLabel: UILabel!
    @IBOutlet weak var settingsPage: UIButton!
    @IBOutlet weak var photoButton: UIButton!
    @IBAction func capturePhoto(_ photoButton: UIButton) {
        if(SettingsController.settingsArray.count == 0) {
            CamViewController.count = 0;
            self.takePhoto()
        }
        else {
            self.captureSettings(index: 0)
        }
    }
    
    
    //------------------------------------------------------------------------------------------------------------------------------
    //---------------------------------------------MARK: View Controller Life Cycle-------------------------------------------------
    //------------------------------------------------------------------------------------------------------------------------------

    override func viewDidLoad() {
        super.viewDidLoad()
        
        UIConfig()
        previewView.session = session
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
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
            setupResult = .notAuthorized
        }
        sessionQueue.async {
            self.configureSession()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
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
                                                            style: .`default`, handler: { _ in UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
                    }))
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
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
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation),
                deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                    return
            }
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private let session = AVCaptureSession()
    
    private var isSessionRunning = false
    
    private let sessionQueue = DispatchQueue(label: "session queue")
    
    private var setupResult: SessionSetupResult = .success
    
    var videoDeviceInput: AVCaptureDeviceInput!
    
    @IBOutlet weak var previewView: PreviewView!
    
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        let defaultVideoDevice = defaultDevice()
        self.captureDevice = defaultVideoDevice
        guard let videoInput = try? AVCaptureDeviceInput(device: defaultVideoDevice) else {
            print("Unable to obtain video input for default camera.")
            return
        }
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
            self.videoDeviceInput = videoInput
            
            DispatchQueue.main.async {
                let statusBarOrientation = UIApplication.shared.statusBarOrientation
                var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                if statusBarOrientation != .unknown {
                    if let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: statusBarOrientation) {
                        initialVideoOrientation = videoOrientation
                    }
                }
                self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
            }
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
        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    func defaultDevice() -> AVCaptureDevice {
        if let device = AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInDualCamera, for: AVMediaType.video, position: AVCaptureDevice.Position.back) {
            print("defaultDevice - using dual cam")
            return device // use dual camera on supported devices
        } else if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            print("defaultDevice - using wide angle cam")
            return device // use default back facing camera otherwise
        } else {
            fatalError("All supported devices are expected to have at least one of the queried capture devices.")
        }
    }
    
    private func UIConfig() {
        photoButton.isEnabled = false
        photoButton.layer.shadowColor = UIColor.black.cgColor
        photoButton.layer.shadowOffset = CGSize(width: 0.0, height: 2.0)
        photoButton.layer.masksToBounds = false
        photoButton.layer.shadowRadius = 1.0
        photoButton.layer.shadowOpacity = 0.5
        photoButton.layer.cornerRadius = photoButton.frame.width / 4
        
        settingsPage.layer.shadowColor = UIColor.black.cgColor
        settingsPage.layer.shadowOffset = CGSize(width: 0.0, height: 2.0)
        settingsPage.layer.masksToBounds = false
        settingsPage.layer.shadowRadius = 1.0
        settingsPage.layer.shadowOpacity = 0.5
        settingsPage.layer.cornerRadius = settingsPage.frame.width / 4
    }
    
    // MARK: Focus tap
    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        //let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        //focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, at devicePoint: CGPoint, monitorSubjectAreaChange: Bool) {
        sessionQueue.async {
            
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
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
                let expValInt = Int(1 / CMTimeGetSeconds(exp))
              
                DispatchQueue.main.async {
                    self.isoLabel.text = String(iso)
                    self.expLabel.text = "1/" + String(expValInt)
                    self.isoLabel.isHidden = false
                    self.expLabel.isHidden = false
                    self.photoButton.isEnabled = true
                }
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    // MARK: Take photo
    private func takePhoto()
    {
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
            }
            let device = self.videoDeviceInput.device
            self.printSettings(dev: device);
            
            let rawFormatType = kCVPixelFormatType_14Bayer_RGGB
            guard self.photoOutput.availableRawPhotoPixelFormatTypes.contains(NSNumber(value: rawFormatType).uint32Value) else {
                print("No available RAW pixel formats")
                return
            }
            
            let photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormatType)
            
            // MARK: Flash mode
            photoSettings.flashMode = .off
            photoSettings.isAutoStillImageStabilizationEnabled = false
            photoSettings.isHighResolutionPhotoEnabled = true
            
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, willCapturePhotoAnimation: {
                // MARK: willCapturePhotoAnimation
                print("willCapturePhotoAnimation")
//                DispatchQueue.main.async {
//                    self.previewView.videoPreviewLayer.opacity = 0
//                    UIView.animate(withDuration: 0.25) {
//                        self.previewView.videoPreviewLayer.opacity = 1
//                    }
//                }
            }, completionHandler: { photoCaptureProcessor in
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                    
                    //MARK: Repeated Capturing
                    if(CamViewController.settingCount < SettingsController.settingsArray.count) {
                        CamViewController.count += 1
                        if(CamViewController.count >= SettingsController.settingsArray[CamViewController.settingCount].num) {
                            CamViewController.settingCount += 1
                            CamViewController.count = 0
                        }
                        if(CamViewController.settingCount < SettingsController.settingsArray.count) {
                            self.captureSettings(index: CamViewController.settingCount)
                        }
                        else {
                            CamViewController.count = 0
                            CamViewController.settingCount = 0
                            let alert = UIAlertController(title: "Complete!", message: "", preferredStyle: UIAlertControllerStyle.alert)
                            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                            self.present(alert, animated: true, completion: nil)
                        }
                    }
                }
            })
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
        }
    }
    
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
            DispatchQueue.main.async {
                self.photoButton.isEnabled = isSessionRunning
            }
        }
        keyValueObservations.append(keyValueObservation)
        
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: session)
        
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
        
        self.addObserver(self, forKeyPath: "captureDevice.lensPosition" , options: .new, context: nil)
        self.addObserver(self, forKeyPath: "captureDevice.exposureDuration", options: .new, context: nil)
        self.addObserver(self, forKeyPath: "captureDevice.ISO", options: .new, context: nil)
        
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
        self.removeObserver(self, forKeyPath: "captureDevice.lensPosition")
        self.removeObserver(self, forKeyPath: "captureDevice.exposureDuration")
        self.removeObserver(self, forKeyPath: "captureDevice.ISO")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        
        if keyPath == "captureDevice.lensPosition" {
            //self.lensPosition.text = String(format: "%.1f", (self.videoDeviceInput.device.lensPosition)!)
            //print("\(self.videoDeviceInput.device.lensPosition)")
        }
        
        if keyPath == "captureDevice.exposureDuration" {
            let exposureDurationSeconds = CMTimeGetSeconds((self.captureDevice?.exposureDuration)!)
            self.expLabel.text = String(format: "Exp: 1/%.f", 1.0 / exposureDurationSeconds)
        }
        
        if keyPath == "captureDevice.ISO" {
            self.isoLabel.text = String(format: "Iso: %.f", (self.captureDevice?.iso)!)
        }
    }
    
    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
        fatalError("------subjectAreaDidChange------")
    }
    
    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        print("Capture session runtime error: \(error)")
        
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
    }
    
    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        
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
    
    //------------------------------------------------------------------------------------------------------------------------------
    //---------------------------------------------------Helper Method--------------------------------------------------------------
    //------------------------------------------------------------------------------------------------------------------------------
    
    private func setLabel(iso: Float, exposureDurationSeconds: Float64) {
        self.isoLabel.text = String(format: "Iso: %.f", iso)
        self.expLabel.text = String(format: "Exp: 1/%.f", 1.0 / exposureDurationSeconds)
        self.isoLabel.isHidden = false
        self.expLabel.isHidden = false
        self.photoButton.isEnabled = true
    }
    
    private func captureSettings(index: Int) {
        let currentSetting = SettingsController.settingsArray[index]
        
        if(CamViewController.count == 0) {
            if(currentSetting.auto) {
                takePhotoWithAuto()
            } else {
                takePhotoWithBothSet(time: currentSetting.exp, isoVal: currentSetting.iso)
            }
        }
        else if(CamViewController.count < currentSetting.num) {
            takePhoto()
        }
    }
    
    private func takePhotoWithAuto() {
        do {
            try self.videoDeviceInput.device.lockForConfiguration()
            captureDevice?.exposureMode = .autoExpose
            takePhoto()
            self.videoDeviceInput.device.unlockForConfiguration()
        } catch let error {
            print("Could not lock device for configuration: \(error)")
        }
    }
    
    private func takePhotoWithBothSet(time: Float64, isoVal: Float) {
        do {
            try self.captureDevice?.lockForConfiguration()
            self.captureDevice?.setExposureModeCustom(duration: CMTimeMakeWithSeconds(time, 1000*1000*1000), iso: isoVal, completionHandler: { (time) -> Void in
                self.takePhoto()
            })
            self.captureDevice?.unlockForConfiguration()
        } catch let error {
            print("Could not lock device for configuration: \(error)")
        }
    }
    
    private func takePhotoWithExpSet(time: Float64) {
        do {
            try self.videoDeviceInput.device.lockForConfiguration()
            self.videoDeviceInput.device.setExposureModeCustom(duration: CMTimeMakeWithSeconds(time, 1000*1000*1000), iso: AVCaptureDevice.currentISO, completionHandler: { (time) -> Void in
                self.takePhoto()
            })
            self.videoDeviceInput.device.unlockForConfiguration()
        } catch let error {
            print("Could not lock device for configuration: \(error)")
        }
    }
    
    private func takePotoWithIsoSet(isoVal: Float) {
        let devISO = getCurrentISO(dev: self.videoDeviceInput.device)
        print("SetISO - deviso: \(devISO), setting iso: \(isoVal)")
        do {
            try self.videoDeviceInput.device.lockForConfiguration()
            self.videoDeviceInput.device.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: isoVal, completionHandler: { (time) -> Void in
                self.takePhoto()
            })
            self.videoDeviceInput.device.unlockForConfiguration()
        } catch let error {
            print("Could not lock device for configuration: \(error)")
        }
    }
    
    private func getCurrentISO(dev: AVCaptureDevice) -> Float {
        return dev.iso
    }
    
    private func printSettings(dev: AVCaptureDevice) {
        let iso = dev.iso
        let exposureDurationSeconds = CMTimeGetSeconds(dev.exposureDuration)
        
        print(String(format: "printSettings - Iso: %.f", iso))
        print(String(format: "printSettings - ExpVal:  1/%.f", 1.0 / exposureDurationSeconds))
        print("printSettings - expCMTimeSec: \(exposureDurationSeconds)")
        print("printSettings - device.exposureMode: \(dev.exposureMode.rawValue) (locked = 0, autoExpose = 1, continuousAutoExposure = 2, custom = 3)")
        print("printSettings - Settings No. \(CamViewController.settingCount), Photo No. \(CamViewController.count)")
    }
    
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
    
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}









