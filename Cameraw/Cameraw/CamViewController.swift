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
    
    @IBOutlet weak var previewView: PreviewView!
    
    @IBOutlet weak var statusView: UIView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var statusValue: UILabel!
    @IBOutlet weak var isoLabel: UILabel!
    @IBOutlet weak var expLabel: UILabel!
    @IBOutlet weak var modeLabel: UILabel!
    
    @IBOutlet weak var settingsPage: UIButton!
    @IBOutlet weak var photoButton: UIButton!
    @IBOutlet weak var cleanButton: UIButton!
    
    @IBOutlet weak var captureStatusView: UIView!
    @IBOutlet weak var captureMsg: UILabel!
    @IBOutlet weak var captureProgress: UIProgressView!
    
    
    let session = AVCaptureSession()
    
    let photoOutput = AVCapturePhotoOutput()
    
    @objc var captureDevice: AVCaptureDevice?
    
    var videoDeviceInput: AVCaptureDeviceInput!
    
    private var isSessionRunning = false
    
    private let sessionQueue = DispatchQueue(label: "Configuration")
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private var setupResult: SessionSetupResult = .success
    
    private enum CaptureOption {
        case lockExp
        case lockFocus
        case manual
        case none
    }

    private var captureOp: CaptureOption = .none

    public enum WorkingMode {
        case manualCapture
        case aeCapture
        case none
    }
    
    private var workMode: WorkingMode = .aeCapture
    
    private var cameraState: CameraState = .initialization {
        didSet{
            DispatchQueue.main.async {
                self.modeLabel.text = self.cameraState.rawValue
            }
        }
    }
    
    public enum CameraState: String{
        case initialization = "Initialization"
        case previewing = "Previewing"
        case preparing = "Preparing"
        case preparingError = "PreparingError"
        case capturing = "Capturing"
        case capturingError = "CapturingError"
        case capturingFinished = "CapturingFinished"
    }
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    private var keyValueObservations = [NSKeyValueObservation]()
    
    static let deviceID: String = UIDevice.current.identifierForVendor!.uuidString + "_"
    static var currentTimestamp: String!
    static var currentScenName: String!
    private var allPhotoNumsInCurrentSetting: Float! = 0
    
    var currentSettingIndex = 0
    var settingIndex = 0
    var currentPhotoCount: Int = 0 {
        didSet {
            let fractionalProgress = Float(currentPhotoCount) / allPhotoNumsInCurrentSetting
            let animated = currentPhotoCount != 0
            DispatchQueue.main.async {
                self.captureProgress.setProgress(fractionalProgress, animated: animated)
            }
        }
    }
}

extension CamViewController {
    
    //------------------------------------------------------------------------------------------------------------------------------
    //---------------------------------------------MARK: View Controller Life Cycle-------------------------------------------------
    //------------------------------------------------------------------------------------------------------------------------------

    override func viewDidLoad() {
        super.viewDidLoad()
        uiConfig()
        checkVideoPermissions()
        previewView.session = session
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
                self.cameraState = .previewing
                
            case .notAuthorized:
                self.requestPermission()
                
            case .configurationFailed:
                let message = NSLocalizedString("Unable to capture video", comment: "Alert message when something goes wrong during capture session configuration")
                self.userAlertGenerator(title: "Cameraw", message: message, actions: [UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)], style: .alert)
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
    
}


//MARK: Photo capturing process
extension CamViewController {
    
    private func readyForCapture(mode: WorkingMode) {
        DispatchQueue.main.async {
            self.captureStatusView.isHidden = false
            self.captureMsg.text = "Getting Ready..."
            self.captureMsg.isHidden = false
            self.photoButton.isEnabled = false
            self.photoButton.alpha = 0.5
            self.settingsPage.isEnabled = false
            self.settingsPage.alpha = 0.5
            self.cleanButton.isEnabled = false
            self.cleanButton.alpha = 0.5
        }
        
        cameraState = .preparing
        
        if (mode == .manualCapture) {
            workMode = .manualCapture
            if(SettingsController.settingsArray.count == 0) {
                SettingsController.settingsArray.append(SettingObj(num: 1))
                self.lockFocus()
            }
            else {
                self.lockFocus()
            }
        } else if (mode == .aeCapture) {
            workMode = .aeCapture
            SettingsController.settingsArray.removeAll()
            SettingsController.settingsArray.append(SettingObj(num: 1))
            self.lockFocus()
        }
    }
    
