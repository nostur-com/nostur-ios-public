//
//  FullScreenMediaView.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/03/2025.
//

import SwiftUI
import NavigationBackport

struct FullScreenMediaView: View {
    @State private var showFullImage = true
    @Namespace private var namespace

    var body: some View {
        ZStack {
            Image("NosturLogo")
                .resizable()
                .scaledToFit()
                .frame(width: showFullImage ? .infinity : 100, height: showFullImage ? .infinity : 100)
                .matchedGeometryEffect(id: "image", in: namespace)
                .onTapGesture {
                    withAnimation {
                        showFullImage = true
                    }
                }
            
            if showFullImage {
                Color.black
                    .edgesIgnoringSafeArea(.all)
                    .overlay {
                        
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close", systemImage: "multiply") {
                                withAnimation {
                                    showFullImage = false
                                }
                            }
                        }
                    }
                    .animation(.easeOut(duration: 0.5), value: showFullImage)
            }
            
            Image("NosturLogo")
                .resizable()
                .scaledToFit()
                .opacity(showFullImage ? 1.0 : 0)
                .matchedGeometryEffect(id: "image", in: namespace)
        }
    }
}

#Preview {
    NBNavigationStack {
        FullScreenMediaView()
    }
}

// .matchedGeometryEffect(id: "image", in: namespace)
// .edgesIgnoringSafeArea(.all)
// .animation(.easeOut(duration: 0.5), value: showFullImage)
