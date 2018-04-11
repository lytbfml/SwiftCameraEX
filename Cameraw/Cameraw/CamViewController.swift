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
    
    static let deviceID: String = UIDevice.current.identifierForVendor!.uuidString + "_"
    
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
    
    static var currentTimestamp: String!
    static var currentScenName: String!
    
    private var allPhotoNumsInCurrentSetting: Float!
    
    private let photoOutput = AVCapturePhotoOutput()
    
    private var inProgressPhotoCaptureDelegates = [Int64: PhotoCaptureProcessor]()
    
    private var keyValueObservations = [NSKeyValueObservation]()
    
    @objc var captureDevice: AVCaptureDevice?
    
    var videoDeviceInput: AVCaptureDeviceInput!
    
    private let session = AVCaptureSession()
    
    private var isSessionRunning = false
    
    private let sessionQueue = DispatchQueue(label: "session queue")
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private enum CaptureOption {
        case lockExp
        case lockFocus
        case manual
        case none
    }
    
    public enum WorkingMode {
        case manualCapture
        case aeCapture
        case none
    }
    
    private var setupResult: SessionSetupResult = .success
    
    private var captureOp: CaptureOption = .none
    
    private var workMode: WorkingMode = .aeCapture
    
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
    
    @IBAction func cleanBtnPressed(_ sender: Any) {
        self.clearAllFilesFromDocDirectory()
    }
    
    @IBAction func capturePhoto(_ photoButton: UIButton) {
        
        readyForCapture(mode: workMode)
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
        photoButton.layer.cornerRadius = photoButton.frame.width / 2
        
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
    }
    
    
    // MARK: Take photo
    private func takePhoto()
    {
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        sessionQueue.async {
            if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                photoOutputConnection.videoOrientation = videoPreviewLayerOrientation!
            }
            let device = self.captureDevice!
            
            self.printSettings(dev: device);
            
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
            
            let photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, device: device, photoCount: self.currentPhotoCount, willCapturePhotoAnimation: {
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
    
    private func readyForCapture(mode: WorkingMode) {
        DispatchQueue.main.async {
            self.captureStatusView.isHidden = false
            self.captureMsg.text = "Getting Ready..."
            self.captureMsg.isHidden = false
        }
        
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
    
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
            DispatchQueue.main.async {
                self.photoButton.isEnabled = isSessionRunning
                self.statusValue.text = self.getStatusValue()
            }
        }
        keyValueObservations.append(keyValueObservation)
        
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: session)
        
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
        
        self.addObserver(self, forKeyPath: "captureDevice.exposureMode" , options: .new, context: nil)
        self.addObserver(self, forKeyPath: "captureDevice.exposureDuration", options: .new, context: nil)
        self.addObserver(self, forKeyPath: "captureDevice.whiteBalanceMode", options: .new, context: nil)
        self.addObserver(self, forKeyPath: "captureDevice.focusMode", options: .new, context: nil)
        self.addObserver(self, forKeyPath: "captureDevice.ISO", options: .new, context: nil)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
        self.removeObserver(self, forKeyPath: "captureDevice.exposureMode")
        self.removeObserver(self, forKeyPath: "captureDevice.exposureDuration")
        self.removeObserver(self, forKeyPath: "captureDevice.whiteBalanceMode")
        self.removeObserver(self, forKeyPath: "captureDevice.ISO")
        self.removeObserver(self, forKeyPath: "captureDevice.focusMode")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        
        if keyPath == "captureDevice.exposureMode" {
            let expModeVal = captureDevice?.exposureMode.rawValue
            DispatchQueue.main.async {
                self.statusValue.text = self.getStatusValue()
            }
            if(self.captureOp == .lockExp && expModeVal == 0) {
                self.captureOp = .none
                onLockExpComplete()
            }
        }
        
        if keyPath == "captureDevice.exposureDuration" {
            let exposureDurationSeconds = CMTimeGetSeconds((self.captureDevice?.exposureDuration)!)
            DispatchQueue.main.async {
                self.expLabel.text = String(format: "1/%.f", 1.0 / exposureDurationSeconds)
            }
        }
        
        if keyPath == "captureDevice.focusMode" {
            let focusModeVal = captureDevice?.focusMode.rawValue
            DispatchQueue.main.async {
                self.statusValue.text = self.getStatusValue()
            }
            if(focusModeVal == 0 && self.captureOp == .lockFocus) {
                self.captureOp = .none
                onFocusComplete()
            }
        }
        
        if keyPath == "captureDevice.ISO" {
            DispatchQueue.main.async {
                self.isoLabel.text = String(format: "%.f", (self.captureDevice?.iso)!)
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
    
    //------------------------------------------------------------------------------------------------------------------------------
    //---------------------------------------------------Helper Method--------------------------------------------------------------
    //------------------------------------------------------------------------------------------------------------------------------
    
    private func captureSettings(index: Int) {
        if(index == 0 && currentSettingIndex == 0) {
            
            
            CamViewController.currentTimestamp = getTimestamp()
            CamViewController.currentScenName = createScenName()
            var count = 0
            for tempObj in SettingsController.settingsArray {
                count += tempObj.num
            }
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
        //MARK: Repeated Capturing
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
                onAllSettingComplete()
            }
        }
    }
    
    private func onAllSettingComplete() {
        DispatchQueue.main.async {
            self.captureStatusView.isHidden = true
        }
        currentSettingIndex = 0
        settingIndex = 0
        currentPhotoCount = 0
        let alert = UIAlertController(title: "Capture complete. Please confirm the following:", message: "During the capture session,\n1.the device camera did not move\n2.the scene content remained the same\n\nClick 'Confirm' to choose scene label, or 'Discard' to discard the current scene images.", preferredStyle: UIAlertControllerStyle.alert)
        alert.addAction(UIAlertAction(title: "Confirm", style: .default, handler: { (action) in
            let actSheet = UIAlertController(title: "Choose scene label", message: "", preferredStyle: .actionSheet)
            actSheet.addAction(UIAlertAction(title: "No label", style: .default, handler: nil))
            actSheet.addAction(UIAlertAction(title: "Books", style: .default, handler: { (action) in
                self.renameCurrentScene(label: "Books")
            }))
            actSheet.addAction(UIAlertAction(title: "Apple(s)", style: .default, handler: { (action) in
                
            }))
            actSheet.addAction(UIAlertAction(title: "Orange(s)", style: .default, handler: { (action) in
                
            }))
            actSheet.addAction(UIAlertAction(title: "Chair(s)", style: .default, handler: { (action) in
                
            }))
            actSheet.addAction(UIAlertAction(title: "Stairs/Stairwell", style: .default, handler: { (action) in
                
            }))
            actSheet.addAction(UIAlertAction(title: "Backpack", style: .default, handler: { (action) in
                
            }))
            actSheet.addAction(UIAlertAction(title: "Clock", style: .default, handler: { (action) in
                
            }))
            actSheet.addAction(UIAlertAction(title: "Keyboard", style: .default, handler: { (action) in
                
            }))
            actSheet.addAction(UIAlertAction(title: "Water bottle", style: .default, handler: { (action) in
                
            }))
            actSheet.addAction(UIAlertAction(title: "Keys", style: .default, handler: { (action) in
                
            }))
            self.present(actSheet, animated: true, completion: nil)
        }))
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive, handler: { (action) in
            self.removeCurrentScene()
        }))
        self.present(alert, animated: true, completion: nil)
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









