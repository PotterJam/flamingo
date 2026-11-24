# Building Spellslingers maps

A map is registered in five places, all keyed by the same id:

- `catalog.ex` `@maps`: id and display name.
- `terrain.ex` `map_shape/2`: the land, as a function of cell centre.
- `assets/js/hooks/arena_art.ts` `maps`, plus `priv/static/images/spellslingers/bg_<id>.webp` (backdrop) and `tex_<id>.webp` (ground texture).
- `assets/js/hooks/spell_arena.ts` `PALETTES`: sky, hills, water, grass, soil, rock.

## Left and right edges

The playable world stops at column 0 and column `width - 1`, marked on screen by a dashed line at each side (`drawEdgeLines` in `spell_arena.ts`). Walking, flying and jumping stop at the line as at a wall (`Units.blocked?/4`). A knock is the one thing that carries a wizard past it (`knock_step` in `physics.ex`). Past the line there is nothing to land on, so the wizard falls until the sea gets them; crossing the line itself does no harm.

The map itself never visibly ends. The camera can pan `EDGE_VIEW` (14) cells past each side, and the client fills everything past the line with the outer `EDGE_FADE` (22) columns of the map, mirrored, so the ground and sea carry on seamlessly beyond the line and off the screen (`buildEdges`). Shape the outer columns with that in mind:

- **Whatever is in the outer 22 columns is what players see past the edge.** Low, wide ground or open sea reads best. A tall cliff, tower or overhang at the edge is mirrored as a twin on the far side of the line.
- **Remember that land past the line is scenery.** A wizard knocked over the line falls past it into the sea, so ground near an edge is where a good knock wins the duel.
- **Cave maps** (top row mostly rock, like `cavern`) also get their ceiling continued upward. A solid rock wall down the edge columns is fine, and is how the cavern stops people walking off its sides.
- **Never let the continued land go translucent over the backdrop.** An earlier edge faded the mirrored land to partial opacity, which showed up as a pink, ghostly copy of the cliff hanging in the sky. A later one sloped the land down into the sea as a headland just past the edge, which still looked like the map stopping. The mirrored land is drawn solid, at full strength, with no slope.

## Checking a new map

Start a Spells match on the new arena with one AI flamingo (turn length at most 120 s, or Start does nothing), skip the tour, then pan to each edge (right-drag or sideways trackpad scroll) at the default zoom and zoomed out (scroll). Look at both edges: the land should run on past the dashed line to the screen's edge. Blast land near an edge to check that the continuation updates with the crater. Check the backdrop's parallax at both extremes too: the painting should never run out.
