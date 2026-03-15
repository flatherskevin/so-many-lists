# Technical Requirements

## Platform And Stack

- The app is an iOS SwiftUI application.
- SwiftData is the persistence layer for lists and starter sets.
- AI generation integrates with Apple Intelligence and `FoundationModels` when available.

## Architecture Requirements

- Keep list-editing and starter-set-editing flows modular and DRY.
- Shared behaviors such as media intake, voice capture, and intelligence application should be implemented as reusable components or shared flow logic.
- Maintain draft-based conversion boundaries between UI, generation, merge logic, sharing, and persistence.
- Treat list documents and starter set documents as separate persisted entities with parallel behavior, not as the same record type with ad hoc flags.

## AI Implementation Requirements

- Real model-backed generation is required for AI list creation features.
- If AI is unavailable, the app must either:
  - fail clearly, or
  - use an explicitly labeled fallback path that is not presented as AI output.
- Any fallback implementation must be visibly distinct from AI-generated output in code and product behavior.
- Generation requests should carry prompt, voice transcript, media context, starter sets, and existing items when available so the model can avoid duplication and better structure output.

## Data Integrity Requirements

- Normalize item titles before merge and insertion.
- Merge logic must avoid duplicate entries across generated content, starter sets, and existing list content.
- Section and entry ordering must remain stable through explicit sort order fields.
- Import/export payloads must round-trip through a documented codec format without silent corruption.

## Persistence And Sharing Requirements

- Persist both lists and starter sets locally through SwiftData.
- Share/export should include both readable text and an app-importable payload.
- URL import handling must fail safely with a user-visible error state when payload decoding fails.

## Testing Requirements

- Maintain unit coverage for:
  - share codec round-trip behavior
  - duplicate-safe merge behavior
  - starter set application behavior
  - generation output quality guards for representative prompts
  - duplication behavior resetting list identity and completion state
- Add or update tests whenever merge normalization, generation behavior, or persistence conversion changes.

## Current Implementation Gap

- The repository currently contains a heuristic local draft builder used as a generation fallback in unsupported environments.
- That implementation is useful for development continuity, but it does not satisfy the stricter project requirement that AI list creation rely on real model-backed generation unless the product explicitly labels the fallback as non-AI behavior.
