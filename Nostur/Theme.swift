//
//  AppTheme.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/08/2023.
//

import Foundation
import SwiftUI
import Combine

public struct Theme: Equatable, Identifiable {
    public var id = "Default"
    public var primary = Color.primary
    public var secondary = Color.secondary
    public var accent = Color("defaultAccentColor")
    public var background = Color("defaultBackground")
    public var secondaryBackground = Color("defaultSecondaryBackground")
    public var listBackground = Color("defaultListBackground")
    public var badge = Color.red
    
    // Need to remove/redo/rename these:
    public var lineColor = Color("defaultLineColor")
    public var footerButtons = Color("defaultFooterButtonsColor")
    
    static public func == (lhs: Theme, rhs: Theme) -> Bool {
        lhs.id == rhs.id
    }
}

class Themes: ObservableObject {
    
    @Published var theme: Theme = Theme()
    
    static let `default` = Themes()
    
    public var selectedTheme: String {
        get { UserDefaults.standard.string(forKey: "app_theme") ?? "default" }
        set { UserDefaults.standard.setValue(newValue, forKey: "app_theme") }
    }
        
    private init() {
        switch selectedTheme {
        case "default":
            loadDefault()
        case "classic":
            loadClassic()
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
        case "bw":
            loadBlackAndWhite()
        default:
            loadDefault()
        }
    }
    
    public func loadDefault() {
        selectedTheme = "default"
        theme = Self.DEFAULT
    }
    
    static let DEFAULT = Theme()
    
    static let CLASSIC = Theme(
        id: "Classic",
        primary: Color.primary,
        secondary: Color.secondary,
        accent: Color("classicAccentColor"),
        background: Color("classicBackground"),
        secondaryBackground: Color(.secondarySystemBackground),
        listBackground: Color("classicListBackground"),
        badge: Color.red,
        lineColor: Color("classicLineColor"),
        footerButtons: Color("classicAccentColor")
    )
    
    public func loadClassic() {
        selectedTheme = "classic"
        theme = Self.CLASSIC
    }
    
    static let GREEN = Theme(
        id: "Green",
        primary: Color.primary,
        secondary: Color.secondary,
        accent: Color("greenAccentColor"),
        background: Color("greenBackground"),
        secondaryBackground: Color(.secondarySystemBackground),
        listBackground: Color("greenListBackground"),
        badge: Color.red,
        lineColor: Color("greenLineColor"),
        footerButtons: Color("greenAccentColor")
    )
    
    public func loadGreen() {
        selectedTheme = "green"
        theme = Self.GREEN
    }
    
    static let PINK = Theme(
        id: "Pink",
        primary: Color.primary,
        secondary: Color.secondary,
        accent: Color("pinkAccentColor"),
        background: Color("pinkBackground"),
        secondaryBackground: Color(.secondarySystemBackground),
        listBackground: Color("pinkListBackground"),
        badge: Color.red,
        lineColor: Color("pinkLineColor"),
        footerButtons: Color(red: 255/255, green: 50/255, blue: 221/255)
    )
    
    public func loadPink() {
        selectedTheme = "pink"
        theme = Self.PINK
    }
    
    static let ORANGE = Theme(
        id: "Orange",
        primary: Color.primary,
        secondary: Color.secondary,
        accent: Color("orangeAccentColor"),
        background: Color("orangeBackground"),
        secondaryBackground: Color(.secondarySystemBackground),
        listBackground: Color("orangeListBackground"),
        badge: Color.red,
        lineColor: Color("orangeLineColor"),
        footerButtons: Color("orangeAccentColor")
    )
    
    public func loadOrange() {
        selectedTheme = "orange"
        theme = Self.ORANGE
    }
    
    static let PURPLE = Theme(
        id: "Purple",
        primary: Color.primary,
        secondary: Color.secondary,
        accent: Color("purpleAccentColor"),
        background: Color("purpleBackground"),
        secondaryBackground: Color(.secondarySystemBackground),
        listBackground: Color("purpleListBackground"),
        badge: Color.red,
        lineColor: Color("purpleLineColor"),
        footerButtons: Color("purpleAccentColor")
    )
    
    public func loadPurple() {
        selectedTheme = "purple"
        theme = Self.PURPLE
    }
    
    static let RED = Theme(
        id: "Red",
        primary: Color.primary,
        secondary: Color.secondary,
        accent: Color("redAccentColor"),
        background: Color("redBackground"),
        secondaryBackground: Color(.secondarySystemBackground),
        listBackground: Color("redListBackground"),
        badge: Color.red,
        lineColor: Color("redLineColor"),
        footerButtons: Color("redAccentColor")
    )
    
    public func loadRed() {
        selectedTheme = "red"
        theme = Self.RED
    }
    
    static let BLUE = Theme(
        id: "Blue",
        primary: Color.primary,
        secondary: Color.secondary,
        accent: Color("blueAccentColor"),
        background: Color("blueBackground"),
        secondaryBackground: Color(.secondarySystemBackground),
        listBackground: Color("blueListBackground"),
        badge: Color.red,
        lineColor: Color("blueLineColor"),
        footerButtons: Color("blueAccentColor")
    )
    
    public func loadBlue() {
        selectedTheme = "blue"
        theme = Self.BLUE
    }
    
    static let BLACK_AND_WHITE = Theme(
        id: "BlackAndWhite",
        primary: Color.primary,
        secondary: Color.secondary,
        accent: Color("bwAccentColor"),
        background: Color("bwBackground"),
        secondaryBackground: Color(.secondarySystemBackground),
        listBackground: Color("bwListBackground"),
        badge: Color.red,
        lineColor: Color("bwLineColor"),
        footerButtons: Color("bwAccentColor")
    )
    
    public func loadBlackAndWhite() {
        selectedTheme = "bw"
        theme = Self.BLACK_AND_WHITE
    }
}

import NavigationBackport

#Preview("Posts") {
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

#Preview("App") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadReposts()
    }) {
        NosturMainView()
    }
}
