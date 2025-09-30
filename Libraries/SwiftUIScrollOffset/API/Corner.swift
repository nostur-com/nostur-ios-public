/**
*  SwiftUIScrollOffset
*  Copyright (c) Ciaran O'Brien 2024
*  MIT license, see LICENSE file for details
*/

import Foundation

@frozen public enum Corner: Int8, CaseIterable, Hashable, Sendable {
    case topLeading
    case bottomLeading
    case bottomTrailing
    case topTrailing
}
