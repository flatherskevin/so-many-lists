import Foundation
import FoundationModels
import SwiftData

enum ListGenerationError: Error, LocalizedError {
    case emptyPrompt
    case modelUnavailable(SystemLanguageModel.Availability.UnavailableReason)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            "Add a prompt, voice note, or media context before generating a list."
        case .modelUnavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                "Apple Intelligence is not available on this device."
            case .appleIntelligenceNotEnabled:
                "Apple Intelligence is turned off. Enable it in Settings to generate lists."
            case .modelNotReady:
                "Apple Intelligence is still preparing its on-device model. Try again in a bit."
            @unknown default:
                "Apple Intelligence is unavailable right now."
            }
        case .invalidResponse:
            "Apple Intelligence returned an empty draft."
        }
    }
}

protocol ListGenerationServicing {
    var providerLabel: String { get }
    func generate(request: ListGenerationRequest) async throws -> GeneratedListDraft
}

struct AppleIntelligenceAvailability: Equatable {
    let isAvailable: Bool
    let message: String?

    static func current() -> AppleIntelligenceAvailability {
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return AppleIntelligenceAvailability(isAvailable: true, message: nil)
            case .unavailable(let reason):
                return AppleIntelligenceAvailability(
                    isAvailable: false,
                    message: ListGenerationError.modelUnavailable(reason).errorDescription
                )
            }
        }

        return AppleIntelligenceAvailability(
            isAvailable: false,
            message: "Apple Intelligence is not available in this environment."
        )
    }
}

struct PreferredListGenerationService: ListGenerationServicing {
    let providerLabel = "Apple Intelligence"

    func generate(request: ListGenerationRequest) async throws -> GeneratedListDraft {
        if #available(iOS 26.0, *) {
            return try await AppleIntelligenceListGenerationService().generate(request: request)
        }
        return try await HybridLocalListGenerationService().generate(request: request)
    }
}

struct HybridLocalListGenerationService: ListGenerationServicing {
    let providerLabel = "Local draft engine"

    func generate(request: ListGenerationRequest) async throws -> GeneratedListDraft {
        let normalizedPrompt = [
            request.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            request.voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedPrompt.isEmpty || !request.attachments.isEmpty else {
            throw ListGenerationError.emptyPrompt
        }

        let basePrompt = normalizedPrompt.isEmpty ? defaultPrompt(for: request.kind, attachments: request.attachments) : normalizedPrompt
        return HeuristicDraftBuilder.buildDraft(
            kind: request.kind,
            prompt: basePrompt,
            attachments: request.attachments,
            starterSets: request.starterSets
        )
    }

    private func defaultPrompt(for kind: ListKind, attachments: [MediaAttachment]) -> String {
        let attachmentSummary = attachments.map(\.summary).joined(separator: ", ")
        if attachmentSummary.isEmpty {
            return "Create a \(kind.title.lowercased()) list."
        }
        return "Create a \(kind.title.lowercased()) list using \(attachmentSummary)."
    }
}

@available(iOS 26.0, *)
@Generable(description: "A structured list draft with sections and concise items.")
private struct FoundationModelListDraft {
    let title: String
    let summary: String
    let sections: [FoundationModelSection]
}

@available(iOS 26.0, *)
@Generable(description: "A single section in a generated list.")
private struct FoundationModelSection {
    let title: String
    let entries: [FoundationModelEntry]
}

@available(iOS 26.0, *)
@Generable(description: "A single checklist item with optional metadata.")
private struct FoundationModelEntry {
    let title: String
    let notes: String?
    let quantity: String?
    let category: String?
    let place: String?
}

struct AppleIntelligenceListGenerationService: ListGenerationServicing {
    let providerLabel = "Apple Intelligence"

