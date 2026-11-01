import SwiftUI

struct PollComposer: View {
    @Binding var draft: PollDraft
    var onRemove: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Poll")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.primary)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondary)
                .accessibilityLabel(String(localized: "Remove poll", comment: "Removes the poll from a post being written"))
            }
            .padding(.bottom, 4)

            ForEach($draft.answers) { $answer in
                answerRow($answer)
                if answer.id != draft.answers.last?.id {
                    Divider().padding(.leading, 34)
                }
            }

            if draft.answers.count < PollDraft.maximumAnswers {
                Button {
                    draft = draft.addingAnswer()
                } label: {
                    Label(String(localized: "Add answer", comment: "Adds another poll answer"), systemImage: "plus")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
            }

            if draft.hasDuplicateAnswers {
                Text("Each answer needs its own label.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }

            HStack(alignment: .center, spacing: 12) {
                Menu {
                    ForEach(PollDraft.Duration.allCases) { duration in
                        Button {
                            draft.duration = duration
                        } label: {
                            if draft.duration == duration {
                                Label(duration.title, systemImage: "checkmark")
                            } else {
                                Text(duration.title)
                            }
                        }
                    }
                } label: {
                    Label(draft.duration.endsLabel, systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(theme.primary)
                }
                .accessibilityLabel(draft.duration.endsLabel)

                Spacer(minLength: 8)

                Toggle(isOn: $draft.multipleChoice) {
                    Text("Multiple")
                        .font(.subheadline)
                }
                .toggleStyle(.switch)
                .fixedSize()
                .accessibilityLabel(String(localized: "Allow multiple answers", comment: "Poll can accept more than one answer"))
            }
            .padding(.top, 8)

            Text(draft.multipleChoice
                 ? String(localized: "People can choose more than one answer. Votes are public.", comment: "Shown while creating a multiple-choice poll")
                 : String(localized: "People choose one answer. Votes are public.", comment: "Shown while creating a single-choice poll"))
                .font(.caption)
                .foregroundStyle(theme.secondary)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(theme.listBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.lineColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func answerRow(_ answer: Binding<PollDraft.Answer>) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: draft.multipleChoice ? 4 : 11)
                .stroke(theme.secondary.opacity(0.45), lineWidth: 1.5)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            TextField(String(localized: "Answer", comment: "Placeholder for a poll answer"), text: answer.label)
                .font(.body)
                .textFieldStyle(.plain)
                .submitLabel(.next)
                .onChange(of: answer.label.wrappedValue) { newValue in
                    let flattened = newValue.replacingOccurrences(of: "\n", with: " ")
                    if flattened.count > PollDraft.maximumLabelLength {
                        answer.label.wrappedValue = String(flattened.prefix(PollDraft.maximumLabelLength))
                    } else if flattened != newValue {
                        answer.label.wrappedValue = flattened
                    }
                }

            if draft.answers.count > PollDraft.minimumAnswers {
                Button {
                    draft.answers.removeAll { $0.id == answer.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.body)
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondary)
                .accessibilityLabel(String(localized: "Remove answer", comment: "Removes one poll answer"))
            }
        }
        .frame(minHeight: 44)
    }
}
