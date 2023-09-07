//
//  FeedSettings+AppThemeSwitcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/09/2023.
//

import SwiftUI

struct AppThemeSwitcher: View {
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
                    .onTapGesture {
                        Theme.default.loadDefault()
                        showFeedSettings = false
                    }
                Color("purpleAccentColor")
                    .frame(width: 25, height: 25)
                    .onTapGesture {
                        Theme.default.loadPurple()
                        showFeedSettings = false
                    }
                Color("redAccentColor")
                    .frame(width: 25, height: 25)
                    .onTapGesture {
                        Theme.default.loadRed()
                        showFeedSettings = false
                    }
                Color("greenAccentColor")
                    .frame(width: 25, height: 25)
                    .onTapGesture {
                        Theme.default.loadGreen()
                        showFeedSettings = false
                    }
                Color("blueAccentColor")
                    .frame(width: 25, height: 25)
                    .onTapGesture {
                        Theme.default.loadBlue()
                        showFeedSettings = false
                    }
                Color("pinkAccentColor")
                    .frame(width: 25, height: 25)
                    .onTapGesture {
                        Theme.default.loadPink()
                        showFeedSettings = false
                    }
                Color("orangeAccentColor")
                    .frame(width: 25, height: 25)
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
