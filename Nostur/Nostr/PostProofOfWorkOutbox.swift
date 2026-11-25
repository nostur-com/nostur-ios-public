import Combine
import CoreData
import Foundation

struct PendingProofPostPresentation {
    let post: NRPost
    let relay: RelayData?
}

@MainActor
final class PostProofOfWorkOutbox: ObservableObject {
    struct PendingPost: Identifiable {
        enum Status: Equatable {
            case preparing, signing, ready
        }

        let id: UUID
        var status: Status = .preparing
    }

    private struct Job {
        var signedEvent: NEvent?
        var deadlineUptime: TimeInterval?
        let prepareTask: Task<Void, Never>
        var countdownTask: Task<Void, Never>?
        let publish: (NEvent) -> Void
        let restore: () -> Void
    }

    static let shared = PostProofOfWorkOutbox()
    @Published private(set) var posts: [PendingPost] = []
    @Published var showsFailure = false
    private var jobs: [UUID: Job] = [:]
    private var previews: [UUID: NRPost] = [:]
    private let undoWindow: TimeInterval

    init(undoWindow: TimeInterval = Unpublisher.publishDelay) {
        self.undoWindow = undoWindow
    }

    func queue(_ event: NEvent, target: Int, account: CloudAccount, relay: RelayData?, replyToID: String?,
               draft: ComposerDraft, onPublish: @escaping () -> Void) {
        let accountID = account.objectID
        let id = enqueue(waitForPreview: true, publish: { [weak self] id, signed in
            Unpublisher.shared.publishPreparedPost(signed, lockToThisRelay: relay) {
                Drafts.shared.finishPendingProofPost(id: id, restore: false)
                self?.removePreview(id)
            }
            onPublish()
        }, restore: { id in
            Drafts.shared.finishPendingProofPost(id: id, restore: true)
        }, prepare: { [weak self] id in
            do {
                let post = await withBgContext { _ in
                    Self.makePreview(event, id: id, replyToID: replyToID)
                }
                try Task.checkCancellation()
                guard let self, self.jobs[id] != nil else { return }
                self.previews[id] = post
                sendNotification(.pendingProofPost, PendingProofPostPresentation(post: post, relay: relay))
                self.startCountdown(id)

                let mined = try await PostProofOfWork.mine(event, target: target)
                try Task.checkCancellation()
                guard let signingAccount = try? viewContext().existingObject(with: accountID) as? CloudAccount,
                      !signingAccount.isDeleted, signingAccount.isFullAccount, signingAccount.publicKey == mined.publicKey else {
                    self.fail(id)
                    return
                }
                if signingAccount.isNC {
                    self.beginRemoteSigning(mined, account: signingAccount, id: id)
                    try await Task.sleep(nanoseconds: 45_000_000_000)
                    self.fail(id)
                } else {
                    let signed = try signingAccount.signEvent(mined)
                    self.acceptSignature(signed, expectedID: mined.id, id: id)
                }
            } catch is CancellationError {
                // Undo removed the job before cancelling its work.
            } catch {
                self?.fail(id)
            }
        })
        Drafts.shared.rememberPendingProofPost(id: id, draft: draft)
    }

    nonisolated static func makePreview(_ event: NEvent, id: UUID, replyToID: String?) -> NRPost {
        var displayEvent = event
        displayEvent.id = "pending-proof-\(id.uuidString)"
        let preview = createPreviewEvent(displayEvent, insertIntoContext: false)
        preview.replyToId = replyToID ?? preview.replyToId
        preview.kTag = Int64(event.fastTags.first(where: { $0.0 == "k" })?.1 ?? "") ?? 0
        return NRPost(event: preview, isPreview: true, pendingProofPostID: id)
    }

    @discardableResult
    func enqueue(waitForPreview: Bool = false, publish: @escaping (UUID, NEvent) -> Void,
                 restore: @escaping (UUID) -> Void,
                 prepare: @escaping (UUID) async -> Void) -> UUID {
        let id = UUID()
        posts.append(PendingPost(id: id))
        let prepareTask = Task { await prepare(id) }
        jobs[id] = Job(prepareTask: prepareTask, publish: { publish(id, $0) }, restore: { restore(id) })
        if !waitForPreview { startCountdown(id) }
        return id
    }

    func startCountdown(_ id: UUID) {
        guard jobs[id]?.deadlineUptime == nil, jobs[id] != nil else { return }
        jobs[id]?.deadlineUptime = ProcessInfo.processInfo.systemUptime + undoWindow
        jobs[id]?.countdownTask = Task { [weak self, undoWindow] in
            do {
                try await Task.sleep(nanoseconds: UInt64(undoWindow * 1_000_000_000))
                self?.sendNow(id)
            } catch { }
        }
    }

    func undo(_ id: UUID) {
        guard let job = finish(id) else { return }
        job.restore()
        removePreview(id)
    }

    func sendNow(_ id: UUID) {
        guard let job = jobs[id], job.deadlineUptime != nil, let event = job.signedEvent,
              let completed = finish(id) else { return }
        completed.publish(event)
    }

    func markReady(_ event: NEvent, id: UUID) {
        guard let index = posts.firstIndex(where: { $0.id == id }), let job = jobs[id], job.signedEvent == nil else { return }
        jobs[id]?.signedEvent = event
        jobs[id]?.prepareTask.cancel()
        if let deadlineUptime = job.deadlineUptime, ProcessInfo.processInfo.systemUptime >= deadlineUptime {
            sendNow(id)
        } else {
            posts[index].status = .ready
        }
    }

    private func beginRemoteSigning(_ event: NEvent, account: CloudAccount, id: UUID) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        posts[index].status = .signing
        RemoteSignerManager.shared.requestSignature(forEvent: event, usingAccount: account, requestID: signingRequestID(id)) { [weak self] signed in
            Task { @MainActor in self?.acceptSignature(signed, expectedID: event.id, id: id) }
        }
    }

    private func acceptSignature(_ event: NEvent, expectedID: String, id: UUID) {
        guard jobs[id] != nil else { return }
        guard event.id == expectedID, (try? event.verified(logInvalidID: false)) == true else {
            fail(id)
            return
        }
        markReady(event, id: id)
    }

    private func fail(_ id: UUID) {
        guard let job = finish(id) else { return }
        job.restore()
        removePreview(id)
        showsFailure = true
    }

    private func removePreview(_ id: UUID) {
        if let post = previews.removeValue(forKey: id) {
            sendNotification(.unpublishedNRPost, post)
        }
    }

    private func finish(_ id: UUID) -> Job? {
        guard let job = jobs.removeValue(forKey: id) else { return nil }
        if let index = posts.firstIndex(where: { $0.id == id }) {
            if posts[index].status == .signing {
                RemoteSignerManager.shared.cancelSignatureRequest(signingRequestID(id))
            }
            posts.remove(at: index)
        }
        job.prepareTask.cancel()
        job.countdownTask?.cancel()
        return job
    }

    private func signingRequestID(_ id: UUID) -> String { "sign-event-\(id.uuidString)" }
}
