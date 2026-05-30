import SwiftUI
import StripePaymentSheet

struct PaymentView: View {
    let task: TaskItem
    let onSuccess: () async -> Void
    @Environment(\.dismiss) var dismiss
    @State private var paymentSheet: PaymentSheet?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var paymentResult: PaymentSheetResult?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let result = paymentResult {
                    paymentResultView(result)
                } else {
                    Spacer()
                    // Summary
                    VStack(spacing: 16) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 56)).foregroundStyle(.blue)
                        Text("Secure Payment").font(.title2.bold())
                        Text("Your payment will be held in escrow until the task is completed and confirmed.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        VStack(spacing: 8) {
                            paymentRow(label: "Task", value: task.title)
                            paymentRow(label: "Amount", value: "\(task.currency) \(task.budget, specifier: "%.2f")")
                            paymentRow(label: "Commission", value: "Free (0%)")
                            Divider()
                            paymentRow(label: "Total", value: "\(task.currency) \(task.budget, specifier: "%.2f")")
                                .fontWeight(.bold)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    Spacer()

                    if isLoading {
                        ProgressView("Preparing payment...")
                    } else if let sheet = paymentSheet {
                        PaymentSheet.PaymentButton(
                            paymentSheet: sheet,
                            onCompletion: handlePaymentResult
                        ) {
                            Text("Pay with Apple Pay / Card")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .background(.blue).foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                    }

                    if let error = errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal)
                    }

                    Spacer(minLength: 20)
                }
            }
            .navigationTitle("Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await preparePayment() }
        }
    }

    @ViewBuilder
    private func paymentResultView(_ result: PaymentSheetResult) -> some View {
        VStack(spacing: 20) {
            switch result {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64)).foregroundStyle(.green)
                Text("Payment Successful").font(.title2.bold())
                Text("The task is now in progress. Payment is held securely until completion.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
            case .failed(let error):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 64)).foregroundStyle(.red)
                Text("Payment Failed").font(.title2.bold())
                Text(error.localizedDescription).multilineTextAlignment(.center)
                    .foregroundStyle(.secondary).padding(.horizontal)
            case .canceled:
                Image(systemName: "xmark.circle").font(.system(size: 64)).foregroundStyle(.gray)
                Text("Payment Canceled").font(.title2.bold())
            @unknown default:
                EmptyView()
            }
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func paymentRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }

    private func preparePayment() async {
        isLoading = true
        errorMessage = nil
        do {
            struct PaymentIntentResponse: Codable {
                let clientSecret: String
                let publishableKey: String
            }
            let response: PaymentIntentResponse = try await NetworkManager.shared.requestJSON(
                "/payments/create-intent",
                body: ["task_id": task.id]
            )
            StripeAPI.defaultPublishableKey = response.publishableKey

            var config = PaymentSheet.Configuration()
            config.merchantDisplayName = "Taskly"
            config.applePay = .init(merchantId: "merchant.com.taskly.app", merchantCountryCode: "US")
            config.allowsDelayedPaymentMethods = false

            paymentSheet = PaymentSheet(paymentIntentClientSecret: response.clientSecret, configuration: config)
        } catch {
            errorMessage = "Failed to load payment: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func handlePaymentResult(_ result: PaymentSheetResult) {
        paymentResult = result
        if case .completed = result {
            Task { await onSuccess() }
        }
    }
}
