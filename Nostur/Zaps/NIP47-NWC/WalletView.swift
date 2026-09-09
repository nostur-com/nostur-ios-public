import SwiftUI
import NavigationBackport

@MainActor
final class WalletViewModel: ObservableObject {
    @Published var balance: Int?
    @Published var transactions: [NWCTransaction] = []
    @Published var walletName = "Connected wallet"
    @Published var network: String?
    @Published var methods: Set<String> = []
    @Published var connected = false
    @Published var loading = false
    @Published var loadingPage = false
    @Published var hasMore = false
    @Published var error: String?
    @Published var balanceError: String?
    @Published var historyError: String?
    @Published var infoWarning: String?
    @Published var filter = ""

    private var connection: NWCWalletClient.Connection?
    private var encryption = "nip04"
    private var offset = 0
    private var until = 0
    private var generation = UUID()
    private var historyGeneration = UUID()
    private let client = NWCWalletClient.shared

    func refresh() async {
        let generation = UUID()
        self.generation = generation
        historyGeneration = UUID()
        connection = NWCWalletClient.Connection.current()
        connected = connection != nil
        balance = nil
        transactions = []
        methods = []
        walletName = "Connected wallet"
        network = nil
        error = nil
        infoWarning = nil
        balanceError = nil
        historyError = nil
        hasMore = false
        loadingPage = false
        offset = 0
        until = Int(Date().timeIntervalSince1970)
        guard let connection else { loading = false; return }
        loading = true
        defer { if self.generation == generation { loading = false } }
        do {
            let capabilities = try await client.discover(connection)
            guard self.generation == generation else { return }
            encryption = capabilities.encryption
            methods = capabilities.methods
            if methods.contains("get_info") {
                do {
                    let info = try await client.request("get_info", connection: connection, encryption: encryption)
                    guard self.generation == generation else { return }
                    if let available = info.methods { methods = Set(available) }
                    if let alias = info.alias, !alias.isEmpty { walletName = alias }
                    network = info.network
                } catch is CancellationError { return }
                catch {
                    guard self.generation == generation else { return }
                    infoWarning = "Could not check connection permissions. Available wallet features may be restricted."
                }
            }
            async let balanceRequest: () = loadBalance(generation: generation)
            async let historyRequest: () = loadNextPage()
            _ = await (balanceRequest, historyRequest)
        } catch is CancellationError {
        } catch {
            guard self.generation == generation else { return }
            self.error = error.localizedDescription
        }
    }

    private func loadBalance(generation: UUID) async {
        guard methods.contains("get_balance"), let connection else { return }
        do {
            let result = try await client.request("get_balance", connection: connection, encryption: encryption)
            guard self.generation == generation else { return }
            guard let balance = result.balance else { throw NWCWalletClient.Failure.invalidResponse }
            self.balance = balance
        } catch is CancellationError {
        } catch {
            guard self.generation == generation else { return }
            balanceError = error.localizedDescription
        }
    }

    func refreshHistory() async {
        // During initial discovery, refresh() will request the current filter.
        guard !loading else { return }
        historyGeneration = UUID()
        transactions = []
        offset = 0
        until = Int(Date().timeIntervalSince1970)
        hasMore = false
        loadingPage = false
        historyError = nil
        await loadNextPage()
    }

    func loadNextPage() async {
        guard !loadingPage, methods.contains("list_transactions"), let connection else { return }
        let generation = self.generation
        let historyGeneration = self.historyGeneration
        loadingPage = true
        historyError = nil
        defer { if self.generation == generation && self.historyGeneration == historyGeneration { loadingPage = false } }
        do {
            let params = NWCRequest.NWCParams(limit: 20, offset: offset, until: until, type: filter.isEmpty ? nil : filter)
            let result = try await client.request("list_transactions", params: params, connection: connection, encryption: encryption)
            guard self.generation == generation && self.historyGeneration == historyGeneration else { return }
            guard let page = result.transactions else { throw NWCWalletClient.Failure.invalidResponse }
            var ids = Set(transactions.map(\.id))
            transactions.append(contentsOf: page.filter { ids.insert($0.id).inserted })
            offset += page.count
            hasMore = result.total_count.map { offset < $0 && !page.isEmpty } ?? (page.count == 20)
        } catch is CancellationError {
        } catch {
            guard self.generation == generation && self.historyGeneration == historyGeneration else { return }
            historyError = error.localizedDescription
        }
    }
}

