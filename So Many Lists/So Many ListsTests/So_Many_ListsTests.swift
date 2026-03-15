//
//  So_Many_ListsTests.swift
//  So Many ListsTests
//
//  Created by Kevin Flathers on 3/12/26.
//

import XCTest
import SwiftData
@testable import So_Many_Lists

final class So_Many_ListsTests: XCTestCase {

    func testShareCodecRoundTripsPayload() throws {
        let draft = GeneratedListDraft(
            title: "Paris Weekend",
            kind: .tripPlan,
            summary: "A trip plan.",
            prompt: "Weekend in Paris",
            sections: [
                SectionDraft(title: "Before You Go", entries: [
                    EntryDraft(title: "Book hotel"),
                    EntryDraft(title: "Reserve museum tickets")
                ])
            ]
        )
        let payload = SharedListPayload(draft: draft, exportedAt: .now)
        let codec = ListShareCodec()

        let url = try codec.url(for: payload)
        let decoded = try codec.decode(url: url)

        XCTAssertEqual(decoded.draft.title, draft.title)
        XCTAssertEqual(decoded.draft.kind, draft.kind)
        XCTAssertEqual(decoded.draft.sections.first?.entries.count, 2)
    }

    func testDuplicateResetsIdentityAndCompletion() throws {
        let container = try ModelContainer(
            for: ListDocument.self,
            ListSectionModel.self,
            ListEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let document = ListDocument.fromDraft(
            GeneratedListDraft(
                title: "Market Run",
                kind: .grocery,
                summary: "Grouped groceries.",
                prompt: "milk, apples",
                sections: [
                    SectionDraft(title: "Groceries", entries: [
                        EntryDraft(title: "Milk", isComplete: true),
                        EntryDraft(title: "Apples", isComplete: false)
                    ])
                ]
            )
        )
        context.insert(document)

        let duplicate = ListLibraryService().duplicate(document, in: context)

        XCTAssertNotEqual(duplicate.id, document.id)
        XCTAssertEqual(duplicate.title, "Market Run Copy")
        XCTAssertEqual(duplicate.sortedSections.first?.sortedEntries.allSatisfy { !$0.isComplete }, true)
    }

    func testDraftBuilderUsesAttachmentsForTripPlan() {
        let draft = HeuristicDraftBuilder.buildDraft(
            kind: .tripPlan,
            prompt: "book flight, plan dinner, museum tickets",
            attachments: [MediaAttachment(kind: .video, summary: "Neighborhood walk-through")]
        )

        XCTAssertTrue(draft.sections.contains(where: { $0.title == "Captured Inspiration" }))
        XCTAssertEqual(draft.kind, .tripPlan)
    }

    func testGeneralPromptExpandsIntoMultipleChecklistItems() {
        let draft = HeuristicDraftBuilder.buildDraft(
            kind: .general,
            prompt: "help me plan my daughter's birthday party next weekend",
            attachments: []
        )

        let items = draft.sections.flatMap(\.entries).map(\.title)
        XCTAssertGreaterThan(items.count, 3)
        XCTAssertFalse(items.contains("Help me plan my daughter's birthday party next weekend"))
    }

    func testGroceryPromptDoesNotCollapseToOneRawSentence() {
        let draft = HeuristicDraftBuilder.buildDraft(
            kind: .grocery,
            prompt: "make a grocery list for taco night and breakfast for the week",
            attachments: []
        )

        let items = draft.sections.flatMap(\.entries).map(\.title)
        XCTAssertGreaterThan(items.count, 5)
        XCTAssertTrue(items.contains("Tortillas"))
        XCTAssertTrue(items.contains("Eggs"))
    }

    func testStarterSetMergeAvoidsDuplicatePackingItems() {
        let essentials = StaticListSet(
            id: "packing-trip-essentials",
            title: "Trip Essentials",
            subtitle: "Core travel items you almost always need.",
            kind: .packing,
            sections: [
                SectionDraft(title: "Clothes", entries: [
                    EntryDraft(title: "Socks"),
                    EntryDraft(title: "Underwear")
                ]),
                SectionDraft(title: "Toiletries", entries: [
                    EntryDraft(title: "Toothbrush")
                ]),
                SectionDraft(title: "Tech", entries: [
                    EntryDraft(title: "Phone charger")
                ])
            ]
        )

        let draft = HeuristicDraftBuilder.buildDraft(
            kind: .packing,
            prompt: "weekend trip with phone charger, socks, toothbrush",
            attachments: [],
            starterSets: [essentials]
        )

        let items = draft.sections.flatMap(\.entries).map(\.title)
        XCTAssertEqual(items.filter { $0 == "Phone Charger" }.count, 1)
        XCTAssertEqual(items.filter { $0 == "Socks" }.count, 1)
        XCTAssertEqual(items.filter { $0 == "Toothbrush" }.count, 1)
        XCTAssertTrue(items.contains("Underwear"))
    }

    func testApplyingStarterSetToDocumentOnlyAddsMissingItems() throws {
        let container = try ModelContainer(
            for: ListDocument.self,
            ListSectionModel.self,
            ListEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let document = ListDocument.fromDraft(
            GeneratedListDraft(
                title: "Packing",
                kind: .packing,
                summary: "Test",
                prompt: "",
                sections: [
                    SectionDraft(title: "Clothes", entries: [
                        EntryDraft(title: "Socks")
                    ]),
                    SectionDraft(title: "Tech", entries: [
                        EntryDraft(title: "Phone charger")
                    ])
                ]
            )
        )
        context.insert(document)

        let essentials = StaticListSet(
            id: "packing-trip-essentials",
            title: "Trip Essentials",
            subtitle: "Core travel items you almost always need.",
            kind: .packing,
            sections: [
                SectionDraft(title: "Essentials", entries: [
                    EntryDraft(title: "Contacts")
                ]),
                SectionDraft(title: "Clothes", entries: [
                    EntryDraft(title: "Socks"),
                    EntryDraft(title: "Underwear")
                ]),
                SectionDraft(title: "Tech", entries: [
                    EntryDraft(title: "Phone charger")
                ])
            ]
        )
        StaticListSetService().apply(essentials, to: document)

        let items = document.sortedSections.flatMap(\.sortedEntries).map(\.title)
        XCTAssertEqual(items.filter { $0 == "Socks" }.count, 1)
        XCTAssertEqual(items.filter { $0 == "Phone charger" }.count, 1)
        XCTAssertTrue(items.contains("Underwear"))
        XCTAssertTrue(items.contains("Contacts"))
    }

}
