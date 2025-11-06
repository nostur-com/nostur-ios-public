//
//  ScrollOffsetTest.swift
//  Nostur
//
//  Created by Fabian Lachman on 30/09/2025.
//

import SwiftUI
import NavigationBackport

@available(iOS 18.0, *)
struct ScrollOffsetTest: View {
    @ScrollOffsetProxy(.top, id: "Foo") private var scrollOffsetProxy
    
    var body: some View {
        VStack(spacing: 0) {
//            Color.red
//                .frame(height: 32) <-- This won't work because then we need to add +32 in NXListRow .preference(key: ListRowTopOffsetKey.self ..
            List {
                ForEach(0...70, id: \.self) { i in
//                    NXListRow {
//                        Text("Hello, World!")
//                            .padding(10)
//                            .padding(.top, 40)
//                            .background(Color.random)
//                            .padding(10)
//                            .background(Color.random)
//                            .id(i)
//                        
//                    } onAppearOnce: {
//                        print("onAppearOnce: \(String(describing: i))")
//                        return true
//                    }
//                    .listRowInsets(EdgeInsets())
//                    .listRowSeparator(.hidden)
                }
            }
            .scrollOffsetID("Foo")
            .listStyle(.plain)
            .listRowInsets(EdgeInsets())
            .withContainerTopOffsetEnvironmentKey()
            
            
//            Button("Scroll to Bottom") {
//               scrollOffsetProxy.scrollTo(0, withAnimation: true)
//            }
//            .padding()
        }
//        .edgesIgnoringSafeArea(.top)
    }
}

@available(iOS 18.0, *)
#Preview {
    PreviewContainer {
        NBNavigationStack {
            ScrollOffsetTest()
                .navigationTitle("What")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