struct WalletView: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var settings = SettingsStore.shared
    @StateObject private var model = WalletViewModel()
    @State private var showSettings = false
    @State private var showConnectionInfo = false
    @State private var selectedTransaction: NWCTransaction?
    @State private var revealBalance = false
    @ObservedObject private var exchangeRate = ExchangeRateModel.shared

    private var availableFeatures: String {
        let names = ["get_balance": "Balance", "list_transactions": "Activity", "pay_invoice": "Payments", "make_invoice": "Receive invoices"]
        return model.methods.sorted().compactMap { names[$0] }.joined(separator: ", ")
    }

    private var refreshID: String {
        "\(settings.activeNWCconnectionId):\(settings.nwcReady):\(showSettings)"
    }

    var body: some View {
        NXForm {
            if !model.connected && !model.loading {
                Section {
                    Label("Connect a wallet", systemImage: "wallet.pass")
                        .font(.headline)
                    Text("Connect a Nostr Wallet Connect wallet to see your balance and payment activity.")
                        .foregroundStyle(.secondary)
                    Button("Connect wallet") { showSettings = true }
                }
            } else {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "bolt.fill")
                            .font(.title2)
                            .foregroundStyle(theme.accent)
                            .frame(width: 48, height: 48)
                            .background(theme.accent.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            if let balance = model.balance {
                                Text(revealBalance ? "\(NWCTransaction.formattedSats(Int64(balance))) sats" : "•••••• sats")
                                    .font(.title.bold())
                                if revealBalance,
                                   let fiat = exchangeRate.formattedFiatValue(sats: Double(balance) / 1000, includeParentheses: false) {
                                    Text(fiat).foregroundStyle(.secondary)
                                }
                            } else if model.loading {
                                ProgressView()
                            } else {
                                Text("Balance unavailable").font(.headline)
                            }
                        }
                        Spacer()
                        if model.balance != nil {
                            Button { revealBalance.toggle() } label: {
                                Image(systemName: revealBalance ? "eye.slash" : "eye")
                            }
                            .accessibilityLabel(revealBalance ? "Hide balance" : "Show balance")
                        }
                    }
                    if let error = model.balanceError { Text(error).foregroundStyle(.secondary) }
                    if !model.loading && model.error == nil && !model.methods.contains("get_balance") {
                        Text("Balance is not available for this connection.").foregroundStyle(.secondary)
                    }
                    if let error = model.error {
                        Text(error).foregroundStyle(.secondary)
                        Button("Try again") { Task { await model.refresh() } }
                    }
                }

                Section("Activity") {
                    if model.methods.contains("list_transactions") {
                        Picker("Payments", selection: $model.filter) {
                            Text("All").tag("")
                            Text("Received").tag("incoming")
                            Text("Sent").tag("outgoing")
                        }
                        .pickerStyle(.segmented)
                        .disabled(model.loading)
                        ForEach(model.transactions) { transaction in
                            Button { selectedTransaction = transaction } label: {
                                WalletTransactionRow(transaction: transaction)
                            }
                            .buttonStyle(.plain)
                        }
                        if model.loadingPage || model.loading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else if let error = model.historyError {
                            Text(error).foregroundStyle(.secondary)
                            Button("Retry activity") { Task { await model.loadNextPage() } }
                        } else if model.transactions.isEmpty {
                            Text("No payments found.").foregroundStyle(.secondary)
                        }
                        if model.hasMore && !model.loadingPage && !model.loading && model.historyError == nil {
                            Button("Load more") { Task { await model.loadNextPage() } }
                        }
                    } else if model.loading {
                        ProgressView()
                    } else if model.error == nil {
                        Text("Transaction history is not available for this connection. Your wallet may require history permission or a new connection.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Connect to your wallet to load activity.").foregroundStyle(.secondary)
                    }
                }

            }
        }
        .navigationTitle("Wallet")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showConnectionInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Wallet connection")
                    .disabled(!model.connected)
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Refresh wallet")
                    .disabled(model.loading || !model.connected)
            }
        }
        .task(id: refreshID) {
            revealBalance = settings.nwcShowBalance
            if !showSettings { await model.refresh() }
        }
        .task(id: model.filter) { await model.refreshHistory() }
        .refreshable { await model.refresh() }
        .nbNavigationDestination(isPresented: $showSettings) { ZapsSettings() }
        .sheet(isPresented: $showConnectionInfo) {
            NBNavigationStack {
                WalletConnectionView(model: model, availableFeatures: availableFeatures)
            }
            .environment(\.theme, theme)
        }
        .sheet(item: $selectedTransaction) { transaction in
            NBNavigationStack {
                WalletTransactionDetail(transaction: transaction)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { selectedTransaction = nil } } }
            }
            .environment(\.theme, theme)
        }
    }

}

