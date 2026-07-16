# gradientfall/game — Godot project conventions

Godot 4.x, GDScript, statically typed everywhere. All assets generated in code.

## Folder layout

```
game/
├── project.godot
├── icon.svg              # code-authored SVG
├── src/                  # all GDScript, mirrors scenes/
│   ├── autoloads/        # EventBus, GameState, ContentDB (registered in project.godot)
│   ├── main/             # boot scene logic
│   ├── player/           # character controller (Phase 1, milestone 2)
│   ├── world/            # terrain, regions, day/night
│   └── ui/               # HUD, dialogue, menus
└── scenes/               # .tscn files, one folder per src/ sibling
    ├── main/
    ├── player/
    ├── world/
    └── ui/
```

## Rules

- snake_case files/dirs; PascalCase node names and `class_name`.
- Every script fully typed: `var x: int`, typed function signatures, typed loops.
- Autoloads are the only globals. New global state goes through `GameState`;
  cross-system communication goes through `EventBus` signals.
- **Content is never hardcoded.** Quests/NPCs/items/monsters/quizzes/lore/POIs
  load from `../content/approved/` via `ContentDB`. In-editor and desktop debug
  runs read the repo folder directly (see `content_db.gd`); export packing is
  decided in the save/load milestone.
- `.uid` files are committed once Godot generates them (first editor open).
- The game must run clean from the editor at every commit (CLAUDE.md iron rule 1).
