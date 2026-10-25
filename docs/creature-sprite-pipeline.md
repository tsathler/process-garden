# Creature sprite prototype pipeline

## CV2.0–CV2.1 scope

This is an opt-in art study. It does not change the main scene, `CreatureVisual` production drawing, process species mapping, hitboxes, REAL/DEMO sources, or the GardenController's production visual limit. The current geometric creatures remain available in the comparison scene as the baseline.

Six original transparent PNG idle illustrations are now included: Wisp, Beetle, Moth, Spore, Crystal, and Larva. CV2.1 used the three approved CV2.0 PNGs as visual references for the additional species. No commercial-game art or external asset was used. The referenced concept board was not present as a local image in the repository, so the new assets follow the approved sprite finish and written anatomy/palette direction; no exact matching to that board is claimed. These are single images, not sprite sheets and not frame-by-frame animation.

## Candidate dimensions and display scale

| Property | Prototype value |
|---|---|
| Source PNG canvas | 1254 × 1254 pixels per species |
| Source format | RGBA PNG with transparent corners |
| Current visual target | 34 logical pixels on the longest source dimension |
| Context study | 23–26 logical pixels on the longest source dimension |
| Nearest comparison | Twice each preview's game-scale display size |
| Pivot | Centered `Sprite2D`, zero offset |
| Filtering | `CanvasItem.TEXTURE_FILTER_NEAREST` |
| Frames / animation | One still idle illustration per species; no animated frames yet |

24×24, 32×32, and 48×48 are future authoring candidates, not approved frame sizes. The preview scales the large source PNG at draw time; it does not resample or replace the original art. The 34-pixel target was chosen to compare the art against the existing roughly 30-pixel visual body at the 640×360 logical resolution. Review at game size before choosing a final authored frame size. If accepted, the source assets should be cleaned and authored into a compact frame with consistent padding rather than shipped at this prototype resolution.

## Pixel and alpha rules

- Keep one creature per transparent PNG. Do not combine the concept board or unrelated creatures into a texture.
- Use transparent RGBA corners and preserve clean alpha edges.
- Keep the visual center at the `Sprite2D` origin; reserve padding around tendrils, legs, and wings.
- Keep the visible silhouette within the intended logical bounds at 34 pixels. The existing process hitboxes are unchanged for this prototype; production integration must define and test art-aligned hitboxes before enabling sprites.
- Keep palette and outline language consistent across species. Use nearest-neighbor filtering at every display scale.
- Name static art `<species>_idle.png`; when hand-authored animation is approved, use `<species>_<state>_<frame>.png` or an explicit `SpriteFrames` resource with documented frame rate. Do not describe transform bobbing as frame-by-frame animation.
- Use lossless PNG import for pixel art. Do not enable mipmaps or linear filtering for these sprites.

## Preview and validation

- Comparison: `res://scenes/previews/creature_sprite_preview.tscn` (six sprite species, current Wisp/Beetle baselines, game scale, 2× nearest, and monochrome silhouettes).
- Context density: `res://scenes/previews/creature_density_preview.tscn` (48 decorative sprites, eight per species, independent of process data and garden limits).
- Deterministic resource and compatibility checks: `godot --headless --path garden --script res://tests/run_sprite_prototype_tests.gd`.

Automated tests verify resources, alpha, dimensions, nearest filtering/layout, deterministic production species mapping, current hitboxes, preview sample count, and balanced context density. They do not judge artistic quality. The full six-species collection requires a Windows screenshot review before integration.

## CV2.2 resolution gate

The six approved 1254×1254 source PNGs are immutable references. Their SHA-256 values are checked by `res://tests/run_sprite_resolution_tests.gd`. Each source currently imports losslessly as RGBA8 with mipmaps disabled; preview sprites use centered origins and nearest filtering. Production creatures currently draw at about 34 logical pixels, so resolution candidates must be judged at that display size rather than by inspecting their texture dimensions alone.

