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
    
    
    static public let MIN_MEDIA_ROW_HEIGHT = 200.0 // TODO: change based on device?
    static public let MAX_MEDIA_ROW_HEIGHT = 600.0 // TODO: change based on device?
    
    static public let POST_MAX_ROW_HEIGHT:CGFloat = 1200.0
    
    // 428    - 10        - (50)  10      -  (10)         - 10
    // Screen - Box-left  - (PFP) (Space) -  (text-right) - Box-right
    static public let POST_ROW_HPADDING:CGFloat = 10.0
    static public let POST_ROW_PFP_WIDTH:CGFloat = 50.0
    static public let POST_ROW_PFP_DIAMETER:CGFloat = 50.0
    static public let POST_PFP_SPACE:CGFloat = 10.0
    static public let KIND1_TRAILING:CGFloat = 10.0
    static public var ROW_PFP_SPACE:CGFloat { get { Self.POST_ROW_PFP_WIDTH + (Self.POST_PFP_SPACE) }}
    
    static public let PREVIEW_HEIGHT:CGFloat = 70.0
    
    static public let PFP_BIG:CGFloat = 75.0 // Bigger PFP on Profile View and Profile Cards
    
    @Published var listWidth:CGFloat = UIScreen.main.bounds.width // Should override for IS_IPAD / macOS
    
    static public let BOX_PADDING:CGFloat = 10.0 // TODO: Should start using this everywhere instead if .padding(10)
    
    /// Substracts profile pic space from list width
    func availableNoteRowImageWidth() -> CGFloat {
        // 10 + ( 50 ) + 10 + (availableWidth) + 10
        return (listWidth - (Self.BOX_PADDING*2) - (Self.POST_ROW_PFP_WIDTH) - (Self.POST_PFP_SPACE))
    }
    
    // NoteRow but without the profile pic on the side
    func articleRowImageWidth() -> CGFloat {
        // 10 + (availableWidth) + 10 
        return (listWidth - (Self.POST_ROW_HPADDING * 2))
    }
    
    /// No profile pic,  no shadow box padding, only Detail ContentRenderer padding
    func availablePostDetailImageWidth() -> CGFloat {
        return listWidth
    }
    
    /// Substracts profile pic space from list width
    func availablePostDetailRowImageWidth() -> CGFloat {
        // ( 50 ) + 10 + (availableWidth) + 10
        return (listWidth - (Self.POST_ROW_PFP_WIDTH) - (Self.POST_PFP_SPACE))
//        return (listWidth - (Self.BOX_PADDING*2) - (Self.POST_ROW_PFP_WIDTH) - (Self.POST_PFP_SPACE))
         //   -10    684               -10
    }
    
    static func embeddedDim(availableWidth: CGFloat) -> DIMENSIONS {
        let embeddedDim = DIMENSIONS()
//        if isArticle {
//            embeddedDim.listWidth = self.listWidth - (20 * 2)
//        }
//        else {
            embeddedDim.listWidth = availableWidth
//        }
        return embeddedDim
    }
}





