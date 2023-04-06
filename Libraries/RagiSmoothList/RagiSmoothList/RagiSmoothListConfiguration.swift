//
//  RagiSmoothListConfiguration.swift
//  RagiSmoothList
//
//  Created by ragingo on 2022/12/11.
//

import SwiftUI

public struct RagiSmoothListConfiguration {
    public var separator: Separator
    public var edit: Edit
    public var animation: Animation

    public init(
        separator: Separator = .init(),
        edit: Edit = .init(),
        animation: Animation = .init()
    ) {
        self.separator = separator
        self.edit = edit
        self.animation = animation
    }
}

// MARK: - Separator
public extension RagiSmoothListConfiguration {
    struct Separator {
        public var isVisible: Bool
        public var insets: EdgeInsets?
        public var color: Color?

        public init(isVisible: Bool = true, insets: EdgeInsets? = nil, color: Color? = nil) {
            self.isVisible = isVisible
            self.insets = insets
            self.color = color
        }
    }
}

// MARK: - Edit
public extension RagiSmoothListConfiguration {
    struct Edit {
        public var deleteButtonBackgroundColor: Color?
        public var deleteButtonImage: UIImage?

        public init(
            deleteButtonBackgroundColor: Color? = nil,
            deleteButtonImage: UIImage? = nil
        ) {
            self.deleteButtonBackgroundColor = deleteButtonBackgroundColor
            self.deleteButtonImage = deleteButtonImage
        }
    }
}

// MARK: - Animation
public extension RagiSmoothListConfiguration {
    struct Animation {
        public enum Mode: String, CaseIterable {
            case fade
            case right
            case left
            case top
            case bottom
            case disable
            case middle
            case automatic
        }

        public var mode: Mode

        public init(mode: Mode = .automatic) {
            self.mode = mode
        }
    }
}
