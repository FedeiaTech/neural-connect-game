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
- [x] **T6.2 Localization infrastructure** — translation CSV, keys in all UI, language setting persisted, live switch.
  - `locale/translations.csv` (`keys,en,es`, semantic UPPER_SNAKE keys: `MENU_*`, `COMMON_*`, `SETTINGS_*`, `MISSIONS_*`, `HUD_*`, `SUMMARY_*`, `PAUSE_*`), registered in `project.godot` `internationalization/locale/translations`.
  - Translation files: the CSV importer writes `locale/translations.{en,es}.translation` next to the CSV (not under `.godot/`); those are the resources the project setting loads at runtime, so they are committed with `translations.csv.import`. Re-import is byte-identical (hash checked).
  - Scenes hold keys; Labels/Buttons auto-translate. Formatted texts are built with `tr()` and rebuilt on `NOTIFICATION_TRANSLATION_CHANGED`: HUD moves/summary stats/tooltips, chapter headings ("Chapter %d: %s"), mission tooltips, mission-select reset texts. `GlowTitle` draws `atr(text)` and re-measures on the notification. The game name "Neural Connect" stays untranslated.
  - `GameState.language` ("en"/"es") saved under `settings.language`; missing/invalid -> `default_language_for(OS.get_locale_language())` (es -> es, else en). The resolved value is written on the next save. `set_language()` applies `TranslationServer.set_locale` live and saves. Settings has an OptionButton "English"/"Español" (auto-translate disabled).
  - Tests: the sandbox and text-asserting suites force `en` and restore the locale. `tests/localization/test_localization.gd` covers table completeness, placeholders, registration, every scene text being a key, default/persistence/invalid language, live switch of GlowTitle, HUD and chapter headings. RED observed (parse errors: missing `default_language_for`, `get_language_selector`); GREEN 370/370.
- [ ] **T6.3 Content translation** — mission names, chapters, story texts in en/es.
- [ ] **T6.4 Docs** — SDD + plan updated.

## Progress / evidence

(none yet)

Engram mirror: pending (engram MCP unavailable this session).
