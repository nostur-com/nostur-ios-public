//
//  AppTheme.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/08/2023.
//

import Foundation
import SwiftUI
import Combine

class Theme: ObservableObject {
    
    static let `default` = Theme()
    @AppStorage("app_theme") var selectedTheme = "default"
    
    @Published var primary = Color("defaultPrimary")
    @Published var secondary = Color("defaultSecondary")
    @Published var accent = Color("defaultAccentColor")
    @Published var background = Color("defaultBackground")
    @Published var secondaryBackground = Color("defaultSecondaryBackground")
    @Published var listBackground = Color("defaultListBackground")
    @Published var badge = Color.red
    
    // Need to remove/redo/rename these:
    @Published var lineColor = Color("defaultLineColor")
    @Published var footerButtons = Color("defaultLineColor")
    
    init() {
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
        primary = Color("defaultPrimary")
        secondary = Color("defaultSecondary")
        accent = Color("defaultAccentColor")
        background = Color("defaultBackground")
        secondaryBackground = Color("defaultSecondaryBackground")
        listBackground = Color("defaultListBackground")
        lineColor = Color("defaultLineColor")
        footerButtons = Color("defaultLineColor")
    }
    
    public func loadGreen() {
        selectedTheme = "green"
        primary = Color.primary
        secondary = Color.secondary
        accent = Color("greenAccentColor")
        background = Color("greenBackground")
        secondaryBackground = Color(.secondarySystemBackground)
        listBackground = Color("greenListBackground")
        lineColor = Color("greenAccentColor")
        footerButtons = Color("greenAccentColor")
    }
    
    public func loadPink() {
        selectedTheme = "pink"
        primary = Color.primary
        secondary = Color.secondary
        accent = Color("pinkAccentColor")
        background = Color("pinkBackground")
        secondaryBackground = Color(.secondarySystemBackground)
        listBackground = Color("pinkListBackground")
        lineColor = Color("pinkAccentColor")
        footerButtons = Color(red: 255/255, green: 50/255, blue: 221/255)
    }
    
    public func loadOrange() {
        selectedTheme = "orange"
        primary = Color.primary
        secondary = Color.secondary
        accent = Color("orangeAccentColor")
        background = Color("orangeBackground")
        secondaryBackground = Color(.secondarySystemBackground)
        listBackground = Color("orangeListBackground")
        lineColor = Color("orangeAccentColor")
        footerButtons = Color("orangeAccentColor")
    }
    
    public func loadPurple() {
        selectedTheme = "purple"
        primary = Color.primary
        secondary = Color.secondary
        accent = Color("purpleAccentColor")
        background = Color("purpleBackground")
        secondaryBackground = Color(.secondarySystemBackground)
        listBackground = Color("purpleListBackground")
        lineColor = Color("purpleAccentColor")
        footerButtons = Color("purpleAccentColor")
    }
    
    public func loadRed() {
        selectedTheme = "red"
        primary = Color.primary
        secondary = Color.secondary
        accent = Color("redAccentColor")
        background = Color("redBackground")
        secondaryBackground = Color(.secondarySystemBackground)
        listBackground = Color("redListBackground")
        lineColor = Color("redAccentColor")
        footerButtons = Color("redAccentColor")
    }
    
    public func loadBlue() {
        selectedTheme = "blue"
        primary = Color.primary
        secondary = Color.secondary
        accent = Color("blueAccentColor")
        background = Color("blueBackground")
        secondaryBackground = Color(.secondarySystemBackground)
        listBackground = Color("blueListBackground")
        lineColor = Color("blueAccentColor")
        footerButtons = Color("blueAccentColor")
    }
}

struct Previews_Theme_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadReposts()
        }) {
            NavigationStack {
                VStack {
                    Button("Color Blue") {
                        Theme.default.selectedTheme = "pink"
                        Theme.default.primary = Color.primary
                        Theme.default.secondary = Color.secondary
                        Theme.default.accent = Color("pinkAccentColor")
                        Theme.default.background = Color(red: 255/255, green: 200/255, blue: 221/255)
                        Theme.default.secondaryBackground = Color(red: 255/255, green: 179/255, blue: 208/255)
                        Theme.default.listBackground = Color(red: 205/255, green: 180/255, blue: 219/255)
                        Theme.default.lineColor = Color(red: 255/255, green: 200/255, blue: 221/255)
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
                    Theme.default.loadPurple()
                }
                .environmentObject(Theme.default)
                .tint(Theme.default.accent)
            }
        }
    }
}
