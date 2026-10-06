# Neural Connect

2D puzzle game in Godot 4.7 (GL Compatibility, GDScript). The player drags neurons so that
dendrites (straight segments) do not cross. Design: `docs/SDD.md`. Plan: `docs/plans/implementation-plan.md`.

## Handoff (read first)

Status: design is complete, **no code implemented yet**. Next step: start the plan at **T0.1**
in `docs/plans/implementation-plan.md` and follow tasks in order, checking each off when done.

Decisions already made (all details in `docs/SDD.md`, do not re-ask):
- Straight-segment dendrites; elasticity is visual only. Aesthetics must stay swappable (logic separate from drawing).
- Special tension dendrite: light green, thins when stretched, breaks at max length, restarts the level. Advanced levels only.
- Win = zero crossings. Crossing dendrites and their neurons are highlighted live.
- Neuron vs neuron: solid, stops at contact but stays grabbed. Neuron vs dendrite: free (crossing is flagged). Obstacles block neurons, not dendrites.
- Red neurons are fixed. Per-level play-area shape and obstacles; living (animated) boundary with fixed collision shape.
- All levels hand-designed ("missions" = fixed story levels in chapters). No procedural levels. Story text every 2-3 missions.
- Scoring: moves AND time to give stars; generous par values, tune later. Move = one full drag.
- Mouse first, touch-ready input. Multi-platform is the long-term goal.
- No external images: all art via code, shaders and particles. Interactive animated menus.
- Architecture: pure `PuzzleModel` (RefCounted) + views; one autoload (`GameState`); signals up, calls down; no EventBus.
- GDScript only. Tests with gdUnit4. Write the model test-first.

Conventions: code, comments, identifiers and UI text in English. Conversation with the user in Spanish (Rioplatense).
Use commits as conventional commits, no AI attribution. The user wanted to be told before implementation starts (they were switching model).

## GodotPrompter

This is a Godot project with GodotPrompter skills available. Before implementing any game system, you MUST check for a matching `godot-prompter:*` skill and invoke it. This applies to all agents, subagents, and sessions working in this repository.

Key skills: `player-controller`, `state-machine`, `event-bus`, `scene-organization`, `component-system`, `resource-pattern`, `godot-ui`, `hud-system`, `ai-navigation`, `camera-system`, `audio-system`, `save-load`, `inventory-system`, `godot-testing`.

For the full skill list, invoke `godot-prompter:using-godot-prompter`.
