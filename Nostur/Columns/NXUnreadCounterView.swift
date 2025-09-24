//
//  NXUnreadCounterView.swift
//  Nosturix
//
//  Created by Fabian Lachman on 01/08/2024.
//

import SwiftUI

struct NXUnreadCounterView: View {
    public var vm: NXColumnViewModelInner
    
    var body: some View {
        if #available(iOS 26.0, *) {
            NXUnreadCounterView26(vm: vm)
        }
        else {
            NXUnreadCounterView15(vm: vm)
        }
    }
}

@available(iOS 26.0, *)
struct NXUnreadCounterView26: View {
    
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject public var vm: NXColumnViewModelInner
    
    var body: some View {
//        RoundedRectangle(cornerRadius: 20)
        Color.clear
//            .foregroundColor(theme.accent)
            .frame(width: 61, height: 36)
            .overlay(alignment: .leading) {
                Text(vm.unreadCount.description)
                    .foregroundColor(.white)
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
                    .foregroundColor(.white)
            }
            .fontWeightBold()
//            .foregroundColor(.white)
//            .padding(5)
            .modifier {
                if colorScheme == .dark {
                    $0.glassEffect(.clear.tint(theme.accent.opacity(0.35)).interactive())
                }
                else {
                    $0.glassEffect(
                        .clear.tint(
                            theme.accent
                                .mix(with: .black, by: 0.10)
                                .opacity(0.6)
                        )
                        .interactive()
                    )
                }
            }
        
//            .opacity(0.85)
            .contentShape(Rectangle())
    }
}


struct NXUnreadCounterView15: View {
    
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

@available(iOS 26.0, *)
#Preview("Glass effect test") {
    @Previewable @State var vmInner = NXColumnViewModelInner()
    @Previewable @State var vmInner2 = NXColumnViewModelInner()
    @Previewable @State var vmInner3 = NXColumnViewModelInner()
    @Previewable @State var vmInner4 = NXColumnViewModelInner()
    PreviewContainer {
        ZStack {
            
            let _ = Themes.default.loadDefault()
            
            Themes.default.theme.background
            
            ScrollView {
                VStack(spacing: 0) {
                    Box {
                        PostRowDeletable(nrPost: testNRPost())
                    }
                    Box {
                        PostRowDeletable(nrPost: testNRPost())
                    }
                    Box {
                        PostRowDeletable(nrPost: testNRPost())
                    }
                    Box {
                        PostRowDeletable(nrPost: testNRPost())
                    }
                    Color.clear
                        .frame(height: 500)
                    Box {
                        PostRowDeletable(nrPost: testNRPost())
                    }
                    Spacer()
                }
            }
            
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
                
                Color.clear
                    .frame(height: 500)
            }
        }
    }
}
