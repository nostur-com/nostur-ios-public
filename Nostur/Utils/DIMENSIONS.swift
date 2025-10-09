//
//  DIMENSIONS.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/04/2023.
//

import SwiftUI

/// Helpers for determining the width of images and video in content
class DIMENSIONS {

    static public let MIN_MEDIA_ROW_HEIGHT = 200.0 // TODO: change based on device?
    static public let MAX_MEDIA_ROW_HEIGHT = 1200.0 // TODO: change based on device?
    
    static public let POST_MAX_ROW_HEIGHT: CGFloat = 1200.0
    
    // 428    - 10        - (50)  10      -  (10)         - 10
    // Screen - Box-left  - (PFP) (Space) -  (text-right) - Box-right
    static public let POST_ROW_HPADDING: CGFloat = 10.0
    static public let POST_ROW_PFP_WIDTH: CGFloat = 50.0
    static public let POST_ROW_PFP_DIAMETER: CGFloat = 50.0
    static public let POST_PFP_SPACE: CGFloat = 10.0
    static public let KIND1_TRAILING: CGFloat = 10.0
    static public var ROW_PFP_SPACE: CGFloat { get { Self.POST_ROW_PFP_WIDTH + (Self.POST_PFP_SPACE) }}
    
    static public let PREVIEW_HEIGHT: CGFloat = 60.0
    
    static public let PFP_BIG: CGFloat = 75.0 // Bigger PFP on Profile View and Profile Cards
    
    static public let BOX_PADDING: CGFloat = 10.0 // TODO: Should start using this everywhere instead if .padding(10)
    
    /// Subtracts profile pic space from list width
    static func availableNoteRowImageWidth(_ listWidth: CGFloat) -> CGFloat { // TODO: Check if we need to turn this into lazy computed property
        // 10 + ( 50 ) + 10 + (availableWidth) + 10
        return (listWidth - (Self.BOX_PADDING * 2) - (Self.POST_ROW_PFP_WIDTH) - (Self.POST_PFP_SPACE))
    }
    
    static func availableNoteRowWidth(_ listWidth: CGFloat) -> CGFloat {
        return (listWidth - (Self.BOX_PADDING * 2) - (Self.POST_ROW_PFP_WIDTH) - (Self.POST_PFP_SPACE))
    }
    
    // NoteRow but without the profile pic on the side
    static func articleRowImageWidth(_ listWidth: CGFloat) -> CGFloat {
        // 10 + (availableWidth) + 10 
        return (listWidth - (Self.POST_ROW_HPADDING * 2))
    }
    
    /// Subtracts profile pic space from list width
    static func availablePostDetailRowImageWidth(_ listWidth: CGFloat) -> CGFloat {
        // ( 50 ) + 10 + (availableWidth) + 10
        return (listWidth - (Self.POST_ROW_PFP_WIDTH) - (Self.POST_PFP_SPACE))
//        return (listWidth - (Self.BOX_PADDING*2) - (Self.POST_ROW_PFP_WIDTH) - (Self.POST_PFP_SPACE))
         //   -10    684               -10
    }    
}





