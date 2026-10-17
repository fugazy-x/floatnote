# FloatNote tutorial

A friendly walk-through for your first day with FloatNote. It takes about 10 minutes.

**Try it inside FloatNote:** the app has a built-in, hands-on tutorial note. It opens by itself the first time you use FloatNote, and you can open a fresh copy any time from Settings (⌘,) > Help > Tutorial. You can also drag [FloatNote Tutorial.txt](FloatNote%20Tutorial.txt) onto the box.

## 1. Install and first launch

1. Open **FloatNote.dmg** and drag FloatNote to **Applications**.
2. Open FloatNote. macOS says that it cannot verify the app. Click **Done**.
3. Open **System Settings > Privacy & Security**, scroll down and click **Open Anyway**.

<!-- IMAGE: docs/images/tutorial-open-anyway.png, shows the Open Anyway button in Privacy & Security -->

FloatNote starts quietly: the box appears in the top-right corner, faint (15%), and it does not take your cursor. Keep working; the box waits for you.

**Permissions.** macOS asks for these the first time you use the features that need them:

- **Accessibility**: for the Right Option and Right Command taps, and for ⌃⌥S (selection to note).
- **Documents folder**: your notes live in Documents/FloatNote.

## 2. Show and hide the box

- **Tap Right Option** (the Option key on the right) to bring the box in. Tap it again to hide it.
- **Esc** jumps back to the app you were in and fades the box to 5%. Clicks go through the faded box.
- **⌘W** sends the box to the Dock. Tap Right Option or click it in the Dock to bring it back.

<!-- IMAGE: docs/images/tutorial-show-hide.gif, shows a Right Option tap bringing the box in and Esc fading it -->

### Opacity

FloatNote has two kinds of see-through:

- **At rest.** When you leave the box (Esc or Right Option), the whole box fades to 5% and clicks go through it. At launch it starts at 15%, also click-through.
- **Background.** While you work in the box, its background has its own opacity (60% at first); the text stays solid. Change it with **, and .** (or < and >) in window mode (10% steps) or with the **Opacity** slider in Settings (⌘,), from 40% to 100%. It is saved.

Try it: press ⌘, , drag the Opacity slider left and right while you watch the box, then press Esc.

## 3. Type and format

Just type. Each line starts plain. Type these at the start of a line:

| Type | Gives |
|---|---|
| `# ` | Title |
| `## ` | Subtitle |
| `---` | Single line |
| `===` | Double line |
| `1. ` | Numbered list (Return adds the next item; Return on an empty item ends the list) |
| `- ` | Bullet list (same indent; Return adds the next `- `; Return on an empty item ends the list) |

Styles (select text first, or press before you type):

| Key | Style |
|---|---|
| ⌘B / ⌘I / ⌘U | Bold / italic / underline |
| fn L (or ⇧⌘H) | Highlight |
| fn X (or ⇧⌘X) | Strikethrough |
| fn U (or ⇧⌘A) | ALL CAPS |
| fn T (or ⌥⌘T) | Lines above and below a title |

On a list item (`- ` or `1. `), **double-click** strikes the whole item through and **triple-click** (or **⌘+click**) highlights it; do it again to undo. Elsewhere, double-click still selects a word.

The style marks stay hidden; you only see the result. ⌘+ and ⌘− change the text size.

<!-- IMAGE: docs/images/tutorial-formatting.png, shows a title, a list, a highlight and a double line -->

## 4. Copy in from any app (⌃⌥S)

Select text in any app (Safari, Mail, a PDF…) and press **⌃⌥S**. The text is added to the end of the note you have open in FloatNote, with one blank line between paragraphs and one blank line before it. The box does not pop up; if it is showing, it says "Added to …" for a moment (otherwise the next time you show it). Only when no note is open (a blank new note, or an empty library) does the text become a new note, in fullscreen. If nothing is selected, nothing happens. Text you select inside FloatNote itself becomes a new note.

## 5. Find your way

- **Navigator: fn O (or ⌥⌘V).** A list of the titles in this note. ↑ ↓ to move, Return to jump there, ⌘F to filter, Esc to close.
- **Find: ⌘F.** Find + replace: fn R (or ⌥⌘F). ⌘G / ⇧⌘G go to the next / previous match.

### Paragraph mode (fn P or ⌥⌘P)

Paragraph mode takes the paragraph your cursor is in and shows it one sentence per line, with space between the lines. A coloured border and **-- PARAGRAPH --** show that it is on.

- Edit each sentence on its own line; ↑ ↓ move between them. Return starts a new sentence line. Cut (⌘X) and paste (⌘V) a line to move a sentence.
- ⌘Z undoes edits made in paragraph mode.
- **Esc** (or fn P again) leaves it: the lines are joined back into one paragraph with one space between sentences, and the note is saved. Back in the note, one ⌘Z undoes the whole paragraph edit.
- Copy out (fn J) and Ask Grok / Ask Claude use the joined paragraph while you are in paragraph mode.

Try it on this paragraph (paste it into a note):

> The fox ran fast. It was late for dinner. Its friends were already at the table. Nobody saved it any soup.

1. Click in the paragraph and press fn P. Each sentence gets its own line.
2. Cut the last line and paste it at the top.
3. Change "fast" to "very fast".
4. Press Esc. It is one paragraph again.

