//
//  Compatibility.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/01/2024.
//

import SwiftUI

import UIKit

func setAppIconBadgeCount(_ count: Int, center: UNUserNotificationCenter = UNUserNotificationCenter.current()) {
    if #available(iOS 16, *) {
        let center = UNUserNotificationCenter.current()
        Task {
            try? await center.setBadgeCount(count)
        }
    }
    else {
        UIApplication.shared.applicationIconBadgeNumber = count
    }
}

extension List {
    @ViewBuilder
    func scrollContentBackgroundCompat(_ visibility: Visibility) -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(visibility)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func scrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func contentMarginsTopCompat(_ length: CGFloat? = nil) -> some View {
        if #available(iOS 17.0, *) {
            self.contentMargins(.top, length, for: .scrollContent)
        }
        else {
            self
        }
    }
}

extension Form {
    @ViewBuilder
    func scrollContentBackgroundCompat(_ visibility: Visibility) -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(visibility)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func scrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func formStyleGrouped() -> some View {
        if #available(iOS 16.0, *) {
            self.formStyle(.grouped)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func contentMarginsTopCompat(_ length: CGFloat? = nil) -> some View {
        if #available(iOS 17.0, *) {
            self.contentMargins(.top, length, for: .scrollContent)
        }
        else {
            self
        }
    }
}

extension View {
    
    @ViewBuilder
    func contentMarginsTopCompat(_ length: CGFloat? = nil) -> some View {
        if #available(iOS 17.0, *) {
            self.contentMargins(.top, length, for: .scrollContent)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func scrollDismissesKeyboardCompat() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.immediately)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func toolbarVisibleCompat(_ visibility: Visibility) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(visibility)
        }
        else {
            self
        }
    }  
    
    @ViewBuilder
    func toolbarNavigationBackgroundVisible() -> some View {
        if #available(iOS 16.0, *) {
            self.toolbarBackground(.visible, for: .navigationBar)
        }
        else {
            self
        }
    }
        
    @ViewBuilder
    func scrollContentBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        }
        else {
            self
        }
    }
    
    
    @ViewBuilder
    func scrollDisabledCompat() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollDisabled(true)
        }
        else {
            self
        }
    }    
    
    @ViewBuilder
    func scrollTargetBehaviorViewAligned() -> some View {
        if #available(iOS 17.0, *) {
            self.scrollTargetBehavior(.viewAligned)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func symbolEffectPulse() -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.pulse, options: .speed(3).repeat(10), isActive: true)
        }
        else {
            self
        }
    }
    
    
    @ViewBuilder
    func rollingNumber() -> some View {
        if #available(iOS 17.0, *) {
            self.contentTransition(.numericText(countsDown: false))
        }
        else {
            self
        }
    }
    
    
    @ViewBuilder
    func safeAreaPadding() -> some View {
        if #available(iOS 17.0, *) {
            self.safeAreaPadding(.horizontal, 0)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func safeAreaScroll() -> some View {
        if #available(iOS 17.0, *) {
            self.safeAreaPadding(.vertical, 10.0)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func presentationBackgroundCompat<S>(_ style: S) -> some View where S : ShapeStyle {
        if #available(iOS 16.4, *) {
            self.presentationBackground(style)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func presentationDetents200() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.height(200)])
        }
        else {
            self
        }
    }
    
    
    @ViewBuilder
    func contentTransitionOpacity() -> some View {
        if #available(iOS 16.0, *) {
            self.contentTransition(.opacity)
        }
        else {
            self
        }
    }
    
    
    @ViewBuilder
    func presentationDetents250medium() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.height(250), .medium])
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func presentationDetentsMedium() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.medium])
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func presentationDetentsLarge() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.large])
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func presentationDetents45ml() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.fraction(0.45), .medium, .large])
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func highPriorityGestureIf<T>(condition: Bool, gesture: T) -> some View where T : Gesture {
        if condition {
            self.highPriorityGesture(gesture)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func gestureIf<T>(condition: Bool, gesture: T) -> some View where T : Gesture {
        if condition {
            self.gesture(gesture)
        }
        else {
            self
        }
    }

    @ViewBuilder
    func presentationDetents350l() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents([.height(350), .large])
        }
    }
    
    @ViewBuilder
    func presentationDragIndicatorVisible() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDragIndicator(.visible)
        }
        else {
            self
        }
    }
        
    @ViewBuilder
    func pickerStyleCompatNavigationLink() -> some View {
        if #available(iOS 16.0, *) {
            self.pickerStyle(.navigationLink)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func fontWeightBold() -> some View {
        if #available(iOS 16.0, *) {
            self.fontWeight(.bold)
        }
        else {
            self
        }
    }
    @ViewBuilder
    func fontWeightLight() -> some View {
        if #available(iOS 16.0, *) {
            self.fontWeight(.light)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func fontItalic() -> some View {
        if #available(iOS 16.0, *) {
            self.italic()
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func nosturTabsCompat(theme: Theme) -> some View {
        if #available(iOS 16.0, *) {
            self
                .toolbarBackground(theme.listBackground, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func nosturNavBgCompat(theme: Theme) -> some View {
        if #available(iOS 16.0, *) {
            self
                .toolbarBackground(theme.listBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        else {
            self
        }
    }
}
