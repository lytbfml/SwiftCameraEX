//
//  SettingObj.swift
//  Cameraw
//
//  Created by J L Newman on 3/16/18.
//  Copyright © 2018 Yangxiao Wang. All rights reserved.
//
struct SettingObj {
    
    var iso: Float
    var exp: Float64
    var num: Int
    var auto: Bool
}

extension SettingObj {
    init(iso: Float, exp:Float64, num: Int) {
        self.iso = iso
        self.exp = exp
        self.num = num
        self.auto = false
    }
    
    init(num: Int) {
        self.auto = true
        self.iso = 0
        self.exp = 0
        self.num = num
    }
}
