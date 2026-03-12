import Foundation
import SwiftData

enum ListGenerationError: Error, LocalizedError {
    case emptyPrompt

    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            "Add a prompt, voice note, or media context before generating a list."
        }
    }
}

protocol ListGenerationServicing {
    var providerLabel: String { get }
    func generate(request: ListGenerationRequest) async throws -> GeneratedListDraft
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
            attachments: request.attachments
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

enum HeuristicDraftBuilder {
    static func buildDraft(kind: ListKind, prompt: String, attachments: [MediaAttachment]) -> GeneratedListDraft {
        let tokens = expandedItems(for: kind, prompt: prompt, attachments: attachments)
        let title = suggestedTitle(for: kind, prompt: prompt)
        let attachmentNote = attachments.isEmpty ? "" : " Based on \(attachments.count) attachment\(attachments.count == 1 ? "" : "s")."

        return GeneratedListDraft(
            title: title,
            kind: kind,
            summary: "\(summaryPrefix(for: kind))\(attachmentNote)",
            prompt: prompt,
            sections: sections(for: kind, tokens: tokens, attachments: attachments)
        )
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