private struct WalletTransactionRow: View {
    let transaction: NWCTransaction
    @Environment(\.theme) private var theme
    @ObservedObject private var exchangeRate = ExchangeRateModel.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let pubkey = transaction.zapContactPubkey, pubkey.count == 64 {
                WalletZapIdentity(pubkey: pubkey, transaction: transaction, compact: true)
            } else {
                Image(systemName: transaction.type == "incoming" ? "arrow.down.left" : "arrow.up.right")
                    .font(.headline)
                    .foregroundStyle(theme.accent)
                    .frame(width: 38, height: 38)
                    .background(theme.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.title).font(.body.weight(.medium)).lineLimit(1)
                    if let description = displayDescription {
                        Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(transaction.type == "incoming" ? "+" : "−")\(NWCTransaction.formattedSats(transaction.amount)) sats")
                    .font(.body.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(transaction.type == "incoming" ? theme.accent : .primary)
                if let fiat = exchangeRate.formattedFiatValue(sats: Double(transaction.amount) / 1000) {
                    Text(fiat).font(.caption).foregroundStyle(.secondary)
                }
                if let state = transaction.state, state != "settled" {
                    Text(state.capitalized)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var displayDescription: String? {
        guard let description = transaction.description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty else { return nil }
        return description
    }
}

private struct WalletTransactionDetail: View {
    let transaction: NWCTransaction
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @ObservedObject private var exchangeRate = ExchangeRateModel.shared

    var body: some View {
        NXForm {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: transaction.type == "incoming" ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                        .font(.system(size: 42)).foregroundStyle(theme.accent)
                    Text("\(transaction.type == "incoming" ? "+" : "−")\(NWCTransaction.formattedSats(transaction.amount)) sats")
                        .font(.largeTitle.bold()).monospacedDigit()
                    if let fiat = exchangeRate.formattedFiatValue(sats: Double(transaction.amount) / 1000) {
                        Text(fiat).font(.headline).foregroundStyle(.secondary)
                    }
                    if let state = transaction.state, state != "settled" {
                        Text(state.capitalized).font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.secondary.opacity(0.12), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            if let pubkey = transaction.zapContactPubkey, pubkey.count == 64 {
                Section {
                    WalletZapIdentity(pubkey: pubkey, transaction: transaction, compact: false)
                    if let postId = transaction.zapPostId, postId.count == 64 {
                        Button {
                            dismiss()
                            navigateTo(NotePath(id: postId), context: "Default")
                        } label: {
                            Label("Open zapped post", systemImage: "text.bubble")
                        }
                    }
                    Button {
                        dismiss()
                        navigateTo(ContactPath(key: pubkey), context: "Default")
                    } label: {
                        Label("View profile", systemImage: "person.crop.circle")
                    }
                }
            } else if let description = cleanDescription {
                Section { Text(description).font(.body) }
            }
            Section {
                HStack(spacing: 0) {
                    summaryItem("Date", transaction.date.formatted(date: .abbreviated, time: .omitted))
                    Divider().frame(height: 36)
                    summaryItem("Time", transaction.date.formatted(date: .omitted, time: .shortened))
                    if let fees = transaction.fees_paid {
                        Divider().frame(height: 36)
                        summaryItem("Fee", "\(NWCTransaction.formattedSats(fees)) sats")
                    }
                }
            }
            Section {
                DisclosureGroup("Technical details") {
                    technicalValue("Payment hash", transaction.payment_hash)
                    if let invoice = transaction.invoice { technicalValue("Invoice", invoice) }
                    if let settled = transaction.settled_at {
                        technicalValue("Settled", Date(timeIntervalSince1970: TimeInterval(settled)).formatted(date: .abbreviated, time: .standard))
                    }
                }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cleanDescription: String? {
        let value = transaction.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func summaryItem(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func technicalValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced()).textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

private struct WalletZapIdentity: View {
    let transaction: NWCTransaction
    let compact: Bool
    @ObservedObject private var contact: NRContact

    init(pubkey: String, transaction: NWCTransaction, compact: Bool) {
        self.transaction = transaction
        self.compact = compact
        self.contact = NRContact.instance(of: pubkey)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PFP(pubkey: contact.pubkey, nrContact: contact, size: compact ? 38 : 46, forceFlat: true)
            VStack(alignment: .leading, spacing: 4) {
                narrative
                    .font(compact ? .body.weight(.medium) : .headline)
                    .lineLimit(compact ? 2 : nil)
                if let content = zapContent {
                    Text(content).font(compact ? .subheadline : .body)
                        .foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if contact.metadata_created_at == 0 { QueuedFetcher.shared.enqueue(pTag: contact.pubkey) }
        }
    }

    private var narrative: Text {
        let incoming = transaction.type == "incoming"
        let action = incoming ? "Received zap from " : "Sent zap to "
        let context = transaction.zapPostId == nil ? " directly" : " on a post"
        return Text(action) + Text(contact.anyName).bold() + Text(context)
    }

    private var zapContent: String? {
        let value = (transaction.zapRequest?.content ?? transaction.description)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}

private struct WalletConnectionView: View {
    @ObservedObject var model: WalletViewModel
    let availableFeatures: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NXForm {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.system(size: 36)).foregroundStyle(.secondary)
                    Text(model.walletName).font(.title2.bold())
                    if let network = model.network { Text(network.capitalized).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            if !availableFeatures.isEmpty {
                Section("Available features") { Text(availableFeatures) }
            }
            if let warning = model.infoWarning {
                Section { Text(warning).foregroundStyle(.secondary) }
            }
            Section {
                NavigationLink { ZapsSettings() } label: {
                    Label("Wallet settings", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("Wallet connection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
