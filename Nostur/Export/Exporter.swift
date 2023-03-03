//
//  Exporter.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/03/2023.
//

import Foundation
import SwiftUI
import CoreData
import CoreTransferable
import UniformTypeIdentifiers

final class Exporter {
    
    let pubkey:String
    
    init(_ pubkey:String) {
        self.pubkey = pubkey
    }
    
    func exportAllEventsForPubkey() -> Data {
        // create background context
        let bg = EventsProvider.shared.container.newBackgroundContext()
        
        // query
        let r = Event.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)]
        r.predicate = NSPredicate(format: "pubkey == %@", pubkey)
        
        var nEvents:[NEvent] = []
        if let events = try? bg.fetch(r) {
            for event in events {
                nEvents.append(event.toNEvent())
            }
        }
        
        // convert to json
        var jsonl:[String] = []
        for nEvent in nEvents {
            jsonl.append(nEvent.wrappedEventJson())
            if let last = jsonl.last {
                print(last)
            }
        }
        
        print("Exported \(nEvents.count) events")
        
        return String(jsonl.joined(separator:"\n")).data(using: .utf8)!
        // provide share
    }
}


struct EventsJsonl: Transferable {
    var jsonl:Data
    
    init(pubkey:String) {
        let exporter = Exporter(pubkey)
        self.jsonl = exporter.exportAllEventsForPubkey()
    }
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .events) { archive in
            archive.jsonl
        }
    }
}


extension UTType {
    static let events = UTType(exportedAs: "com.nostur.events")
}

struct EventsArchive: FileDocument {

    static var readableContentTypes = [UTType.events]

    var jsonl:Data?

    init(pubkey:String) {
        let exporter = Exporter(pubkey)
        self.jsonl = exporter.exportAllEventsForPubkey()
    }

    // this initializer loads data that has been saved previously
    init(configuration: ReadConfiguration) throws {
//        if let data = configuration.file.regularFileContents {
//            jsonl = data
//        }
    }

    // this will be called when the system wants to write our data to disk
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: jsonl!)
    }
}
