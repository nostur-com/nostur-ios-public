//
//  DIMENSIONS.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/04/2023.
//

import SwiftUI

/// Helpers for determining the width of images and video in content
class DIMENSIONS: ObservableObject {
    
    static let shared = DIMENSIONS()
    
    static public let POST_MAX_ROW_HEIGHT:CGFloat = 900.0
    
    // 428    - 5        - (10 + 50 + 10 ) -         (10) - 5
    // Screen - Box-left  - (10 + PFP+ 10 ) - (text-right) - Box-right
    static public let POST_ROW_HPADDING:CGFloat = 10.0
    static public let POST_ROW_PFP_WIDTH:CGFloat = 50.0
    static public let POST_ROW_PFP_HEIGHT:CGFloat = 50.0
    static public let POST_ROW_PFP_HPADDING:CGFloat = 10.0
    static public let KIND1_TRAILING:CGFloat = 10.0
    static public var ROW_PFP_SPACE:CGFloat { get { Self.POST_ROW_PFP_WIDTH + (2 * Self.POST_ROW_PFP_HPADDING) }}
    
    static public let PREVIEW_HEIGHT:CGFloat = 70.0
    
    static public let PFP_BIG:CGFloat = 75.0 // Bigger PFP on Profile View and Profile Cards
    
    @Published var listWidth:CGFloat = UIScreen.main.bounds.width // Should override for IS_IPAD / macOS
    
    /// Substracts profile pic space from list width
    func availableNoteRowImageWidth() -> CGFloat {
        // 10 + ( 10+50+10 ) (availableWidth) + 10 + 10
        return (listWidth - (Self.POST_ROW_HPADDING * 2) - (Self.POST_ROW_PFP_WIDTH) - (Self.POST_ROW_PFP_HPADDING * 2))
    }
    
    // NoteRow but without the profile pic on the side
    func articleRowImageWidth() -> CGFloat {
        // 10 + ( 10+50+10 ) (availableWidth) + 10 + 10
        return (listWidth - (Self.POST_ROW_HPADDING * 2))
    }
    
    /// No profile pic,  no shadow box padding, only Detail ContentRenderer padding
    func availablePostDetailImageWidth() -> CGFloat {
        return (listWidth - (Self.POST_ROW_HPADDING * 2))
    }
    
    /// Substracts profile pic space from list width
    func availablePostDetailRowImageWidth() -> CGFloat {
        //( 10+50+10 ) (availableWidth) + 10
        return (listWidth - (Self.POST_ROW_PFP_WIDTH) - (Self.POST_ROW_PFP_HPADDING * 2))
    }
}





