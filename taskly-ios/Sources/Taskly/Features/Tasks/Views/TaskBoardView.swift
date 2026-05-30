import SwiftUI

struct TaskBoardView: View {
    @StateObject private var vm = TaskBoardViewModel()
    @State private var selectedTask: TaskItem?
    @State private var selectedService: ServiceCard?

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
                         ? "\(vm.tasks.count) tasks"
                         : "\(vm.services.count) services")
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
            .navigationTitle("Taskly")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.load() }
            .onChange(of: vm.boardMode) { _, _ in Task { await vm.load() } }
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
                    TaskCardView(task: task)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .onTapGesture { selectedTask = task }
                }
                .listStyle(.plain)
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
                    ServiceCardView(service: service)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .onTapGesture { selectedService = service }
                }
                .listStyle(.plain)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}
