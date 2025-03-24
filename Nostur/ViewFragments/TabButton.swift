//
//  TabButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/02/2023.
//

import SwiftUI

// Tabs for main feeds, not for DetailPane
struct TabButton<Content: View>: View {
    @EnvironmentObject private var themes: Themes
    public var action: () -> Void
    public var systemIcon: String?
    public var imageName: String?
    public var title: String
    public var secondaryText: String?
    public var selected: Bool
    public var unread: Int?
    public var muted: Bool
    
    private let tools: () -> Content?
    
    init(action: @escaping () -> Void,
         systemIcon: String? = nil,
         imageName: String? = nil,
         title: String = "",
         secondaryText: String? = nil,
         selected: Bool = false,
         unread: Int? = nil,
         muted: Bool = false,
         @ViewBuilder tools: @escaping () -> Content? = { EmptyView() }
    ) {
        self.action = action
        self.systemIcon = systemIcon
        self.imageName = imageName
        self.title = title
        self.secondaryText = secondaryText
        self.selected = selected
        self.unread = unread
        self.muted = muted
        self.tools = tools
    }
    
    var body: some View {
        Button { action() } label: {
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 3) {
                    if let systemIcon = systemIcon {
                        Image(systemName: systemIcon)
                            .font(.subheadline)
                            .foregroundColor(themes.theme.accent)
                    }
                    else if let imageName = imageName {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundColor(themes.theme.accent)
                    }
                    else {
                        Text(title).lineLimit(1)
                            .font(.subheadline)
                            .foregroundColor(themes.theme.accent)
                    }
                        
                    if let secondaryText {
                        Text(secondaryText).lineLimit(1)
                            .font(.caption)
                            .foregroundColor(themes.theme.accent.opacity(0.5))
                    }
                    self.tools()
                    if let unread, unread > 0 {
                        Text("\(unread)")
                            .font(.footnote)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .background(Capsule().foregroundColor(themes.theme.badge))
                            .opacity(muted ? 0.25 : 1.0)
                            .offset(y: -2)
                    }
                }
                .padding(.horizontal, 5)
                .frame(height: 41)
                .fixedSize()
                themes.theme.accent
                    .frame(height: 1)
                    .opacity(selected ? 1 : 0.15)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }
}

#Preview("Tab buttons") {
    PreviewContainer {
        VStack(spacing: 0) {
            
            // MANY TABS
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing:0) {
                    Group {
                        TabButton(action: {
                            print("dede")
                        }, title: "Following", selected:true)
                        Spacer()
                        
                        TabButton(action: {
                            print("dede")
                        }, title: "Quality")
                        Spacer()
                        
                        TabButton(action: {
                            print("dede")
                        }, title: "Hot", secondaryText: "4h")
                        Spacer()
                        
                        TabButton(action: {
                            print("dede")
                        }, title: "Gallery")
                        Spacer()
                    }
                    Group {
                        TabButton(action: {
                            print("dede")
                        }, title: "Explore")
                        Spacer()
                        
                        TabButton(action: {
                            print("dede")
                        }, title: "Articles")
                        Spacer()
                        
                        TabButton(action: {
                            print("dede")
                        }, title: "Popular")
                    }
                }
//                .padding(.horizontal, 10)
                .frame(minWidth: UIScreen.main.bounds.width)
            }
            
            Divider()
            
            // LESS TABS
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing:0) {
                    TabButton(action: {
                        print("dede")
                    }, title: "Following")

                    Spacer()

                    TabButton(action: {
                        print("dede")
                    }, title: "Explore")
                }
//                .padding(.horizontal, 10)
                .frame(minWidth: UIScreen.main.bounds.width)
            }
            

            Divider()
            
            // NO SPACERS
            HStack(spacing: 2) {
                TabButton(action: {
                    print("dede")
                }, title: "Following")
                
                TabButton(action: {
                    print("dede")
                }, title: "Hot", secondaryText: "4h")
                
                TabButton(action: {
                    print("dede")
                }, title: "Globalish", unread:3)
                
                TabButton(action: {
                    print("dede")
                }, title: "testing!", selected: true)
            }
//            .padding(.horizontal, 10)
            .frame(minWidth: UIScreen.main.bounds.width)
        }
        .frame(width: UIScreen.main.bounds.width)
        .onAppear {
            Themes.default.loadPink()
        }
    }
}
