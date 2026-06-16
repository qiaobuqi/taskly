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
            if !authManager.isLoggedIn {
                SignInPromptView(message: "Sign in to view your profile, tasks and wallet")
                    .navigationTitle("Profile")
            } else {
            ScrollView {
                VStack(spacing: Space.lg) {
                    if let user = authManager.currentUser {
                        profileHeader(user)
                    }

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
                    .cardSurface(padding: Space.sm)
                    .padding(.horizontal, Space.lg)

                    Picker("", selection: $selectedTab) {
                        Text("My Tasks").tag(0)
                        Text("My Jobs").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Space.lg)

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
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .task { await loadData() }
            .refreshable { await loadData() }
            .sheet(isPresented: $showWallet) { WalletView() }
            .sheet(isPresented: $showVerification) { VerificationView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            } // end else (logged in)
        }
    }

    @ViewBuilder
    private func profileHeader(_ user: User) -> some View {
        VStack(spacing: Space.md) {
            KFImage(URL(string: user.avatar ?? ""))
                .placeholder {
                    Circle().fill(.white.opacity(0.25))
                        .overlay(Image(systemName: "person.fill").font(.largeTitle).foregroundStyle(.white))
                }
                .resizable().scaledToFill()
                .frame(width: 88, height: 88).clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 3))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            HStack(spacing: 6) {
                Text(user.nickname).font(.title2.bold())
                if user.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                }
            }
            .foregroundStyle(.white)

            if let bio = user.bio {
                Text(bio).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }

            // Stats on a translucent strip for legibility over the gradient.
            HStack(spacing: 0) {
                headerStat("\(user.completedCount)", "Completed")
                Divider().frame(height: 32).overlay(.white.opacity(0.3))
                headerStat(String(format: "%.1f", user.rating), "Rating")
                Divider().frame(height: 32).overlay(.white.opacity(0.3))
                headerStat(user.skillTags.isEmpty ? "–" : "\(user.skillTags.count)", "Skills")
            }
            .padding(.vertical, Space.md)
            .background(.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .padding(.top, Space.xs)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity)
        .background(Brand.gradient)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .shadow(color: .brand.opacity(0.3), radius: 16, y: 8)
        .padding(.horizontal, Space.lg)
        .padding(.top, Space.sm)
    }

    private func headerStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
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
                    Image(systemName: icon).font(.title2).foregroundStyle(Color.brand)
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
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    NavigationLink("Verification") { VerificationView() }
                    NavigationLink("Payment Methods") { Text("Payment Methods").padding() }
                }
                Section("Legal") {
                    NavigationLink("Privacy Policy") {
                        WebView(url: Legal.privacyURL).ignoresSafeArea(edges: .bottom)
                            .navigationTitle("Privacy Policy").navigationBarTitleDisplayMode(.inline)
                    }
                    NavigationLink("Terms of Service") {
                        WebView(url: Legal.termsURL).ignoresSafeArea(edges: .bottom)
                            .navigationTitle("Terms of Service").navigationBarTitleDisplayMode(.inline)
                    }
                }
                Section("Support") {
                    Link("Contact Us", destination: URL(string: "mailto:luyutech@m.cnirv.com")!)
                }
                Section {
                    Button("Sign Out", role: .destructive) {
                        authManager.logout()
                        dismiss()
                    }
                }
                // Account deletion is required by App Store Guideline 5.1.1(v) for any
                // app that lets users create an account.
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        if isDeleting { ProgressView() } else { Text("Delete Account") }
                    }
                    .disabled(isDeleting)
                } footer: {
                    Text("Permanently deletes your account and personal data.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .alert("Delete Account?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        isDeleting = true
                        do {
                            try await authManager.deleteAccount()
                            dismiss()
                        } catch {
                            // Don't dismiss: the account still exists, so the user
                            // must see that the deletion failed.
                            deleteError = error.localizedDescription
                        }
                        isDeleting = false
                    }
                }
            } message: {
                Text("This permanently deletes your account and personal data. This cannot be undone.")
            }
            .alert("Couldn't Delete Account", isPresented: .init(
                get: { deleteError != nil }, set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }
}
