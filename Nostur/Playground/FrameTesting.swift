//
//  FrameTesting.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/09/2023.
//

import SwiftUI

struct FrameTesting: View {
    @EnvironmentObject private var themes:Themes
    
    var body: some View {
        HStack {
            Color.pink
                .frame(width: 10, height: 50)
            
            LazyVStack(spacing: GUTTER) {
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
            .background(themes.theme.listBackground)
            
            LazyVStack(spacing: GUTTER) {
                Something()
                    .frame(height: 25)
    //                .clipped()
                
                Something()
                    .frame(height: 50)
    //                .clipped()
            }
            .background(themes.theme.listBackground)
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
            .environmentObject(Themes.default)
            .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}

#Preview("Centering") {
    VStack {
        HStack(spacing: 5) {
            ProgressView()
            Text(Int(100), format: .percent)
                .frame(width: 48)
            Image(systemName: "multiply.circle.fill")
                .padding(10)
                .contentShape(Rectangle())
                .onTapGesture {
                    
                }
        }
//                    .centered()
        .frame(minHeight: 100, maxHeight: 250)
    }
}
