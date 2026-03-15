import PhotosUI
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \ListDocument.updatedAt, order: .reverse) private var lists: [ListDocument]
    @State private var searchText = ""
    @State private var showingCreateSheet = false
    @State private var sharingMessage: ShareMessage?
    @State private var navigationPath: [UUID] = []
    @State private var showingStarterSets = false
    @State private var showingFeatures = false

    private let libraryService = ListLibraryService()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.97, green: 0.98, blue: 0.94), Color(red: 0.88, green: 0.95, blue: 0.97)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if filteredLists.isEmpty {
                    EmptyLibraryView {
                        showingCreateSheet = true
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(filteredLists) { list in
                                NavigationLink(value: list.id) {
                                    LibraryCard(list: list)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Duplicate") {
                                        _ = libraryService.duplicate(list, in: modelContext)
                                    }
                                    Button("Share") {
                                        sharingMessage = ShareMessage(text: appState.shareCodec.shareMessage(for: list))
                                    }
                                    Button("Delete", role: .destructive) {
                                        deleteList(list)
                                    }
                                }
                                .swipeActions {
                                    Button {
                                        sharingMessage = ShareMessage(text: appState.shareCodec.shareMessage(for: list))
                                    } label: {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    .tint(.blue)

                                    Button {
                                        _ = libraryService.duplicate(list, in: modelContext)
                                    } label: {
                                        Label("Duplicate", systemImage: "plus.square.on.square")
                                    }
                                    .tint(.orange)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("So Many Lists")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        Button {
                            showingCreateSheet = true
                        } label: {
                            Label("Create", systemImage: "sparkles")
                        }

                        Button {
                            showingStarterSets = true
                        } label: {
                            Label("Starter Sets", systemImage: "square.stack.3d.up")
                        }

                        Button {
                            showingFeatures = true
                        } label: {
                            Label("Features", systemImage: "rectangle.grid.1x2")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Quick List", systemImage: "plus.circle.fill") {
                        ForEach(ListKind.allCases) { kind in
                            Button(kind.title, systemImage: kind.iconName) {
                                let draft = GeneratedListDraft(
                                    title: kind.title,
                                    kind: kind,
                                    summary: "A manually created \(kind.title.lowercased()) list.",
                                    prompt: "",
                                    sections: [SectionDraft(title: kind.emptySectionTitle, entries: [])],
                                    sourceKind: .manual
                                )
                                let document = ListDocument.fromDraft(draft)
                                modelContext.insert(document)
                                navigationPath.append(document.id)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search lists")
            .sheet(isPresented: $showingCreateSheet) {
                CreateListFlow { draft in
                    let document = ListDocument.fromDraft(draft)
                    modelContext.insert(document)
                    navigationPath.append(document.id)
                }
            }
            .sheet(isPresented: $showingStarterSets) {
                StarterSetLibraryView()
            }
            .sheet(isPresented: $showingFeatures) {
                FeaturesGuideView()
                    .environmentObject(appState)
            }
            .sheet(item: $appState.pendingImport) { payload in
                ImportPreviewSheet(payload: payload) { draft in
                    let document = ListDocument.fromDraft(draft)
                    modelContext.insert(document)
                    appState.pendingImport = nil
                    navigationPath.append(document.id)
                } onDismiss: {
                    appState.pendingImport = nil
                }
            }
            .sheet(item: $sharingMessage) { message in
                ShareSheet(items: [message.text])
            }
            .alert("Import Error", isPresented: Binding(
                get: { appState.importErrorMessage != nil },
                set: { if !$0 { appState.importErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(appState.importErrorMessage ?? "")
            }
            .navigationDestination(for: UUID.self) { id in
                if let document = lists.first(where: { $0.id == id }) {
                    ListDetailView(document: document) {
                        navigationPath.removeAll()
                    }
                } else {
                    Color.clear
                        .onAppear {
                            navigationPath.removeAll()
                        }
                }
            }
        }
    }

    private var filteredLists: [ListDocument] {
        guard !searchText.isEmpty else { return lists }
        return lists.filter { list in
            list.title.localizedCaseInsensitiveContains(searchText) ||
            list.listSummary.localizedCaseInsensitiveContains(searchText) ||
            list.sortedSections.flatMap(\.sortedEntries).contains { entry in
                entry.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private func deleteList(_ list: ListDocument) {
        navigationPath.removeAll { $0 == list.id }
        modelContext.delete(list)
    }

}

private struct ShareMessage: Identifiable {
    let id = UUID()
    let text: String
}

private struct IntelligenceComposerState {
    var prompt = ""
    var voiceTranscript = ""
    var attachments: [MediaAttachment] = []
    var photoItems: [PhotosPickerItem] = []
    var isGenerating = false
    var errorMessage: String?
    var showingCamera = false
    var showingVoiceSheet = false
}

private struct AppleIntelligenceDisclosureSection<Content: View>: View {
    let title: String
    let availability: AppleIntelligenceAvailability
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                if availability.isAvailable {
                    content
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(availability.message ?? "Apple Intelligence is unavailable right now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("You can still edit this list manually on this device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            } label: {
                HStack {
                    Label(title, systemImage: availability.isAvailable ? "sparkles" : "sparkles.slash")
                    Spacer()
                    Text(availability.isAvailable ? "Available" : "Unavailable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(availability.isAvailable ? Color.secondary : Color.orange)
                }
            }
        }
    }

}

private struct EmptyLibraryView: View {
    let createAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 54))
                .foregroundStyle(.teal)
            Text("Start with less typing.")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Generate a grocery run, packing list, or travel plan in one pass, then edit everything locally.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Create Your First List", action: createAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(28)
    }
}

private struct LibraryCard: View {
    let list: ListDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(list.kind.title, systemImage: list.kind.iconName)
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(color.opacity(0.12)))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text(list.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            if !list.listSummary.isEmpty {
                Text(list.listSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Updated \(list.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
    }

    private var color: Color {
        switch list.kind {
        case .general: .teal
        case .grocery: .green
        case .packing: .orange
        case .tripPlan: .blue
        }
    }
}

private struct AnnouncementCard: View {
    let tile: AnnouncementTile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: tile.symbolName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(color)
                Spacer()
                Text("Announcement")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Text(tile.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(tile.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tile.badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(color.opacity(0.12)))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }

    private var color: Color {
        switch tile.accentName {
        case "orange": .orange
        case "blue": .blue
        case "green": .green
        default: .teal
        }
    }
}

private struct FeaturesGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(AnnouncementCatalog.tiles) { tile in
                        VStack(alignment: .leading, spacing: 10) {
                            AnnouncementCard(tile: tile)
                            Text(tile.detailTitle)
                                .font(.headline)
                            Text(tile.detailBody)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button(appState.dismissedAnnouncementIDs.contains(tile.id) ? "Show On Home" : "Hide On Home") {
                                if appState.dismissedAnnouncementIDs.contains(tile.id) {
                                    appState.restoreAnnouncement(id: tile.id)
                                } else {
                                    appState.dismissAnnouncement(id: tile.id)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Features")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct IntelligenceComposerSection: View {
    let title: String
    @Binding var prompt: String
    @Binding var voiceTranscript: String
    @Binding var attachments: [MediaAttachment]
    @Binding var photoItems: [PhotosPickerItem]
    let isGenerating: Bool
    @Binding var showingCamera: Bool
    @Binding var showingVoiceSheet: Bool
    let promptLabel: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        Group {
            if title.isEmpty {
                content
            } else {
                Section(title) {
                    content
                }
            }
        }
    }

    private var content: some View {
        Group {
            TextField(promptLabel, text: $prompt, axis: .vertical)
                .lineLimit(3...6)
            if !voiceTranscript.isEmpty {
                LabeledContent("Voice Prompt") {
                    Text(voiceTranscript)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            PhotosPicker(selection: $photoItems, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                Label("Import Photos or Videos", systemImage: "photo.on.rectangle.angled")
            }
            Button("Capture with Camera", systemImage: "camera.fill") {
                showingCamera = true
            }
            Button("Record Voice Prompt", systemImage: "waveform.circle.fill") {
                showingVoiceSheet = true
            }
            if !attachments.isEmpty {
                ForEach(attachments) { attachment in
                    Label(attachment.summary, systemImage: icon(for: attachment.kind))
                        .font(.subheadline)
                }
                .onDelete { offsets in
                    attachments.remove(atOffsets: offsets)
                }
            }
            Button(action: action) {
                if isGenerating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label(actionTitle, systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isGenerating)
        }
    }

    private func icon(for kind: MediaKind) -> String {
        switch kind {
        case .photo: "photo"
        case .video: "video"
        case .cameraPhoto: "camera"
        }
    }
}

private struct CreateListFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StarterSetDocument.updatedAt, order: .reverse) private var starterSetDocuments: [StarterSetDocument]
    @State private var kind: ListKind = .general
    @State private var prompt = ""
    @State private var voiceTranscript = ""
    @State private var attachments: [MediaAttachment] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var generatedDraft: GeneratedListDraft?
    @State private var errorMessage: String?
    @State private var isGenerating = false
    @State private var showingCamera = false
    @State private var showingVoiceSheet = false
    @State private var selectedStarterSetIDs: Set<String> = []
    @State private var appleIntelligenceAvailability = AppleIntelligenceAvailability.current()

    let onSave: (GeneratedListDraft) -> Void
    private let generator = PreferredListGenerationService()
    private let starterSetService = StaticListSetService()

    var body: some View {
        NavigationStack {
            Form {
                Section("List Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(ListKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.iconName).tag(kind)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("What should the list do?") {
                    TextField("Describe the list you want", text: $prompt, axis: .vertical)
                        .lineLimit(4...8)
                    if !voiceTranscript.isEmpty {
                        LabeledContent("Voice Prompt") {
                            Text(voiceTranscript)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                starterSetSection

                Section("Add context") {
                    PhotosPicker(selection: $photoItems, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                        Label("Import Photos or Videos", systemImage: "photo.on.rectangle.angled")
                    }
                    Button("Capture with Camera", systemImage: "camera.fill") {
                        showingCamera = true
                    }
                    Button("Record Voice Prompt", systemImage: "waveform.circle.fill") {
                        showingVoiceSheet = true
                    }
                    if !attachments.isEmpty {
                        ForEach(attachments) { attachment in
                            Label(attachment.summary, systemImage: icon(for: attachment.kind))
                                .font(.subheadline)
                        }
                        .onDelete { offsets in
                            attachments.remove(atOffsets: offsets)
                        }
                    }
                }

                actionSection

                if let generatedDraft {
                    Section("Preview") {
                        DraftPreview(draft: generatedDraft)
                        Button("Save List") {
                            onSave(generatedDraft)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Create List")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                appleIntelligenceAvailability = AppleIntelligenceAvailability.current()
            }
            .onChange(of: kind) { _, newKind in
                let validIDs = Set(starterSetDocuments.filter { $0.kind == newKind }.map { $0.id.uuidString })
                selectedStarterSetIDs = selectedStarterSetIDs.intersection(validIDs)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: photoItems) {
                await importSelectedItems()
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker { _ in
                    attachments.append(MediaAttachment(kind: .cameraPhoto, summary: "Live camera photo"))
                }
            }
            .sheet(isPresented: $showingVoiceSheet) {
                VoiceCaptureSheet(transcript: $voiceTranscript)
            }
            .alert("Could Not Generate", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func importSelectedItems() async {
        for item in photoItems {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let kind: MediaKind = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) ? .video : .photo
                attachments.append(MediaAttachment(kind: kind, summary: "\(kind.title) import (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"))
            }
        }
        photoItems.removeAll()
    }

    private func generateDraft() async {
        isGenerating = true
        defer { isGenerating = false }

        do {
            generatedDraft = try await generator.generate(
                request: ListGenerationRequest(
                    prompt: prompt,
                    kind: kind,
                    voiceTranscript: voiceTranscript,
                    attachments: attachments,
                    starterSets: selectedStarterSets
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var availableStarterSets: [StaticListSet] {
        starterSetDocuments
            .filter { $0.kind == kind }
            .map { $0.makeStaticListSet() }
    }

    private var selectedStarterSets: [StaticListSet] {
        availableStarterSets.filter { selectedStarterSetIDs.contains($0.id) }
    }

    @ViewBuilder
    private var starterSetSection: some View {
        if !availableStarterSets.isEmpty {
            Section("Starter Sets") {
                ForEach(availableStarterSets) { set in
                    starterSetRow(for: set)
                }
            }
        }
    }

    private func starterSetRow(for set: StaticListSet) -> some View {
        Button {
            toggle(set)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedStarterSetIDs.contains(set.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedStarterSetIDs.contains(set.id) ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(set.title)
                        .foregroundStyle(.primary)
                    Text(set.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var actionSection: some View {
        Section {
            if !appleIntelligenceAvailability.isAvailable {
                Label {
                    Text(appleIntelligenceAvailability.message ?? "Apple Intelligence is unavailable right now.")
                } icon: {
                    Image(systemName: "sparkles.slash")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Button {
                Task { await generateDraft() }
            } label: {
                if isGenerating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Generate Draft", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isGenerating || !appleIntelligenceAvailability.isAvailable)

            Button("Create Empty \(kind.title) List") {
                onSave(emptyDraft())
                dismiss()
            }
        }
    }

    private func emptyDraft() -> GeneratedListDraft {
        starterSetService.merge(selectedStarterSets, into: GeneratedListDraft(
            title: kind.title,
            kind: kind,
            summary: "A manually created \(kind.title.lowercased()) list.",
            prompt: prompt,
            sections: [SectionDraft(title: kind.emptySectionTitle, entries: [])],
            sourceKind: .manual
        ))
    }

    private func toggle(_ set: StaticListSet) {
        if selectedStarterSetIDs.contains(set.id) {
            selectedStarterSetIDs.remove(set.id)
        } else {
            selectedStarterSetIDs.insert(set.id)
        }
    }

    private func icon(for kind: MediaKind) -> String {
        switch kind {
        case .photo: "photo"
        case .video: "video"
        case .cameraPhoto: "camera"
        }
    }
}

private struct DraftPreview: View {
    let draft: GeneratedListDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.title)
                .font(.headline)
            Text(draft.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(draft.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title)
                        .font(.subheadline.bold())
                    ForEach(section.entries) { entry in
                        Text("• \(entry.title)")
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct VoiceCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var transcript: String
    @StateObject private var viewModel = VoiceCaptureViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Speak your list prompt")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(viewModel.transcript.isEmpty ? "Tap record and describe what you need." : viewModel.transcript)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 24).fill(Color(.secondarySystemBackground)))
                Button {
                    viewModel.toggle()
                } label: {
                    Label(viewModel.isRecording ? "Stop Recording" : "Start Recording", systemImage: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Voice Prompt")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        viewModel.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use Transcript") {
                        transcript = viewModel.transcript
                        viewModel.stop()
                        dismiss()
                    }
                    .disabled(viewModel.transcript.isEmpty)
                }
            }
        }
    }
}

private struct ImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let payload: SharedListPayload
    let onImport: (GeneratedListDraft) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Import Shared List")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Preview the list before saving it as a new local copy.")
                        .foregroundStyle(.secondary)
                    DraftPreview(draft: payload.draft)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 24).fill(Color(.secondarySystemBackground)))
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") {
                        var draft = payload.draft
                        draft.id = UUID()
                        draft.title = "\(draft.title) Imported"
                        draft.sections = draft.sections.map { section in
                            SectionDraft(
                                id: UUID(),
                                title: section.title,
                                entries: section.entries.map { entry in
                                    var importedEntry = entry
                                    importedEntry.id = UUID()
                                    return importedEntry
                                }
                            )
                        }
                        onImport(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ListDetailView: View {
    @Bindable var document: ListDocument
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \StarterSetDocument.updatedAt, order: .reverse) private var starterSetDocuments: [StarterSetDocument]
    @State private var shareMessage: ShareMessage?
    @State private var newSectionTitle = ""
    @State private var intelligence = IntelligenceComposerState()
    @State private var aiSectionExpanded = AppleIntelligenceAvailability.current().isAvailable
    @State private var appleIntelligenceAvailability = AppleIntelligenceAvailability.current()
    private let starterSetService = StaticListSetService()
    private let generator = PreferredListGenerationService()
    var onDelete: () -> Void = {}

    var body: some View {
        List {
            summarySection
            aiAssistSection
            ForEach(document.sortedSections) { section in
                Section {
                    ForEach(section.sortedEntries) { entry in
                        EntryRow(entry: entry) {
                            document.touch()
                        }
                    }
                    .onDelete { offsets in
                        deleteEntries(in: section, offsets: offsets)
                    }

                    Button("Add Item", systemImage: "plus") {
                        addEntry(to: section)
                    }
                    .font(.subheadline.weight(.semibold))
                } header: {
                    TextField("Section Title", text: Binding(
                        get: { section.title },
                        set: { section.title = $0; document.touch() }
                    ))
                    .textInputAutocapitalization(.words)
                }
            }

            Section("Add Section") {
                TextField("New section", text: $newSectionTitle)
                Button("Add Section") {
                    addSection()
                }
                .disabled(newSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(availableStarterSets) { set in
                        Button("Apply \(set.title)", systemImage: "square.stack.3d.up.fill") {
                            starterSetService.apply(set, to: document)
                        }
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        _ = ListLibraryService().duplicate(document, in: modelContext)
                    }
                    Button("Share", systemImage: "square.and.arrow.up") {
                        shareMessage = ShareMessage(text: appState.shareCodec.shareMessage(for: document))
                    }
                    Button("Delete List", role: .destructive) {
                        onDelete()
                        modelContext.delete(document)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $shareMessage) { message in
            ShareSheet(items: [message.text])
        }
        .sheet(isPresented: $intelligence.showingCamera) {
            CameraPicker { _ in
                intelligence.attachments.append(MediaAttachment(kind: .cameraPhoto, summary: "Live camera photo"))
            }
        }
        .sheet(isPresented: $intelligence.showingVoiceSheet) {
            VoiceCaptureSheet(transcript: $intelligence.voiceTranscript)
        }
        .task(id: intelligence.photoItems) {
            await importSelectedItems()
        }
        .task {
            appleIntelligenceAvailability = AppleIntelligenceAvailability.current()
            aiSectionExpanded = appleIntelligenceAvailability.isAvailable
        }
        .alert("Could Not Generate", isPresented: Binding(
            get: { intelligence.errorMessage != nil },
            set: { if !$0 { intelligence.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(intelligence.errorMessage ?? "")
        }
    }

    private var summarySection: some View {
        Section {
            TextField("List Title", text: $document.title)
                .font(.headline)
                .onChange(of: document.title) { _, _ in document.touch() }
            TextField("Summary", text: $document.listSummary, axis: .vertical)
                .lineLimit(2...4)
                .onChange(of: document.listSummary) { _, _ in document.touch() }
            HStack {
                Label(document.kind.title, systemImage: document.kind.iconName)
                Spacer()
                Text("\(document.outstandingCount) open")
                    .foregroundStyle(.secondary)
            }
            if !availableStarterSets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableStarterSets) { set in
                            Button(set.title) {
                                starterSetService.apply(set, to: document)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var aiAssistSection: some View {
        AppleIntelligenceDisclosureSection(
            title: "Apple Intelligence",
            availability: appleIntelligenceAvailability,
            isExpanded: $aiSectionExpanded,
            content: {
                IntelligenceComposerSection(
                    title: "",
                    prompt: $intelligence.prompt,
                    voiceTranscript: $intelligence.voiceTranscript,
                    attachments: $intelligence.attachments,
                    photoItems: $intelligence.photoItems,
                    isGenerating: intelligence.isGenerating,
                    showingCamera: $intelligence.showingCamera,
                    showingVoiceSheet: $intelligence.showingVoiceSheet,
                    promptLabel: "Describe what to add to this list",
                    actionTitle: "Generate and Add Items"
                ) {
                    Task { await extendListWithAI() }
                }
            }
        )
    }

    private var availableStarterSets: [StaticListSet] {
        starterSetDocuments
            .filter { $0.kind == document.kind }
            .map { $0.makeStaticListSet() }
    }

    private func importSelectedItems() async {
        for item in intelligence.photoItems {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let kind: MediaKind = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) ? .video : .photo
                intelligence.attachments.append(MediaAttachment(kind: kind, summary: "\(kind.title) import (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"))
            }
        }
        intelligence.photoItems.removeAll()
    }

    private func extendListWithAI() async {
        intelligence.isGenerating = true
        defer { intelligence.isGenerating = false }

        do {
            let draft = try await generator.generate(
                request: ListGenerationRequest(
                    prompt: intelligence.prompt,
                    kind: document.kind,
                    voiceTranscript: intelligence.voiceTranscript,
                    attachments: intelligence.attachments,
                    starterSets: [],
                    existingEntries: document.sortedSections.flatMap(\.sortedEntries).map(\.title)
                )
            )
            starterSetService.apply(draft, to: document)
            intelligence = IntelligenceComposerState()
        } catch {
            intelligence.errorMessage = error.localizedDescription
        }
    }

    private func addSection() {
        let section = ListSectionModel(
            title: newSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            sortOrder: document.sections.count,
            list: document
        )
        document.sections.append(section)
        newSectionTitle = ""
        document.touch()
    }

    private func addEntry(to section: ListSectionModel) {
        let entry = ListEntry(title: "New Item", sortOrder: section.entries.count, section: section)
        section.entries.append(entry)
        document.touch()
    }

    private func deleteEntries(in section: ListSectionModel, offsets: IndexSet) {
        let sorted = section.sortedEntries
        for offset in offsets {
            modelContext.delete(sorted[offset])
        }
        document.touch()
    }

}

private struct StarterSetLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StarterSetDocument.updatedAt, order: .reverse) private var starterSets: [StarterSetDocument]
    @State private var editingStarterSet: StarterSetDocument?

    var body: some View {
        NavigationStack {
            List {
                if starterSets.isEmpty {
                    ContentUnavailableView("No Starter Sets", systemImage: "square.stack.3d.up")
                } else {
                    ForEach(starterSets) { starterSet in
                        NavigationLink {
                            StarterSetDetailView(starterSet: starterSet)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(starterSet.title)
                                    .font(.headline)
                                Text(starterSet.subtitle.isEmpty ? starterSet.kind.title : starterSet.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(starterSets[index])
                        }
                    }
                }
            }
            .navigationTitle("Starter Sets")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        let starterSet = StarterSetDocument(
                            title: "New Packing Set",
                            subtitle: "",
                            kind: .packing,
                            sections: [
                                StarterSetSectionModel(title: ListKind.packing.emptySectionTitle, sortOrder: 0)
                            ]
                        )
                        modelContext.insert(starterSet)
                        editingStarterSet = starterSet
                    }
                }
            }
            .sheet(item: $editingStarterSet) { starterSet in
                NavigationStack {
                    StarterSetDetailView(starterSet: starterSet, isNew: true)
                }
            }
        }
    }
}

private struct StarterSetDetailView: View {
    @Bindable var starterSet: StarterSetDocument
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var newSectionTitle = ""
    @State private var intelligence = IntelligenceComposerState()
    @State private var aiSectionExpanded = AppleIntelligenceAvailability.current().isAvailable
    @State private var appleIntelligenceAvailability = AppleIntelligenceAvailability.current()
    private let starterSetService = StaticListSetService()
    private let generator = PreferredListGenerationService()
    var isNew = false

    var body: some View {
        List {
            Section {
                TextField("Title", text: $starterSet.title)
                    .onChange(of: starterSet.title) { _, _ in starterSet.touch() }
                TextField("Description", text: $starterSet.subtitle, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: starterSet.subtitle) { _, _ in starterSet.touch() }
                Picker("Type", selection: Binding(
                    get: { starterSet.kind },
                    set: { starterSet.kind = $0; starterSet.touch() }
                )) {
                    ForEach(ListKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            }

            AppleIntelligenceDisclosureSection(
                title: "Apply Intelligence",
                availability: appleIntelligenceAvailability,
                isExpanded: $aiSectionExpanded,
                content: {
                    IntelligenceComposerSection(
                        title: "",
                        prompt: $intelligence.prompt,
                        voiceTranscript: $intelligence.voiceTranscript,
                        attachments: $intelligence.attachments,
                        photoItems: $intelligence.photoItems,
                        isGenerating: intelligence.isGenerating,
                        showingCamera: $intelligence.showingCamera,
                        showingVoiceSheet: $intelligence.showingVoiceSheet,
                        promptLabel: "Describe what this starter set should include",
                        actionTitle: "Generate and Add Items"
                    ) {
                        Task { await extendStarterSetWithAI() }
                    }
                }
            )

            ForEach(starterSet.sortedSections) { section in
                Section {
                    ForEach(section.sortedEntries) { entry in
                        StarterSetEntryRow(entry: entry) {
                            starterSet.touch()
                        }
                    }
                    .onDelete { offsets in
                        let sorted = section.sortedEntries
                        for index in offsets {
                            modelContext.delete(sorted[index])
                        }
                        starterSet.touch()
                    }

                    Button("Add Item", systemImage: "plus") {
                        let entry = StarterSetEntryModel(title: "New Item", sortOrder: section.entries.count, section: section)
                        section.entries.append(entry)
                        starterSet.touch()
                    }
                } header: {
                    TextField("Section Title", text: Binding(
                        get: { section.title },
                        set: { section.title = $0; starterSet.touch() }
                    ))
                }
            }

            Section("Add Section") {
                TextField("New section", text: $newSectionTitle)
                Button("Add Section") {
                    let section = StarterSetSectionModel(
                        title: newSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                        sortOrder: starterSet.sections.count,
                        starterSet: starterSet
                    )
                    starterSet.sections.append(section)
                    newSectionTitle = ""
                    starterSet.touch()
                }
                .disabled(newSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle(starterSet.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $intelligence.showingCamera) {
            CameraPicker { _ in
                intelligence.attachments.append(MediaAttachment(kind: .cameraPhoto, summary: "Live camera photo"))
            }
        }
        .sheet(isPresented: $intelligence.showingVoiceSheet) {
            VoiceCaptureSheet(transcript: $intelligence.voiceTranscript)
        }
        .task(id: intelligence.photoItems) {
            await importSelectedItems()
        }
        .task {
            appleIntelligenceAvailability = AppleIntelligenceAvailability.current()
            aiSectionExpanded = appleIntelligenceAvailability.isAvailable
        }
        .alert("Could Not Generate", isPresented: Binding(
            get: { intelligence.errorMessage != nil },
            set: { if !$0 { intelligence.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(intelligence.errorMessage ?? "")
        }
    }

    private func importSelectedItems() async {
        for item in intelligence.photoItems {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let kind: MediaKind = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) ? .video : .photo
                intelligence.attachments.append(MediaAttachment(kind: kind, summary: "\(kind.title) import (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"))
            }
        }
        intelligence.photoItems.removeAll()
    }

    private func extendStarterSetWithAI() async {
        intelligence.isGenerating = true
        defer { intelligence.isGenerating = false }

        do {
            let draft = try await generator.generate(
                request: ListGenerationRequest(
                    prompt: intelligence.prompt,
                    kind: starterSet.kind,
                    voiceTranscript: intelligence.voiceTranscript,
                    attachments: intelligence.attachments,
                    starterSets: [],
                    existingEntries: starterSet.sortedSections.flatMap(\.sortedEntries).map(\.title)
                )
            )
            starterSetService.apply(draft, to: starterSet)
            intelligence = IntelligenceComposerState()
        } catch {
            intelligence.errorMessage = error.localizedDescription
        }
    }
}

private struct StarterSetEntryRow: View {
    @Bindable var entry: StarterSetEntryModel
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Item", text: $entry.title)
            TextField("Notes", text: $entry.entryNotes, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1...3)
            HStack {
                TextField("Qty", text: $entry.quantity)
                TextField("Category", text: $entry.category)
                TextField("Place", text: $entry.place)
            }
            .font(.caption)
        }
        .onChange(of: entry.title) { _, _ in onChange() }
        .onChange(of: entry.entryNotes) { _, _ in onChange() }
        .onChange(of: entry.quantity) { _, _ in onChange() }
        .onChange(of: entry.category) { _, _ in onChange() }
        .onChange(of: entry.place) { _, _ in onChange() }
    }
}

private struct EntryRow: View {
    @Bindable var entry: ListEntry
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button {
                    entry.isComplete.toggle()
                    onChange()
                } label: {
                    Image(systemName: entry.isComplete ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(entry.isComplete ? .green : .secondary)
                }
                .buttonStyle(.plain)

                TextField("Item", text: $entry.title)
                    .strikethrough(entry.isComplete)
            }
            TextField("Notes", text: $entry.entryNotes, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1...3)
            HStack {
                TextField("Qty", text: $entry.quantity)
                TextField("Category", text: $entry.category)
                TextField("Place", text: $entry.place)
            }
            .font(.caption)
        }
        .onChange(of: entry.title) { _, _ in onChange() }
        .onChange(of: entry.entryNotes) { _, _ in onChange() }
        .onChange(of: entry.quantity) { _, _ in onChange() }
        .onChange(of: entry.category) { _, _ in onChange() }
        .onChange(of: entry.place) { _, _ in onChange() }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .modelContainer(for: [ListDocument.self, ListSectionModel.self, ListEntry.self, StarterSetDocument.self, StarterSetSectionModel.self, StarterSetEntryModel.self], inMemory: true)
}
