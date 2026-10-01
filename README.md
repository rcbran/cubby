# Ditto

A local-only clipboard manager for macOS 26+, in the spirit of Paste. History never leaves the Mac.

- **⇧⌘V** opens the drawer. Arrow keys move, Return pastes, ⇧Return pastes as plain text, ⌘1–9 pastes the first nine, ⌘C copies, Delete removes, Esc closes.
- Start typing (or ⌘F) to search.
- Right-click a card for more.

Auto-paste needs Ditto in System Settings → Privacy & Security → Accessibility. Without it, the item still lands on the clipboard and ⌘V works.

## Build

```bash
script/build.sh --run            # build/Ditto.app, then launch it
script/build.sh --run --show     # and open the drawer right away
```

Debug flags: `--appearance light|dark` forces a theme; `--snapshot <file.png>` saves the drawer's layout and quits.

History lives in `~/Library/Application Support/Ditto/` (`history.sqlite` plus `images/`).
