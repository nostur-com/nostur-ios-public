//
//  FeedSettings+AppThemeSwitcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI

struct AppThemeSwitcher: View {
    @AppStorage("app_theme") var selectedTheme = "default"
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        HStack {
            Spacer()
            Color("defaultAccentColor")
                .frame(width: 25, height: 25)
                .padding(3)
                .background(selectedTheme == "default" ? Color.secondary : .clear)
                .onTapGesture {
                    Themes.default.loadDefault()
                    dismiss()
                }
            Color("classicAccentColor")
                .frame(width: 25, height: 25)
                .padding(3)
                .background(selectedTheme == "classic" ? Color.secondary : .clear)
                .onTapGesture {
                    Themes.default.loadClassic()
                    dismiss()
                }
            Color("purpleAccentColor")
                .frame(width: 25, height: 25)
                .padding(3)
                .background(selectedTheme == "purple" ? Color.secondary : .clear)
                .onTapGesture {
                    Themes.default.loadPurple()
                    dismiss()
                }
            Color("redAccentColor")
                .frame(width: 25, height: 25)
                .padding(3)
                .background(selectedTheme == "red" ? Color.secondary : .clear)
                .onTapGesture {
                    Themes.default.loadRed()
                    dismiss()
                }
            Color("greenAccentColor")
                .frame(width: 25, height: 25)
                .padding(3)
                .background(selectedTheme == "green" ? Color.secondary : .clear)
                .onTapGesture {
                    Themes.default.loadGreen()
                    dismiss()
                }
            Color("blueAccentColor")
                .frame(width: 25, height: 25)
                .padding(3)
                .background(selectedTheme == "blue" ? Color.secondary : .clear)
                .onTapGesture {
                    Themes.default.loadBlue()
                    dismiss()
                }
            Color("pinkAccentColor")
                .frame(width: 25, height: 25)
                .padding(3)
                .background(selectedTheme == "pink" ? Color.secondary : .clear)
                .onTapGesture {
                    Themes.default.loadPink()
                    dismiss()
                }
            Color("orangeAccentColor")
                .frame(width: 25, height: 25)
                .padding(3)
                .background(selectedTheme == "orange" ? Color.secondary : .clear)
                .onTapGesture {
                    Themes.default.loadOrange()
                    dismiss()
                }
            Spacer()
        }
    }
}

import NavigationBackport

struct FeedSettings_AppThemeSwitcher_Previews: PreviewProvider {
    static var previews: some View {
        NBNavigationStack {
            AppThemeSwitcher()
                .environmentObject(Themes.default)
        }
    }
}