    private func captureSettings(index: Int) {
        if(index == 0 && currentSettingIndex == 0) {
            CamViewController.currentTimestamp = getTimestamp()
            CamViewController.currentScenName = createScenName()
            let maxISO: Float! = captureDevice?.activeFormat.maxISO
            let minISO: Float! = captureDevice?.activeFormat.minISO
            let maxEXP: Float64! = CMTimeGetSeconds((captureDevice?.activeFormat.maxExposureDuration)!)
            let minEXP: Float64! = CMTimeGetSeconds((captureDevice?.activeFormat.minExposureDuration)!)

            var count = 0
            for tempObj in SettingsController.settingsArray {
                count += tempObj.num
                if(!tempObj.auto) {
                    let valid: Bool = (tempObj.iso.isLess(than: maxISO) && minISO.isLess(than: tempObj.iso) && tempObj.exp.isLess(than: maxEXP) && minEXP.isLess(than: tempObj.exp))
                    if (!valid) {
                        cameraState = .preparingError
                        onAllSettingComplete(message: String(format: "The passed ISO/EXP value is outside the supported range (ISO: %.6f - %.6f ), EXP: %.6f  - %.6f)", minISO, maxISO, minEXP, maxEXP))
                        
                        return
                    }
                }
            }
            cameraState = .capturing
            allPhotoNumsInCurrentSetting = Float(count)
            currentPhotoCount = 0
            DispatchQueue.main.async {
                self.captureMsg.text = "Capture In Progress"
                self.captureProgress.isHidden = false
            }
        }
        
        let currentSetting = SettingsController.settingsArray[index]
        
        if(currentSettingIndex == 0) {
            if(currentSetting.auto && workMode == .manualCapture) {
                lockExp()
            } else if (currentSetting.auto && workMode == .aeCapture) {
                takePhoto()
            } else {
                takePhotoWithBothSet(time: currentSetting.exp, isoVal: currentSetting.iso)
            }
        }
        else if(currentSettingIndex < currentSetting.num) {
            takePhoto()
        }
    }
    
    private func onCaptureSettingComplete() {
        currentPhotoCount += 1
        if(settingIndex < SettingsController.settingsArray.count) {
            currentSettingIndex += 1
            if(currentSettingIndex >= SettingsController.settingsArray[settingIndex].num) {
                settingIndex += 1
                currentSettingIndex = 0
            }
            if(settingIndex < SettingsController.settingsArray.count) {
                self.captureSettings(index: settingIndex)
            }
            else {
                cameraState = .capturingFinished
                onAllSettingComplete()
            }
        }
    }
    
    private func onAllSettingComplete(message: String = "Success") {
        DispatchQueue.main.async {
            self.captureStatusView.isHidden = true
            self.photoButton.isEnabled = true
            self.photoButton.alpha = 1
            self.settingsPage.isEnabled = true
            self.settingsPage.alpha = 1
            self.cleanButton.isEnabled = true
            self.cleanButton.alpha = 1
        }
        currentSettingIndex = 0
        settingIndex = 0
        currentPhotoCount = 0
        if(cameraState == .capturingFinished) {
            showLabelSelection()
        } else {
            userAlertGenerator(title: "Error", message: NSLocalizedString(message, comment: "Error message"), actions: [UIAlertAction(title: "Ok", style: .default, handler: nil)], style: .alert)
        }
        releaseAFAE()
        cameraState = .previewing
    }
    
