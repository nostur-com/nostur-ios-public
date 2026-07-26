//
//  SearchModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/01/2025.
//

import CoreData
import Foundation

typealias SearchTerm = String

final class SearchCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

struct SearchResults {
    let contacts: [NRContact]
    let posts: [NRPost]
    let remainingPostIDs: [PostID]

    static let empty = SearchResults(contacts: [], posts: [], remainingPostIDs: [])
}

private struct ContactSearchCandidate {
    let pubkey: Pubkey
    let matchedTerms: UInt64
}

private struct PostSearchCandidate {
    let id: PostID
    let pubkey: Pubkey
    let createdAt: Int64
}

class SearchModel {
    static let postPageSize = 25

    private static let contactCandidateLimit = 500
    private static let contactResultLimit = 50
    private static let postCandidateLimit = 500
    private static let postResultLimit = 150
    private static let maximumTermCount = 63

    @MainActor
    static func searchInNames(
        _ searchText: String,
        cancellationToken: SearchCancellationToken
    ) async -> SearchResults {
        let terms = normalizedTerms(searchText)
        guard !terms.isEmpty, !cancellationToken.isCancelled else {
            return .empty
        }

        let blockedPubkeys = blocks()
        let context = bg()
        return await withCheckedContinuation {
            (continuation: CheckedContinuation<SearchResults, Never>) in
            context.perform {
                continuation.resume(
                    returning: performSearch(
                        terms: terms,
                        blockedPubkeys: blockedPubkeys,
                        cancellationToken: cancellationToken,
                        context: context
                    )
                )
            }
        }
    }

    @MainActor
    static func loadPosts(
        ids: [PostID],
        cancellationToken: SearchCancellationToken
    ) async -> [NRPost] {
        await withCheckedContinuation {
            (continuation: CheckedContinuation<[NRPost], Never>) in
            guard !ids.isEmpty, !cancellationToken.isCancelled else {
                continuation.resume(returning: [])
                return
            }

            let context = bg()
            context.perform {
                guard !cancellationToken.isCancelled else {
                    continuation.resume(returning: [])
                    return
                }
                let posts = fetchPosts(ids: ids, context: context)
                continuation.resume(returning: cancellationToken.isCancelled ? [] : posts)
            }
        }
    }

