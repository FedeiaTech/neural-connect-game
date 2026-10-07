# Feature: localization-and-reset

Objective: user request (2026-10-07) — "be able to reset the levels" and "add Spanish language", decided autonomously (user asked not to be asked).
Interpretation:
- Reset = reset saved campaign progress (all missions back to locked/unplayed, stars and records cleared) from Settings, with a confirmation step; plus reset of a single mission's record from Mission select. In-level restart already exists (HUD button, R key, pause menu) and must stay discoverable.
- Spanish = full localization (en + es): every UI string, mission names, chapter titles/subtitles and story texts; language selector in Settings; default from OS locale (es* → es, else en); saved in the save file.
Constraints: neutral/professional Spanish; default font (covers Latin accents); no new autoloads; Godot 4.7 CSV translations.
Branch: `feat/mvp-foundation`. Slice base: `ed085e3`.

## Tasks (route: delegated direct — writer trigger, 2+ non-trivial files)

- [ ] **T6.1 Progress reset** — GameState API + Settings confirm flow + per-mission reset.
- [ ] **T6.2 Localization infrastructure** — translation CSV, keys in all UI, language setting persisted, live switch.
- [ ] **T6.3 Content translation** — mission names, chapters, story texts in en/es.
- [ ] **T6.4 Docs** — SDD + plan updated.

## Progress / evidence

(none yet)

Engram mirror: pending (engram MCP unavailable this session).
