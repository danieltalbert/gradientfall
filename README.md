# Gradientfall

[![Content + Godot CI](https://github.com/danieltalbert/gradientfall/actions/workflows/verify.yml/badge.svg)](https://github.com/danieltalbert/gradientfall/actions/workflows/verify.yml)
[![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478CBF?logo=godot-engine&logoColor=white)](https://godotengine.org/)
[![Status: active vertical slice](https://img.shields.io/badge/status-active%20vertical%20slice-7b61ff)](docs/ROADMAP.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-59d6a4.svg)](LICENSE)

Gradientfall is an in-development 3D action-adventure that turns machine-learning concepts into geography, combat, quests, and exploration. The current build is an honest **vertical slice**: a playable Datasedge Meadows environment with a third-person controller, data-driven content, real-time combat foundations, the Bit companion, and a deliberately ambitious code-authored visual stack.

![Gradientfall portfolio preview](docs/assets/social-preview.png)

## What is working today

- Godot 4.7 project with a typed GDScript architecture and autoload-based state/event boundaries.
- Third-person movement and camera controls in a generated 3D landscape.
- Melee/ranged combat foundations, enemy spawning, health, damage shards, and combat HUD.
- Bit companion behavior and landmark reactions.
- Inventory, item pickups foraged from the meadow, usable consumables, and Tokens.
- Dynamic sky, celestial layers, clouds, water, terrain, grass, vegetation, particles, and painterly shaders.
- Schema-validated JSON pipeline for quests, NPCs, items, monsters, quizzes, lore, and points of interest.
- 85 approved content entries across all seven types; the inbox is currently clear.

This repository does **not** claim that the ten-region, 40–80 hour design is complete. The vision is documented in [the GDD](docs/GDD.md); the shipped scope and next gates live in [the roadmap](docs/ROADMAP.md) and [devlog](docs/DEVLOG.md).

## Architecture

```text
content/       JSON schemas, inbox batches, and approved game content
docs/          GDD, worldbook, roadmap, devlog, and content workflow
game/          Godot project, scenes, typed scripts, and code-authored assets
tools/         content validation and authoring utilities
```

The runtime never hardcodes authored content. `ContentDB` loads validated entries from `content/approved`, while `GameState` owns durable state and `EventBus` handles cross-system signals. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/CONTENT_PIPELINE.md](docs/CONTENT_PIPELINE.md).

## Run locally

Requirements: Godot 4.7.1 and Python 3.11+.

```powershell
python tools/validate_content.py --inbox
python tools/validate_content.py --all
godot --editor --path game
```

The local verification gate is:

```powershell
godot --headless --editor --path game --quit
```

Godot can return zero even when its output contains a script parse error, so CI also rejects `SCRIPT ERROR`, `Parse Error`, and failed-script-load messages.

## Provenance

Gradientfall was extracted from the `danieltalbert` profile repository with its path history intact, then updated from a verified source-only snapshot of active local work. Generated engine caches and agent-only metadata were deliberately excluded.

## License

Original code, documentation, and code-authored assets are available under the [MIT License](LICENSE). Dataset extracts will be added only with explicit source and license records before release.