`res://scenes/previews/sprite_resolution_preview.tscn` compares each original with 64×64, 96×96, 128×128, and 192×192 candidates in a 640×360 scene. Candidate textures are resized in memory using nearest-neighbor sampling and are not saved or substituted for the approved PNGs. This is a technical downsampling study, not hand-authored pixel art. Its visual gate must confirm eye readability, species-specific anatomy, outlines, alpha edges, and important details before a production frame size is chosen.

Approximate uncompressed RGBA8 storage per frame is 16 KiB at 64², 36 KiB at 96², 64 KiB at 128², and 144 KiB at 192². The four candidate sizes together require about 260 KiB per species, or 1.52 MiB for six species, excluding texture/GPU overhead. A 1254² RGBA8 source is about 6.0 MiB uncompressed, or 36.0 MiB for all six; these are byte-count estimates, not measured runtime memory. The preview holds source and candidate textures together, so its resource usage is intentionally not representative of a production build.

No frame-by-frame animation assets are created at this gate. Once the user approves a resolution, animation production can be evaluated at that size. Transform movement or tint changes must remain documented as procedural effects, not drawn sprite frames. Windows validation commands:

```powershell
$godot = 'C:\tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$project = 'C:\Projects\ProcessGarden'
& $godot --headless --editor --path $project --quit
& $godot --headless --path $project --script res://tests/run_sprite_resolution_tests.gd
& $godot --path $project res://scenes/previews/sprite_resolution_preview.tscn
```

Automated checks establish that candidate sizes, alpha, resource sharing, source hashes, and display scale are correct. They cannot select the best-looking resolution. The resolution and subsequent animation work remain pending visual review of this preview.

## CV2.2-A Wisp and Moth proof

This isolated proof uses the approved Wisp and Moth PNGs as immutable base frames. Three generated pose edits were added for Wisp (tendril pose, middle tail curl, left tail curl) and two for Moth (mid-beat and down-beat). They are exploratory AI-assisted frame edits, not hand-painted pixel art; the approved idle art remains frame zero. The original six PNGs are unchanged and the builder checks the Wisp and Moth hashes before writing anything.

Run `res://tests/build_animation_poc_assets.gd` on Windows to produce the 128×128 working copies under `assets/creatures/prototypes/cozy_mystic/cv22a/128/`. The builder reads source PNGs directly and applies Godot nearest-neighbor resizing; it never overwrites the originals. Runtime `SpriteFrames` resources are built in memory and shared between idle and active playback. The frame sequence is Wisp indices 0→1→2→3→2→1 and Moth 0→1→2→1; active playback changes the playback rate while reusing the same frame textures. A small 1.2 px sinusoidal float in the comparison scene is procedural and is not counted as sprite animation.

Open `res://scenes/previews/animation_poc_preview.tscn` for the approved source, prepared texture, idle loop, active loop, silhouette, and nearest-neighbor enlargement. Open `res://scenes/previews/animation_poc_density_preview.tscn` for 24 decorative Wisp/Moth sprites with deterministic phase offsets. Neither preview uses process data or changes production species, hitboxes, GardenController, or the main scene.

The prepared frame set contains seven unique 128×128 RGBA8 images: four Wisp poses and three Moth poses. At 4 bytes per pixel, the nominal uncompressed frame payload is about 448 KiB. The two previews additionally load the original Wisp and Moth textures for comparison; driver allocations and imported texture overhead are not measured here. Frame consistency, loop quality, low-resolution facial detail, and contextual density still require Godot Windows screenshots and user approval. These generated edits are not accepted production art until that review.

## CV2.2-B six-species animation study

The isolated study now uses the same 128×128 working size for all six species. It keeps the approved idle PNGs immutable and verifies their SHA-256 values before building working frames. Wisp and Moth reuse their existing CV2.2-A source poses. Beetle, Spore, Crystal, and Larva each add one transparent, AI-assisted pose edit under `assets/creatures/prototypes/cozy_mystic/cv22b/source/`; these edits preserve the reference sprite as closely as the image-editing output allowed, but they are exploratory art rather than hand-painted frames and still need visual approval.

