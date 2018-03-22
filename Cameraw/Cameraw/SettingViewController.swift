//
//  SettingViewController.swift
//  Cameraw
//
//  Created by J L Newman on 3/16/18.
//  Copyright © 2018 Yangxiao Wang. All rights reserved.
//

import UIKit

class SettingViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    @IBOutlet weak var settingTableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        settingTableView.delegate = self
        settingTableView.dataSource = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        settingTableView.reloadData()
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return SettingsController.settingsArray.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = settingTableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = "\(indexPath.row + 1)"
        let currentSetting = SettingsController.settingsArray[indexPath.row]
        if(currentSetting.auto) {
            cell.detailTextLabel?.text = "Auto Exposure, Num: \(String(currentSetting.num))"
        } else {
            cell.detailTextLabel?.text = "ISO: \(String(currentSetting.iso)),  Exposure: \(String(currentSetting.exp)), Num: \(String(currentSetting.num))"
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if (editingStyle == .delete) {
            SettingsController.removeSetting(index: indexPath.row)
            settingTableView.deleteRows(at: [indexPath], with: .fade)
        }
    }
    
    @IBAction func doneButtonTapped(_ sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
    }
}


