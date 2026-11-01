# Level generation scripts

**The `.map` file is the level. Scripts are temporary scaffolding for building a section of it.**

| Where | What | Lifetime |
|---|---|---|
| `mapgen.py`, `editmap.py` | Helpers for writing and editing `.map` files | Permanent |
| `active/` | Scripts for sections still being built | Deleted when the section is done |

## Rules

1. **New section, new script in `active/`.** Say at the top of the file which part of the map it owns, and make it safe
   to run again.
2. **A section is done when you start editing it in TrenchBroom, or move on to the next one.** Commit the map, then
   delete the section's script in that same commit. Do this before making any hand edits there, because re-running the
   script overwrites them.
3. **Nothing outside `active/` is level-specific.** If a script is in `active/`, it is safe to run. If it isn't
   needed any more, it is gone.

`active/` should normally hold only what you are working on now. If it is empty, everything is in the map.

Need an old script back? `git log --diff-filter=D --name-only -- tools/levelgen` lists the deleted ones, and
`git show <commit>^:<path>` prints one. They were written for the map as it was then, so read before running.

## Running

From the project root:

    python tools/levelgen/active/<script>.py
