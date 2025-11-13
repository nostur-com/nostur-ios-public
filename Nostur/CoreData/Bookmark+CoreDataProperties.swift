//
//  Bookmark+CoreDataProperties.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/11/2023.
//
//

import SwiftUI
import CoreData

extension Bookmark {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Bookmark> {
        return NSFetchRequest<Bookmark>(entityName: "Bookmark")
    }

    // -- MARK: iCloud fields --
    @NSManaged public var eventId: String?
    @NSManaged public var json: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var color_: String?
    
    // Default is orange.
    // "orange", "red", "blue", "purple", "green", "brown" (BOOKMARK_COLORS)
    public var color: Color {
        get {
            return switch color_ {
                case "red":
                    .red
                case "blue":
                    .blue
                case "purple":
                    .purple
                case "green":
                    .green
                case "orange":
                    .orange
                case "brown":
                    .brown
                default:
                    .orange
                
            }
        }
        set {
            color_ = switch newValue {
            case .orange:
                "orange"
            case .red:
                "red"
            case .blue:
                "blue"
            case .purple:
                "purple"
            case .green:
                "green"
            case .brown:
                "brown"
            default:
                "orange"
            }
        }
    }

}

extension Bookmark : Identifiable {

}
