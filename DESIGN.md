# Process Garden — Digital Wildlife Sanctuary

**Visual Style Guide v2.0**
**Status:** Proposed art direction
**Engine:** Godot 4.7.2
**Logical resolution:** Keep the current project settings
**Style:** Bioluminescent pixel art, digital microfauna, field observatory

## 1. Product identity

Process Garden is an artificial ecosystem whose organisms represent real or simulated computer processes. The experience should communicate life, mystery, calm, and precision. The interface is an instrument for observing the garden; the creatures remain the visual focus.

Use *Rain World*, *DREDGE*, and *Into the Breach* as broad references for atmosphere, interface restraint, and legibility. Do not copy their assets, layouts, or visual identity.

## 2. Creature design language

Each species should have:

- A silhouette recognizable at its actual on-screen size, including without color.
- Consistent anatomy, a limited palette, a dark readable outline, and a bioluminescent core or mark.
- One primary animation and one restrained secondary animation.
- A hitbox that follows its visible geometry.
- Small, deterministic variations derived from the full process identity `(pid, create_time)`.

Keep details large enough to read at game scale. A visual variant must not change the base species when CPU or RAM changes, and snapshots must not reroll its appearance.

### Species direction

| Species | Anatomy | Primary motion | Dominant color |
|---|---|---|---|
| Wisp | Ethereal drop and fins | Organic floating | Mint |
| Beetle | Carapace and legs | Firm movement and sway | Green |
| Spore | Mushroom cap and stem | Gentle pulse and bob | Violet |
| Crystal | Facets and core | Restrained floating | Ice blue |
| Moth | Wings and antennae | Flutter and short arcs | Cream lilac |
| Larva | Segmented body | Undulation and low travel | Teal green |

Wisp, Beetle, Spore, and Crystal are the current implemented set. Moth and Larva are proposed additions; this guide alone does not imply that they are implemented.

Plan up to three subtle anatomical variants per species. Hash the stable process identity to select a variant. Variants may adjust antennae, segments, facets, spots, or proportions; they should preserve the species silhouette and hitbox rules.

## 3. Color tokens

These are reference tokens. Keep the existing cave palette coherent; do not replace colors solely to match the table.

| Role | Color | Hex |
|---|---|---|
| Abyss | Environment | `#090E1C` |
| Deep Rock | Environment | `#111A2C` |
| Stone | Environment | `#17243B` |
| Subtle Border | Interface/environment | `#34516A` |
| Wisp | Organism | `#45DCC2` |
| Beetle | Organism | `#88D89B` |
| Spore | Organism | `#C59CE8` |
| Crystal | Organism | `#9AD8FF` |
| Moth | Organism | `#E9CE9D` |
| Larva | Organism | `#79B8A1` |
| Primary Text | Interface | `#F2F7FD` |
| Secondary Text | Interface | `#91ACC2` |
| Active | Interface | `#91E9C7` |
| Attention | Interface | `#E8C773` |
| Disconnected | Interface | `#E28C9C` |

Use text as well as color to communicate connection state.

## 4. Animation language

Creature motion may combine five bounded layers:

1. Species movement: floating, firm travel, pulsing, or fluttering.
2. Rest animation: breathing or a slow pulse.
3. CPU response: a restrained change in energy, speed, or glow.
4. Selection: a clear but modest highlight.
5. Lifecycle and connectivity: spawn, despawn, and truthful data freshness.

Preserve the existing CPU behavior mapping and RAM-to-size mapping. Smooth changes over time, cap visual extremes, and avoid jumps, excessive tremble, or animation that makes the hitbox disagree with the visible organism. Null CPU remains unavailable data, not zero.

## 5. Environment

Keep the current cave, fungi, rocks, ground, and ambient particles. Improve the setting incrementally through geological asymmetry, varied vegetation, restrained organic halos, foreground/background depth, and clear separation between decoration and selectable organisms.

Environment decoration must not intercept creature clicks. Prefer the existing Godot `CanvasItem` approach and Compatibility renderer. Avoid many per-creature lights, costly full-screen effects, and unnecessary shaders.

## 6. Field Observatory interface

The interface should read as a compact instrument for observing an unfamiliar ecosystem.

- **Header:** compact title, source mode, connection state, process and creature counts, and existing DEMO controls.
- **Specimen card:** process name, species, PID, CPU, RAM, and data freshness. Leave room for a larger creature portrait in a future iteration.
- **Connectivity:** show `CONNECTED`, `STALE`, `DISCONNECTED`, or `DEMO` in text and color.
- **Interaction:** visible selection, keyboard focus for controls, and no invisible control blocking the garden.

Keep REAL and DEMO unmistakable. Never present simulated records as real processes or stale metrics as current. Do not show command lines, full executable paths, user data, or other private process information.

Preserve the current logical resolution, pixel-art scaling, and window aspect behavior. Test both the default and enlarged window sizes; do not trade legibility for a rigid layout.

## 7. Technical and scope constraints

- Preserve the Compatibility renderer, process identity `(pid, create_time)`, deterministic DEMO source, snapshot contract, and current 30-creature visual limit.
- Reuse native Godot `CanvasItem` and UI controls; add no required external assets or dependencies.
- Keep profiling disabled in normal application use.
- Do not add complex physics, reproduction, combat, extensive AI, progression, a full bestiary, advanced filters, post-processing-heavy effects, or multiple functional biomes under this direction alone.
- The art direction does not authorize changes to process collection, API behavior, or snapshot semantics.

## 8. Visual approval checklist

Approve a species when its silhouette reads without color at actual game size, its motion is stable, its hitbox matches its shape, selection works, and it belongs to the same visual world as the other species.

Approve a wider visual set when:

- All species feel like inhabitants of one coherent ecosystem.
- Organisms remain distinct from the cave and from one another at up to 30 represented creatures.
- Selection, metrics, REAL/DEMO identity, and connection freshness remain legible.
- Resizing does not hide or overlap important controls.
- Automated tests, click interaction, and Windows graphical review pass.

## 9. Performance reference

The E04 Windows benchmark used Godot 4.7.2, seed 2025, and 30 seconds per scenario. Reported average FPS for 50 / 150 / 300 / 500 processes was **60.03 / 59.10 / 57.57 / 54.83**. It reported zero invalid snapshots, zero orphan nodes, and no more than 60 creatures under the earlier cap. This is a synthetic instrumented benchmark, not a promise of normal-use FPS. Do not treat small run-to-run differences as a regression by themselves. Preserve the method and limitations in [`docs/e03.2-benchmark.md`](docs/e03.2-benchmark.md).

## 10. Current implementation note

At the time this guide was added, four species are implemented. E04.3 interface changes have passed the headless GDScript suite, while their Windows graphical review and benchmark remain pending. The guide records the proposed direction; it does not mark those pending gates as approved.