    private func takePhoto()
    {
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
            }
            
            self.printSettings(dev: self.captureDevice!);
            
            let rawFormatType = kCVPixelFormatType_14Bayer_RGGB
            guard self.photoOutput.availableRawPhotoPixelFormatTypes.contains(NSNumber(value: rawFormatType).uint32Value) else {
                print("No available RAW pixel formats")
                return
            }
            
            let photoSettings = AVCapturePhotoSettings(rawPixelFormatType: rawFormatType,  processedFormat: [AVVideoCodecKey : AVVideoCodecType.jpeg])
            
            // MARK: Flash mode
            photoSettings.flashMode = .off
            photoSettings.isAutoStillImageStabilizationEnabled = false
            photoSettings.isHighResolutionPhotoEnabled = true
            
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, device: self.captureDevice!, photoCount: self.currentPhotoCount, willCapturePhotoAnimation: {
//                DispatchQueue.main.async {
//                    self.previewView.videoPreviewLayer.opacity = 0
//                    UIView.animate(withDuration: 0.25) {
//                        self.previewView.videoPreviewLayer.opacity = 1
//                    }
//                }
            }, completionHandler: { photoCaptureProcessor in
                self.sessionQueue.async {
                    self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = nil
                    print("Finish \(self.currentPhotoCount)\n")
                    self.onCaptureSettingComplete()
                }
            })
            self.inProgressPhotoCaptureDelegates[photoCaptureProcessor.requestedPhotoSettings.uniqueID] = photoCaptureProcessor
            self.photoOutput.capturePhoto(with: photoSettings, delegate: photoCaptureProcessor)
        }
    }
    
    private func lockFocus() {
        do {
            try captureDevice?.lockForConfiguration()
            captureOp = .lockFocus
            captureDevice?.focusMode = .autoFocus
            captureDevice?.unlockForConfiguration()
        } catch let error {
            print("Could not lock device for configuration: \(error)")
        }
    }
    
    private func onFocusComplete() {
        if(workMode == .manualCapture) {
            captureSettings(index: 0)
        } else if (workMode == .aeCapture) {
            lockExp()
        }
    }
    
    private func lockExp() {
        do {
            try captureDevice?.lockForConfiguration()
            captureOp = .lockExp
            captureDevice?.exposureMode = .autoExpose
            captureDevice?.unlockForConfiguration()
        } catch let error {
            print("Could not lock device for configuration: \(error)")
        }
    }
    
    private func onLockExpComplete() {
        if(workMode == .manualCapture) {
            takePhoto()
        } else if (workMode == .aeCapture) {
            let isoI: Float! = captureDevice?.iso
            let expI: Float64! = CMTimeGetSeconds((captureDevice?.exposureDuration)!)
            let isoMax: Float = isoI * 3
            let isoMin: Float = isoI / 2
            let isoMean: Float = (isoMax + isoMin) / 2
            let expMax: Float64 = expI * 2
            let expMin: Float64 = expI / 2
            let expMean: Float64 = (expMax + expMin) / 2
            
            SettingsController.settingsArray.append(SettingObj(iso: isoMin, exp: expMin, num: 1))
            SettingsController.settingsArray.append(SettingObj(iso: isoMin, exp: expMean, num: 1))
            SettingsController.settingsArray.append(SettingObj(iso: isoMin, exp: expMax, num: 1))
            SettingsController.settingsArray.append(SettingObj(iso: isoMean, exp: expMin, num: 1))
            SettingsController.settingsArray.append(SettingObj(iso: isoMean, exp: expMean, num: 1))
            SettingsController.settingsArray.append(SettingObj(iso: isoMean, exp: expMax, num: 1))
            SettingsController.settingsArray.append(SettingObj(iso: isoMax, exp: expMin, num: 1))
            SettingsController.settingsArray.append(SettingObj(iso: isoMax, exp: expMean, num: 1))
            SettingsController.settingsArray.append(SettingObj(iso: isoMax, exp: expMax, num: 1))
            captureSettings(index: 0)
        }
    }
    
    private func releaseAFAE() {
        do {
            try captureDevice?.lockForConfiguration()
            captureDevice?.focusMode = .continuousAutoFocus
            captureDevice?.exposureMode = .continuousAutoExposure
            captureDevice?.unlockForConfiguration()
        } catch let error {
            print("Could not lock device for configuration: \(error)")
        }
    }
    
    private func takePhotoWithAuto() {
        do {
            try self.videoDeviceInput.device.lockForConfiguration()
            captureDevice?.focusMode = .autoFocus
            captureDevice?.exposureMode = .autoExpose
            takePhoto()
            self.videoDeviceInput.device.unlockForConfiguration()
        } catch let error {
            print("Could not lock device for configuration: \(error)")
        }
    }
    
    private func takePhotoWithBothSet(time: Float64, isoVal: Float) {
        do {
            try captureDevice?.lockForConfiguration()
            captureDevice?.setExposureModeCustom(duration: CMTimeMakeWithSeconds(time, 1000*1000*1000), iso: isoVal, completionHandler: { (time) -> Void in
                self.takePhoto()
            })
            captureDevice?.unlockForConfiguration()
        } catch let error {
            print("Could not lock device for configuration: \(error)")
        }
    }
    
    private func takePhotoWithExpSet(time: Float64) {
        do {
            try captureDevice?.lockForConfiguration()
            captureDevice?.setExposureModeCustom(duration: CMTimeMakeWithSeconds(time, 1000*1000*1000), iso: AVCaptureDevice.currentISO, completionHandler: { (time) -> Void in
                self.takePhoto()
            })
            captureDevice?.unlockForConfiguration()
        } catch let error {
            print("Could not lock device for configuration: \(error)")
        }
    }
    
    private func takePotoWithIsoSet(isoVal: Float) {
        do {
            try captureDevice?.lockForConfiguration()
            captureDevice?.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: isoVal, completionHandler: { (time) -> Void in
                self.takePhoto()
            })
            captureDevice?.unlockForConfiguration()
        } catch let error {
            print("Could not lock device for configuration: \(error)")
        }
    }
}

