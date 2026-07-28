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

struct SearchContactStage {
    let contacts: [NRContact]
    let matchedTermsByPubkey: [Pubkey: UInt64]

    static let empty = SearchContactStage(contacts: [], matchedTermsByPubkey: [:])
}

struct SearchPostResult: Identifiable {
    let id: PostID
    let pubkey: Pubkey
    let createdAt: Date
    let content: String
    let author: NRContact?
}

private struct ContactSearchCandidate {
    let pubkey: Pubkey
    let matchedTerms: UInt64
}

private struct ContactSearchFetchResult: Sendable {
    let profiles: [ProfileInfo]
    let matchedTermsByPubkey: [Pubkey: UInt64]
}

private struct PostSearchCandidate: Sendable {
    let id: PostID
    let pubkey: Pubkey
    let createdAt: Int64
    let content: String
}

private struct PostSearchFetchResult: Sendable {
    let candidates: [PostSearchCandidate]
    let authorProfiles: [ProfileInfo]
}

class SearchModel {
    private static let contactCandidateLimit = 500
    private static let contactResultLimit = 50
    private static let postCandidateLimit = 500
    private static let postResultLimit = 150
    private static let maximumTermCount = 63

    @MainActor
    static func searchContacts(
        _ searchText: String,
        cancellationToken: SearchCancellationToken
    ) async -> SearchContactStage {
        let terms = normalizedTerms(searchText)
        guard !terms.isEmpty, !cancellationToken.isCancelled else {
            return .empty
        }

        let blockedPubkeys = blocks()
        let context = bg()
        let fetchResult = await withCheckedContinuation {
            (continuation: CheckedContinuation<ContactSearchFetchResult?, Never>) in
            context.perform {
                guard !cancellationToken.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }

                let allTermsMask = maskForAllTerms(terms)
                let candidates = fetchContactCandidates(
                    terms: terms,
                    blockedPubkeys: blockedPubkeys,
                    context: context
                )
                guard !cancellationToken.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }

                let termMasks = Dictionary(
                    uniqueKeysWithValues: candidates.map { ($0.pubkey, $0.matchedTerms) }
                )
                let matchingPubkeys = candidates
                    .filter { $0.matchedTerms == allTermsMask }
                    .sorted { rankedBefore($0, $1) }
                    .prefix(contactResultLimit)
                    .map(\.pubkey)
                let profiles = fetchContactProfiles(
                    pubkeys: matchingPubkeys,
                    context: context
                )

                continuation.resume(
                    returning: cancellationToken.isCancelled
                        ? nil
                        : ContactSearchFetchResult(
                            profiles: profiles,
                            matchedTermsByPubkey: termMasks
                        )
                )
            }
        }

        guard let fetchResult, !cancellationToken.isCancelled else { return .empty }
        let contacts = fetchResult.profiles.map { profile in
            let contact = NRContact.instance(of: profile.pubkey)
            contact.refreshForSearch(from: profile)
            return contact
        }
        return SearchContactStage(
            contacts: contacts,
            matchedTermsByPubkey: fetchResult.matchedTermsByPubkey
        )
    }

    @MainActor
    static func searchPosts(
        _ searchText: String,
        contactTermMasks: [Pubkey: UInt64],
        cancellationToken: SearchCancellationToken
    ) async -> [SearchPostResult] {
        let terms = normalizedTerms(searchText)
        guard !terms.isEmpty, !cancellationToken.isCancelled else { return [] }

        let blockedPubkeys = blocks()
        let context = bg()
        let fetchResult = await withCheckedContinuation {
            (continuation: CheckedContinuation<PostSearchFetchResult?, Never>) in
            context.perform {
                guard !cancellationToken.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }

                let candidates = Array(fetchPostCandidates(
                    terms: terms,
                    allTermsMask: maskForAllTerms(terms),
                    contactTermMasks: contactTermMasks,
                    blockedPubkeys: blockedPubkeys,
                    context: context
                )
                .sorted { rankedBefore($0, $1) }
                .prefix(postResultLimit))

                guard !cancellationToken.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }

                var seenAuthorPubkeys = Set<Pubkey>()
                let authorPubkeys = candidates
                    .map(\.pubkey)
                    .filter { seenAuthorPubkeys.insert($0).inserted }
                let authorProfiles = fetchContactProfiles(
                    pubkeys: authorPubkeys,
                    context: context
                )
                continuation.resume(
                    returning: cancellationToken.isCancelled
                        ? nil
                        : PostSearchFetchResult(
                            candidates: candidates,
                            authorProfiles: authorProfiles
                        )
                )
            }
        }

        guard let fetchResult, !cancellationToken.isCancelled else { return [] }
        let authors = fetchResult.authorProfiles.map { profile in
            let contact = NRContact.instance(of: profile.pubkey)
            contact.refreshForSearch(from: profile)
            return contact
        }
        let authorsByPubkey = Dictionary(
            uniqueKeysWithValues: authors.map { ($0.pubkey, $0) }
        )
        return fetchResult.candidates.map { candidate in
            SearchPostResult(
                id: candidate.id,
                pubkey: candidate.pubkey,
                createdAt: Date(timeIntervalSince1970: TimeInterval(candidate.createdAt)),
                content: String(candidate.content.prefix(1000)),
                author: authorsByPubkey[candidate.pubkey]
            )
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

    static func normalizedTerms(_ searchText: String) -> [SearchTerm] {
        var seen = Set<SearchTerm>()
        return searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).lowercased() }
            .filter { seen.insert($0).inserted }
            .prefix(maximumTermCount)
            .map { $0 }
    }

    static func matches(
        terms: [SearchTerm],
        searchableValues: [String]
    ) -> Bool {
        termMask(terms: terms, searchableValues: searchableValues) == maskForAllTerms(terms)
    }

    private static func maskForAllTerms(_ terms: [SearchTerm]) -> UInt64 {
        guard !terms.isEmpty else { return 0 }
        return (UInt64(1) << UInt64(terms.count)) - 1
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
                createdAt: row["created_at"] as? Int64 ?? 0,
                content: content
            )
        }
    }

    private static func fetchContactProfiles(
        pubkeys: [Pubkey],
        context: NSManagedObjectContext
    ) -> [ProfileInfo] {
        guard !pubkeys.isEmpty else { return [] }

        let request = Contact.fetchRequest()
        request.predicate = NSPredicate(format: "pubkey IN %@", pubkeys)
        guard let contacts = try? context.fetch(request) else { return [] }

        let contactsByPubkey = Dictionary(uniqueKeysWithValues: contacts.map { ($0.pubkey, $0) })
        return pubkeys.compactMap { pubkey in
            guard let contact = contactsByPubkey[pubkey] else { return nil }
            return profileInfo(contact)
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
