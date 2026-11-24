# Building Spellslingers maps

A map is registered in five places, all keyed by the same id:

- `catalog.ex` `@maps`: id and display name.
- `terrain.ex` `map_shape/2`: the land, as a function of cell centre.
- `assets/js/hooks/arena_art.ts` `maps`, plus `priv/static/images/spellslingers/bg_<id>.webp` (backdrop) and `tex_<id>.webp` (ground texture).
- `assets/js/hooks/spell_arena.ts` `PALETTES`: sky, hills, water, grass, soil, rock.

## Left and right edges

The world stops at column 0 and column `width - 1`, but the camera can pan `EDGE_VIEW` (14) cells past each side, so players always see what lies beyond the edge. The client fills that space from the outer `EDGE_FADE` (22) columns of the map, mirrored, so whatever you put in those columns is what players see past the edge. Shape the outer columns with that in mind:

- **Land at an edge should be ground running down into the sea.** The edge treatment continues the ground surface it finds in the edge column (the first land under open air, or under the ceiling on a cave map) and brings it down into the water. Low, wide ground near the edges reads best. A tall cliff or tower right at the edge gives an abrupt drop.
- **Keep floating platforms and overhangs at least about 6 cells inside each edge.** Anything above the ground surface in the edge strip is not continued, so a platform that touches the edge gets sliced off at the world boundary.
- **Open sea at an edge is fine.** If the edge column has no land above `water_level`, the sea just carries on.
- **Cave maps** (top row mostly rock, like `cavern`) also get their ceiling continued upward. A solid rock wall down the edge column is fine, and is how the cavern finishes its sides.
- **Never let the continued land go translucent over the backdrop.** An earlier edge faded the mirrored land to partial opacity, which showed up as a pink, ghostly copy of the cliff hanging in the sky. Land past the edge is solid and finished with a grass lip and outline like the rest of the land: every map's sides end as a headland, the edge's ground sloping gently (over about 20 cells) into the sea (`buildEdges` in `spell_arena.ts`).

## Checking a new map

Start a Spells match on the new arena with one AI flamingo (turn length at most 120 s, or Start does nothing), skip the tour, then pan to each edge (right-drag or sideways trackpad scroll) at the default zoom and zoomed out (scroll). Look at both edges, and blast land near an edge to check that the continuation updates with the crater. Check the backdrop's parallax at both extremes too: the painting should never run out.