    func generate(request: ListGenerationRequest) async throws -> GeneratedListDraft {
        let normalizedPrompt = [
            request.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            request.voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedPrompt.isEmpty || !request.attachments.isEmpty else {
            throw ListGenerationError.emptyPrompt
        }

        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw ListGenerationError.modelUnavailable(reason)
        }

        let session = LanguageModelSession(model: model, instructions: instructions(for: request.kind))
        let response = try await session.respond(generating: FoundationModelListDraft.self) {
            """
            Build a \(request.kind.title.lowercased()) list from this user intent:
            \(normalizedPrompt)
            """

            if !request.attachments.isEmpty {
                """
                Attachment context:
                \(request.attachments.map(\.summary).joined(separator: "\n"))
                """
            }

            if !request.existingEntries.isEmpty {
                """
                Items already on the list. Do not repeat them:
                \(request.existingEntries.joined(separator: "\n"))
                """
            }

            if !request.starterSets.isEmpty {
                """
                Starter set items already included or expected. Do not repeat them:
                \(request.starterSets.flatMap(\.sections).flatMap(\.entries).map(\.title).joined(separator: "\n"))
                """
            }
        }

        let sections: [SectionDraft] = response.content.sections.compactMap { section in
            let entries: [EntryDraft] = section.entries.compactMap { entry in
                let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                return EntryDraft(
                    title: title,
                    notes: entry.notes ?? "",
                    metadata: EntryMetadataDraft(
                        quantity: entry.quantity ?? "",
                        category: entry.category ?? "",
                        place: entry.place ?? ""
                    )
                )
            }
            guard !entries.isEmpty else { return nil }
            return SectionDraft(title: section.title, entries: entries)
        }

        guard !sections.isEmpty else {
            throw ListGenerationError.invalidResponse
        }

        let draft = GeneratedListDraft(
            title: response.content.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? request.kind.title : response.content.title,
            kind: request.kind,
            summary: response.content.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? HeuristicDraftBuilder.summaryPrefix(for: request.kind) : response.content.summary,
            prompt: normalizedPrompt,
            sections: sections
        )

        return StaticListSetService().merge(request.starterSets, into: draft)
    }

    private func instructions(for kind: ListKind) -> String {
        switch kind {
        case .general:
            """
            You create practical checklists. Return short section titles and concise action items. Avoid duplicates and avoid echoing the user prompt verbatim.
            Never output raw narrative fragments, amenities, or clauses copied from the user's description. Convert context into useful checklist items.
            """
        case .grocery:
            """
            You create grocery lists organized by store-style sections like Produce, Pantry, Protein, Dairy, Frozen, and Household. Avoid duplicates and keep item titles short.
            """
        case .packing:
            """
            You create packing lists organized into sections like Essentials, Clothes, Toiletries, Tech, and Extras. Avoid duplicates, include likely necessities, and keep item titles short.
            Only include real things a person would bring, wear, or buy for the trip. Do not include itinerary facts, lodging amenities, or sentence fragments from the prompt.
            """
        case .tripPlan:
            """
            You create trip plans organized into moments like Before You Go, Travel Day, and While You're There. Keep items actionable, concise, and non-duplicative.
            Do not restate the user's narrative as items. Convert context into concrete actions or reservations instead of copying phrases.
            """
        }
    }
}

enum HeuristicDraftBuilder {
    static func buildDraft(kind: ListKind, prompt: String, attachments: [MediaAttachment], starterSets: [StaticListSet] = []) -> GeneratedListDraft {
        let tokens = expandedItems(for: kind, prompt: prompt, attachments: attachments)
        let title = suggestedTitle(for: kind, prompt: prompt)
        let attachmentNote = attachments.isEmpty ? "" : " Based on \(attachments.count) attachment\(attachments.count == 1 ? "" : "s")."

        let draft = GeneratedListDraft(
            title: title,
            kind: kind,
            summary: "\(summaryPrefix(for: kind))\(attachmentNote)",
            prompt: prompt,
            sections: sections(for: kind, tokens: tokens, attachments: attachments)
        )

        return StaticListSetService().merge(starterSets, into: draft)
    }

