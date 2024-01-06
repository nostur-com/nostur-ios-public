//
//  AppTheme.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/08/2023.
//

import Foundation
import SwiftUI
import Combine

public struct Theme {
    public var primary = Color("defaultPrimary")
    public var secondary = Color("defaultSecondary")
    public var accent = Color("defaultAccentColor")
    public var background = Color("defaultBackground")
    public var secondaryBackground = Color("defaultSecondaryBackground")
    public var listBackground = Color("defaultListBackground")
    public var badge = Color.red
    
    // Need to remove/redo/rename these:
    public var lineColor = Color("defaultLineColor")
    public var footerButtons = Color("defaultLineColor")
}

class Themes: ObservableObject {
    
    @Published var theme:Theme = Theme()
    
    static let `default` = Themes()
    
    public var selectedTheme: String {
        get { UserDefaults.standard.string(forKey: "app_theme") ?? "default" }
        set { UserDefaults.standard.setValue(newValue, forKey: "app_theme") }
    }
        
    private init() {
        switch selectedTheme {
        case "default":
            loadDefault()
        case "purple":
            loadPurple()
        case "red":
            loadRed()
        case "green":
            loadGreen()
        case "blue":
            loadBlue()
        case "pink":
            loadPink()
        case "orange":
            loadOrange()
        default:
            loadDefault()
        }
    }
    
    public func loadDefault() {
        selectedTheme = "default"
        theme = Theme()
    }
    
    public func loadGreen() {
        selectedTheme = "green"
        theme = Theme(
            primary: Color.primary,
            secondary: Color.secondary,
            accent: Color("greenAccentColor"),
            background: Color("greenBackground"),
            secondaryBackground: Color(.secondarySystemBackground),
            listBackground: Color("greenListBackground"),
            badge: Color.red,
            lineColor: Color("greenAccentColor"),
            footerButtons: Color("greenAccentColor")
        )
    }
    
    public func loadPink() {
        selectedTheme = "pink"
        
        theme = Theme(
            primary: Color.primary,
            secondary: Color.secondary,
            accent: Color("pinkAccentColor"),
            background: Color("pinkBackground"),
            secondaryBackground: Color(.secondarySystemBackground),
            listBackground: Color("pinkListBackground"),
            badge: Color.red,
            lineColor: Color("pinkAccentColor"),
            footerButtons: Color(red: 255/255, green: 50/255, blue: 221/255)
        )
    }
    
    public func loadOrange() {
        selectedTheme = "orange"
        theme = Theme(
            primary: Color.primary,
            secondary: Color.secondary,
            accent: Color("orangeAccentColor"),
            background: Color("orangeBackground"),
            secondaryBackground: Color(.secondarySystemBackground),
            listBackground: Color("orangeListBackground"),
            badge: Color.red,
            lineColor: Color("orangeAccentColor"),
            footerButtons: Color("orangeAccentColor")
        )
    }
    
    public func loadPurple() {
        selectedTheme = "purple"
        
        theme = Theme(
            primary: Color.primary,
            secondary: Color.secondary,
            accent: Color("purpleAccentColor"),
            background: Color("purpleBackground"),
            secondaryBackground: Color(.secondarySystemBackground),
            listBackground: Color("purpleListBackground"),
            badge: Color.red,
            lineColor: Color("purpleAccentColor"),
            footerButtons: Color("purpleAccentColor")
        )
    }
    
    public func loadRed() {
        selectedTheme = "red"
        theme = Theme(
            primary: Color.primary,
            secondary: Color.secondary,
            accent: Color("redAccentColor"),
            background: Color("redBackground"),
            secondaryBackground: Color(.secondarySystemBackground),
            listBackground: Color("redListBackground"),
            badge: Color.red,
            lineColor: Color("redAccentColor"),
            footerButtons: Color("redAccentColor")
        )
    }
    
    public func loadBlue() {
        selectedTheme = "blue"
        theme = Theme(
            primary: Color.primary,
            secondary: Color.secondary,
            accent: Color("blueAccentColor"),
            background: Color("blueBackground"),
            secondaryBackground: Color(.secondarySystemBackground),
            listBackground: Color("blueListBackground"),
            badge: Color.red,
            lineColor: Color("blueAccentColor"),
            footerButtons: Color("blueAccentColor")
        )
    }
}

import NavigationBackport

struct Previews_Theme_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadReposts()
        }) {
            NBNavigationStack {
                VStack {
                    Button("Color Blue") {
                        Themes.default.loadBlue()
                    }                
                    if let p = PreviewFetcher.fetchNRPost() {
                        PostOrThread(nrPost: p)
                            .onAppear {
                                p.loadParents()
                            }
                    }
                    if let p = PreviewFetcher.fetchNRPost() {
                        PostOrThread(nrPost: p)
                            .onAppear {
                                p.loadParents()
                            }
                    }
                }
                .onAppear {
                    Themes.default.loadPurple()
                }
                .environmentObject(Themes.default)
                .tint(Themes.default.theme.accent)
            }
        }
    }
}
