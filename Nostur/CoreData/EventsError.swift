////
////  EventsError.swift
////  Nostur
////
////  Created by Fabian Lachman on 21/01/2023.
////
//
//import Foundation
//
//enum EventError: Error {
//    case wrongDataFormat(error: Error)
//    case missingData
//    case creationError
//    case batchInsertError
//    case batchDeleteError
//    case persistentHistoryChangeError
//    case unexpectedError(error: Error)
//}
//
//extension EventError: LocalizedError {
//    var errorDescription: String? {
//        switch self {
//        case .wrongDataFormat(let error):
//            return NSLocalizedString("Could not digest the fetched data. \(error.localizedDescription)", comment: "")
//        case .missingData:
//            return NSLocalizedString("Found and will discard a quake missing a valid code, magnitude, place, or time.", comment: "")
//        case .creationError:
//            return NSLocalizedString("Failed to create a new Quake object.", comment: "")
//        case .batchInsertError:
//            return NSLocalizedString("Failed to execute a batch insert request.", comment: "")
//        case .batchDeleteError:
//            return NSLocalizedString("Failed to execute a batch delete request.", comment: "")
//        case .persistentHistoryChangeError:
//            return NSLocalizedString("Failed to execute a persistent history change request.", comment: "")
//        case .unexpectedError(let error):
//            return NSLocalizedString("Received unexpected error. \(error.localizedDescription)", comment: "")
//        }
//    }
//}
//
//extension EventError: Identifiable {
//    var id: String? {
//        errorDescription
//    }
//}
