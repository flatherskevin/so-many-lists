# Product Requirements

## Product Summary

So Many Lists is an iOS app for quickly turning messy intent into usable lists. Users should be able to create lists manually, generate them from AI-supported inputs, refine them in place, save reusable starter sets, and share/import lists cleanly.

## Core User Outcomes

- Create a list quickly with minimal typing.
- Turn prompt, voice, photo, or video context into a structured list draft.
- Edit generated output directly without switching to a separate editing product surface.
- Save reusable starter sets that reflect the user's own recurring needs.
- Apply starter sets and AI additions without introducing duplicate items.
- Share a list in a human-readable format and re-open it in the app via import.

## Supported Product Behavior

- The app must support at least these list kinds:
  - General
  - Grocery
  - Packing
  - Trip Plan
- AI-assisted generation should produce concise sections and actionable entries rather than copying user narrative verbatim.
- Starter sets are first-class user data.
  - They are created, stored, edited, and reused by the user.
  - They are not app-shipped preset bundles masquerading as user content.
- List creation and list editing should stay precise and minimal.
  - Prefer a shared editor or shared interaction patterns over parallel create/edit screens when the same editor can serve both.

## AI And Intelligence Requirements

- Use Apple Intelligence or another real model-backed generation path for AI list creation features.
- Do not replace AI generation with hardcoded item libraries, keyword-to-item maps, canned packing lists, or similar fake-generation shortcuts.
- If AI is unavailable in the current environment, the app must fail clearly or expose an explicitly labeled fallback path.
- The app must never present heuristic or hardcoded output as if it came from AI.

## Starter Set And Merge Requirements

- Applying a starter set must feel additive, not destructive.
- Generated content and starter set content must be normalized and merged before insertion.
- Duplicate items should be avoided even when wording differs by case, plurality, or minor formatting.

## Non-Goals

- Shipping fixed built-in starter set catalogs as the primary starter-set experience.
- Splitting the product into separate manual-edit and AI-edit product lines.
- Treating raw attachment or transcript input as the final user-facing list output.