//MARK: Configuration Process
extension CamViewController {
    
    private func uiConfig() {
        photoButton.isEnabled = false
        photoButton.layer.shadowColor = UIColor.black.cgColor
        photoButton.layer.shadowOffset = CGSize(width: 0.0, height: 2.0)
        photoButton.layer.masksToBounds = false
        photoButton.layer.shadowRadius = 1.0
        photoButton.layer.shadowOpacity = 0.5
        photoButton.layer.cornerRadius = photoButton.frame.width / 2
        
        settingsPage.isEnabled = false
        settingsPage.layer.shadowColor = UIColor.black.cgColor
        settingsPage.layer.shadowOffset = CGSize(width: 0.0, height: 2.0)
        settingsPage.layer.masksToBounds = false
        settingsPage.layer.shadowRadius = 1.0
        settingsPage.layer.shadowOpacity = 0.5
        settingsPage.layer.cornerRadius = settingsPage.frame.width / 5
        
        cleanButton.layer.shadowColor = UIColor.black.cgColor
        cleanButton.layer.shadowOffset = CGSize(width: 0.0, height: 2.0)
        cleanButton.layer.masksToBounds = false
        cleanButton.layer.shadowRadius = 1.0
        cleanButton.layer.shadowOpacity = 0.5
        cleanButton.layer.cornerRadius = cleanButton.frame.width / 5
        
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.text = "AF/AE/AWB Mode:\nISO:\nEXP:\nCapture Status:"
        
        captureProgress.transform = CGAffineTransform(scaleX: 1, y: 4)

    }
    
    private func checkVideoPermissions() {
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
    }
    
