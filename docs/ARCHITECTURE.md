# Architecture

## Summary

So Many Lists is an iOS SwiftUI app backed by SwiftData. It helps users create, edit, extend, store, and share structured lists, with support for AI-assisted draft generation and reusable starter sets.

## System Shape

- `So_Many_ListsApp` bootstraps the SwiftData `ModelContainer`, injects `AppState`, and routes incoming share URLs into the app import flow.
- `ContentView` is the main library shell. It owns navigation into list detail, create/generate flows, starter set management, and app feature surfaces.
- `AppState` holds app-wide transient state for shared-list import handling and announcement dismissal state.

## Persistence Model

SwiftData stores two first-class document types:

- `ListDocument`
  - Stores a user list, source metadata, timestamps, and ordered sections.
  - Contains `ListSectionModel`, which contains ordered `ListEntry` rows.
- `StarterSetDocument`
  - Stores a reusable user-defined starter set, subtitle, timestamps, and ordered sections.
  - Contains `StarterSetSectionModel`, which contains ordered starter-set entries.

Draft structs such as `GeneratedListDraft`, `SectionDraft`, and `EntryDraft` act as transfer shapes between UI, AI generation, merge logic, sharing, and persistence.

## Service Boundaries

- `PreferredListGenerationService`
  - Entry point for list generation.
  - Prefers Apple Intelligence on supported environments.
  - Currently falls back to a local heuristic draft builder when Apple Intelligence is unavailable.
- `AppleIntelligenceListGenerationService`
  - Uses `FoundationModels` and `SystemLanguageModel`.
  - Produces structured sections and entries from prompt, voice, attachments, existing list items, and starter sets.
- `HybridLocalListGenerationService` and `HeuristicDraftBuilder`
  - Build non-model-backed drafts locally.
  - Useful for local development, but this behavior is in tension with project policy requiring real model-backed AI for AI generation features.
- `StaticListSetService`
  - Merges starter sets or AI-generated additions into a list or starter set.
  - Normalizes entry titles to avoid duplicates across sections.
- `ListLibraryService`
  - Handles list duplication while resetting identity and completion state.
- `ListShareCodec`
  - Encodes and decodes `SharedListPayload` into the `somanylists://import` URL format.

## Primary Flows

- Library flow
  - Browse, search, duplicate, delete, and share saved lists.
- Create flow
  - Start a manual list or generate a draft from prompt, voice, and media inputs.
  - Optionally apply selected starter sets before save.
- List detail flow
  - Edit sections and entries directly.
  - Extend an existing list with AI while preventing duplicate insertions.
- Starter set flow
  - Create, edit, and save reusable starter sets as user-owned data.
  - Extend starter sets with AI using the same merge rules used for lists.
- Sharing/import flow
  - Export a list as readable text plus a deep link payload.
  - Import shared payloads through app URL handling.

## Cross-Cutting Constraints

- Ordered content is preserved through `sortOrder` on sections and entries.
- Duplicate prevention is implemented by normalized title matching rather than exact string equality.
- Voice capture, media intake, and AI application are embedded in the UI layer but should remain modular and reusable across list and starter-set editing flows.
