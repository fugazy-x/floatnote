# Changelog

All notable changes to FloatNote. Versions are tags on GitHub; dates are the release dates.

## 1.0.14 (2026-10-17)

- Fixed triple-click (and ⌘-click) on a list line that already had a highlight inside it: the old inner highlight is merged, so you no longer get stray `==` signs. Triple-clicking again removes the highlight cleanly.
- Strike and underline had the same bug and are fixed the same way.

## 1.0.13 (2026-10-17)

- ⌃⌥S now adds the selected text to the end of the note you have open (one blank line before the block and between its paragraphs; the file name and created date stay), without opening fullscreen or taking focus: the box shows "Added to …" if it is showing, otherwise the next time it is shown. Only when no note is open (a blank new note or an empty library) does it create a new note in fullscreen, as before. Text selected inside FloatNote itself still becomes a new note.
- Fixed two crashes: a line with `<u>` twice and no `</u>`, and a file named like `Note -- something.txt` in the notes folder.
- A note file that cannot be read (not downloaded from iCloud yet, no permission, over 50 MB) is no longer opened as an empty note; the note you are in stays open and a message says why. Before, typing into it could overwrite the real file.
- Files in UTF-16 or Windows Western encodings are read (and saved back as UTF-8) instead of being treated as unreadable.
- Saves are flushed to disk before they replace the note.
- The ⌘O list reads only the start of each note, and nothing at all for notes with a custom name (faster with many or big notes).
- First launch without Accessibility access: the system dialog is shown once and a short hint explains that the Right Option tap needs it. ⌃⌥S says so if its shortcut is taken by another app.
- `install.sh` now compiles before it removes the installed app, so a failed build leaves the old one.
- Removed the unused "Apple Events" permission text and the dead one-time format migrations of early versions.
- Added fuzz tests for the text logic.

## 1.0.12 (2026-10-16)

- Six new themes: Graphite, Fog, Harbor (default), Parchment, Arcade, Sorbet. Saved old theme names carry over; the opacity slider starts at 40%.
- Dash lists: a line starting with `- ` is a list item; Return continues it.
- On list items: double-click strikes the item, ⌘+click or triple-click highlights it.
- Fullscreen (fn F) works from the ⌘O list, and ⌘W there minimizes.
- Post to X: select text, press fn M (or ⌃⌘X); X opens in your browser with the text ready and you press Post.
- Fullscreen info strip: move the mouse to the top edge for date, time, word count and battery.

## 1.0.11 (2026-10-15)

- ⌃⌥S turns selected text from any app into a new note, in fullscreen, with one blank line between paragraphs.
- Paragraph mode: extra space between sentences (display only; copy out is unchanged).
- ⌘O list: hover band, click to select, double-click to open.
- ⌘O rename of the note's file: ← starts empty (blank = default name), → / R / F2 keep the name, also ⌘+click or press and hold. The number and date stay in the file name.

## 1.0.10 (2026-10-15)

- Highlight and other styles no longer break titles, and a crash when styling a selection that ends at the end of the note is fixed.
- Notes keep their created date; the ⌘O list shows, sorts and groups by it.
- ⌥⌘⌫ moves a note to the Trash without asking; ⌘⌫ asks first, then moves it to the Trash. There is no permanent delete.

## 1.0.9 (2026-10-14)

- ⌘W minimizes the box to the Dock with the genie animation; Right Option or a click on the Dock icon restores it.
- ⌘W in fullscreen leaves fullscreen first, then minimizes.
- ⌘O list: a thin line and some space between days.
- `install.sh` version and login fixes.

## 1.0.8 (2026-10-14)

- Hiding FloatNote closes Settings, the cheat sheet and the Ask field.
- Optional one-time sign-in helpers for Grok and Claude (tutorial step and Settings buttons).

## 1.0.7 (2026-10-14)

- Tutorial: Paragraph mode walkthrough.

## 1.0.6 (2026-10-14)

- New users start with the Harbor theme (black and blue).
- Empty notes go to the Trash automatically; a prompt offers to delete tutorial notes; a faint Tutorial button shows while you have fewer than 20 notes.
- `#` and `##` titles work without a space after them.

## 1.0.5 – 1.0.3 (2026-10-14)

- New app icon (white line-art notebook).
- New notes start on a title line.
- The first-launch tutorial comes forward; light themes rest at 2.5%.
- ⌘/ page 2: every shortcut, grouped.

## 1.0.2 – 1.0.1 (2026-10-14)

- Default box is about 60% of the screen and centred.
- Ask Claude (fn K / ⌃⌘K).
- Built-in hands-on tutorial note; written tutorial in `docs/TUTORIAL.md`.

## 1.0.0 (2026-10-14)

- First release: a floating note box (Right Option shows and hides it), plain `.txt` notes in Documents/FloatNote, styles, titles, lists, find and replace, navigator, paragraph mode, fullscreen, window mode, copy out for Google Docs, Ask Grok.