    static func expandedItems(for kind: ListKind, prompt: String, attachments: [MediaAttachment]) -> [String] {
        let cleanedPrompt = cleaned(prompt)
        let explicitPhrases = splitIntoPhrases(cleanedPrompt)
        let contextTerms = significantTerms(in: cleanedPrompt)

        switch kind {
        case .general:
            return expandGeneralItems(prompt: cleanedPrompt, phrases: explicitPhrases, contextTerms: contextTerms)
        case .grocery:
            return expandGroceryItems(prompt: cleanedPrompt, phrases: explicitPhrases, contextTerms: contextTerms, attachments: attachments)
        case .packing:
            return expandPackingItems(prompt: cleanedPrompt, phrases: explicitPhrases, contextTerms: contextTerms)
        case .tripPlan:
            return expandTripItems(prompt: cleanedPrompt, phrases: explicitPhrases, contextTerms: contextTerms)
        }
    }

    static func suggestedTitle(for kind: ListKind, prompt: String) -> String {
        let cleaned = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return kind.title
        }
        return String(cleaned.prefix(36))
    }

    static func summaryPrefix(for kind: ListKind) -> String {
        switch kind {
        case .general: "A flexible checklist drafted from your prompt."
        case .grocery: "A grocery plan grouped to make store runs faster."
        case .packing: "A packing list broken into useful travel categories."
        case .tripPlan: "A trip plan organized into the moments that matter."
        }
    }

    static func sections(for kind: ListKind, tokens: [String], attachments: [MediaAttachment]) -> [SectionDraft] {
        let seed = tokens.isEmpty ? defaultItems(for: kind) : tokens

        switch kind {
        case .general:
            return [SectionDraft(title: "To Do", entries: seed.enumerated().map { index, token in
                EntryDraft(title: prettify(token), metadata: metadata(for: token, fallbackCategory: "General", index: index))
            })]
        case .grocery:
            let groups = Dictionary(grouping: seed, by: grocerySection)
            let order = ["Produce", "Pantry", "Protein", "Dairy", "Frozen", "Household"]
            let sections = order.compactMap { title -> SectionDraft? in
                guard let items = groups[title], !items.isEmpty else { return nil }
                return SectionDraft(title: title, entries: items.enumerated().map { index, token in
                    var draft = EntryDraft(title: prettify(token))
                    draft.metadata = metadata(for: token, fallbackCategory: title, index: index)
                    return draft
                })
            }
            return sections.isEmpty ? [SectionDraft(title: "Groceries", entries: defaultItems(for: .grocery).enumerated().map { index, token in
                EntryDraft(title: token, metadata: metadata(for: token, fallbackCategory: "Groceries", index: index))
            })] : sections
        case .packing:
            let order = ["Essentials", "Clothes", "Toiletries", "Tech", "Extras"]
            let groups = Dictionary(grouping: seed, by: packingSection)
            return order.compactMap { title in
                guard let items = groups[title], !items.isEmpty else { return nil }
                return SectionDraft(title: title, entries: items.enumerated().map { index, token in
                    var draft = EntryDraft(title: prettify(token))
                    draft.metadata = metadata(for: token, fallbackCategory: title, index: index)
                    return draft
                })
            }
        case .tripPlan:
            let sections = [
                SectionDraft(title: "Before You Go", entries: planEntries(seed, range: 0..<min(3, seed.count), category: "Prep")),
                SectionDraft(title: "Travel Day", entries: planEntries(seed, range: min(3, seed.count)..<min(6, seed.count), category: "Travel")),
                SectionDraft(title: "While You're There", entries: planEntries(seed, range: min(6, seed.count)..<seed.count, category: "Trip"))
            ]
            let filtered = sections.filter { !$0.entries.isEmpty }
            if filtered.isEmpty {
                return [SectionDraft(title: "Trip Plan", entries: defaultItems(for: .tripPlan).enumerated().map { index, token in
                    EntryDraft(title: token, metadata: metadata(for: token, fallbackCategory: "Trip", index: index))
                })]
            }
            if !attachments.isEmpty {
                return filtered + [SectionDraft(title: "Captured Inspiration", entries: attachments.enumerated().map { index, attachment in
                    EntryDraft(
                        title: "Review \(attachment.kind.title.lowercased())",
                        notes: attachment.summary,
                        metadata: metadata(for: attachment.summary, fallbackCategory: "Reference", index: index)
                    )
                })]
            }
            return filtered
        }
    }

