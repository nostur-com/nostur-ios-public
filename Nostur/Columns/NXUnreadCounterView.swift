//
//  NXUnreadCounterView.swift
//  Nosturix
//
//  Created by Fabian Lachman on 01/08/2024.
//

import SwiftUI

struct NXUnreadCounterView: View {
    
    @Environment(\.theme) private var theme
    @ObservedObject public var vm: NXColumnViewModelInner
    
    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .foregroundColor(theme.accent)
            .frame(width: 61, height: 36)
            .overlay(alignment: .leading) {
                Text(vm.unreadCount.description)
                    .font(.system(size: vm.unreadCount > 999 ? 13 : 16, weight: .bold))
                    .animation(.snappy, value: vm.unreadCount)
                    .rollingNumber()
                    .fixedSize()
                    .frame(width: 35, alignment: .center)
                    .padding(.leading, 7)
                    
            }
            .overlay(alignment: .trailing) {
                Image(systemName: "arrow.up")
                    .padding(.trailing, 6)
                    .font(.footnote)
            }
            .fontWeightBold()
            .foregroundColor(.white)
            .padding(5)
            .opacity(0.85)
            .contentShape(Rectangle())
    }
}

@available(iOS 17.0, *)
#Preview {
    @Previewable @State var vmInner = NXColumnViewModelInner()
    @Previewable @State var vmInner2 = NXColumnViewModelInner()
    @Previewable @State var vmInner3 = NXColumnViewModelInner()
    @Previewable @State var vmInner4 = NXColumnViewModelInner()
    ZStack {
        
        let _ = Themes.default.loadDefault()
        
        Themes.default.theme.background
        
        VStack(spacing: 20) {
            NXUnreadCounterView(vm: vmInner)
                .environmentObject(Themes.default)
                .onAppear {
                    vmInner.unreadIds["test"] = 5
                }
            
            NXUnreadCounterView(vm: vmInner2)
                .environmentObject(Themes.default)
                .onAppear {
                    vmInner2.unreadIds["test"] = 27
                }
            
            NXUnreadCounterView(vm: vmInner3)
                .environmentObject(Themes.default)
                .onAppear {
                    vmInner3.unreadIds["test"] = 342
                }
            
            NXUnreadCounterView(vm: vmInner4)
                .environmentObject(Themes.default)
                .onAppear {
                    vmInner4.unreadIds["test"] = 3420
                }
        }
    }
}
