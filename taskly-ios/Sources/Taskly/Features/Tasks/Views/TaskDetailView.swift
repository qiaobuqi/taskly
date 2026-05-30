import SwiftUI
import Kingfisher

struct TaskDetailView: View {
    let task: TaskItem
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var vm: TaskDetailViewModel
    @State private var showApply = false
    @State private var showChat = false
    @State private var showPayment = false
    @State private var showCompletion = false
    @State private var showReview = false
    @State private var showReport = false

    init(task: TaskItem) {
        self.task = task
        _vm = StateObject(wrappedValue: TaskDetailViewModel(task: task))
    }

    var currentTask: TaskItem { vm.task ?? task }
    var isOwner: Bool { authManager.currentUser?.id == currentTask.publisherId }
    var isAssignee: Bool { authManager.currentUser?.id == currentTask.assigneeId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Images
                if !currentTask.images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(currentTask.images, id: \.self) { url in
                                KFImage(URL(string: url))
                                    .resizable().scaledToFill()
                                    .frame(width: 200, height: 140)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding()
                    }
                }

                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(currentTask.category.displayName, systemImage: currentTask.category.icon)
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            StatusBadge(status: currentTask.status)
                        }
                        Text(currentTask.title).font(.title2.bold())
                        Text("\(currentTask.currency) \(currentTask.budget, specifier: "%.0f")")
                            .font(.title.bold()).foregroundStyle(.blue)
                    }

                    Divider()

                    // Details
                    VStack(alignment: .leading, spacing: 12) {
                        DetailRow(icon: "doc.text", label: "Description", value: currentTask.description)
                        DetailRow(icon: "mappin.and.ellipse", label: "Location", value: currentTask.address)
                        if let deadline = currentTask.deadline {
                            DetailRow(icon: "clock", label: "Deadline",
                                      value: deadline.formatted(date: .long, time: .shortened))
                        }
                        DetailRow(icon: "person.2", label: "Applicants",
                                  value: "\(currentTask.applicantCount) applied")
                    }

                    // Publisher
                    if let publisher = currentTask.publisher {
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Posted by").font(.headline)
                            UserRowView(user: publisher)
                                .onTapGesture { showReport = true }
                        }
                    }

                    // Assignee (if in progress)
                    if let assignee = currentTask.assignee, currentTask.status != .open {
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Assigned to").font(.headline)
                            UserRowView(user: assignee)
                        }
                    }

                    // Applications list (owner view, task is open)
                    if isOwner && currentTask.status == .open {
                        Divider()
                        ApplicationsSection(taskId: currentTask.id, onAccept: { await vm.reload() })
                    }

                    Spacer(minLength: 100)
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showReport = true } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .sheet(isPresented: $showApply) { ApplyView(task: currentTask) }
        .sheet(isPresented: $showChat) {
            if let publisher = currentTask.publisher {
                ChatView(otherUser: publisher, taskId: currentTask.id)
            }
        }
        .sheet(isPresented: $showPayment) {
            PaymentView(task: currentTask, onSuccess: { await vm.reload() })
        }
        .sheet(isPresented: $showCompletion) {
            SubmitCompletionView(task: currentTask, onSuccess: { await vm.reload() })
        }
        .sheet(isPresented: $showReview) {
            if let reviewee = isOwner ? currentTask.assignee : currentTask.publisher {
                ReviewView(task: currentTask, reviewee: reviewee, onSuccess: { await vm.reload() })
            }
        }
        .confirmationDialog("Report or Block", isPresented: $showReport) {
            Button("Report this task", role: .destructive) { Task { await vm.report() } }
            Button("Cancel", role: .cancel) {}
        }
        .task { await vm.reload() }
    }

    @ViewBuilder
    private var actionBar: some View {
        let status = currentTask.status
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                // Non-owner: apply or message
                if !isOwner && !isAssignee && status == .open {
                    Button { showChat = true } label: {
                        Label("Message", systemImage: "bubble.left")
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.primary)
                    Button { showApply = true } label: {
                        Text("Apply Now").fontWeight(.semibold)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(.blue).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                // Owner: pay to start (after accepting applicant)
                if isOwner && status == .inProgress {
                    Button { showPayment = true } label: {
                        Text("Pay & Confirm").fontWeight(.semibold)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(.blue).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                // Assignee: mark complete
                if isAssignee && status == .inProgress {
                    Button { showCompletion = true } label: {
                        Text("Mark Complete").fontWeight(.semibold)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(.green).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                // Owner: confirm completion
                if isOwner && status == .pendingConfirm {
                    Button { Task { await vm.confirmCompletion() } } label: {
                        Text("Confirm & Release Payment").fontWeight(.semibold)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(.green).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                // Both: leave review
                if (isOwner || isAssignee) && status == .completed {
                    Button { showReview = true } label: {
                        Text("Leave Review").fontWeight(.semibold)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(.orange).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
            .background(.background)
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: TaskStatus

    var color: Color {
        switch status {
        case .open: return .green
        case .inProgress: return .orange
        case .pendingConfirm: return .blue
        case .completed: return .gray
        case .cancelled: return .red
        case .disputed: return .purple
        }
    }

    var body: some View {
        Text(status.displayName)
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Applications Section

struct ApplicationsSection: View {
    let taskId: Int
    let onAccept: () async -> Void
    @State private var applications: [Application] = []
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Applications (\(applications.count))").font(.headline)
            if isLoading {
                ProgressView()
            } else if applications.isEmpty {
                Text("No applications yet").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(applications) { app in
                    ApplicationRowView(application: app) {
                        Task {
                            await accept(applicationId: app.id)
                            await onAccept()
                        }
                    }
                }
            }
        }
        .task { await loadApplications() }
    }

    private func loadApplications() async {
        isLoading = true
        defer { isLoading = false }
        do {
            applications = try await NetworkManager.shared.request("/tasks/\(taskId)/applications")
        } catch { print("Failed to load applications: \(error)") }
    }

    private func accept(applicationId: Int) async {
        do {
            let _: EmptyResponse = try await NetworkManager.shared.requestJSON(
                "/tasks/\(taskId)/applications/\(applicationId)/accept", body: EmptyResponse()
            )
        } catch { print("Accept failed: \(error)") }
    }
}

struct ApplicationRowView: View {
    let application: Application
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let applicant = application.applicant {
                UserRowView(user: applicant)
            }
            Text(application.message).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            HStack {
                Text("Offered: $\(application.proposedPrice, specifier: "%.0f")")
                    .font(.subheadline.bold()).foregroundStyle(.blue)
                Spacer()
                if application.status == .pending {
                    Button("Accept", action: onAccept)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(.blue).foregroundStyle(.white)
                        .clipShape(Capsule())
                } else {
                    Text(application.status.rawValue.capitalized)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - ViewModel

@MainActor
final class TaskDetailViewModel: ObservableObject {
    @Published var task: TaskItem?
    private let taskId: Int

    init(task: TaskItem) {
        self.task = task
        self.taskId = task.id
    }

    func reload() async {
        do {
            task = try await NetworkManager.shared.request("/tasks/\(taskId)")
        } catch { print("Reload failed: \(error)") }
    }

    func confirmCompletion() async {
        do {
            let _: EmptyResponse = try await NetworkManager.shared.requestJSON(
                "/tasks/\(taskId)/confirm", body: EmptyResponse()
            )
            await reload()
        } catch { print("Confirm failed: \(error)") }
    }

    func report() async {
        do {
            struct ReportBody: Encodable { let targetType, reason: String; let targetId: Int }
            let _: EmptyResponse = try await NetworkManager.shared.requestJSON(
                "/reports",
                body: ReportBody(targetType: "task", reason: "inappropriate", targetId: taskId)
            )
        } catch { print("Report failed: \(error)") }
    }
}
