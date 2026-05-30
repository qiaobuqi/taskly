import SwiftUI
import Kingfisher

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var myTasks: [TaskItem] = []
    @State private var myJobs: [TaskItem] = []
    @State private var selectedTab = 0
    @State private var showWallet = false
    @State private var showVerification = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let user = authManager.currentUser {
                        profileHeader(user)
                    }

                    Divider()

                    // Quick actions
                    HStack(spacing: 0) {
                        QuickActionButton(icon: "creditcard", label: "Wallet") { showWallet = true }
                        Divider().frame(height: 40)
                        QuickActionButton(icon: "person.badge.shield.checkmark",
                                          label: "Verify",
                                          badge: authManager.currentUser?.verificationStatus == .none ? "!" : nil) {
                            showVerification = true
                        }
                        Divider().frame(height: 40)
                        QuickActionButton(icon: "star", label: "Reviews") {}
                    }

                    Divider()

                    Picker("", selection: $selectedTab) {
                        Text("My Tasks").tag(0)
                        Text("My Jobs").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    LazyVStack(spacing: 12) {
                        let items = selectedTab == 0 ? myTasks : myJobs
                        ForEach(items) { task in
                            NavigationLink(destination: TaskDetailView(task: task)) {
                                TaskCardView(task: task)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                        if items.isEmpty {
                            Text(selectedTab == 0 ? "No tasks posted yet" : "No jobs taken yet")
                                .foregroundStyle(.secondary).padding(.top, 40)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .task { await loadData() }
            .refreshable { await loadData() }
            .sheet(isPresented: $showWallet) { WalletView() }
            .sheet(isPresented: $showVerification) { VerificationView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    @ViewBuilder
    private func profileHeader(_ user: User) -> some View {
        VStack(spacing: 12) {
            KFImage(URL(string: user.avatar ?? ""))
                .placeholder {
                    Circle().fill(Color(.systemGray5))
                        .overlay(Image(systemName: "person.fill").font(.largeTitle).foregroundStyle(.gray))
                }
                .resizable().scaledToFill()
                .frame(width: 80, height: 80).clipShape(Circle())

            HStack(spacing: 6) {
                Text(user.nickname).font(.title2.bold())
                if user.isVerified {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue)
                }
            }

            if let bio = user.bio {
                Text(bio).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }

            HStack(spacing: 32) {
                StatView(value: "\(user.completedCount)", label: "Completed")
                StatView(value: String(format: "%.1f", user.rating), label: "Rating")
                StatView(value: user.skillTags.count > 0 ? "\(user.skillTags.count)" : "–", label: "Skills")
            }
        }
        .padding()
    }

    private func loadData() async {
        do {
            async let tasks: [TaskItem] = NetworkManager.shared.request("/users/me/tasks")
            async let jobs: [TaskItem] = NetworkManager.shared.request("/users/me/jobs")
            (myTasks, myJobs) = try await (tasks, jobs)
        } catch { print("Profile load failed: \(error)") }
    }
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    var badge: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon).font(.title2)
                    if let badge {
                        Text(badge)
                            .font(.caption2.bold()).foregroundStyle(.white)
                            .padding(3).background(.red).clipShape(Circle())
                            .offset(x: 8, y: -8)
                    }
                }
                Text(label).font(.caption)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .foregroundStyle(.primary)
    }
}

struct StatView: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    NavigationLink("Verification") { VerificationView() }
                    NavigationLink("Payment Methods") { Text("Payment Methods").padding() }
                }
                Section("Support") {
                    Link("Help Center", destination: URL(string: "https://taskly.app/help")!)
                    Link("Contact Us", destination: URL(string: "mailto:support@taskly.app")!)
                }
                Section {
                    Button("Sign Out", role: .destructive) {
                        authManager.logout()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
