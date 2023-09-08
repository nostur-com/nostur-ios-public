//
//  FeedSettings+AppThemeSwitcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI

struct AppThemeSwitcher: View {
    @AppStorage("app_theme") var selectedTheme = "default"
    @Binding var showFeedSettings:Bool
    
    var body: some View {
        VStack {
            Text("App theme")
                .fontWeight(.bold)
                .hCentered()
            HStack {
                Spacer()
                Color("defaultAccentColor")
                    .frame(width: 25, height: 25)
                    .padding(3)
                    .background(selectedTheme == "default" ? Color.secondary : .clear)
                    .onTapGesture {
                        Theme.default.loadDefault()
                        showFeedSettings = false
                    }
                Color("purpleAccentColor")
                    .frame(width: 25, height: 25)
                    .padding(3)
                    .background(selectedTheme == "purple" ? Color.secondary : .clear)
                    .onTapGesture {
                        Theme.default.loadPurple()
                        showFeedSettings = false
                    }
                Color("redAccentColor")
                    .frame(width: 25, height: 25)
                    .padding(3)
                    .background(selectedTheme == "red" ? Color.secondary : .clear)
                    .onTapGesture {
                        Theme.default.loadRed()
                        showFeedSettings = false
                    }
                Color("greenAccentColor")
                    .frame(width: 25, height: 25)
                    .padding(3)
                    .background(selectedTheme == "green" ? Color.secondary : .clear)
                    .onTapGesture {
                        Theme.default.loadGreen()
                        showFeedSettings = false
                    }
                Color("blueAccentColor")
                    .frame(width: 25, height: 25)
                    .padding(3)
                    .background(selectedTheme == "blue" ? Color.secondary : .clear)
                    .onTapGesture {
                        Theme.default.loadBlue()
                        showFeedSettings = false
                    }
                Color("pinkAccentColor")
                    .frame(width: 25, height: 25)
                    .padding(3)
                    .background(selectedTheme == "pink" ? Color.secondary : .clear)
                    .onTapGesture {
                        Theme.default.loadPink()
                        showFeedSettings = false
                    }
                Color("orangeAccentColor")
                    .frame(width: 25, height: 25)
                    .padding(3)
                    .background(selectedTheme == "orange" ? Color.secondary : .clear)
                    .onTapGesture {
                        Theme.default.loadOrange()
                        showFeedSettings = false
                    }
                Spacer()
            }
        }
    }
}

struct FeedSettings_AppThemeSwitcher_Previews: PreviewProvider {
    static var previews: some View {
        AppThemeSwitcher(showFeedSettings: .constant(true))
            .environmentObject(Theme.default)
    }
}
