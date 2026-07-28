# Gradientfall documentation map

Gradientfall's documentation separates the playable truth, the long-range
vision, the world canon, and the development record. Start with the path that
matches your question.

| If you want to... | Read |
| --- | --- |
| Understand the game and its design pillars | [`GDD.md`](GDD.md) |
| See what is implemented, next, or still gated | [`ROADMAP.md`](ROADMAP.md) |
| Follow the newest engineering and visual decisions | [`DEVLOG.md`](DEVLOG.md) |
| Learn the regions, characters, creatures, and ML metaphors | [`WORLDBOOK.md`](WORLDBOOK.md) |
| Navigate the continent and regional relationships | [`WORLD_ATLAS.md`](WORLD_ATLAS.md) |
| Understand runtime boundaries and system wiring | [`ARCHITECTURE.md`](ARCHITECTURE.md) |
| Add or validate authored JSON content | [`CONTENT_PIPELINE.md`](CONTENT_PIPELINE.md) |
| Understand the autonomous-work quality bar | [`AUTONOMY.md`](AUTONOMY.md) |

## Evidence and art direction

- [`progress/`](progress/) contains in-engine evidence tied to completed
  milestones, including Kern studies, Datasedge Meadows, Bootstrap, and time-of-day
  captures.
- [`concept-art/`](concept-art/) contains clearly labeled mood studies for
  future regions. These images guide tone; they are not presented as current
  gameplay or locked canon.
- [`assets/`](assets/) contains repository presentation artwork such as the
  social preview.

## Content production

- [`briefs/`](briefs/) holds self-contained authoring briefs.
- Runtime-ready records live under [`../content/approved/`](../content/approved/).
- New records enter through [`../content/inbox/`](../content/inbox/) and must
  pass `python tools/validate_content.py --inbox` before promotion.
- Schemas under [`../content/schemas/`](../content/schemas/) are the structural
  contract for all seven content types.

## Current verification

The repository's `verify` workflow and local validator check content structure,
Python tooling, and Godot script parsing. Visible milestones also require
human inspection of rendered evidence; a clean headless boot is necessary but
does not substitute for that visual gate.

[Return to the project README](../README.md)
