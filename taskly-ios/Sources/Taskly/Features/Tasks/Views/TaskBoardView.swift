import SwiftUI

extension Notification.Name {
    /// Posted after a task/service is created so open boards refresh immediately,
    /// instead of the user having to switch tabs to see their new post.
    static let tasksDidChange = Notification.Name("tasksDidChange")
}

struct TaskBoardView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var vm = TaskBoardViewModel()
    @State private var selectedTask: TaskItem?
    @State private var selectedService: ServiceCard?
    @State private var showPostChooser = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Task / Service segment
                Picker("Mode", selection: $vm.boardMode) {
                    Text("Tasks").tag(TaskBoardViewModel.BoardMode.tasks)
                    Text("Services").tag(TaskBoardViewModel.BoardMode.services)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // Category filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryChip(title: "All", isSelected: vm.selectedCategory == nil) {
                            vm.applyFilter(category: nil)
                        }
                        ForEach(TaskCategory.allCases, id: \.self) { cat in
                            CategoryChip(icon: cat.icon, title: cat.displayName,
                                         isSelected: vm.selectedCategory == cat) {
                                vm.applyFilter(category: cat)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                Divider()

                // Sort bar
                HStack {
                    Text(vm.boardMode == .tasks
                         ? "\(vm.tasks.count) task\(vm.tasks.count == 1 ? "" : "s")"
                         : "\(vm.services.count) service\(vm.services.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(TaskBoardViewModel.SortOption.allCases, id: \.self) { opt in
                            Button(opt.displayName) { vm.applySort(opt) }
                        }
                    } label: {
                        Label(vm.sortBy.displayName, systemImage: "arrow.up.arrow.down")
                            .font(.caption)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                // Content
                if vm.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if vm.boardMode == .tasks {
                    taskList
                } else {
                    serviceList
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .overlay(alignment: .bottomTrailing) {
                // Floating "create" button — the mainstream place for a primary
                // create action (Airtasker / Gmail), instead of a middle tab.
                Button {
                    Analytics.shared.track("post_tapped")
                    // Posting requires an account — prompt login for guests.
                    if authManager.isLoggedIn { showPostChooser = true } else { router.showLogin = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.brand, in: Circle())
                        .shadow(color: .brand.opacity(0.45), radius: 12, y: 6)
                }
                .padding(.trailing, Space.lg)
                .padding(.bottom, Space.lg)
                .accessibilityLabel("Post a task or service")
            }
            .confirmationDialog("What do you want to post?", isPresented: $showPostChooser, titleVisibility: .visible) {
                Button("Post a Task") {
                    Analytics.shared.track("post_choose", ["type": "task"])
                    router.showPostTask = true
                }
                Button("Offer a Service") {
                    Analytics.shared.track("post_choose", ["type": "service"])
                    router.showPostService = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .navigationTitle("Taskly")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.load() }
            .onChange(of: vm.boardMode) { _, _ in Task { await vm.load() } }
            .onReceive(NotificationCenter.default.publisher(for: .tasksDidChange)) { _ in
                Task { await vm.load() }
            }
            .navigationDestination(item: $selectedTask) { TaskDetailView(task: $0) }
            .navigationDestination(item: $selectedService) { ServiceCardDetailView(service: $0) }
        }
    }

    private var taskList: some View {
        Group {
            if vm.tasks.isEmpty {
                ContentUnavailableView("No tasks yet", systemImage: "list.bullet.clipboard")
            } else {
                List(vm.tasks) { task in
                    // A Button (not .onTapGesture) is used here on purpose: inside a
                    // List, row tap handling swallows a bare .onTapGesture, so cards
                    // appeared dead and never navigated. Button taps register reliably.
                    Button { selectedTask = task } label: {
                        TaskCardView(task: task)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await vm.load() }
            }
        }
    }

    private var serviceList: some View {
        Group {
            if vm.services.isEmpty {
                ContentUnavailableView("No services yet", systemImage: "person.badge.shield.checkmark")
            } else {
                List(vm.services) { service in
                    Button { selectedService = service } label: {
                        ServiceCardView(service: service)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await vm.load() }
            }
        }
    }
}

struct CategoryChip: View {
    var icon: String? = nil
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.caption) }
                Text(title).font(.subheadline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isSelected ? Color.brand : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}
