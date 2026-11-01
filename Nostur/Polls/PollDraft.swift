import Foundation

/// Composer state for a new NIP-88 poll. Option ids stay stable while the person edits.
struct PollDraft: Equatable {
    struct Answer: Identifiable, Equatable {
        let id: String
        var label: String
    }

    enum Duration: String, CaseIterable, Identifiable, Equatable {
        case hour
        case day
        case threeDays
        case week
        case month
        case open

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hour: String(localized: "1 hour", comment: "Poll length")
            case .day: String(localized: "1 day", comment: "Poll length")
            case .threeDays: String(localized: "3 days", comment: "Poll length")
            case .week: String(localized: "1 week", comment: "Poll length")
            case .month: String(localized: "30 days", comment: "Poll length")
            case .open: String(localized: "No end date", comment: "Poll does not expire")
            }
        }

        /// Full phrase shown on the duration control.
        var endsLabel: String {
            switch self {
            case .hour: String(localized: "Ends in 1 hour", comment: "Poll ends one hour after it is posted")
            case .day: String(localized: "Ends in 1 day", comment: "Poll ends one day after it is posted")
            case .threeDays: String(localized: "Ends in 3 days", comment: "Poll ends three days after it is posted")
            case .week: String(localized: "Ends in 1 week", comment: "Poll ends one week after it is posted")
            case .month: String(localized: "Ends in 30 days", comment: "Poll ends 30 days after it is posted")
            case .open: String(localized: "No end date", comment: "Poll does not expire")
            }
        }

        func endsAt(from now: Date) -> Int? {
            let seconds: Int? = switch self {
            case .hour: 3_600
            case .day: 86_400
            case .threeDays: 3 * 86_400
            case .week: 7 * 86_400
            case .month: 30 * 86_400
            case .open: nil
            }
            guard let seconds else { return nil }
            return Int(now.timeIntervalSince1970) + seconds
        }
    }

    struct Built: Equatable {
        let content: String
        let tags: [[String]]
    }

    static let minimumAnswers = 2
    static let maximumAnswers = 6
    static let maximumLabelLength = 80

    var answers: [Answer]
    var multipleChoice: Bool
    var duration: Duration

    static func new() -> PollDraft {
        let first = optionID()
        let second = optionID(existing: [first])
        return PollDraft(answers: [Answer(id: first, label: ""), Answer(id: second, label: "")],
                         multipleChoice: false, duration: .day)
    }

    func addingAnswer() -> PollDraft {
        guard answers.count < Self.maximumAnswers else { return self }
        var copy = self
        copy.answers.append(Answer(id: Self.optionID(existing: Set(answers.map(\.id))), label: ""))
        return copy
    }

    func isReady(question: String) -> Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && publishableAnswers() != nil
    }

    /// Kind 1068 content and tags. Nil until the question and answers are usable.
    /// Relay tags are omitted when none of the supplied URLs can be advertised.
    func builtEvent(question: String, relays: [String], now: Date) -> Built? {
        let content = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let answers = publishableAnswers() else { return nil }
        let relayURLs = NostrPoll.relayURLs(relays)
        var tags = answers.map { ["option", $0.id, $0.label] }
        tags.append(contentsOf: relayURLs.map { ["relay", $0] })
        tags.append(["polltype", multipleChoice ? "multiplechoice" : "singlechoice"])
        if let endsAt = duration.endsAt(from: now) {
            tags.append(["endsAt", String(endsAt)])
        }
        return Built(content: content, tags: tags)
    }

    var hasDuplicateAnswers: Bool {
        let labels = normalizedAnswers().filter { !$0.label.isEmpty }.map { $0.label.lowercased() }
        return Set(labels).count != labels.count
    }

    func publishableAnswers() -> [Answer]? {
        let filled = normalizedAnswers().filter { !$0.label.isEmpty }
        guard filled.count >= Self.minimumAnswers,
              Set(filled.map { $0.label.lowercased() }).count == filled.count,
              filled.allSatisfy({ Self.isOptionID($0.id) }) else { return nil }
        return filled
    }

    private func normalizedAnswers() -> [Answer] {
        answers.map { answer in
            let label = answer.label
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Answer(id: answer.id, label: String(label.prefix(Self.maximumLabelLength)))
        }
    }

    static func optionID(existing: Set<String> = []) -> String {
        var generator = SystemRandomNumberGenerator()
        return optionID(existing: existing, generator: &generator)
    }

    static func optionID(existing: Set<String>, generator: inout some RandomNumberGenerator) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var id = ""
        repeat {
            id = String((0..<8).map { _ in alphabet.randomElement(using: &generator)! })
        } while !isOptionID(id) || existing.contains(id)
        return id
    }

    static func isOptionID(_ id: String) -> Bool {
        id.count == 8 && id.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
