//
//  UIFont+Nostur.swift
//  Nostur
//
//  Body font helpers that respect the Mac Catalyst in-app text size setting.
//

import UIKit
import SwiftUI

extension UIFont {
    /// Preferred body font, scaled by `SettingsStore.textSizeScale` on Mac Catalyst.
    static func nosturBody() -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: .body)
        let scale = SettingsStore.shared.textSizeScale
        guard abs(scale - 1.0) > 0.001 else { return base }
        return base.withSize(base.pointSize * scale)
    }
    
    /// Preferred font for a text style, scaled by `SettingsStore.textSizeScale` on Mac Catalyst.
    static func nosturPreferred(forTextStyle style: UIFont.TextStyle) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let scale = SettingsStore.shared.textSizeScale
        guard abs(scale - 1.0) > 0.001 else { return base }
        return base.withSize(base.pointSize * scale)
    }
}

extension Font {
    /// SwiftUI body font matching `UIFont.nosturBody()`.
    static func nosturBody() -> Font {
        Font(UIFont.nosturBody() as CTFont)
    }
}
