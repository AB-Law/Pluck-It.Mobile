import SwiftUI

struct CollectionsView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var collections: [Collection] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var isCreating = false
    @State private var query = ""
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var newIsPublic = false
    @State private var selectedCollection: Collection?
    @State private var collectionToDelete: Collection?

    private var filteredCollections: [Collection] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return collections
        }
        return collections.filter { collection in
            [collection.name, collection.description]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
                .contains(normalized)
        }
    }

    private var totalItems: Int {
        selectedCollection?.clothingItemIds?.count
            ?? selectedCollection?.itemIds?.count
            ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
                    controls
                        .pluckReveal(delay: 0.02)

                    if let errorText {
                        stateError(errorText)
                            .pluckReveal()
                    } else if loading && filteredCollections.isEmpty {
                        stateLoading()
                            .pluckReveal()
                    } else if filteredCollections.isEmpty {
                        emptyState
                            .pluckReveal()
                    } else {
                        collectionGrid
                            .pluckReveal()

                        if let selected = selectedCollection {
                            selectionDetails(for: selected)
                                .pluckReveal()
                        }
                    }
                }
                .padding(.horizontal, PluckTheme.Spacing.md)
                .padding(.vertical, PluckTheme.Spacing.sm)
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        pluckImpactFeedback()
                        isCreating = true
                    } label: {
                        Label("New", systemImage: "plus")
                            .foregroundStyle(PluckTheme.primaryText)
                    }
                }
            }
            .task {
                await loadCollections()
            }
            .refreshable {
                await loadCollections()
            }
            .shellToolbar()
            .scrollContentBackground(.hidden)
            .alert("Delete collection", isPresented: Binding(
                get: { collectionToDelete != nil },
                set: { if !$0 { collectionToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) {
                    collectionToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    guard let collectionToDelete else { return }
                    Task {
                        await deleteCollection(collectionToDelete)
                        self.collectionToDelete = nil
                    }
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .sheet(isPresented: $isCreating, onDismiss: {
                newName = ""
                newDescription = ""
                newIsPublic = false
            }) {
                createCollectionSheet
            }
        }
    }

    private var controls: some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            HStack(spacing: PluckTheme.Spacing.sm) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(PluckTheme.secondaryText)
                    TextField("Search collections", text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .submitLabel(.search)
                        .onSubmit {
                            pluckImpactFeedback(.light)
                            Task { await loadCollections() }
                        }
                }
                .padding(10)
                .background(PluckTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))

                Menu {
                    Button("All") {
                        query = ""
                        pluckImpactFeedback()
                        Task { await loadCollections() }
                    }
                    Button("Public only") {
                        query = "public"
                        pluckImpactFeedback()
                        Task { await loadCollections(query: "public") }
                    }
                    Button("Private only") {
                        query = "private"
                        pluckImpactFeedback()
                        Task { await loadCollections(query: "private") }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                        .frame(width: PluckTheme.Control.rowHeight, height: PluckTheme.Control.rowHeight)
                        .background(PluckTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                        .foregroundStyle(PluckTheme.primaryText)
                }
            }

        }
    }

    private var collectionGrid: some View {
        LazyVStack(spacing: PluckTheme.Spacing.sm) {
            ForEach(Array(filteredCollections.enumerated()), id: \.element.id) { index, collection in
                collectionCard(for: collection)
                    .pluckReveal(delay: min(Double(index) * 0.03, 0.28))
                    .onTapGesture {
                        pluckImpactFeedback(.light)
                        withAnimation {
                            selectedCollection = collection
                        }
                    }
            }
        }
    }

    private func collectionCard(for collection: Collection) -> some View {
        HStack(spacing: PluckTheme.Spacing.sm) {
            if let image = normalizedImageURL(collection.imageUrl) {
                AsyncImage(url: image) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                            .fill(PluckTheme.card)
                            .overlay(ProgressView().tint(PluckTheme.primaryText))
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderThumb(label: collection.name)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 64, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
            } else {
                placeholderThumb(label: collection.name)
            }

            VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
                Text(collection.name.isEmpty ? "Untitled collection" : collection.name)
                    .font(.headline)
                    .foregroundStyle(PluckTheme.primaryText)
                if let description = collection.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                        .lineLimit(2)
                } else {
                    Text("No description")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.mutedText)
                }

                HStack(spacing: PluckTheme.Spacing.xs) {
                    Text(collection.isPublic ? "Public" : "Private")
                        .font(.caption2)
                        .foregroundStyle(collection.isPublic ? PluckTheme.success : PluckTheme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(collection.isPublic ? PluckTheme.success.opacity(0.2) : PluckTheme.card)
                        )

                    if let memberCount = collection.memberUserIds?.count {
                        Text("\(memberCount) members")
                            .font(.caption2)
                            .foregroundStyle(PluckTheme.secondaryText)
                    }

                    Spacer()

                    let itemCount = collection.clothingItemIds?.count ?? collection.itemIds?.count ?? 0
                    Text("\(itemCount) items")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.secondaryText)
                }
            }
            .padding(.vertical, PluckTheme.Spacing.xs)

            if selectedCollection?.id == collection.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(PluckTheme.success)
            }
        }
        .padding(PluckTheme.Spacing.md)
        .background(PluckTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
        .overlay {
            if selectedCollection?.id == collection.id {
                RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                    .stroke(PluckTheme.info, lineWidth: 1)
            }
            else {
                RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                    .stroke(PluckTheme.border, lineWidth: 0.7)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: selectedCollection)
    }

    private func placeholderThumb(label: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                .fill(PluckTheme.card)
            VStack(spacing: 4) {
                Image(systemName: "folder")
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(PluckTheme.secondaryText)
            .padding(6)
        }
        .frame(width: 64, height: 80)
    }

    private func selectionDetails(for collection: Collection) -> some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
            Text("Collection details")
                .font(.headline)
                .foregroundStyle(PluckTheme.primaryText)

            VStack(spacing: PluckTheme.Spacing.sm) {
                HStack {
                    Text("Status")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                    Spacer()
                    Text(collection.isPublic ? "Public" : "Private")
                        .font(.caption)
                        .foregroundStyle(collection.isPublic ? PluckTheme.success : PluckTheme.secondaryText)
                }

                HStack {
                    Text("Items")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                    Spacer()
                    Text(String(totalItems))
                        .font(.caption)
                        .foregroundStyle(PluckTheme.primaryText)
                }

                if let createdAt = collection.createdAt {
                    HStack {
                        Text("Created")
                            .font(.caption)
                            .foregroundStyle(PluckTheme.secondaryText)
                        Spacer()
                        Text(createdAt)
                            .font(.caption)
                            .foregroundStyle(PluckTheme.primaryText)
                    }
                }

                HStack {
                    Text("Action")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                    Spacer()
                    Button("Focus") {
                        selectedCollection = collection
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)

                    Button("Delete") {
                        collectionToDelete = collection
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .tint(PluckTheme.danger)
                    .disabled(loading)
                }
            }
            .padding(PluckTheme.Spacing.md)
            .background(PluckTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
        }
    }

    private var emptyState: some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            Image(systemName: "folder")
                .font(.title)
                .foregroundStyle(PluckTheme.mutedText)
            Text("No collections found")
                .font(.headline)
                .foregroundStyle(PluckTheme.primaryText)
            Text("Tap + to create one")
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)

            Button("Create collection") {
                pluckImpactFeedback()
                isCreating = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private var createCollectionSheet: some View {
        NavigationStack {
            Form {
                Section("Collection") {
                    TextField("Name", text: $newName)
                        .textInputAutocapitalization(.words)
                    TextField("Description", text: $newDescription)
                        .textInputAutocapitalization(.sentences)
                }

                Toggle("Public", isOn: $newIsPublic)

                Section {
                    Button("Create") {
                        pluckImpactFeedback()
                        Task {
                            await createCollection()
                            isCreating = false
                        }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(PluckTheme.danger)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        pluckImpactFeedback()
                        isCreating = false
                    }
                }
            }
        }
    }

    private func stateLoading() -> some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            ProgressView("Loading collections")
                .foregroundStyle(PluckTheme.secondaryText)
            HStack {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                        .fill(PluckTheme.card)
                        .frame(height: 84)
                        .overlay(ProgressView().tint(PluckTheme.primaryText))
                }
            }
        }
        .padding(.vertical, PluckTheme.Spacing.md)
        .frame(maxWidth: .infinity)
    }

    private func stateError(_ message: String) -> some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            Text("Could not read collections")
                .foregroundStyle(PluckTheme.danger)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadCollections() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private func loadCollections(query: String? = nil) async {
        guard !loading else { return }
        loading = true
        errorText = nil
        do {
            let trimmed = (query ?? self.query).trimmingCharacters(in: .whitespacesAndNewlines)
            collections = try await appServices.collectionService.fetchCollections(query: trimmed.isEmpty ? nil : trimmed)
            if let selected = selectedCollection, !collections.contains(selected) {
                selectedCollection = nil
            }
        } catch {
            if !isCancelledError(error) {
                errorText = String(describing: error)
            }
        }
        loading = false
    }

    private func isCancelledError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError { return urlError.code == .cancelled }
        return false
    }

    private func createCollection() async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let request = CreateCollectionRequest(
                name: trimmed,
                isPublic: newIsPublic,
                description: newDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : newDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                clothingItemIds: []
            )
            let created = try await appServices.collectionService.createCollection(request)
            selectedCollection = created
            await loadCollections()
            await MainActor.run {
                newName = ""
                newDescription = ""
                newIsPublic = false
            }
        } catch {
            errorText = String(describing: error)
        }
    }

    private func deleteCollection(_ collection: Collection) async {
        do {
            try await appServices.collectionService.deleteCollection(collection.id)
            await loadCollections()
            if selectedCollection?.id == collection.id {
                selectedCollection = nil
            }
        } catch {
            errorText = String(describing: error)
        }
    }
}