    private func requestPermission() {
        DispatchQueue.main.async {
            let changePrivacySetting = "Cameraw doesn't have permission to use the camera, please change privacy settings"
            let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
            let alertController = UIAlertController(title: "Cameraw", message: message, preferredStyle: .alert)
            
            alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
            
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .default, handler: { _ in
                UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
            }))
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        do {
            captureDevice = defaultDevice()
            let videoInput = try AVCaptureDeviceInput(device: captureDevice!)
            
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                videoDeviceInput = videoInput
                
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
            
        } catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.isLivePhotoCaptureEnabled = false
            photoOutput.isDepthDataDeliveryEnabled = false
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
}

//MARK: Observer and
extension CamViewController {
    private func addObservers() {
        
        let sessionObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
            DispatchQueue.main.async {
                self.photoButton.isEnabled = isSessionRunning
                self.statusValue.text = self.getStatusValue()
                self.statusView.isHidden = !(isSessionRunning)
                self.settingsPage.isEnabled = isSessionRunning
            }
        }
        
        let expObservation = captureDevice?.observe(\.exposureDuration, options: .new, changeHandler: { (_, change) in
            guard let newExp = change.newValue else { return }
            let exposureDurationSeconds = CMTimeGetSeconds(newExp)
            DispatchQueue.main.async {
                self.expLabel.text = String(format: "1/%.f", 1.0 / exposureDurationSeconds)
            }
        })
        
