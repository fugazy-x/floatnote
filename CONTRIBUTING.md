# Contributing to FloatNote

Thanks for helping. FloatNote is one Swift file (`FloatNote.swift`) with no Xcode project and no dependencies.

## Build and test

```bash
bash install.sh                      # builds ~/Applications/FloatNote.app and opens it (needs the Xcode command line tools)
bash floatnote-tests/run-tests.sh    # runs the logic tests (all must pass)
```

`install.sh` keeps your login-item setting when you set `FLOATNOTE_KEEP_LOGIN=1`.

## How the code is organised

- The text logic (markers, lists, titles, file names, export, shortcuts list) lives in small `enum`s with no UI. Everything between `// BEGIN MarkerLogic` and `// END MarkerLogic` is compiled by the test script together with `floatnote-tests/main.swift`.
- `AppDelegate` holds the windows and event handling.
- New behaviour should come with a test in `floatnote-tests/main.swift` when it can be tested as logic.

## Ground rules

- Notes are plain text files. Never lose or rewrite a user's note without an atomic save and a way back (the Trash).
- Keep shortcuts consistent: every `fn` letter also has a ⌘ version, and a new shortcut must appear in `ShortcutList`, the ⌘/ cheat sheet, the tutorial (in-app and `docs/`) and the README.
- No network calls, no analytics. Web pages open in the browser only on a user action.
- Small, focused pull requests. Describe what you checked by hand, since much of the UI cannot be tested automatically.

## Reporting bugs

Open an issue with your macOS version, the FloatNote version and the steps. Please do not paste private notes.