| Species | Unique prepared frames | Loop | Pose change |
|---|---:|---|---|
| Wisp | 4 | 0→1→2→3→2→1 | Existing tail/tendril pose edits from CV2.2-A |
| Beetle | 2 | 0↔1 | Existing shell/head with an alternate leg stance and slight antenna bend |
| Spore | 2 | 0↔1 | Gentle cap/filament sway; face and body remain stable |
| Crystal | 2 | 0↔1 | Small support/stance change with the same crystal arrangement |
| Moth | 3 | 0→1→2→1 | Existing open, mid-beat, and down-beat wing poses from CV2.2-A |
| Larva | 2 | 0↔1 | Subtle segment and foot wave with the head held nearly steady |

The two-frame loops are intentionally slow and alternate between the approved idle and one authored pose. Idle and active `SpriteFrames` animations share the same textures; active mode changes playback rate, not anatomy. The comparison preview also applies a separate one-pixel procedural float. That float is not counted as drawn-frame animation. The preview shows all species at once in static, animated, 2× nearest, and monochrome silhouette views. The context scene contains 48 decorative `AnimatedSprite2D` nodes, eight per species, with stable phase offsets derived from a small deterministic identity hash and one shared `SpriteFrames` resource per species. Neither scene touches the main scene or process systems.

The standardized set has 15 unique 128×128 RGBA8 textures (4 Wisp, 2 Beetle, 2 Spore, 2 Crystal, 3 Moth, 2 Larva). At four bytes per pixel, the uncompressed frame payload is about 960 KiB, excluding texture-driver overhead. Prepared images are generated only by `res://tests/build_animation_poc_assets.gd`; that script skips already valid 128×128 RGBA outputs and refuses to overwrite invalid existing outputs. The `SpriteFrames` objects are shared per species in each preview, and their idle/active states reuse texture references.

Run the following on Windows after synchronizing the changed preview/test scripts and `cv22b/source` images. The builder creates `cv22b/128` in the Godot project before the animation tests load those frames. This remains an art study: automated tests can verify integrity and distinct pixels, but only Windows screenshots and review can approve pose fidelity, loop smoothness, and density.

```powershell
$godot = 'C:\tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$project = 'C:\Projects\ProcessGarden'
& $godot --headless --editor --path $project --quit
& $godot --headless --path $project --script res://tests/build_animation_poc_assets.gd
& $godot --headless --path $project --script res://tests/run_animation_poc_tests.gd
& $godot --headless --path $project --script res://tests/run_sprite_prototype_tests.gd
& $godot --headless --path $project --script res://tests/run_tests.gd
& $godot --path $project res://scenes/previews/animation_poc_preview.tscn
& $godot --path $project res://scenes/previews/animation_poc_density_preview.tscn
```

## CV2.3-A production renderer integration

The approved 15 files from `prototypes/cozy_mystic/cv22b/128/` are copied byte-for-byte into `assets/creatures/cozy_mystic/128/`. The production runtime reads only this stable directory; it does not run the preview builder. The 1254×1254 approved source PNGs and CV2.2 preview assets remain unchanged.

`CozyMysticSpriteLibrary` lazily creates and caches one shared looping `SpriteFrames` resource per species. Each `AnimatedSprite2D` owns its own frame/playback state and uses nearest filtering at a 34 logical-pixel display size. CPU activity drives bounded, smoothed per-instance `speed_scale`; shared `SpriteFrames` resources are not mutated. RAM retains the existing bounded creature scale. The current pose loops are frame-based; vertical float, small body sway, scale, and brightness remain procedural.

`ProcessCreature` remains the process identity, movement, metric, lifecycle, and selection owner. `GardenController` switches the same creature nodes between `LEGACY` and `COZY_MYSTIC`; selection, identity, positions, metrics, and sprite phase are retained. Cozy visuals are created lazily so a normal LEGACY run does not pay for extra renderer nodes. The current legacy drawing code has four forms; the two new art species map to its closest old forms (Moth→Wisp, Larva→Beetle) only while LEGACY is shown. The canonical six-species identity mapping is shared between both render modes, and the details panel names that canonical species.

