//
//  MessageExpirationSheet.swift
//  Nostur
//
//  The "Disappearing messages" timer picker (screen 01-picker-sheet). Presented from the composer's
//  + button and from Conversation info. Lets the user pick a per-message timer (Off / 7 days /
//  30 days / Custom, >= 2 days) and toggle a per-conversation, device-local auto-apply default.
//

import SwiftUI

struct MessageExpirationSheet: View {

    // Where the sheet was opened from. Changes whether picks are per-message or the conversation default.
    enum Context {
        case composer            // from the + button: sets the per-message draft (auto-apply toggle opts in)
        case conversationDefault // from Conversation info: directly sets the auto-apply default; no toggle
    }

    @ObservedObject var vm: ConversionVM
    var context: Context = .composer
    @Environment(\.theme) private var theme

    @State private var autoApply: Bool = false
    @State private var showCustomPicker: Bool = false
    // Custom is a *duration* in days (min 2), not an absolute date. A fixed date makes no sense as an
    // auto-apply default (every later message would be born already-expired).
    @State private var customDays: Int = 7

    private let customDayOptions: [Int] = Array(2...365)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                VStack(spacing: 0) {
                    optionRow(label: "Off", duration: nil, row: .off)
                    rowDivider
                    optionRow(label: "7 days", duration: DMExpiry.sevenDaysSeconds, row: .sevenDays)
                    rowDivider
                    optionRow(label: "30 days", duration: DMExpiry.thirtyDaysSeconds, row: .thirtyDays)
                    rowDivider
                    customRow
                }
                .background(theme.listBackground, in: RoundedRectangle(cornerRadius: 18))

                if showCustomPicker {
                    customPicker
                }

                if showsAutoApplyToggle {
                    Toggle(isOn: $autoApply) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-apply to messages I send")
                            Text("A setting on this device")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(theme.accent)
                    .padding()
                    .background(theme.listBackground, in: RoundedRectangle(cornerRadius: 18))
                    .onValueChange(autoApply) { _, newValue in applyAutoApply(newValue) }
                }

                Text("May disappear up to 2 days early (send time is obscured). Supported apps like Nostur honor it. Others may keep a copy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(theme.background)
        .onAppear {
            autoApply = vm.expirySetting.enabled
        }
        .modifier(ExpirySheetDetents(expanded: showCustomPicker))
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundStyle(theme.accent)
                Text("Disappearing messages")
                    .font(.headline)
            }
            Text("How long should messages you send stay around?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Option rows

    private var rowDivider: some View { Divider().padding(.leading) }

    private var showsAutoApplyToggle: Bool { context == .composer }

    // The duration the sheet currently reflects: the per-message draft in the composer, or the
    // conversation's auto-apply default when opened from Conversation info.
    private var effectiveDuration: Int? {
        switch context {
        case .composer:
            return vm.resolvedExpiryDuration()
        case .conversationDefault:
            let setting = vm.expirySetting
            return setting.enabled ? setting.durationSeconds : nil
        }
    }

    // Which row currently owns the checkmark (exactly one).
    private enum SelectedRow { case off, sevenDays, thirtyDays, custom }

    private var selectedRow: SelectedRow {
        if showCustomPicker { return .custom }
        guard let d = effectiveDuration else { return .off }
        if d == DMExpiry.sevenDaysSeconds { return .sevenDays }
        if d == DMExpiry.thirtyDaysSeconds { return .thirtyDays }
        return .custom // a non-preset duration (e.g. 5 days)
    }

    private func optionRow(label: LocalizedStringKey, duration: Int?, row: SelectedRow) -> some View {
        Button {
            selectDuration(duration)
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedRow == row {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accent)
                }
            }
            .contentShape(Rectangle())
            .padding()
        }
    }

    private var customRow: some View {
        Button {
            if !showCustomPicker, let current = effectiveDuration {
                customDays = min(365, max(2, current / 86_400)) // seed the wheel from the current value
            }
            withAnimation { showCustomPicker.toggle() }
            if showCustomPicker { applyCustom() }
        } label: {
            HStack {
                Text("Custom…")
                    .foregroundStyle(.primary)
                Spacer()
                if selectedRow == .custom {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accent)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding()
        }
    }

    private var customPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Disappear after")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Days", selection: $customDays) {
                ForEach(customDayOptions, id: \.self) { day in
                    Text(DMExpiry.presetLabel(forDuration: day * 86_400)).tag(day) // reuses the "%@ days" key
                }
            }
            .pickerStyle(.wheel)
            .tint(theme.accent)
            .onValueChange(customDays) { _, _ in applyCustom() }
        }
        .padding()
        .background(theme.listBackground, in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: Actions

    private func selectDuration(_ duration: Int?) {
        withAnimation {
            showCustomPicker = false
        }
        switch context {
        case .composer:
            if let duration {
                vm.draftExpiry = .duration(duration)
                if autoApply { persist(enabled: true, duration: duration) }
            }
            else {
                vm.draftExpiry = .off // clear for THIS message; the auto-apply toggle is separate
            }
        case .conversationDefault:
            // The whole screen IS the auto-apply default: picking a duration enables it, "Off" disables it.
            if let duration {
                persist(enabled: true, duration: duration)
            }
            else {
                persist(enabled: false, duration: vm.expirySetting.durationSeconds)
            }
        }
    }

    private func applyCustom() {
        let seconds = customDays * 86_400 // the wheel starts at 2 days, so this is always valid
        switch context {
        case .composer:
            vm.draftExpiry = .duration(seconds)
            if autoApply { persist(enabled: true, duration: seconds) }
        case .conversationDefault:
            persist(enabled: true, duration: seconds)
        }
    }

    private func applyAutoApply(_ on: Bool) {
        if on {
            let duration = vm.resolvedExpiryDuration() ?? DMExpiry.sevenDaysSeconds
            persist(enabled: true, duration: duration)
            vm.draftExpiry = .auto // follow the newly-enabled default
        }
        else {
            persist(enabled: false, duration: vm.expirySetting.durationSeconds)
        }
    }

    private func persist(enabled: Bool, duration: Int) {
        vm.saveExpirySetting(
            DMExpirySetting(enabled: enabled, durationSeconds: duration, label: DMExpiry.presetLabel(forDuration: duration))
        )
    }
}

// Applies presentation detents (iOS 16+) and grows the sheet to .large while the custom day picker is open.
private struct ExpirySheetDetents: ViewModifier {
    let expanded: Bool
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents(expanded ? [.large] : [.medium, .large])
        } else {
            content
        }
    }
}
