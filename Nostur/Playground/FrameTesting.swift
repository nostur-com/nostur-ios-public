//
//  FrameTesting.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/09/2023.
//

import SwiftUI

struct FrameTesting: View {
    @EnvironmentObject var theme:Theme
    
    var body: some View {
        HStack {
            Color.pink
                .frame(width: 10, height: 50)
            
            LazyVStack(spacing: 10) {
                Something()
//                    .fixedSize()
                    .frame(height: 25)
//                    .fixedSize()
//                    .clipped()
                
                Something()
//                    .fixedSize()
                    .frame(height: 50)
//                    .fixedSize()
//                    .clipped()
            }
            .background(theme.listBackground)
            
            LazyVStack(spacing: 10) {
                Something()
                    .frame(height: 25)
    //                .clipped()
                
                Something()
                    .frame(height: 50)
    //                .clipped()
            }
            .background(theme.listBackground)
        }
        .frame(maxHeight: 50)
//        .clipped()
    }
}

struct Something: View {
    var body: some View {
        Box {
            VStack {
                Text("Hello, World! Hello World! Hello World! Hello World! Hello World! Hello World")
                Text("Hello, World! Hello World! Hello World! Hello World! Hello World! Hello World")
                Text("Hello, World! Hello World! Hello World! Hello World! Hello World! Hello World")
                Text("Hello, World! Hello World! Hello World! Hello World! Hello World! Hello World")
                    .background(.red)
            }
            .background(.green)
        }
        .padding(10)
        .background(.purple)
    }
}

struct FrameTesting_Previews: PreviewProvider {
    static var previews: some View {
        FrameTesting()
        
        
        
        
            .environmentObject(Theme.default)
            .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}
