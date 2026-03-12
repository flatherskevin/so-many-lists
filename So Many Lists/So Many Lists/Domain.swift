import Foundation
import SwiftData

enum ListKind: String, Codable, CaseIterable, Identifiable {
    case general
    case grocery
    case packing
    case tripPlan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .grocery: "Grocery"
        case .packing: "Packing"
        case .tripPlan: "Trip Plan"
        }
    }

    var iconName: String {
        switch self {
        case .general: "checklist"
        case .grocery: "cart.fill"
        case .packing: "suitcase.rolling.fill"
        case .tripPlan: "airplane.departure"
        }
    }

    var tintName: String {
        switch self {
        case .general: "teal"
        case .grocery: "green"
        case .packing: "orange"
        case .tripPlan: "blue"
        }
    }

    var emptySectionTitle: String {
        switch self {
        case .general: "Items"
        case .grocery: "Groceries"
        case .packing: "Packing List"
        case .tripPlan: "Plan"
        }
    }
}

enum ListSourceKind: String, Codable {
    case manual
    case generated
    case imported
}

enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case photo
    case video
    case cameraPhoto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: "Photo"
        case .video: "Video"
        case .cameraPhoto: "Camera"
        }
    }
}

struct MediaAttachment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: MediaKind
    var summary: String
}

struct EntryMetadataDraft: Codable, Hashable {
    var quantity: String = ""
    var category: String = ""
    var place: String = ""
    var dueDate: Date?
}

struct EntryDraft: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    var isComplete: Bool = false
    var metadata: EntryMetadataDraft = .init()
}

struct SectionDraft: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var entries: [EntryDraft]
}

struct GeneratedListDraft: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var kind: ListKind
    var summary: String
    var prompt: String
    var sections: [SectionDraft]
    var sourceKind: ListSourceKind = .generated
}

struct ListGenerationRequest: Codable, Hashable {
    var prompt: String
    var kind: ListKind
    var voiceTranscript: String
    var attachments: [MediaAttachment]
}

struct SharedListPayload: Codable, Hashable {
    var draft: GeneratedListDraft
    var exportedAt: Date
}

extension SharedListPayload: Identifiable {
    var id: UUID { draft.id }
}

@Model
final class ListDocument {
    @Attribute(.unique) var id: UUID
    var title: String
    var kindRawValue: String
    var listSummary: String
    var sourcePrompt: String
    var sourceKindRawValue: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ListSectionModel.list)
    var sections: [ListSectionModel]

    init(
        id: UUID = UUID(),
        title: String,
        kind: ListKind,
        listSummary: String = "",
        sourcePrompt: String = "",
        sourceKind: ListSourceKind = .manual,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sections: [ListSectionModel] = []
    ) {
        self.id = id
        self.title = title
        self.kindRawValue = kind.rawValue
        self.listSummary = listSummary
        self.sourcePrompt = sourcePrompt
        self.sourceKindRawValue = sourceKind.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sections = sections
    }

    var kind: ListKind {
        get { ListKind(rawValue: kindRawValue) ?? .general }
        set { kindRawValue = newValue.rawValue }
    }

    var sourceKind: ListSourceKind {
        get { ListSourceKind(rawValue: sourceKindRawValue) ?? .manual }
        set { sourceKindRawValue = newValue.rawValue }
    }

    var completionProgress: Double {
        let entries = sections.flatMap(\.entries)
        guard !entries.isEmpty else { return 0 }
        let completed = entries.filter(\.isComplete).count
        return Double(completed) / Double(entries.count)
    }

    var outstandingCount: Int {
        sections.flatMap(\.entries).filter { !$0.isComplete }.count
    }

    func touch() {
        updatedAt = .now
    }
}

@Model
final class ListSectionModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var sortOrder: Int
    var list: ListDocument?
    @Relationship(deleteRule: .cascade, inverse: \ListEntry.section)
    var entries: [ListEntry]

    init(
        id: UUID = UUID(),
        title: String,
        sortOrder: Int,
        list: ListDocument? = nil,
        entries: [ListEntry] = []
    ) {
        self.id = id
        self.title = title
        self.sortOrder = sortOrder
        self.list = list
        self.entries = entries
    }
}

@Model
final class ListEntry {
    @Attribute(.unique) var id: UUID
    var title: String
    var entryNotes: String
    var isComplete: Bool
    var sortOrder: Int
    var quantity: String
    var category: String
    var place: String
    var dueDate: Date?
    var section: ListSectionModel?

    init(
        id: UUID = UUID(),
        title: String,
        entryNotes: String = "",
        isComplete: Bool = false,
        sortOrder: Int,
        quantity: String = "",
        category: String = "",
        place: String = "",
        dueDate: Date? = nil,
        section: ListSectionModel? = nil
    ) {
        self.id = id
        self.title = title
        self.entryNotes = entryNotes
        self.isComplete = isComplete
        self.sortOrder = sortOrder
        self.quantity = quantity
        self.category = category
        self.place = place
        self.dueDate = dueDate
        self.section = section
    }
}

extension ListDocument {
    static func fromDraft(_ draft: GeneratedListDraft) -> ListDocument {
        let document = ListDocument(
            id: draft.id,
            title: draft.title,
            kind: draft.kind,
            listSummary: draft.summary,
            sourcePrompt: draft.prompt,
            sourceKind: draft.sourceKind,
            createdAt: .now,
            updatedAt: .now
        )

        document.sections = draft.sections.enumerated().map { sectionIndex, sectionDraft in
            let section = ListSectionModel(
                id: sectionDraft.id,
                title: sectionDraft.title,
                sortOrder: sectionIndex,
                list: document
            )
            section.entries = sectionDraft.entries.enumerated().map { entryIndex, entryDraft in
                ListEntry(
                    id: entryDraft.id,
                    title: entryDraft.title,
                    entryNotes: entryDraft.notes,
                    isComplete: entryDraft.isComplete,
                    sortOrder: entryIndex,
                    quantity: entryDraft.metadata.quantity,
                    category: entryDraft.metadata.category,
                    place: entryDraft.metadata.place,
                    dueDate: entryDraft.metadata.dueDate,
                    section: section
                )
            }
            return section
        }

        return document
    }

    func makeDraft(sourceKind: ListSourceKind = .generated) -> GeneratedListDraft {
        GeneratedListDraft(
            id: id,
            title: title,
            kind: kind,
            summary: listSummary,
            prompt: sourcePrompt,
            sections: sortedSections.map { section in
                SectionDraft(
                    id: section.id,
                    title: section.title,
                    entries: section.sortedEntries.map { entry in
                        EntryDraft(
                            id: entry.id,
                            title: entry.title,
                            notes: entry.entryNotes,
                            isComplete: entry.isComplete,
                            metadata: EntryMetadataDraft(
                                quantity: entry.quantity,
                                category: entry.category,
                                place: entry.place,
                                dueDate: entry.dueDate
                            )
                        )
                    }
                )
            },
            sourceKind: sourceKind
        )
    }

    var sortedSections: [ListSectionModel] {
        sections.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.title < rhs.title
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }
}

extension ListSectionModel {
    var sortedEntries: [ListEntry] {
        entries.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.title < rhs.title
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }
}
