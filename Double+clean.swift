//
//  Double+clean.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/02/2023.
//

import Foundation

extension Double {
    var clean: String {
       return self.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(self)
    }
}
