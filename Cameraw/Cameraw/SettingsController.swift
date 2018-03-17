//
//  SettingsController.swift
//  Cameraw
//
//  Created by Yangxiao Wang on 3/16/18.
//  Copyright © 2018 Yangxiao Wang. All rights reserved.
//

import UIKit

class SettingsController: NSObject {
    
    static var settingsArray: Array<SettingObj> = []
    
    class func addSetting(newSetting: SettingObj) {
        SettingsController.settingsArray.append(newSetting)
    }
    
    class func removeSetting(index: Int) {
        SettingsController.settingsArray.remove(at: index)
    }
}
