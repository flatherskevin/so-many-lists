# AGENTS.md

## Project Standards

- Use Apple Intelligence or other real model-backed generation for AI list creation features. Do not replace AI generation with hardcoded item libraries, keyword-to-item maps, canned packing lists, or other fake content generation shortcuts.
- If AI is unavailable in the current environment, fail clearly or use an explicitly labeled fallback path. Do not pretend a heuristic or hardcoded response is AI output.
- Keep list-editing and starter-set-editing flows modular and DRY. Shared behaviors like media intake, voice capture, and intelligence application should be implemented as reusable components.
- Treat starter sets as first-class user data, not app-shipped presets.
- Avoid duplicate list items by normalizing and merging generated content before insertion.
- Prefer precise, minimal UI flows over parallel create/edit screens when the same editor can serve both.
