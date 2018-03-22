//
//  AddSettingViewController.swift
//  Cameraw
//
//  Created by J L Newman on 3/16/18.
//  Copyright © 2018 Yangxiao Wang. All rights reserved.
//

import UIKit

class AddSettingViewController: UIViewController {

    @IBOutlet weak var addISOTxt: UITextField!
    @IBOutlet weak var addExpTxt: UITextField!
    @IBOutlet weak var addNumTxt: UITextField!
    @IBOutlet weak var autoSwitch: UISwitch!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        navigationItem.title = "Add New Setting"
    }
    
    @IBAction func toggleAuto(_ sender: UISwitch) {
        if(autoSwitch.isOn) {
            addISOTxt.isEnabled = false
            addExpTxt.isEnabled = false
        } else {
            addISOTxt.isEnabled = true
            addExpTxt.isEnabled = true
        }
    }
    
    @IBAction func cancelButtonTapped(_ sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func saveButtonTapped(_ sender: UIBarButtonItem) {
        
        if(autoSwitch.isOn) {
            let num = addNumTxt.text!
            if (num.isEmpty) {
                let alert = UIAlertController(title: "Please enter all value", message: "", preferredStyle: UIAlertControllerStyle.alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.present(alert, animated: true, completion: nil)
                return
            }
            let numInt = Int(num)
            SettingsController.addSetting(newSetting: SettingObj(num: numInt!))
        } else {
            let isoTxt = addISOTxt.text!
            let expTxt = addExpTxt.text!
            let num = addNumTxt.text!
            
            if (isoTxt.isEmpty || expTxt.isEmpty || num.isEmpty) {
                let alert = UIAlertController(title: "Please enter all value", message: "", preferredStyle: UIAlertControllerStyle.alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.present(alert, animated: true, completion: nil)
                return
            }
            
            let isoVal = (isoTxt as NSString).floatValue
            let expVal = 1 / (expTxt as NSString).doubleValue
            let numInt = Int(num)
            SettingsController.addSetting(newSetting: SettingObj(iso: isoVal, exp: expVal, num: numInt!))
        }
        
        self.dismiss(animated: true, completion: nil)
    }

}
