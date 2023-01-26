////
////  File.swift
////  Nostur
////
////  Created by Fabian Lachman on 19/01/2023.
////
//
//import Foundation
//import SwiftUI
//
//struct Note: Identifiable, Hashable {
//    
//    var id:String { get { event.id! } }
//    var authorName:String { get { contact != nil ? contact!.authorName : event.authorKey } }
//    var username:String { get { contact != nil ? (contact!.name ?? event.authorKey) : event.authorKey } }
//    var publicKey:String { get { event.pubkey ?? "WHAT" } }
//    var noteText:String { get { event.noteText } }
//    var noteId:String {
//        get {
//            event.id != nil ? try! NIP19(prefix: "note", hexString: event.id!).displayString : "?"
//        }
//    }
//    
//    static func == (lhs: Note, rhs: Note) -> Bool {
//        return lhs.event.id == rhs.event.id
//    }
//    
//    func hash(into hasher: inout Hasher) {
//        hasher.combine(event.id)
//    }
//
//    let event:Event
//    var responses:[Event]? = nil
//    var contact:Contact? = nil
//}