        let isoObservation = captureDevice?.observe(\.iso, options: .new, changeHandler: { (_, change) in
            DispatchQueue.main.async {
                self.isoLabel.text = String(format: "%.f", change.newValue!)
            }
        })
        
        
        keyValueObservations.append(sessionObservation)
        keyValueObservations.append(expObservation!)
        keyValueObservations.append(isoObservation!)
        
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: captureDevice)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
        self.addObserver(self, forKeyPath: #keyPath(captureDevice.exposureMode), options: .new, context: nil)
        //self.addObserver(self, forKeyPath: "captureDevice.exposureMode" , options: .new, context: nil)
        self.addObserver(self, forKeyPath: #keyPath(captureDevice.whiteBalanceMode), options: .new, context: nil)
        self.addObserver(self, forKeyPath: #keyPath(captureDevice.focusMode), options: .new, context: nil)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
        self.removeObserver(self, forKeyPath: #keyPath(captureDevice.exposureMode))
        self.removeObserver(self, forKeyPath: #keyPath(captureDevice.whiteBalanceMode))
        self.removeObserver(self, forKeyPath: #keyPath(captureDevice.focusMode))
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        
        if keyPath == #keyPath(captureDevice.exposureMode) {
            let expModeVal = captureDevice?.exposureMode.rawValue
            DispatchQueue.main.async {
                self.statusValue.text = self.getStatusValue()
            }
            if(self.captureOp == .lockExp && expModeVal == 0) {
                self.captureOp = .none
                onLockExpComplete()
            }
        }
        
        if keyPath == #keyPath(captureDevice.focusMode) {
            let focusModeVal = captureDevice?.focusMode.rawValue
            DispatchQueue.main.async {
                self.statusValue.text = self.getStatusValue()
            }
            if(focusModeVal == 0 && self.captureOp == .lockFocus) {
                self.captureOp = .none
                onFocusComplete()
            }
        }
        
        if keyPath == #keyPath(captureDevice.whiteBalanceMode) {
            let wbModeVal = captureDevice?.whiteBalanceMode.rawValue
            DispatchQueue.main.async {
                self.statusValue.text = self.getStatusValue()
            }
        }
    }
    
    
    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        //let devicePoint = CGPoint(x: 0.5, y: 0.5)
        //focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
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
}

extension CamViewController {
    @IBAction func cleanBtnPressed(_ sender: Any) {
        self.clearAllFilesFromDocDirectory()
    }
    
    @IBAction func capturePhoto(_ photoButton: UIButton) {
        self.readyForCapture(mode: workMode)
    }
}


//------------------------------------------------------------------------------------------------------------------------------
//---------------------------------------------MARK: Helper Method--------------------------------------------------------------
//------------------------------------------------------------------------------------------------------------------------------

extension CamViewController {
    
    private func getTimestamp() -> String {
        let date : Date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'-'HHmmss"
        dateFormatter.timeZone = TimeZone(abbreviation: "CDT")
        let timestamp = dateFormatter.string(from: date)
        return timestamp
    }
    
    private func createScenName() -> String {
        let docPath = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0])
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: docPath.path)
            let count = files.count / 2 + 1
            var scenCount: String
            if(count < 10) {
                scenCount = "00" + String(count)
            } else if (count < 100){
                scenCount = "0" + String(count)
            } else{
                scenCount = String(count)
            }
            let scenName: String = "Scene-" + scenCount
            
            return scenName
        } catch let error {
            fatalError("Unable to count directory \(error)")
        }
    }
    
    private func renameCurrentScene(label: String) {
        let fileManager = FileManager.default
        let docPath = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0])
        let scenPath1 = docPath.appendingPathComponent(CamViewController.currentScenName + "_JPG_" + CamViewController.currentTimestamp)
        let scenPath2 = docPath.appendingPathComponent(CamViewController.currentScenName + "_DNG_" + CamViewController.currentTimestamp)
        let scenDes1 = docPath.appendingPathComponent(CamViewController.currentScenName + "_JPG_" + CamViewController.currentTimestamp + "_" + label)
        let scenDes2 = docPath.appendingPathComponent(CamViewController.currentScenName + "_DNG_" + CamViewController.currentTimestamp + "_" + label)
        do {
            try fileManager.moveItem(at: scenPath1, to: scenDes1)
            try fileManager.moveItem(at: scenPath2, to: scenDes2)
        } catch {
            print("Could not clear temp folder: \(error)")
        }
    }
    
    private func removeCurrentScene() {
        let fileManager = FileManager.default
        let docPath = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0])
        let scenPath1 = docPath.appendingPathComponent(CamViewController.currentScenName + "_JPG_" + CamViewController.currentTimestamp)
        let scenPath2 = docPath.appendingPathComponent(CamViewController.currentScenName + "_DNG_" + CamViewController.currentTimestamp)
        
        do {
            try fileManager.removeItem(at: scenPath1)
            try fileManager.removeItem(at: scenPath2)
            let alert2 = UIAlertController(title: "Complete!", message: "Scene discard", preferredStyle: UIAlertControllerStyle.alert)
            alert2.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert2, animated: true, completion: nil)
        } catch {
            print("Could not clear temp folder: \(error)")
        }
    }
    
    private func userAlertGenerator(title: String?, message: String, actions: [UIAlertAction], style: UIAlertControllerStyle) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: style)
            for action in actions {
                alert.addAction(action)
            }
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    private func showLabelSelection() {
        let title = "Capture complete. Please confirm the following:"
        let msg = NSLocalizedString("During the capture session,\n1.the device camera did not move\n2.the scene content remained the same\n\nClick 'Confirm' to choose scene label, or 'Discard' to discard the current scene images.", comment: "Explain the options")
        var actions = [UIAlertAction]()
        
        let actionConfirm = UIAlertAction(title: "Confirm", style: .default, handler: { _ in
            var labelActions = [UIAlertAction]()
            labelActions.append(UIAlertAction(title: "No label", style: .default, handler: nil))
            labelActions.append(UIAlertAction(title: "Books", style: .default, handler: { _ in
                self.renameCurrentScene(label: "books")
            }))
            labelActions.append(UIAlertAction(title: "Apple(s)", style: .default, handler: { _ in
                self.renameCurrentScene(label: "apple")
            }))
            labelActions.append(UIAlertAction(title: "Orange(s)", style: .default, handler: { (action) in
                self.renameCurrentScene(label: "orange")
            }))
            labelActions.append(UIAlertAction(title: "Chair(s)", style: .default, handler: { (action) in
                self.renameCurrentScene(label: "chair")
            }))
            labelActions.append(UIAlertAction(title: "Stairs/Stairwell", style: .default, handler: { (action) in
                self.renameCurrentScene(label: "stairs")
            }))
            labelActions.append(UIAlertAction(title: "Backpack", style: .default, handler: { (action) in
                self.renameCurrentScene(label: "chair")
            }))
            labelActions.append(UIAlertAction(title: "Clock", style: .default, handler: { (action) in
                self.renameCurrentScene(label: "clock")
            }))
            labelActions.append(UIAlertAction(title: "Keyboard", style: .default, handler: { (action) in
                self.renameCurrentScene(label: "keyboard")
            }))
            labelActions.append(UIAlertAction(title: "Water bottle", style: .default, handler: { (action) in
                self.renameCurrentScene(label: "bottle")
            }))
            labelActions.append(UIAlertAction(title: "Keys", style: .default, handler: { (action) in
                self.renameCurrentScene(label: "keys")
            }))

            self.userAlertGenerator(title: "Choose scene label", message: "Please assign one of the following labels", actions: labelActions, style: .actionSheet)
        })
        
        let actionDiscard = UIAlertAction(title: "Discard", style: .destructive, handler: { (action) in
            self.removeCurrentScene()
        })
        actions.append(actionConfirm)
        actions.append(actionDiscard)
        
        userAlertGenerator(title: title, message: msg, actions: actions, style: .alert)

    }
    
    private func clearAllFilesFromDocDirectory(){
        let fileManager = FileManager.default
        let docPath = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0])
        do {
            let filePaths = try fileManager.contentsOfDirectory(atPath: docPath.path)
            for filePath in filePaths {
                try fileManager.removeItem(at: docPath.appendingPathComponent(filePath))
            }
            let alert = UIAlertController(title: "Complete!", message: "All files removed", preferredStyle: UIAlertControllerStyle.alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        } catch {
            print("Could not clear temp folder: \(error)")
        }
    }
    
    private func getStatusValue() -> String {
        let expModeVal = captureDevice?.exposureMode.rawValue
        var expValName: String
        switch expModeVal {
        case 0:
            expValName = "locked"
        case 1:
            expValName = "auto"
        case 2:
            expValName = "cont_auto"
        case 3:
            expValName = "custom"
        default:
            expValName = "unknown"
        }
        let focusModeVal = captureDevice?.focusMode.rawValue
        var focusModeName: String
        switch focusModeVal {
        case 0:
            focusModeName = "locked"
        case 1:
            focusModeName = "auto"
        case 2:
            focusModeName = "cont_auto"
        default:
            focusModeName = "unknown"
        }
        let wbModeVal = captureDevice?.whiteBalanceMode.rawValue
        var wbModeName: String
        switch wbModeVal {
        case 0:
            wbModeName = "locked"
        case 1:
            wbModeName = "auto"
        case 2:
            wbModeName = "cont_auto"
        default:
            wbModeName = "unknown"
        }
        let statusVal = focusModeName + "/" + expValName + "/" + wbModeName
        
        return statusVal
    }
    
    private func printSettings(dev: AVCaptureDevice) {
        let iso = dev.iso
        let exposureDurationSeconds = CMTimeGetSeconds(dev.exposureDuration)
        print(String(format: "printSettings - Iso: %.f", iso))
        print(String(format: "printSettings - ExpVal:  1/%.f", 1.0 / exposureDurationSeconds))
        print("printSettings - expCMTimeSec: \(exposureDurationSeconds)")
        print("printSettings - exposureMode: \(dev.exposureMode.rawValue) (locked = 0, autoExpose = 1, continuousAutoExposure = 2, custom = 3)")
        print("printSettings - focusMode: \(dev.focusMode.rawValue)")
        print("printSettings - Settings No. \(settingIndex), Photo No. \(currentSettingIndex)")
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









