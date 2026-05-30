import SwiftUI

struct WalletView: View {
    @State private var wallet: Wallet?
    @State private var isLoading = false
    @State private var showWithdraw = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && wallet == nil {
                    ProgressView()
                } else if let wallet {
                    List {
                        // Balance header
                        Section {
                            VStack(spacing: 16) {
                                VStack(spacing: 4) {
                                    Text("Available Balance")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Text("\(wallet.currency) \(wallet.balance, specifier: "%.2f")")
                                        .font(.system(size: 40, weight: .bold))
                                }
                                HStack(spacing: 24) {
                                    VStack(spacing: 2) {
                                        Text("\(wallet.currency) \(wallet.escrowedAmount, specifier: "%.2f")")
                                            .font(.headline)
                                        Text("In Escrow").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Button {
                                    showWithdraw = true
                                } label: {
                                    Text("Withdraw")
                                        .fontWeight(.semibold)
                                        .frame(width: 160).frame(height: 44)
                                        .background(.blue).foregroundStyle(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .disabled(wallet.balance <= 0)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }

                        // Transactions
                        Section("Transaction History") {
                            if wallet.transactions.isEmpty {
                                Text("No transactions yet")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            } else {
                                ForEach(wallet.transactions) { tx in
                                    TransactionRow(transaction: tx)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Wallet unavailable", systemImage: "creditcard.trianglebadge.exclamationmark")
                }
            }
            .navigationTitle("Wallet")
            .task { await loadWallet() }
            .refreshable { await loadWallet() }
            .sheet(isPresented: $showWithdraw) {
                WithdrawView(balance: wallet?.balance ?? 0, currency: wallet?.currency ?? "USD") {
                    await loadWallet()
                }
            }
        }
    }

    private func loadWallet() async {
        isLoading = true
        defer { isLoading = false }
        do {
            wallet = try await NetworkManager.shared.request("/wallet")
        } catch { print("Wallet load failed: \(error)") }
    }
}

struct TransactionRow: View {
    let transaction: WalletTransaction

    var icon: String {
        switch transaction.type {
        case .payment: return "arrow.up.circle.fill"
        case .release: return "arrow.down.circle.fill"
        case .refund: return "arrow.counterclockwise.circle.fill"
        case .withdrawal: return "banknote"
        }
    }

    var iconColor: Color {
        switch transaction.type {
        case .payment: return .red
        case .release: return .green
        case .refund: return .orange
        case .withdrawal: return .blue
        }
    }

    var amountPrefix: String {
        switch transaction.type {
        case .payment, .withdrawal: return "-"
        case .release, .refund: return "+"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description).font(.subheadline)
                Text(transaction.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(amountPrefix)\(transaction.currency) \(transaction.amount, specifier: "%.2f")")
                .font(.subheadline.bold())
                .foregroundStyle(transaction.type == .payment || transaction.type == .withdrawal ? .red : .green)
        }
    }
}

struct WithdrawView: View {
    let balance: Double
    let currency: String
    let onSuccess: () async -> Void
    @Environment(\.dismiss) var dismiss
    @State private var amount: Double = 0
    @State private var accountInfo = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didWithdraw = false

    var body: some View {
        NavigationStack {
            if didWithdraw {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
                    Text("Withdrawal Requested").font(.title2.bold())
                    Text("Funds will arrive within 1 business day.")
                        .foregroundStyle(.secondary)
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                Form {
                    Section("Amount") {
                        HStack {
                            Text(currency)
                            TextField("0.00", value: $amount, format: .number)
                                .keyboardType(.decimalPad)
                        }
                        Text("Available: \(currency) \(balance, specifier: "%.2f")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Bank / Account Info") {
                        TextField("Account details", text: $accountInfo, axis: .vertical)
                            .lineLimit(2...4)
                    }
                    if let error = errorMessage {
                        Section { Text(error).foregroundStyle(.red).font(.caption) }
                    }
                }
                .navigationTitle("Withdraw")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Request") { Task { await withdraw() } }
                            .fontWeight(.semibold)
                            .disabled(isLoading || amount <= 0 || amount > balance || accountInfo.isEmpty)
                    }
                }
            }
        }
    }

    private func withdraw() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            struct WithdrawBody: Encodable { let amount: Double; let currency, accountInfo: String }
            let _: EmptyResponse = try await NetworkManager.shared.requestJSON(
                "/wallet/withdraw",
                body: WithdrawBody(amount: amount, currency: currency, accountInfo: accountInfo)
            )
            didWithdraw = true
            await onSuccess()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
