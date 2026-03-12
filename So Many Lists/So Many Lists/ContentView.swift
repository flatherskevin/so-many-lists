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

    private let libraryService = ListLibraryService()

    var body: some View {
        NavigationStack {
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
                            heroCard
                            ForEach(filteredLists) { list in
                                NavigationLink {
                                    ListDetailView(document: list)
                                } label: {
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
                                        modelContext.delete(list)
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
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Label("Create", systemImage: "sparkles")
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
                                modelContext.insert(ListDocument.fromDraft(draft))
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search lists")
            .sheet(isPresented: $showingCreateSheet) {
                CreateListFlow { draft in
                    modelContext.insert(ListDocument.fromDraft(draft))
                }
            }
            .sheet(item: $appState.pendingImport) { payload in
                ImportPreviewSheet(payload: payload) { draft in
                    modelContext.insert(ListDocument.fromDraft(draft))
                    appState.pendingImport = nil
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

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Build lists from the messiest inputs.")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Turn prompts, voice notes, photos, and videos into clean local lists you can actually use.")
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label("On-device storage", systemImage: "iphone")
                Label("Multimodal input", systemImage: "camera.macro")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct ShareMessage: Identifiable {
    let id = UUID()
    let text: String
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
                Text(list.updatedAt, style: .relative)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
            HStack(spacing: 14) {
                Label("\(list.outstandingCount) left", systemImage: "circle")
                Label("\(Int(list.completionProgress * 100))%", systemImage: "chart.bar.fill")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            ProgressView(value: list.completionProgress)
                .tint(color)
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

private struct CreateListFlow: View {
    @Environment(\.dismiss) private var dismiss
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

    let onSave: (GeneratedListDraft) -> Void
    private let generator = HybridLocalListGenerationService()

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

                Section {
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
                    .disabled(isGenerating)

                    Button("Create Empty \(kind.title) List") {
                        let draft = GeneratedListDraft(
                            title: kind.title,
                            kind: kind,
                            summary: "A manually created \(kind.title.lowercased()) list.",
                            prompt: prompt,
                            sections: [SectionDraft(title: kind.emptySectionTitle, entries: [])],
                            sourceKind: .manual
                        )
                        onSave(draft)
                        dismiss()
                    }
                }

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
                    attachments: attachments
                )
            )
        } catch {
            errorMessage = error.localizedDescription
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
    @State private var shareMessage: ShareMessage?
    @State private var newSectionTitle = ""

    var body: some View {
        List {
            summarySection
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
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        _ = ListLibraryService().duplicate(document, in: modelContext)
                    }
                    Button("Share", systemImage: "square.and.arrow.up") {
                        shareMessage = ShareMessage(text: appState.shareCodec.shareMessage(for: document))
                    }
                    Button("Delete List", role: .destructive) {
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
        .modelContainer(for: [ListDocument.self, ListSectionModel.self, ListEntry.self], inMemory: true)
}
