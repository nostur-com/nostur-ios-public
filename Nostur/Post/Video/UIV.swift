//
//  UIV.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/06/2023.
//

import SwiftUI

struct UIV: View {
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
}

struct UIV_Previews: PreviewProvider {
    static var previews: some View {
        UIV()
            .previewDevice(PreviewDevice(rawValue: "iPhone 14"))
    }
}
