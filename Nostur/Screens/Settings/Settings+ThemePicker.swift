//
//  Settings+ThemePicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/08/2023.
//

import SwiftUI

struct ThemePicker: View {
    @Environment(\.theme) private var theme
    @State private var selectedTheme: String // Should just use @AppStorage("app_theme") here, but this freezes on desktop. so workaround via init() and .onChange(of: selectedTheme).
    
    init() {
        let selectedTheme = UserDefaults.standard.string(forKey: "app_theme") ?? "default"
        _selectedTheme = State(initialValue: selectedTheme)
    }
    
    var body: some View {
        Picker(selection: $selectedTheme) {
            Label("Default", systemImage: "circle.fill")
                .foregroundColor(Color("defaultAccentColor"))
                .tag("default")
            
            Label("Classic", systemImage: "circle.fill")
                .foregroundColor(Color("classicAccentColor"))
                .tag("classic")
            
            Label("Purple", systemImage: "circle.fill")
                .foregroundColor(Color("purpleAccentColor"))
                .tag("purple")
            
            Label("Red", systemImage: "circle.fill")
                .foregroundColor(Color("redAccentColor"))
                .tag("red")
            
            Label("Green", systemImage: "circle.fill")
                .foregroundColor(Color("greenAccentColor"))
                .tag("green")
            
            Label("Blue", systemImage: "circle.fill")
                .foregroundColor(Color("blueAccentColor"))
                .tag("blue")
            
            Label("Pink", systemImage: "circle.fill")
                .foregroundColor(Color("pinkAccentColor"))
                .tag("pink")
            
            Label("Orange", systemImage: "circle.fill")
                .foregroundColor(Color("orangeAccentColor"))
                .tag("orange")
            
            Label("Black & White", systemImage: "circle.fill")
                .foregroundColor(Color("bwAccentColor"))
                .tag("bw")
            
        } label: {
            Text("App theme")
        }
        .pickerStyleCompatNavigationLink()
        .onChange(of: selectedTheme) { theme in
            // switch .load
            
            switch theme {
            case "default":
                Themes.default.loadDefault()
            case "classic":
                Themes.default.loadClassic()
            case "purple":
                Themes.default.loadPurple()
            case "red":
                Themes.default.loadRed()
            case "green":
                Themes.default.loadGreen()
            case "blue":
                Themes.default.loadBlue()
            case "pink":
                Themes.default.loadPink()
            case "orange":
                Themes.default.loadOrange()
            case "bw":
                Themes.default.loadBlackAndWhite()
            default:
                Themes.default.loadDefault()
            }
            
            UserDefaults.standard.set(theme, forKey: "app_theme")
        }
    }
}

import NavigationBackport

struct Settings_ThemePicker_Previews: PreviewProvider {
    static var previews: some View {
        NBNavigationStack {
            Form {
                Section(header: Text("Display", comment:"Setting heading on settings screen")) {
                    ThemePicker()
                }
            }
        }
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
    }
}
