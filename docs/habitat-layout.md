# Habitat layout and environmental pass

`HabitatLayout` is the shared geometry source for environmental support art and
creature placement. It does not change process identity, selection, the visual
cap, REAL/DEMO data sources, or either visual renderer. The current E05.2
worktree sets the represented-creature cap to 30; process monitoring remains
unfiltered.

## Species and habitat

| Species | Eligible habitat | Movement intent |
| --- | --- | --- |
| Wisp | Three AIR regions | Free, local two-dimensional drift |
| Moth | Three AIR regions | Local drift through open gaps |
| Beetle | Main ground, grounded rises and low perches | Short movement along a support segment |
| Larva | Main ground and connected low ground rises | Short ground-following crawl |
| Crystal | Ground, grounded rises and stable perches | Restrained movement on supported surfaces |
| Spore | Fungal ground and mushroom caps | Small movement on moss or fungal support |

Supported creatures keep their navigation origin on the modeled surface. The
visual is offset by the opaque lower extent measured across that species'
frames, including the current RAM scale. Air creatures use their declared
regions. Habitat and species remain stable for the lifetime of the existing
`(pid, create_time)` identity, including renderer changes.

## Deterministic placement

Initial placements are assigned in sorted identity order. Existing nodes keep
their anchors across snapshots. For a new identity, the layout evaluates the
eligible surface or air candidates and compares their visible envelopes with
the occupied visual envelopes. A stable hash of identity, profile ID and
candidate index resolves equal scores. If all compatible sites are occupied,
placement chooses the least-overlapping candidate; terrestrial species remain
on ground or a drawable perch. The current 30-node visual cap includes
despawning nodes.

Air candidates use a fixed Halton sequence inside three non-overlapping
regions. This provides deterministic, non-grid scatter without per-frame
randomness. Candidate generation and placement only run when the represented
population changes.

### E05.1-C composition pass

The previous greedy placement measured only center-to-center distance. The
approved animation frames have opaque bounds close to the 128×128 canvas, so at
the 34 px display size most species occupy roughly 32–34 logical pixels before
RAM scaling. The old 7 px candidate interval therefore allowed distinct
anchors whose visible bodies covered one another.

Placement for newly represented identities now compares cached alpha bounds
unioned across every source frame. The bounds are scaled with the same 34/128
display factor and a conservative RAM scale; supported creatures are aligned
to the modeled contact surface before their rectangle is evaluated. Occupied
creatures include a small motion allowance in addition to visual clearance;
this is a local buffer, not a full territory reservation. Candidate scoring first penalizes intersecting visual
areas, then prefers the greatest nearest-edge clearance. Stable identity,
surface ID and candidate index break ties. Existing identities retain their
current position and habitat across snapshots. New placement is still event
driven and does not run every frame.

The controller exposes `get_composition_metrics()` for diagnostics and the
benchmark CSV records overlap-pair count, summed AABB overlap area, unsupported
grounded occupants, potential interface intersections, saturated surfaces,
and maximum occupancy of one surface. AABB overlap is a conservative
composition signal; it does not prove that a face is hidden. The interface
intersection count includes the fixed details-panel footprint even when that
panel is closed, so it describes potential occlusion, not the visible pixels
covered in a particular frame. Capacity is estimated per surface from the
largest opaque frame envelope among eligible species, scaled to the 34 px
display size and maximum RAM scale, with visual and movement margins. Air
capacity uses a conservative rows-by-columns fit; supported-surface capacity
uses its usable horizontal span. This estimate is diagnostic only, not an
enforced population limit, and it does not model individual face visibility.

The optional GardenController `show_composition_debug` overlay draws the same
envelopes: cyan indicates no AABB intersection and rose indicates an
intersection. It is off by default. This debug work is performed only while
that option is enabled.

### Ground terrain supports

Four shallow ground rises add distinct vertical support lines for Larva,
Beetle and Crystal. These are connected earth and moss mounds, not floating
platforms. Their top contours, profile ranges and rendered polygons come from
the same HabitatLayout data; both ends meet the shared ground contour. Larva
remains restricted to ground-kind surfaces. The existing branches, mineral
outcrop, fungal caps and three-region Halton air layout remain in place.

### Measurement and comparison

The occupancy diagnostics are newly exposed by this pass; no numerical
E05.1-B occupancy baseline was captured, so no before/after reduction is
claimed. Use the same Godot 4.7.2 machine, renderer, DEMO seed 2025, warmup,
scenario duration and populations for future comparisons. The benchmark CSV's
new composition columns are final-scenario measurements; they do not add
per-frame profiling overhead. Compare `overlap_pairs` and `overlap_area_px2`
alongside FPS, maximum frame time, node count, orphans and invalid snapshots.
The overlap sum can count the same pixels more than once when an organism
intersects several neighbors.

## Environmental geometry

The E05.1-B pass adds five modeled, drawn supports: two wall shelves, two
root-supported branches and a central mineral shelf. Their top surfaces and
their support points come from the same profiles used by placement. The ground
contour remains shared by creature navigation, the soil silhouette, moss
marks, root feet and mushroom bases.

Six mushroom structures are rooted on the contour. Spore anchors use the
short flat cap section actually drawn, rather than the wider brim. Decorative
halos, moss marks, rock facets and ambient motes do not create input or habitat
nodes. The environment remains a single CanvasItem behind the creature layer;
it cannot intercept creature clicks.

Painter order is background, distant rock, supported midground structures and
fungi, ground, edge foreground, then ambient decoration. Ground fill is drawn
after the branch and mineral bodies so their lower ends visually join the soil.
The existing 18 deterministic ambient motes still update at a capped 20 Hz.

## Validation

The headless suite includes deterministic checks for species eligibility,
non-row air scatter, opaque visual envelopes, RAM-scaled bounds,
envelope-aware placement, composition diagnostics, ground-rise geometry,
mushroom/ground alignment, stable placement, renderer changes, hit testing and
the current 30-creature cap. A separate placement stress fixture checks 60
distinct logical ground anchors; it is not a product population setting. Run with
Godot 4.7.2 on Windows:

```powershell
& 'C:\tools\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --editor --path 'C:\Projects\ProcessGarden-CV23A-Validation' --quit
& 'C:\tools\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Projects\ProcessGarden-CV23A-Validation' --script res://tests/run_tests.gd
```

The current WSL session cannot launch the Windows Godot runtime, so these
changes require Windows import and suite execution, followed by graphical
review in REAL and DEMO with both renderers. Headless tests do not approve the
composition visually. In the graphical run, inspect all six species at the
30-creature limit, then enable `Garden.show_composition_debug` from the Remote
Inspector to inspect envelopes and compare the resulting diagnostic values.
