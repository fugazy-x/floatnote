# FloatNote

**A note that floats above your other apps.** Tap Right Option to bring it in, write, tap again to send it away. Your notes are plain `.txt` files on your Mac: no account, no sync service, no tracking.

## [⬇ Download FloatNote](https://github.com/fugazy-x/floatnote/releases/latest/download/FloatNote.dmg)

Free and open source (MIT). macOS 26 or later. Apple silicon and Intel.

## What it does

- **A floating note box** that sits above your other apps, can fade almost away (and let clicks through), and comes back with one key. Move it, resize it and set its see-through level from the keyboard.
- **Writing, not formatting.** Titles (`# `), lines (`---`), numbered and dash lists, bold, italic, underline, highlight and strikethrough. The marks stay out of sight; the file stays plain text.
- **Fullscreen** in its own Space, as one centred column; **paragraph mode** to focus on one paragraph; a **navigator** for your titles.
- **⌘O notes list** with search, days, rename, and a safe Trash (never a permanent delete).
- **⌃⌥S** adds whatever you selected in any app to the note you have open (or starts a new note if none is open).
- **Copy out** for Google Docs (styles kept) and clean plain text; **Ask Grok / Ask Claude** and **Post on X** open your browser with the text ready; you press send.
- Six themes, text size, column width and line spacing in Settings (⌘,).

## Install

1. Open FloatNote.dmg and drag FloatNote to Applications.
2. Open FloatNote. macOS says that it cannot verify the app. Click Done.
3. Open System Settings > Privacy & Security. Scroll down and click Open Anyway.
4. When asked, allow FloatNote under **Privacy & Security > Accessibility** (see below). Without it the Right Option tap cannot work.

After this, FloatNote opens normally.

Why the warning? FloatNote is free and not on the App Store, and the app is not signed with an Apple Developer ID or notarized (Apple charges developers for that). If you prefer, build it yourself (below).

## Permissions and privacy

| Feature | Permission | Why |
|---|---|---|
| Right Option tap, Right Command tap | Accessibility | To notice these keys while you work in other apps |
| ⌃⌥S (selection to note) | Accessibility | To read the text you selected in the front app (if that app does not offer it, FloatNote presses ⌘C for you and puts your clipboard back) |
| Notes folder | Documents | Your notes live in Documents/FloatNote |

Your notes are .txt files in Documents/FloatNote. They stay on your Mac. FloatNote has no server, no account and no analytics.

Text leaves your Mac only when you choose: ⌃⌘L opens Grok and ⌃⌘K opens Claude in your browser, ⌃⌘X opens the selection as a new X post for you to review and send, and ⌃⌘G copies the note for you to paste. FloatNote never posts or sends anything by itself.

New to FloatNote? A hands-on tutorial note opens the first time you use it (and any time from Settings > Tutorial). There is also a [written tutorial](docs/TUTORIAL.md).

## Shortcuts

| Key | Action |
|---|---|
| R Option | Shows / hides |
| R Command | Window mode |
| ⌃⌥S | Selected text is added to the open note (no note open: a new note, in fullscreen) |
| | |
| fn L | Highlight |
| fn X | Strikethrough |
| fn T | Title lines |
| | |
| fn O | Navigator |
| fn P | Paragraph mode |
| fn J | Google Doc |
| fn G | Ask Grok |
| fn K | Ask Claude |
| fn M | Post the selection on X (you press Post) |
| | |
| ⌘F | Find |
| fn R | Find + replace |
| ⌘G / ⇧⌘G | Matches |
| ⌘E | Selected find |
| | |
| w a s d | Size |
| < > | Opacity |

| Type | Gives |
|---|---|
| `# ` | Title |
| `## ` | Subtitle |
| `---` | Single line |
| `===` | Double line |

Push ⌘/ in FloatNote to see this list.

## Build from source

You need macOS 26 or later and the Xcode command line tools (`xcode-select --install`). There is no Xcode project and there are no dependencies.

```bash
git clone https://github.com/fugazy-x/floatnote.git
cd floatnote
bash install.sh                      # builds ~/Applications/FloatNote.app and opens it
bash floatnote-tests/run-tests.sh    # logic tests
```

`install.sh` signs with a local certificate named "FloatNote Local Signing" if you have one (so macOS keeps the Accessibility permission across rebuilds), and otherwise signs ad hoc. It asks whether to start FloatNote at login; set `FLOATNOTE_KEEP_LOGIN=1` to keep your current choice.

## FAQ

**The Right Option key does nothing.** Check System Settings > Privacy & Security > Accessibility: FloatNote must be listed and switched on. If you rebuilt or replaced the app, remove it from the list and add it again.

**Where are my notes?** In Documents/FloatNote, one `.txt` file per note, named like `Note 12 -- 14OCT26.txt` (the number and the day it was made). You can rename a file in the ⌘O list; the number and date stay in the file name. Notes you delete go to the macOS Trash.

**Can I use another folder or sync the notes?** Not yet. If your Documents folder is synced by iCloud, the notes sync with it, but FloatNote does not check for changes made elsewhere while a note is open.

**An fn shortcut types a letter or does something else.** Use its ⌘ version (see the ⌘/ cheat sheet, page 2). On some keyboards the fn key is the Globe key and macOS keeps a few letters for itself.

**How do I uninstall?** Drag FloatNote from Applications to the Trash. Your notes stay in Documents/FloatNote. If you turned on "start at login", remove `~/Library/LaunchAgents/local.floatnote.plist` too.

**Does FloatNote send my notes anywhere?** No. See Permissions and privacy.

## Known limitations

- macOS 26 or later only for now.
- Not notarized: the first launch needs Open Anyway.
- One notes folder (Documents/FloatNote); no built-in sync, backup or version history.
- Very large notes (hundreds of thousands of words) can feel slow; files over 50 MB are not opened.
- The app is in English only, and its accessibility support for VoiceOver has not been checked.

## Contributing

Bug reports, ideas and pull requests are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md). Security problems: [SECURITY.md](SECURITY.md). Changes by version: [CHANGELOG.md](CHANGELOG.md). Please follow the [code of conduct](CODE_OF_CONDUCT.md).

## More

- Uninstall: Drag FloatNote from Applications to the Trash. Your notes stay in Documents/FloatNote.
- License: MIT.