## 6. Many notes

- **⌘N** starts a new note. It gets a file (like "Note 3 -- 14OCT26.txt") when you type the first character.
- **⌘O** shows all your notes, newest first. ↑ ↓ to choose, Return to open (or click a row; double-click opens), ⌘F to filter, Esc to close. **←** renames the note's file from scratch, **→** (or R, F2, ⌘+click, or press and hold on a row) keeps the name so you can add on. Return saves, Esc cancels. Saving a blank name removes the custom name and the list goes back to showing the first line. The note's text is not changed, and its date stays. **⌘⌫** deletes the selected note: FloatNote asks first, Return moves the note to the macOS Trash and Esc cancels. To get it back, open the Trash in Finder and choose Put Back. **⌥⌘⌫** moves the note to the Trash at once, without asking. FloatNote has no permanent delete; in Finder, Empty Trash or Delete Immediately removes notes from the Trash for good.
- **Cleanup.** Empty notes go to the Trash by themselves when you leave them. When you leave a tutorial note, FloatNote asks first: Return moves it to the Trash, Esc keeps it as a normal note.
- While you have fewer than 20 notes, a faint **Tutorial** button sits in the box's bottom-right corner. It opens a fresh copy of the tutorial.
- **Drag** a .txt or .md file onto the box to import it as a new note. The original file is not changed.
- Each launch starts with a new note. Your older notes are always in ⌘O and in Documents/FloatNote.

<!-- IMAGE: docs/images/tutorial-notes-list.png, shows the ⌘O list with names on the left and dates on the right -->

## 7. Send text out

**Copy out (fn J or ⌃⌘G)** is one of FloatNote's highlights. It puts two versions on the clipboard: rich text for Google Docs and other rich editors (titles, bold, italic, underline, strikethrough, highlight and lists, with their colours), and clean plain text for everything else (marks like ** and == removed, list numbers as you see them). With no selection it copies the whole note; with a selection, every line the selection touches. In Paragraph mode it copies the joined paragraph.

**Set up (optional):** Ask Grok and Ask Claude open grok.com and claude.ai in your default browser (no account is connected inside FloatNote). Sign in there once and fn G / fn K land ready to send. Settings > Help has **Open grok.com** and **Open claude.ai** buttons for this. One, both or neither is fine.

- **fn J (or ⌃⌘G)** copies the note (or the selected lines) for Google Docs. Paste it there.
- **fn G (or ⌃⌘L)** asks Grok: type your question and press Return. Grok opens in your browser with your question and the text.
- **fn K (or ⌃⌘K)** asks Claude the same way: claude.ai opens with your question and the text filled in; you press send. Esc closes the question field.
- **fn M (or ⌃⌘X)** posts the selected text on X: your browser opens X's new-post window with the text filled in (style marks removed, list dashes and numbers kept), and FloatNote steps aside. You review it and press **Post** yourself; FloatNote never posts for you and needs no X login. With nothing selected it says "Select text first"; over 280 characters it says so, and X shows the count.

## 8. Fullscreen and Settings

- **fn F** puts the note in fullscreen, in its own Space, as a centred column of text. There is no ⌘ version. Esc (or fn F again) takes you back to the box.
- In fullscreen, move the mouse to the top edge of the screen to see the date, time, word count and battery (if your Mac has one), very faintly. It fades away when the mouse leaves.
- In fullscreen, **⌘O** shows the notes list in the same centred column, and Right Option jumps to your last app and back.
- Settings > **Column** (Narrow or Wide) and **Line spacing** (Tight or Loose) change how fullscreen looks.
- **⌘,** opens Settings: font, text size, opacity, theme, and for fullscreen the column width and line spacing.

<!-- IMAGE: docs/images/tutorial-settings.png, shows the Settings window -->

## 9. Move and resize the box (window mode)

Moving the box is one of FloatNote's highlights: put it exactly where you need it, next to what you read or write, and see through it.

**Tap Right Command** (the Command key on the right). A pink border and **-- WINDOW --** show window mode is on; you cannot type while it is on.

- **← → ↑ ↓** move the box.
- **w / s** make it shorter / taller; **a / d** narrower / wider.
- Hold **⇧** for 4× bigger steps.
- **, and .** (or < and >) change the background opacity by 10%.
- **Esc** or another Right Command tap finishes.

In fullscreen, window mode only changes the opacity (, and .).

Try it: tap Right Command, press → three times and ↓ twice, press s twice, press < twice and > twice, then Esc.

## 10. The fn shortcuts

The fn (🌐) shortcuts are quick to press, and each one also has a ⌘ version that always works:

fn L highlight · fn X strikethrough · fn U caps · fn T title lines · fn R find + replace · fn O navigator · fn P paragraph mode · fn J Google Doc · fn G Ask Grok · fn K Ask Claude · fn M post on X · fn Y redo

If an fn shortcut types a letter on your keyboard, use the ⌘ version.

## 11. When you forget a key

Press **⌘/** for the cheat sheet. It has two pages: page 1 has the essentials. Press **→** for page 2: every shortcut, grouped, with both the fn and ⌘ keys. **←** goes back. Press ⌘/ or Esc to close it.
