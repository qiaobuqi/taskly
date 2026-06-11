import SwiftUI
import Kingfisher

struct TaskDetailView: View {
    let task: TaskItem
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var router: AppRouter
    @Environment(\.dismiss) private var dismiss
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
                            .font(.title.bold()).foregroundStyle(Color.brand)
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
        .sheet(isPresented: $showReport) {
            ModerationSheet(
                subject: "user",
                onReport: { await vm.report() },
                // Only non-owners can block the publisher; hide it on your own task.
                onBlock: (!isOwner && currentTask.publisher != nil)
                    ? { await vm.blockPublisher(); dismiss() }
                    : nil
            )
        }
        .task { await vm.reload() }
        .onAppear {
            Analytics.shared.track("task_open",
                ["task_id": currentTask.id, "category": currentTask.category.rawValue])
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        let status = currentTask.status
        // Only render the bar when there's actually an action for this user/status,
        // so we don't leave an empty floating bar (e.g. owner viewing an open task).
        if hasAction(status) {
            HStack(spacing: Space.md) {
                // Non-owner: message + apply
                if !isOwner && !isAssignee && status == .open {
                    Button {
                        if authManager.isLoggedIn { showChat = true } else { router.showLogin = true }
                    } label: {
                        Label("Message", systemImage: "bubble.left")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button {
                        // Applying requires an account — prompt login for guests.
                        guard authManager.isLoggedIn else { router.showLogin = true; return }
                        Analytics.shared.track("apply_open", ["task_id": currentTask.id])
                        showApply = true
                    } label: { Text("Apply Now") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                // Owner: pay to start (after accepting applicant)
                if isOwner && status == .inProgress {
                    Button {
                        Analytics.shared.track("pay_open", ["task_id": currentTask.id, "amount": currentTask.budget])
                        showPayment = true
                    } label: { Text("Pay & Confirm") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                // Assignee: mark complete
                if isAssignee && status == .inProgress {
                    Button { showCompletion = true } label: { Text("Mark Complete") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                // Owner: confirm completion
                if isOwner && status == .pendingConfirm {
                    Button { Task { await vm.confirmCompletion() } } label: { Text("Confirm & Release Payment") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                // Both: leave review — amber so it reads as a distinct, optional action.
                if (isOwner || isAssignee) && status == .completed {
                    Button { showReview = true } label: { Text("Leave Review") }
                        .buttonStyle(PrimaryButtonStyle(tint: .orange))
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .background(.ultraThinMaterial)
        }
    }

    private func hasAction(_ status: TaskStatus) -> Bool {
        (!isOwner && !isAssignee && status == .open)
        || (isOwner && status == .inProgress)
        || (isAssignee && status == .inProgress)
        || (isOwner && status == .pendingConfirm)
        || ((isOwner || isAssignee) && status == .completed)
    }
}

// MARK: - Shared Components

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline)
            }
            Spacer()
        }
    }
}

struct UserRowView: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            KFImage(URL(string: user.avatar ?? ""))
                .placeholder { Circle().fill(Color(.systemGray5)) }
                .resizable().scaledToFill()
                .frame(width: 40, height: 40).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(user.nickname).font(.subheadline.bold())
                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.blue)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    Text(String(format: "%.1f", user.rating)).font(.caption)
                    Text("· \(user.completedCount) completed").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: TaskStatus
    var body: some View { StatusChip(status: status) }
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
                    .font(.subheadline.bold()).foregroundStyle(Color.brand)
                Spacer()
                if application.status == .pending {
                    Button("Accept", action: onAccept)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Color.brand).foregroundStyle(.white)
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

    /// Block the task's publisher. Files a report (notifying the developer) and
    /// hides their content from this user's feed immediately (Guideline 1.2).
    func blockPublisher() async {
        guard let publisherId = task?.publisher?.id ?? task?.publisherId else { return }
        do {
            struct BlockBody: Encodable { let blockedId: Int; let reason: String }
            let _: EmptyResponse = try await NetworkManager.shared.requestJSON(
                "/blocks",
                body: BlockBody(blockedId: publisherId, reason: "blocked from task detail")
            )
            NotificationCenter.default.post(name: .tasksDidChange, object: nil)
        } catch { print("Block failed: \(error)") }
    }
}
