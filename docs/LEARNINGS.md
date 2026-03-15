# Learnings

## Source Of These Learnings

This document is derived from the current repository state, tests, examples, and git history. There are no session transcripts stored in this repo, so these learnings summarize what the implementation and commits show the project has already learned.

## Product And UX Learnings

- One editor should serve both creation and refinement where possible.
  - The current app leans toward a shared create/generate flow and in-place editing instead of separate parallel experiences.
- Starter sets are more valuable as saved user data than as shipped presets.
  - The persisted `StarterSetDocument` model and editor flow show the product has already moved in that direction.
- Multimodal input is only useful if it becomes a clean editable list.
  - Prompt, voice, and media capture all feed into structured drafts rather than staying as raw notes.

## Data And Model Learnings

- Duplicate handling must happen before insertion, not after.
  - `StaticListSetService` normalizes titles and merges before writing into lists or starter sets.
- Shared draft shapes reduce complexity.
  - `GeneratedListDraft`, `SectionDraft`, and `EntryDraft` let the app use the same shapes across AI output, import/export, persistence conversion, and merge operations.
- Starter sets and lists need parallel data models but common behaviors.
  - The domain model duplicates storage types intentionally while sharing merge and draft conversion behavior.

## AI Learnings

- Raw narrative should not be copied into list items.
  - The Apple Intelligence instructions explicitly push the model to transform context into actionable items.
- Existing items and starter sets must be passed into generation to reduce duplication.
  - The generation request and prompts already include both.
- A fake AI path creates policy drift.
  - The current heuristic/local generation path is practical for unsupported environments, but it conflicts with the project standard that AI list creation must use real model-backed generation or fail clearly.

## Process Learnings From Git History

- The largest recent changes concentrated on list evolution and starter sets, indicating those are the main active product surfaces.
- Recent test additions focus on duplicate-safe merge behavior, sharing round-trips, and generation quality, which indicates those are the highest-risk regression areas.
- `AGENTS.md` began as the home for project standards, but the repo now has enough complexity that those standards need durable product, technical, and architecture documents instead of a single instruction file.
