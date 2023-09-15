//
//  Settings+ThemePicker.swift
//  Nostur
//
//  Created by Fabian Lachman on 29/08/2023.
//

import SwiftUI

struct ThemePicker: View {
    @Binding var selectedTheme: String
    
    var body: some View {
        Picker(selection: $selectedTheme) {
            Label("Default", systemImage: "circle.fill")
                .foregroundColor(Color("defaultAccentColor"))
                .tag("default")
            
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
            
        } label: {
            Text("App theme")
        }
        .pickerStyle(.navigationLink)
        .onChange(of: selectedTheme) { theme in
            // switch .load
            
            switch theme {
            case "default":
                Theme.`default`.loadDefault()
            case "purple":
                Theme.`default`.loadPurple()
            case "red":
                Theme.`default`.loadRed()
            case "green":
                Theme.`default`.loadGreen()
            case "blue":
                Theme.`default`.loadBlue()
            case "pink":
                Theme.`default`.loadPink()
            case "orange":
                Theme.`default`.loadOrange()
            default:
                Theme.`default`.loadDefault()
            }
        }
    }
}

//struct ThemePreview: View {
//    @EnvironmentObject var dim:DIMENSIONS
//
//    var body: some View {
//        VStack(spacing:0) {
//            ScrollView(.horizontal, showsIndicators: false) {
//                HStack(spacing:0) {
//                    TabButton(
//                        action: { },
//                        title: String(localized:"Following", comment:"Tab title for feed of people you follow"),
//                        selected: true)
//                    Spacer()
//                    TabButton(
//                        action: {  },
//                        title: String(localized:"Explore", comment:"Tab title for the Explore feed"),
//                        selected: false )
//                }
//            }
//
//            SmoothListMock {
//                Text("test")
//            }
//
//        }
//    }
//}

struct Settings_ThemePicker_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            Form {
                Section(header: Text("Display", comment:"Setting heading on settings screen")) {
                    ThemePicker(selectedTheme: .constant("default"))
                }
            }
        }
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
        .environmentObject(DIMENSIONS.shared)
        .environmentObject(Theme.default)
    }
}