Select `COZY` in the main header to enable the sprite renderer, or `LEGACY` to return. A resource preflight checks all six species before switching; a missing or invalid frame keeps LEGACY active and reports an error. The sprite hitbox is derived from each species' opaque frame bounds with a small click margin. The existing selection order and identity-based panel behavior remain in `GardenController` and `Main`.

The 15 RGBA8 128×128 frames contain approximately 960 KiB of uncompressed pixel data (15 × 128 × 128 × 4 bytes), excluding GPU/import overhead. With LEGACY selected, no Cozy child nodes are created. In Cozy mode each represented process adds one `AnimatedSprite2D`; the species' `SpriteFrames` and texture references are shared.

### CV2.3-A paired renderer benchmark

Measured on Windows with Godot 4.7.2, Compatibility/OpenGL 3.3, NVIDIA RTX 5060 (driver 617.14), seed 2025, 5 s warmup and 30 s measurement. Each renderer/scenario pair used the same `run_benchmark.gd`; only `--renderer` and `--scenario` differed. Runs were isolated per scenario after the all-scenarios invocation stopped after preparing scenario 150; the reason for that interruption was not established. The table records observed results and does not attribute isolated frame spikes to a cause.

| Processes | LEGACY avg FPS | COZY avg FPS | LEGACY p95 frame (ms) | COZY p95 frame (ms) | LEGACY max frame (ms) | COZY max frame (ms) |
|---:|---:|---:|---:|---:|---:|---:|
| 50 | 60.03 | 60.03 | 16.708 | 16.720 | 17.269 | 43.987 |
| 150 | 59.30 | 59.07 | 16.679 | 16.690 | 66.304 | 81.963 |
| 300 | 57.53 | 57.30 | 16.691 | 16.697 | 158.636 | 166.788 |
| 500 | 52.70 | 54.80 | 16.712 | 16.692 | 409.644 | 265.297 |

All eight completed runs recorded zero orphan nodes and zero invalid snapshots. The maximum represented population was 51 in the 50-process scenario and 60 in the other scenarios. Cozy's maximum node count was 60 higher than LEGACY's, corresponding to one lazily created `AnimatedSprite2D` for each represented creature. Static-memory monitor start/end readings (MiB) were: LEGACY 33.45→34.02, 33.52→34.11, 33.98→34.60, 34.96→35.43; COZY 32.97→33.92, 33.40→34.06, 33.86→34.95, 34.47→35.19. These are per-run monitor samples, not proof of leak absence. Average FPS and p95 frame times are close between renderers; isolated maximum frame times remain variable and unexplained. This synthetic, instrumented benchmark is not an exact measurement of ordinary interactive use.

The GDScript validation copy also passed `run_tests.gd` (863), `run_animation_poc_tests.gd` (290), `run_sprite_prototype_tests.gd` (62), and `run_sprite_resolution_tests.gd` (273), each with zero failures and no `ERROR:`/`SCRIPT ERROR:` output. These tests do not replace visual review of the six species in the production garden or manual REAL/DEMO/reconnect checks.

For comparable benchmarks, use the same runner and identical duration, warmup, seed, scenarios, Godot build, window size, and machine, changing only `--renderer`:

```powershell
$godot = 'C:\tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$project = 'C:\Projects\ProcessGarden'
& $godot --path $project --script res://tests/run_benchmark.gd -- --renderer=legacy --duration-seconds=30 --warmup-seconds=5 --seed=2025
& $godot --path $project --script res://tests/run_benchmark.gd -- --renderer=cozy_mystic --duration-seconds=30 --warmup-seconds=5 --seed=2025
```

The benchmark CSV records `visual_renderer`. The WSL implementation pass does not establish Windows graphical performance or artistic approval; both remain validation gates.
