//
//  NXUnreadCounterView.swift
//  Nosturix
//
//  Created by Fabian Lachman on 01/08/2024.
//

import SwiftUI

struct NXUnreadCounterView: View {
    @ObservedObject public var unreadState: NXColumnUnreadState
    public var onTap: () -> Void = {}
    public var onLongPress: () -> Void = {}

    @AppStorage("nx_unread_counter_offset_x") private var offsetX: Double = 0
    @AppStorage("nx_unread_counter_offset_y") private var offsetY: Double = 0
    @State private var dragOffset = CGSize.zero
    
    var body: some View {
        if unreadState.unreadCount != 0 {
            Group {
                if #available(iOS 26.0, *) {
                    NXUnreadCounterView26(unreadCount: unreadState.unreadCount)
                }
                else {
                    NXUnreadCounterView15(unreadCount: unreadState.unreadCount)
                }
            }
            .offset(x: offsetX + dragOffset.width,
                    y: offsetY + dragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let newX = offsetX + value.translation.width
                        let newY = offsetY + value.translation.height

                        // Constrain position within screen bounds with padding
                        let minX: CGFloat = -(ScreenSpace.shared.mainTabSize.width - 91)
                        let minY: CGFloat = 0
                        let maxX: CGFloat = 0
                        let maxY: CGFloat = ScreenSpace.shared.mainTabSize.height - 296

                        offsetX = min(max(newX, minX), maxX)
                        offsetY = min(max(newY, minY), maxY)
                        dragOffset = .zero
                    }
            )
            .onTapGesture(perform: onTap)
            .simultaneousGesture(
                LongPressGesture().onEnded { _ in
                    onLongPress()
                }
            )
        }
    }
}

@available(iOS 26.0, *)
struct NXUnreadCounterView26: View {
    
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    public let unreadCount: Int
    
    var body: some View {
//        RoundedRectangle(cornerRadius: 20)
        Color.clear
//            .foregroundColor(theme.accent)
            .frame(width: 61, height: 36)
            .overlay(alignment: .leading) {
                Text(unreadCount.description)
                    .foregroundColor(.white)
                    .font(.system(size: unreadCount > 999 ? 13 : 16, weight: .bold))
                    .animation(.snappy, value: unreadCount)
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
        
            .glassEffect(
                .clear.tint(
                    colorScheme == .dark
                        ? theme.accent.opacity(0.35)
                        : theme.accent.mix(with: .black, by: 0.10).opacity(0.6)
                )
                .interactive()
            )
            .contentShape(Rectangle())
    }
}


struct NXUnreadCounterView15: View {
    
    @Environment(\.theme) private var theme
    public let unreadCount: Int
    
    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .foregroundColor(theme.accent)
            .frame(width: 61, height: 36)
            .overlay(alignment: .leading) {
                Text(unreadCount.description)
                    .font(.system(size: unreadCount > 999 ? 13 : 16, weight: .bold))
                    .animation(.snappy, value: unreadCount)
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
            NXUnreadCounterView(unreadState: vmInner.unreadState)
                .environmentObject(Themes.default)
                .onAppear {
                    vmInner.unreadIds["test"] = 5
                }
            
            NXUnreadCounterView(unreadState: vmInner2.unreadState)
                .environmentObject(Themes.default)
                .onAppear {
                    vmInner2.unreadIds["test"] = 27
                }
            
            NXUnreadCounterView(unreadState: vmInner3.unreadState)
                .environmentObject(Themes.default)
                .onAppear {
                    vmInner3.unreadIds["test"] = 342
                }
            
            NXUnreadCounterView(unreadState: vmInner4.unreadState)
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
                        PostRowDeletable(nrPost: testNRPost(), theme: Themes.default.theme)
                    }
                    Box {
                        PostRowDeletable(nrPost: testNRPost(), theme: Themes.default.theme)
                    }
                    Box {
                        PostRowDeletable(nrPost: testNRPost(), theme: Themes.default.theme)
                    }
                    Box {
                        PostRowDeletable(nrPost: testNRPost(), theme: Themes.default.theme)
                    }
                    Color.clear
                        .frame(height: 500)
                    Box {
                        PostRowDeletable(nrPost: testNRPost(), theme: Themes.default.theme)
                    }
                    Spacer()
                }
            }
            
            VStack(spacing: 20) {
                NXUnreadCounterView(unreadState: vmInner.unreadState)
                    .environmentObject(Themes.default)
                    .onAppear {
                        vmInner.unreadIds["test"] = 5
                    }
                
                NXUnreadCounterView(unreadState: vmInner2.unreadState)
                    .environmentObject(Themes.default)
                    .onAppear {
                        vmInner2.unreadIds["test"] = 27
                    }
                
                NXUnreadCounterView(unreadState: vmInner3.unreadState)
                    .environmentObject(Themes.default)
                    .onAppear {
                        vmInner3.unreadIds["test"] = 342
                    }
                
                NXUnreadCounterView(unreadState: vmInner4.unreadState)
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
