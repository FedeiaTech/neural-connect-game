# Feature: localization-and-reset

Objective: user request (2026-10-07) — "be able to reset the levels" and "add Spanish language", decided autonomously (user asked not to be asked).
Interpretation:
- Reset = reset saved campaign progress (all missions back to locked/unplayed, stars and records cleared) from Settings, with a confirmation step; plus reset of a single mission's record from Mission select. In-level restart already exists (HUD button, R key, pause menu) and must stay discoverable.
- Spanish = full localization (en + es): every UI string, mission names, chapter titles/subtitles and story texts; language selector in Settings; default from OS locale (es* → es, else en); saved in the save file.
Constraints: neutral/professional Spanish; default font (covers Latin accents); no new autoloads; Godot 4.7 CSV translations.
Branch: `feat/mvp-foundation`. Slice base: `ed085e3`.

## Tasks (route: delegated direct — writer trigger, 2+ non-trivial files)

- [x] **T6.1 Progress reset** — GameState API + Settings confirm flow + per-mission reset.
  - `GameState.reset_progress()` / `reset_mission(id)` (+ `Progress.clear()` / `erase()`); both save at once and emit `progress_changed`; settings untouched.
  - Save semantics: a reset removes the whole mission entry from the save, unknown per-mission keys and unknown (newer) missions included; unknown fields outside the mission records (e.g. `progress.streak`, top-level keys, settings) survive.
  - Per-mission reset clears only that record. Later missions that were completed stay completed (and keep the mission after them unlocked); a mission that was only unlocked by the reset one locks again (linear rule).
  - Settings: "Reset progress" GlowButton swaps for an inline confirmation row (Cancel focused, `ui_cancel` closes it before leaving); confirm shows "Progress reset" for 2.5 s.
  - Mission select: hovering/focusing a completed mission shows a header button "Reset record: mission N"; Delete on a focused completed mission or right-click asks directly; inline confirm; the map is rebuilt (nodes freed at once, no orphans).
  - In-level restart: HUD Restart/Pause buttons got tooltips naming the keys (R, Esc); R action and pause-menu Restart unchanged.
  - Evidence: RED observed for `tests/campaign/test_progress_reset.gd` (missing `erase`/`clear`/`reset_*`), then GREEN; `tests/ui/test_reset_ui.gd` written before the UI but first run after it (not a strict RED). Full suite 357/357, 0 orphans.
- [ ] **T6.2 Localization infrastructure** — translation CSV, keys in all UI, language setting persisted, live switch.
- [ ] **T6.3 Content translation** — mission names, chapters, story texts in en/es.
- [ ] **T6.4 Docs** — SDD + plan updated.

## Progress / evidence

(none yet)

Engram mirror: pending (engram MCP unavailable this session).