    private static func normalizedTerms(_ searchText: String) -> [SearchTerm] {
        var seen = Set<SearchTerm>()
        return searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).lowercased() }
            .filter { seen.insert($0).inserted }
            .prefix(maximumTermCount)
            .map { $0 }
    }

    private static func performSearch(
        terms: [SearchTerm],
        blockedPubkeys: Set<Pubkey>,
        cancellationToken: SearchCancellationToken,
        context: NSManagedObjectContext
    ) -> SearchResults {
        guard !cancellationToken.isCancelled else { return .empty }

        let allTermsMask = (UInt64(1) << UInt64(terms.count)) - 1
        let contactCandidates = fetchContactCandidates(
            terms: terms,
            blockedPubkeys: blockedPubkeys,
            context: context
        )
        guard !cancellationToken.isCancelled else { return .empty }

        let contactTermMasks = Dictionary(
            uniqueKeysWithValues: contactCandidates.map { ($0.pubkey, $0.matchedTerms) }
        )
        let matchingContacts = contactCandidates
            .filter { $0.matchedTerms == allTermsMask }
            .sorted { rankedBefore($0, $1) }
        let matchingContactPubkeys = matchingContacts
            .prefix(contactResultLimit)
            .map(\.pubkey)

        let matchingPosts = fetchPostCandidates(
            terms: terms,
            allTermsMask: allTermsMask,
            contactTermMasks: contactTermMasks,
            blockedPubkeys: blockedPubkeys,
            context: context
        )
        .sorted { rankedBefore($0, $1) }
        let selectedPostIDs = matchingPosts
            .prefix(postResultLimit)
            .map(\.id)

        guard !cancellationToken.isCancelled else { return .empty }

        let contacts = fetchContacts(
            pubkeys: matchingContactPubkeys,
            context: context
        )
        let firstPageIDs = Array(selectedPostIDs.prefix(postPageSize))
        let posts = fetchPosts(ids: firstPageIDs, context: context)

        guard !cancellationToken.isCancelled else { return .empty }
        return SearchResults(
            contacts: contacts,
            posts: posts,
            remainingPostIDs: Array(selectedPostIDs.dropFirst(firstPageIDs.count))
        )
    }

    private static func fetchContactCandidates(
        terms: [SearchTerm],
        blockedPubkeys: Set<Pubkey>,
        context: NSManagedObjectContext
    ) -> [ContactSearchCandidate] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Contact")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["pubkey", "name", "display_name", "fixedName", "nip05"]
        request.fetchLimit = contactCandidateLimit

        let perTermPredicates = terms.map { term in
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "name CONTAINS[cd] %@", term),
                NSPredicate(format: "display_name CONTAINS[cd] %@", term),
                NSPredicate(format: "fixedName CONTAINS[cd] %@", term),
                NSPredicate(format: "nip05 CONTAINS[cd] %@", term)
            ])
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "NOT pubkey IN %@", blockedPubkeys),
            NSCompoundPredicate(orPredicateWithSubpredicates: perTermPredicates)
        ])

        guard let rows = try? context.fetch(request) else { return [] }
        return rows.compactMap { row in
            guard let pubkey = row["pubkey"] as? String else { return nil }
            let searchableValues = [
                row["name"] as? String,
                row["display_name"] as? String,
                row["fixedName"] as? String,
                row["nip05"] as? String
            ].compactMap { $0 }

            return ContactSearchCandidate(
                pubkey: pubkey,
                matchedTerms: termMask(terms: terms, searchableValues: searchableValues)
            )
        }
    }

    private static func fetchPostCandidates(
        terms: [SearchTerm],
        allTermsMask: UInt64,
        contactTermMasks: [Pubkey: UInt64],
        blockedPubkeys: Set<Pubkey>,
        context: NSManagedObjectContext
    ) -> [PostSearchCandidate] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Event")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id", "pubkey", "content", "created_at"]
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        request.fetchLimit = postCandidateLimit

        let contentPredicates = terms.map {
            NSPredicate(format: "content CONTAINS[cd] %@", $0)
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "NOT pubkey IN %@", blockedPubkeys),
            NSPredicate(format: "kind IN {1,1111,1222,1244,20,9802}"),
            NSPredicate(format: "NOT content BEGINSWITH %@", "lnbc"),
            NSCompoundPredicate(orPredicateWithSubpredicates: contentPredicates)
        ])

        guard let rows = try? context.fetch(request) else { return [] }
        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let pubkey = row["pubkey"] as? String
            else { return nil }

            let content = row["content"] as? String ?? ""
            let contentMask = termMask(terms: terms, searchableValues: [content])
            guard contentMask | (contactTermMasks[pubkey] ?? 0) == allTermsMask else {
                return nil
            }

            return PostSearchCandidate(
                id: id,
                pubkey: pubkey,
                createdAt: row["created_at"] as? Int64 ?? 0
            )
        }
    }

    private static func fetchContacts(
        pubkeys: [Pubkey],
        context: NSManagedObjectContext
    ) -> [NRContact] {
        guard !pubkeys.isEmpty else { return [] }

        let request = Contact.fetchRequest()
        request.predicate = NSPredicate(format: "pubkey IN %@", pubkeys)
        guard let contacts = try? context.fetch(request) else { return [] }

        let contactsByPubkey = Dictionary(uniqueKeysWithValues: contacts.map { ($0.pubkey, $0) })
        return pubkeys.compactMap { pubkey in
            guard let contact = contactsByPubkey[pubkey] else { return nil }
            return NRContact.instance(of: pubkey, contact: contact)
        }
    }

    private static func fetchPosts(
        ids: [PostID],
        context: NSManagedObjectContext
    ) -> [NRPost] {
        guard !ids.isEmpty else { return [] }

        let request = Event.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", ids)
        guard let events = try? context.fetch(request) else { return [] }

        let eventsByID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        return ids.compactMap { id in
            guard let event = eventsByID[id] else { return nil }
            return NRPost(event: event)
        }
    }

    private static func termMask(
        terms: [SearchTerm],
        searchableValues: [String]
    ) -> UInt64 {
        terms.enumerated().reduce(into: UInt64(0)) { mask, item in
            let (index, term) = item
            guard searchableValues.contains(where: {
                $0.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                ) != nil
            }) else { return }
            mask |= UInt64(1) << UInt64(index)
        }
    }

    private static func rankedBefore(_ lhs: ContactSearchCandidate, _ rhs: ContactSearchCandidate) -> Bool {
        rankedBefore(lhsPubkey: lhs.pubkey, lhsCreatedAt: 0, rhsPubkey: rhs.pubkey, rhsCreatedAt: 0)
    }

    private static func rankedBefore(_ lhs: PostSearchCandidate, _ rhs: PostSearchCandidate) -> Bool {
        rankedBefore(
            lhsPubkey: lhs.pubkey,
            lhsCreatedAt: lhs.createdAt,
            rhsPubkey: rhs.pubkey,
            rhsCreatedAt: rhs.createdAt
        )
    }

    private static func rankedBefore(
        lhsPubkey: Pubkey,
        lhsCreatedAt: Int64,
        rhsPubkey: Pubkey,
        rhsCreatedAt: Int64
    ) -> Bool {
        let lhsFollowing = isFollowing(lhsPubkey)
        let rhsFollowing = isFollowing(rhsPubkey)
        if lhsFollowing != rhsFollowing {
            return lhsFollowing
        }

        if WOT_FILTER_ENABLED() {
            let webOfTrust = WebOfTrust.shared
            let lhsAllowed = webOfTrust.isAllowed(lhsPubkey)
            let rhsAllowed = webOfTrust.isAllowed(rhsPubkey)
            if lhsAllowed != rhsAllowed {
                return lhsAllowed
            }
        }

        if lhsCreatedAt != rhsCreatedAt {
            return lhsCreatedAt > rhsCreatedAt
        }
        return lhsPubkey < rhsPubkey
    }
}