    static func planEntries(_ tokens: [String], range: Range<Int>, category: String) -> [EntryDraft] {
        guard !tokens.isEmpty else { return [] }
        let safeRange = range.clamped(to: 0..<tokens.count)
        guard !safeRange.isEmpty else { return [] }
        return tokens[safeRange].enumerated().map { index, token in
            var draft = EntryDraft(title: prettify(token))
            draft.metadata = metadata(for: token, fallbackCategory: category, index: index)
            return draft
        }
    }

    static func defaultItems(for kind: ListKind) -> [String] {
        switch kind {
        case .general:
            ["First step", "Important follow-up", "Nice-to-have"]
        case .grocery:
            ["Fruit", "Vegetables", "Bread", "Protein", "Snacks"]
        case .packing:
            ["Passport", "Phone charger", "Shoes", "Toothbrush", "Jacket"]
        case .tripPlan:
            ["Book transportation", "Confirm lodging", "Save must-see spots", "Pack essentials"]
        }
    }

    static func prettify(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        return trimmed
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                return lower.count <= 3 ? lower : lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    nonisolated static func grocerySection(for token: String) -> String {
        let value = token.lowercased()
        if ["apple", "banana", "lettuce", "carrot", "berries", "fruit", "vegetable"].contains(where: value.contains) {
            return "Produce"
        }
        if ["milk", "yogurt", "cheese", "butter", "egg"].contains(where: value.contains) {
            return "Dairy"
        }
        if ["chicken", "beef", "fish", "salmon", "turkey"].contains(where: value.contains) {
            return "Protein"
        }
        if ["ice", "frozen", "pizza"].contains(where: value.contains) {
            return "Frozen"
        }
        if ["soap", "paper", "clean", "detergent"].contains(where: value.contains) {
            return "Household"
        }
        return "Pantry"
    }

    nonisolated static func packingSection(for token: String) -> String {
        let value = token.lowercased()
        if ["shirt", "pants", "dress", "shoe", "sock", "jacket"].contains(where: value.contains) {
            return "Clothes"
        }
        if ["tooth", "soap", "shampoo", "sunscreen", "razor"].contains(where: value.contains) {
            return "Toiletries"
        }
        if ["charger", "phone", "camera", "laptop", "adapter"].contains(where: value.contains) {
            return "Tech"
        }
        if ["passport", "wallet", "ticket", "id"].contains(where: value.contains) {
            return "Essentials"
        }
        return "Extras"
    }

    static func metadata(for token: String, fallbackCategory: String, index: Int) -> EntryMetadataDraft {
        var metadata = EntryMetadataDraft()
        metadata.category = fallbackCategory
        metadata.place = token.lowercased().contains("airport") ? "Airport" : ""

        let words = token.split(separator: " ")
        if let first = words.first, first.first?.isNumber == true {
            metadata.quantity = String(first)
        } else if fallbackCategory == "Produce" || fallbackCategory == "Groceries" {
            metadata.quantity = index == 0 ? "1" : ""
        }

        return metadata
    }

    static func cleaned(_ prompt: String) -> String {
        prompt
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "create me", with: "")
            .replacingOccurrences(of: "make me", with: "")
            .replacingOccurrences(of: "build me", with: "")
            .replacingOccurrences(of: "generate me", with: "")
            .replacingOccurrences(of: "create a", with: "")
            .replacingOccurrences(of: "make a", with: "")
            .replacingOccurrences(of: "build a", with: "")
            .replacingOccurrences(of: "generate a", with: "")
            .replacingOccurrences(of: "i need", with: "")
            .replacingOccurrences(of: "help me", with: "")
            .replacingOccurrences(of: "list for", with: "")
            .replacingOccurrences(of: "checklist for", with: "")
            .replacingOccurrences(of: "shopping list for", with: "")
            .replacingOccurrences(of: "packing list for", with: "")
            .replacingOccurrences(of: "trip plan for", with: "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    static func splitIntoPhrases(_ prompt: String) -> [String] {
        let separators = [",", ".", ";", "\n", " and ", " with ", " plus ", " also "]
        let phrases = separators.reduce([prompt]) { partial, separator in
            partial.flatMap { $0.components(separatedBy: separator) }
        }
        return deduplicated(
            phrases
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)) }
                .filter { $0.count > 2 }
        )
    }

    static func significantTerms(in prompt: String) -> [String] {
        let stopwords: Set<String> = [
            "a", "an", "the", "to", "for", "of", "on", "in", "at", "my", "our", "your", "this", "that",
            "trip", "plan", "list", "checklist", "need", "want", "from", "into", "using", "have", "has",
            "some", "really", "very", "just", "around", "about"
        ]

        return deduplicated(
            prompt
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 2 && !stopwords.contains($0) }
        )
    }

    static func expandGeneralItems(prompt: String, phrases: [String], contextTerms: [String]) -> [String] {
        let explicit = phrases.filter { $0.split(separator: " ").count <= 6 }
        if explicit.count >= 3 {
            return explicit
        }

        let lead = prompt.isEmpty ? "plan" : prompt
        var items = explicit
        items.append("Define the goal for \(lead)")
        items.append("Gather the details or materials needed")
        items.append("Complete the main action items")
        items.append("Review and clean up the final list")

        if contextTerms.contains(where: ["party", "event", "birthday"].contains) {
            items.append(contentsOf: ["Finalize the guest-facing details", "Prep the space and supplies"])
        }

        return deduplicated(items)
    }

    static func expandGroceryItems(prompt: String, phrases: [String], contextTerms: [String], attachments: [MediaAttachment]) -> [String] {
        var items = groceryKeywordMatches(in: phrases + contextTerms)

        let bundles: [(Set<String>, [String])] = [
            (["taco", "tacos", "mexican"], ["Tortillas", "Ground beef", "Avocados", "Salsa", "Limes", "Cilantro"]),
            (["pasta", "italian"], ["Pasta", "Marinara", "Parmesan", "Garlic", "Spinach"]),
            (["breakfast", "brunch"], ["Eggs", "Greek yogurt", "Berries", "Oats", "Coffee"]),
            (["smoothie", "smoothies"], ["Bananas", "Frozen berries", "Yogurt", "Spinach", "Almond milk"]),
            (["kids", "school", "lunch"], ["Bread", "Turkey", "Cheese", "Apples", "Snack packs", "Juice boxes"]),
            (["party", "hosting", "guests"], ["Chips", "Dip", "Sparkling water", "Ice", "Dessert"])
        ]

        for (terms, bundle) in bundles where !terms.isDisjoint(with: Set(contextTerms)) {
            items.append(contentsOf: bundle)
        }

        if attachments.isEmpty == false && items.count < 5 {
            items.append(contentsOf: ["Fresh produce", "Proteins", "Pantry staples", "Snacks", "Household basics"])
        }

        if items.count < 4 {
            items.append(contentsOf: ["Fruit", "Vegetables", "Protein", "Bread", "Snacks"])
        }

        return deduplicated(items)
    }

    static func groceryKeywordMatches(in values: [String]) -> [String] {
        let map: [String: String] = [
            "apple": "Apples", "banana": "Bananas", "berries": "Berries", "berry": "Berries", "lettuce": "Lettuce",
            "spinach": "Spinach", "carrot": "Carrots", "onion": "Onions", "avocado": "Avocados", "lime": "Limes",
            "milk": "Milk", "cheese": "Cheese", "yogurt": "Greek yogurt", "egg": "Eggs", "butter": "Butter",
            "bread": "Bread", "rice": "Rice", "pasta": "Pasta", "cereal": "Cereal", "oat": "Oats", "coffee": "Coffee",
            "chicken": "Chicken", "beef": "Ground beef", "salmon": "Salmon", "turkey": "Turkey", "fish": "Fish",
            "chips": "Chips", "cracker": "Crackers", "juice": "Juice", "water": "Sparkling water", "salsa": "Salsa"
        ]

        return deduplicated(values.flatMap { value in
            map.compactMap { key, item in value.contains(key) ? item : nil }
        })
    }

    static func expandPackingItems(prompt: String, phrases: [String], contextTerms: [String]) -> [String] {
        var items = deduplicated(phrases.filter { $0.split(separator: " ").count <= 4 })

        let bundles: [(Set<String>, [String])] = [
            (["beach", "resort", "pool"], ["Swimsuit", "Flip-flops", "Sunscreen", "Beach cover-up", "Sunglasses"]),
            (["business", "work", "conference"], ["Laptop", "Chargers", "Dress shoes", "Blazer", "Notebook"]),
            (["winter", "cold", "snow"], ["Coat", "Boots", "Gloves", "Warm layers", "Beanie"]),
            (["weekend", "short"], ["2 outfits", "Toiletries", "Phone charger", "Sleepwear"]),
            (["camping", "hiking", "outdoors"], ["Trail shoes", "Water bottle", "Headlamp", "Rain layer", "First-aid basics"])
        ]

        for (terms, bundle) in bundles where !terms.isDisjoint(with: Set(contextTerms)) {
            items.append(contentsOf: bundle)
        }

        items.append(contentsOf: ["ID or passport", "Wallet", "Toothbrush", "Phone charger"])
        return deduplicated(items)
    }

    static func expandTripItems(prompt: String, phrases: [String], contextTerms: [String]) -> [String] {
        var items: [String] = [
            "Book transportation",
            "Confirm lodging",
            "Set trip budget",
            "Save tickets and reservation details",
            "Pack key essentials"
        ]

        let activityMap: [String: [String]] = [
            "beach": ["Plan a beach day", "Pack towels and sun essentials"],
            "museum": ["Reserve museum tickets"],
            "food": ["Save restaurant spots", "Book one standout dinner"],
            "hiking": ["Map trail logistics", "Check weather and gear needs"],
            "family": ["Add kid-friendly downtime", "Plan snacks and breaks"],
            "road": ["Plan fuel and rest stops", "Download maps offline"],
            "weekend": ["Choose 2 or 3 anchor activities"]
        ]

        for term in contextTerms {
            if let mapped = activityMap[term] {
                items.append(contentsOf: mapped)
            }
        }

        items.append(contentsOf: phrases.filter { $0.split(separator: " ").count <= 5 }.map { "Plan \(prettify($0).lowercased())" })
        return deduplicated(items)
    }

    static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            guard trimmed.count > 1 else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return prettify(trimmed)
        }
    }
}

struct StaticListSetService {
    func merge(_ sets: [StaticListSet], into draft: GeneratedListDraft) -> GeneratedListDraft {
        guard !sets.isEmpty else { return draft }

        var mergedDraft = draft
        mergedDraft.sections = merged(draft.sections, with: sets.flatMap(\.sections))
        return mergedDraft
    }

    func merge(_ additions: GeneratedListDraft, into draft: GeneratedListDraft) -> GeneratedListDraft {
        var mergedDraft = draft
        mergedDraft.sections = merged(draft.sections, with: additions.sections)
        return mergedDraft
    }

    func apply(_ set: StaticListSet, to document: ListDocument) {
        var draft = document.makeDraft(sourceKind: document.sourceKind)
        draft = merge([set], into: draft)
        applyDraft(draft, to: document)
    }

    func apply(_ addition: GeneratedListDraft, to document: ListDocument) {
        var draft = document.makeDraft(sourceKind: document.sourceKind)
        draft = merge(addition, into: draft)
        if !addition.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.prompt = addition.prompt
        }
        document.sections = draft.sections.enumerated().map { sectionIndex, sectionDraft in
            let existingSection = document.sections.first {
                $0.title.localizedCaseInsensitiveCompare(sectionDraft.title) == .orderedSame
            }
            let section = existingSection ?? ListSectionModel(
                id: sectionDraft.id,
                title: sectionDraft.title,
                sortOrder: sectionIndex,
                list: document
            )
            section.title = sectionDraft.title
            section.sortOrder = sectionIndex

            section.entries = sectionDraft.entries.enumerated().map { entryIndex, entryDraft in
                let existingEntry = section.entries.first {
                    normalizedKey(for: $0.title) == normalizedKey(for: entryDraft.title)
                }
                let entry = existingEntry ?? ListEntry(
                    id: entryDraft.id,
                    title: entryDraft.title,
                    sortOrder: entryIndex,
                    section: section
                )
                entry.title = entryDraft.title
                entry.entryNotes = entryDraft.notes
                entry.isComplete = entryDraft.isComplete
                entry.sortOrder = entryIndex
                entry.quantity = entryDraft.metadata.quantity
                entry.category = entryDraft.metadata.category
                entry.place = entryDraft.metadata.place
                entry.dueDate = entryDraft.metadata.dueDate
                entry.section = section
                return entry
            }
            return section
        }
        document.listSummary = draft.summary
        document.sourcePrompt = draft.prompt
        document.touch()
    }

    func apply(_ addition: GeneratedListDraft, to starterSet: StarterSetDocument) {
        let existingSections = starterSet.sortedSections.map { section in
            SectionDraft(
                id: section.id,
                title: section.title,
                entries: section.sortedEntries.map { entry in
                    EntryDraft(
                        id: entry.id,
                        title: entry.title,
                        notes: entry.entryNotes,
                        metadata: EntryMetadataDraft(
                            quantity: entry.quantity,
                            category: entry.category,
                            place: entry.place,
                            dueDate: entry.dueDate
                        )
                    )
                }
            )
        }
        let mergedDraft = merged(existingSections, with: addition.sections)

        starterSet.sections = mergedDraft.enumerated().map { sectionIndex, sectionDraft in
            let existingSection = starterSet.sections.first {
                $0.title.localizedCaseInsensitiveCompare(sectionDraft.title) == .orderedSame
            }
            let section = existingSection ?? StarterSetSectionModel(
                id: sectionDraft.id,
                title: sectionDraft.title,
                sortOrder: sectionIndex,
                starterSet: starterSet
            )
            section.title = sectionDraft.title
            section.sortOrder = sectionIndex

            section.entries = sectionDraft.entries.enumerated().map { entryIndex, entryDraft in
                let existingEntry = section.entries.first {
                    normalizedKey(for: $0.title) == normalizedKey(for: entryDraft.title)
                }
                let entry = existingEntry ?? StarterSetEntryModel(
                    id: entryDraft.id,
                    title: entryDraft.title,
                    sortOrder: entryIndex,
                    section: section
                )
                entry.title = entryDraft.title
                entry.entryNotes = entryDraft.notes
                entry.sortOrder = entryIndex
                entry.quantity = entryDraft.metadata.quantity
                entry.category = entryDraft.metadata.category
                entry.place = entryDraft.metadata.place
                entry.dueDate = entryDraft.metadata.dueDate
                entry.section = section
                return entry
            }
            return section
        }

        if !addition.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, starterSet.title.hasPrefix("New ") {
            starterSet.title = addition.title
        }
        if !addition.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            starterSet.subtitle = addition.summary
        }
        starterSet.touch()
    }

    private func applyDraft(_ draft: GeneratedListDraft, to document: ListDocument) {
        document.sections = draft.sections.enumerated().map { sectionIndex, sectionDraft in
            let existingSection = document.sections.first {
                $0.title.localizedCaseInsensitiveCompare(sectionDraft.title) == .orderedSame
            }
            let section = existingSection ?? ListSectionModel(
                id: sectionDraft.id,
                title: sectionDraft.title,
                sortOrder: sectionIndex,
                list: document
            )
            section.title = sectionDraft.title
            section.sortOrder = sectionIndex

            section.entries = sectionDraft.entries.enumerated().map { entryIndex, entryDraft in
                let existingEntry = section.entries.first {
                    normalizedKey(for: $0.title) == normalizedKey(for: entryDraft.title)
                }
                let entry = existingEntry ?? ListEntry(
                    id: entryDraft.id,
                    title: entryDraft.title,
                    sortOrder: entryIndex,
                    section: section
                )
                entry.title = entryDraft.title
                entry.entryNotes = entryDraft.notes
                entry.isComplete = entryDraft.isComplete
                entry.sortOrder = entryIndex
                entry.quantity = entryDraft.metadata.quantity
                entry.category = entryDraft.metadata.category
                entry.place = entryDraft.metadata.place
                entry.dueDate = entryDraft.metadata.dueDate
                entry.section = section
                return entry
            }
            return section
        }
        document.touch()
    }

    private func merged(_ base: [SectionDraft], with additions: [SectionDraft]) -> [SectionDraft] {
        var sections = base
        var seenKeys = Set(sections.flatMap(\.entries).map { normalizedKey(for: $0.title) })

        for addedSection in additions {
            let targetIndex = sections.firstIndex {
                $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(addedSection.title.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            }

            var newEntries: [EntryDraft] = []
            for entry in addedSection.entries {
                let key = normalizedKey(for: entry.title)
                guard !key.isEmpty, seenKeys.insert(key).inserted else { continue }
                newEntries.append(entry)
            }

            guard !newEntries.isEmpty else { continue }

            if let targetIndex {
                sections[targetIndex].entries.append(contentsOf: newEntries)
            } else {
                sections.append(SectionDraft(title: addedSection.title, entries: newEntries))
            }
        }

        return sections.map { section in
            SectionDraft(
                id: section.id,
                title: section.title,
                entries: section.entries.enumerated().map { entryIndex, entry in
                    var updatedEntry = entry
                    if updatedEntry.metadata.category.isEmpty {
                        updatedEntry.metadata = HeuristicDraftBuilder.metadata(
                            for: updatedEntry.title,
                            fallbackCategory: section.title,
                            index: entryIndex
                        )
                    }
                    return updatedEntry
                }
            )
        }
    }

    func normalizedKey(for value: String) -> String {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "flipflops", with: "flip flops")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map(singularize)
            .joined(separator: " ")

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func singularize(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies") {
            return String(word.dropLast(3)) + "y"
        }
        if word.hasSuffix("sses") || word.hasSuffix("ss") {
            return word
        }
        if word.hasSuffix("s") {
            return String(word.dropLast())
        }
        return word
    }
}

struct ListLibraryService {
    func duplicate(_ document: ListDocument, in context: ModelContext) -> ListDocument {
        let draft = document.makeDraft(sourceKind: .manual)
        var copiedDraft = draft
        copiedDraft.id = UUID()
        copiedDraft.title = "\(document.title) Copy"
        copiedDraft.sections = draft.sections.map { section in
            SectionDraft(
                id: UUID(),
                title: section.title,
                entries: section.entries.map { entry in
                    var copiedEntry = entry
                    copiedEntry.id = UUID()
                    copiedEntry.isComplete = false
                    return copiedEntry
                }
            )
        }
        let clone = ListDocument.fromDraft(copiedDraft)
        clone.sourceKind = .manual
        context.insert(clone)
        return clone
    }
}

extension Array where Element == Substring {
    func joined(separator: String) -> String {
        map(String.init).joined(separator: separator)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
