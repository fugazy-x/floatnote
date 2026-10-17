// FloatNote — a tiny floating notepad.
//
//   Right Option (tap)   show the box / hide it again
//   Esc                  jump back
//   ⌘Q                   quit
//
// Notes are saved locally on every keystroke.
// Local copy: ~/Library/Application Support/FloatNote/notes.txt

import Cocoa
import NaturalLanguage
import Carbon.HIToolbox
import IOKit.ps

// ---- tweak these if you like ----
var fontSize: CGFloat = appDefaults.double(forKey: "fontSize") > 0 ? CGFloat(appDefaults.double(forKey: "fontSize")) : 13
let typewriterFonts = ["CourierPrimeSans-Regular", "Courier Prime Sans", "Courier"]   // first one that exists wins
// Note font (Step 4): saved setting "font" = serif | sans | retro (default). Unavailable -> retro.
var noteFontSetting = FontLogic.normalize(appDefaults.string(forKey: "font"))
func noteFont(_ size: CGFloat, _ setting: String = noteFontSetting) -> NSFont {
    (FontLogic.names(setting) + typewriterFonts).lazy.compactMap { NSFont(name: $0, size: size) }.first
        ?? .monospacedSystemFont(ofSize: size, weight: .regular)
}
let boxSize = NSSize(width: 320, height: 210)
let passiveAlpha: CGFloat = 0.05   // whole-box opacity while click-through
let launchAlpha: CGFloat = 0.15    // at launch: shown, click-through, not focused, until Right Option
// ---------------------------------

// F2: the library folder ~/Documents/FloatNote. Each .txt file in it is one note.
// Test-only: "-FloatNoteSandbox <dir>" uses <dir>/FloatNote as the library and a separate defaults suite,
// so a test run never reads or changes the real notes or settings.
let sandboxDir: URL? = {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: "-FloatNoteSandbox"), i + 1 < a.count else { return nil }
    return URL(fileURLWithPath: (a[i + 1] as NSString).expandingTildeInPath, isDirectory: true)
}()
let appDefaults: UserDefaults = sandboxDir.flatMap { _ in UserDefaults(suiteName: "local.floatnote.sandbox") } ?? .standard
let libraryFolder: URL = (sandboxDir ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    .appendingPathComponent("FloatNote", isDirectory: true)

var onSendSelection: (() -> Void)?
let minBoxOpacity: CGFloat = ThemeLogic.minOpacity   // floor of the Settings slider and the , . keys (was 0.15: unreadable over opposite backdrops). Rest (5%/2.5%) and launch (15%) are separate.
var boxOpacity: CGFloat = appDefaults.object(forKey: "opacity") != nil ? CGFloat(appDefaults.double(forKey: "opacity")) : 0.6
var onFontSize: ((CGFloat) -> Void)?
var onStyle: ((String) -> Void)?
var onFind: ((NSTextFinder.Action) -> Void)?
var onExport: (() -> Void)?
var onSettings: (() -> Void)?
var onFullscreen: (() -> Void)?
var onCheatSheet: (() -> Void)?
var onAskGrok: (() -> Void)?
var onAskClaude: (() -> Void)?
var onPostToX: (() -> Void)?
var onNewNote: (() -> Void)?
var onMinimize: (() -> Void)?   // ⌘W in the box: minimize it to the Dock
var onDropFiles: (([URL]) -> Void)?

// F5: the note's text view takes dropped files (import); dropped text is inserted as before.
var onNoteClick: ((NSEvent) -> Bool)?        // clicks on list lines (double click = strike, ⌘+click = highlight); true = handled
final class DropTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        if onNoteClick?(event) == true { return }
        super.mouseDown(with: event)
    }
    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? super.draggingEntered(sender) : .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        fileURLs(sender).isEmpty ? super.prepareForDragOperation(sender) : true
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        if urls.isEmpty { return super.performDragOperation(sender) }
        onDropFiles?(urls)
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if let s = sender, !fileURLs(s).isEmpty { return }
        super.concludeDragOperation(sender)
    }
}

// Cheat sheet: ShortcutList.sheetRows() in groups (no headers). Rows in a group sit close; a wider gap
// separates groups. Groups are slices of sheetRows() in list order; cheatColumns says which groups go in
// which column (10 / 10 rows, mirror-symmetric). Column widths are measured from the text.
let cheatGroupSizes = [3, 3, 4, 4, 2, 4]          // R keys / styles / find / views + send out / size / markers
let cheatColumns = [[0, 1, 3], [2, 4, 5]]         // left: R keys, styles, views · right: find, size, markers
func shortcutSheetView(columns: Int = 2, columnWidth: CGFloat = 0) -> NSView {
    let font = typewriterFonts.lazy.compactMap { NSFont(name: $0, size: 15) }.first ?? .monospacedSystemFont(ofSize: 15, weight: .regular)
    let gap: CGFloat = 14, rowH: CGFloat = 24, groupGap: CGFloat = 14, pad: CGFloat = 28, colGap: CGFloat = 40
    let rows = ShortcutList.sheetRows()
    var groups: [[(keys: String, name: String)]] = []
    var i = 0
    for n in cheatGroupSizes where i < rows.count { groups.append(Array(rows[i..<min(i + n, rows.count)])); i += n }
    if i < rows.count { groups.append(Array(rows[i...])) }
    var colGroups = cheatColumns.map { $0.filter { groups.indices.contains($0) }.map { groups[$0] } }
    let used = Set(cheatColumns.joined())
    for gi in groups.indices where !used.contains(gi) { colGroups[colGroups.count - 1].append(groups[gi]) }
    // Measure: labels draw with a small inset, so add 6pt to each text width.
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    func w(_ t: String) -> CGFloat { ceil((t as NSString).size(withAttributes: attrs).width) + 6 }
    let keyW = rows.map { w($0.keys) }.max() ?? 0
    let nameW = rows.map { w($0.name) }.max() ?? 0
    let colW = keyW + gap + nameW
    func colH(_ c: [[(keys: String, name: String)]]) -> CGFloat {
        CGFloat(c.reduce(0) { $0 + $1.count }) * rowH + CGFloat(max(c.count - 1, 0)) * groupGap
    }
    let cols = colGroups.count
    let h = (colGroups.map(colH).max() ?? 0) + 2 * pad
    let view = CheatTableView(frame: NSRect(x: 0, y: 0, width: CGFloat(cols) * colW + CGFloat(cols - 1) * colGap + 2 * pad, height: h))
    view.inset = pad / 2
    view.dividers = (1..<max(cols, 1)).map { pad + CGFloat($0) * (colW + colGap) - colGap / 2 }
    let lineH = ceil(font.ascender - font.descender + font.leading) + 2
    for (ci, col) in colGroups.enumerated() {
        let x = pad + CGFloat(ci) * (colW + colGap)
        var top = h - pad
        for g in col {
            for row in g {
                let y = top - rowH + (rowH - lineH) / 2
                let k = NSTextField(labelWithString: row.keys); k.font = font; k.textColor = Theme.hint
                k.frame = NSRect(x: x, y: y, width: keyW, height: lineH); view.addSubview(k)
                let n = NSTextField(labelWithString: row.name); n.font = font; n.textColor = Theme.text
                n.frame = NSRect(x: x + keyW + gap, y: y, width: nameW, height: lineH); view.addSubview(n)
                top -= rowH
            }
            if g.count > 0, !(g.map { $0.keys } == col.last?.map { $0.keys }) {   // rule between groups
                let left = ci == 0 ? pad / 2 : view.dividers[ci - 1]
                let right = ci == cols - 1 ? view.bounds.width - pad / 2 : view.dividers[ci]
                view.rules.append((y: top - groupGap / 2, x0: left, x1: right))
            }
            top -= groupGap
        }
    }
    return view
}

// Page 2 view: smaller text, section titles in the hint colour, same hairline table as page 1.
func shortcutPage2View(maxHeight: CGFloat) -> NSView {
    var size: CGFloat = 12
    var built: NSView? = nil
    while built == nil || (built!.frame.height > maxHeight && size > 9) {
        built = shortcutPage2(size: size); size -= 1
    }
    return built!
}
private func shortcutPage2(size: CGFloat) -> NSView {
    let font = typewriterFonts.lazy.compactMap { NSFont(name: $0, size: size) }.first ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    let headFont = NSFont.systemFont(ofSize: size - 1, weight: .semibold)
    let gap: CGFloat = 10, groupGap: CGFloat = 10, pad: CGFloat = 24, colGap: CGFloat = 28, rowPad: CGFloat = 4
    let cols = ShortcutPages.columns(ShortcutPages.sections())
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    func w(_ t: String) -> CGFloat { ceil((t as NSString).size(withAttributes: attrs).width) + 6 }
    let all = cols.flatMap { $0 }.flatMap { $0.rows }
    let keyW = all.map { w($0.keys) }.max() ?? 0
    let nameW = min(all.map { w($0.name) }.max() ?? 0, ceil(size * 19))      // long names wrap
    let colW = keyW + gap + nameW
    let lineH = ceil(font.ascender - font.descender + font.leading) + 1
    func nameH(_ t: String) -> CGFloat {
        let r = (t as NSString).boundingRect(with: NSSize(width: nameW - 6, height: 1000), options: [.usesLineFragmentOrigin], attributes: attrs)
        return max(lineH, ceil(r.height) + 1)
    }
    let headH = lineH
    func colH(_ c: [ShortcutPages.Section]) -> CGFloat {
        c.reduce(0) { $0 + headH + $1.rows.reduce(0) { $0 + nameH($1.name) + rowPad } } + CGFloat(max(c.count - 1, 0)) * groupGap
    }
    let n = cols.count
    let h = (cols.map(colH).max() ?? 0) + 2 * pad
    let view = CheatTableView(frame: NSRect(x: 0, y: 0, width: CGFloat(n) * colW + CGFloat(n - 1) * colGap + 2 * pad, height: h))
    view.inset = pad / 2
    view.dividers = (1..<max(n, 1)).map { pad + CGFloat($0) * (colW + colGap) - colGap / 2 }
    for (ci, col) in cols.enumerated() {
        let x = pad + CGFloat(ci) * (colW + colGap)
        var top = h - pad
        for (si, sec) in col.enumerated() {
            let t = NSTextField(labelWithString: sec.title.uppercased()); t.font = headFont; t.textColor = Theme.hint
            t.frame = NSRect(x: x, y: top - headH, width: colW, height: headH); view.addSubview(t)
            top -= headH
            for row in sec.rows {
                let rh = nameH(row.name)
                let k = NSTextField(labelWithString: row.keys); k.font = font; k.textColor = Theme.hint
                k.frame = NSRect(x: x, y: top - lineH, width: keyW, height: lineH); view.addSubview(k)
                let nm = NSTextField(wrappingLabelWithString: row.name); nm.font = font; nm.textColor = Theme.text
                nm.frame = NSRect(x: x + keyW + gap, y: top - rh, width: nameW, height: rh); view.addSubview(nm)
                top -= rh + rowPad
            }
            if si < col.count - 1 {
                let left = ci == 0 ? pad / 2 : view.dividers[ci - 1]
                let right = ci == n - 1 ? view.bounds.width - pad / 2 : view.dividers[ci]
                view.rules.append((y: top - groupGap / 2 + rowPad / 2, x0: left, x1: right))
            }
            top -= groupGap
        }
    }
    return view
}

// The small page hint ("1/2 →" / "← 2/2") in the sheet's bottom margin, right side, faint.
func addPageHint(_ view: NSView, page: Int) {
    let l = NSTextField(labelWithString: ShortcutPages.hint(page))
    if page == 0 {                                   // clearly visible prompt in the accent colour
        l.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        l.textColor = Theme.highlight
    } else {
        l.font = NSFont.systemFont(ofSize: 9)
        l.textColor = Theme.hint.withAlphaComponent(0.6)
    }
    l.sizeToFit()
    l.frame.origin = NSPoint(x: view.bounds.width - l.frame.width - 18, y: 0)
    view.addSubview(l)
    if ShortcutPages.pulses(page: page, page2Seen: appDefaults.bool(forKey: "cheatPage2Seen")) {
        l.wantsLayer = true
        let a = CABasicAnimation(keyPath: "opacity")    // gentle pulse: 40% -> 100%, about 1 s per cycle
        a.fromValue = 0.4; a.toValue = 1.0; a.duration = 0.5
        a.autoreverses = true; a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        l.layer?.add(a, forKey: "pulse")
    }
}

// The cheat sheet's table lines: hairline border, column dividers, rules between groups. No fills.
final class CheatTableView: NSView {
    var inset: CGFloat = 14
    var dividers: [CGFloat] = []
    var rules: [(y: CGFloat, x0: CGFloat, x1: CGFloat)] = []
    override func draw(_ dirtyRect: NSRect) {
        let px = 1 / (window?.backingScaleFactor ?? 2)
        func snap(_ v: CGFloat) -> CGFloat { (v / px).rounded() * px + px / 2 }
        Theme.text.withAlphaComponent(0.18).setStroke()
        let box = bounds.insetBy(dx: inset, dy: inset)
        let border = NSBezierPath(roundedRect: NSRect(x: snap(box.minX), y: snap(box.minY),
                                                     width: snap(box.maxX) - snap(box.minX), height: snap(box.maxY) - snap(box.minY)),
                                  xRadius: 6, yRadius: 6)
        border.lineWidth = px; border.stroke()
        let lines = NSBezierPath(); lines.lineWidth = px
        for x in dividers { lines.move(to: NSPoint(x: snap(x), y: box.minY)); lines.line(to: NSPoint(x: snap(x), y: box.maxY)) }
        for r in rules { lines.move(to: NSPoint(x: r.x0, y: snap(r.y))); lines.line(to: NSPoint(x: r.x1, y: snap(r.y))) }
        lines.stroke()
    }
}

// Step 9: the cheat sheet window. ⌘/, Esc or a click outside closes it.
final class CheatSheetPanel: NSPanel {
    var onClose: (() -> Void)?
    var onTurn: ((Bool) -> Void)?                     // → next page (true), ← previous page
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onClose?() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onClose?()
        case 124: onTurn?(true)
        case 123: onTurn?(false)
        default: super.keyDown(with: event)
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if mods == [.command], event.keyCode == UInt16(kVK_ANSI_Slash) || event.keyCode == UInt16(kVK_ANSI_W) { onClose?(); return true }
        return super.performKeyEquivalent(with: event)
    }
}

// Task 10: an empty Settings window (normal level). Esc and ⌘W close it; ⌘, keeps it in front.
final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(nil) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if mods == [.command], event.keyCode == UInt16(kVK_ANSI_W) { performClose(nil); return true }
        if mods == [.command], event.keyCode == UInt16(kVK_ANSI_Comma) { performClose(nil); return true }   // ⌘, toggles
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { performClose(nil) } else { super.keyDown(with: event) }
    }
}

// Settings: the theme list. Each row: name + four squares (background, text, title, highlight).
final class ThemeListView: NSView {
    var onPick: ((String) -> Void)?
    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    var rowH: CGFloat = 36
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        for (i, t) in ThemeLogic.all.enumerated() {
            let row = NSRect(x: 0, y: CGFloat(i) * rowH, width: bounds.width, height: rowH)
            let on = t.name == currentTheme.name
            if on {
                Theme.text.withAlphaComponent(0.12).setFill()
                NSBezierPath(roundedRect: row.insetBy(dx: 0, dy: 2), xRadius: 6, yRadius: 6).fill()
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: on ? Theme.bold : Theme.text]
            let mark = on ? "> " : "  "
            NSAttributedString(string: mark + t.name, attributes: attrs)
                .draw(at: NSPoint(x: 10, y: row.midY - font.boundingRectForFont.height / 2))
            for (k, h) in [t.bg, t.text, t.title, t.highlight].enumerated() {
                let sq = NSRect(x: bounds.width - 4 * 26 - 6 + CGFloat(k) * 26, y: row.midY - 8, width: 16, height: 16)
                themeColor(h).setFill(); NSBezierPath(roundedRect: sq, xRadius: 3, yRadius: 3).fill()
                Theme.text.withAlphaComponent(0.35).setStroke()
                let b = NSBezierPath(roundedRect: sq.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3); b.lineWidth = 1; b.stroke()
            }
        }
    }
    func pick(_ i: Int) {
        onPick?(ThemeLogic.all[i].name)
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = Int(p.y / rowH)
        if ThemeLogic.all.indices.contains(i) { pick(i) }
        window?.makeFirstResponder(self)
    }
}

// Settings button (Step 4 style; see draw).
final class SettingsButton: NSView {
    var text = "" { didSet { needsDisplay = true } }
    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    var active = false { didSet { needsDisplay = true } }
    var action2: (() -> Void)?
    private var hover = false
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { action2?() }
    // Step 4 style: selected = full Text + Title-color border; others 40%, hover 70%, no border.
    override func draw(_ dirtyRect: NSRect) {
        let c = Theme.text.withAlphaComponent(active ? 1 : (hover ? 0.7 : 0.4))
        if active {
            Theme.title.setStroke()
            let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5); p.lineWidth = 1.5; p.stroke()
        }
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c]
        let sz = (text as NSString).size(withAttributes: a)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2), withAttributes: a)
    }
}

// A label that never takes clicks (they go to the text underneath).
final class PassThroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    // fn+F delivered as the system "toggle full screen" action: use FloatNote's own fullscreen.
    override func toggleFullScreen(_ sender: Any?) { onFullscreen?() }
    func nativeToggleFullScreen() { super.toggleFullScreen(nil) }     // macOS's own fullscreen Space

    // The app has no menu bar, so the usual editing shortcuts are wired up here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        // Style shortcuts, matched by key position with exact modifiers (Task 5).
        let exact = mods.intersection([.command, .control, .option, .shift])
        if exact == [.command, .shift] {
            switch Int(event.keyCode) {
            case kVK_ANSI_A: onStyle?("caps"); return true     // ⇧⌘A ALL CAPS toggle
            case kVK_ANSI_H: onStyle?("h"); return true        // ⇧⌘H highlight
            case kVK_ANSI_X: onStyle?("s"); return true        // ⇧⌘X strikethrough
            case kVK_ANSI_G: onFind?(.previousMatch); return true   // ⇧⌘G previous match
            default: break
            }
        }
        // Find and replace (Task 7), by key position with exact modifiers.
        if exact == [.command] {
            switch Int(event.keyCode) {
            case kVK_ANSI_F: onFind?(.showFindInterface); return true
            case kVK_ANSI_G: onFind?(.nextMatch); return true
            case kVK_ANSI_E: onFind?(.setSearchString); return true
            default: break
            }
        }
        if exact == [.command], event.keyCode == UInt16(kVK_ANSI_Comma) { onSettings?(); return true }   // ⌘, Settings
        if exact == [.command], event.keyCode == UInt16(kVK_ANSI_Slash) { onCheatSheet?(); return true }  // ⌘/ cheat sheet
        if exact == [.command, .control], event.keyCode == UInt16(kVK_ANSI_G) { onExport?(); return true }   // ⌃⌘G copy out
        if exact == [.command, .control], event.keyCode == UInt16(kVK_ANSI_L) { onAskGrok?(); return true }  // ⌃⌘L ask Grok
        if exact == [.command, .control], event.keyCode == UInt16(kVK_ANSI_K) { onAskClaude?(); return true }  // ⌃⌘K ask Claude
        if exact == [.command, .control], event.keyCode == UInt16(kVK_ANSI_X) { onPostToX?(); return true }    // ⌃⌘X post on X
        if exact == [.command, .option], event.keyCode == UInt16(kVK_ANSI_F) { onFind?(.showReplaceInterface); return true }
        switch key {
        case "x": return send(#selector(NSText.cut(_:)))
        case "c": return send(#selector(NSText.copy(_:)))
        case "v": return send(#selector(NSTextView.pasteAsPlainText(_:)))
        case "t": return true   // ⌘T: no-op (no font panel)
        case "b" where mods.contains(.option): return true   // ⌥⌘B: was title box (removed); does nothing, not bold
        case "b", "i": onStyle?(key); return true
        case "u" where !mods.contains(.shift): onStyle?("u"); return true
        case "a": return send(#selector(NSText.selectAll(_:)))
        case "z":
            if let undo = firstResponder?.undoManager {
                if mods.contains(.shift) { if undo.canRedo { undo.redo() } }
                else if undo.canUndo { undo.undo() }
            }
            return true
        case "=", "+": onFontSize?(1); return true
        case "-", "_": onFontSize?(-1); return true
        case "w": onMinimize?(); return true   // ⌘W: minimize to the Dock (Right Option / Dock click brings it back)
        case "n" where mods.intersection([.command, .control, .option, .shift]) == [.command]: onNewNote?(); return true   // ⌘N new note
        case "q": NSApp.terminate(nil); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    private func send(_ action: Selector) -> Bool {
        firstResponder?.tryToPerform(action, with: self) ?? false
    }
}

// Draws a "---" paragraph as a thin line across the box (the text itself stays "---").
let bandKey = NSAttributedString.Key("floatnoteTutorialBand")   // marks the tutorial highlight bands
let titleKey = NSAttributedString.Key("floatnoteTitle")   // marks text we enlarged for a ## title
// Visual experiment: titles, subtitles and list numbers share one light grey (was #FF2020 red / #1E90FF blue).
// MARK: colors — every view reads the current theme (Step 3). Saved setting "theme".
var currentTheme = ThemeLogic.named(ThemeLogic.migrate(theme: appDefaults.string(forKey: "theme"),
                                                       appearance: appDefaults.string(forKey: "appearance")))
func themeColor(_ h: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    let c = ThemeLogic.rgb(h)
    return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
}
enum Theme {
    static var bg: NSColor { themeColor(currentTheme.bg) }
    static var text: NSColor { themeColor(currentTheme.text) }
    static var title: NSColor { themeColor(currentTheme.title) }
    static var highlight: NSColor { themeColor(currentTheme.highlight) }
    static var hint: NSColor { themeColor(currentTheme.text, ThemeLogic.hintAlpha(dark: currentTheme.dark)) }   // labels, hints, navigator text
    static var rule: NSColor { themeColor(currentTheme.text, 0.5) }           // --- / ===
    static var bold: NSColor { themeColor(ThemeLogic.boldColor(currentTheme)) }   // brighter bold on dark themes (a theme may set its own)
    static var selection: NSColor { themeColor(currentTheme.text, currentTheme.dark ? 0.25 : 0.18) }
    static var appearance: NSAppearance? { NSAppearance(named: currentTheme.dark ? .darkAqua : .aqua) }
}
var bodyColor: NSColor { Theme.text }
var accentGrey: NSColor { Theme.title }
var titlePink: NSColor { Theme.title }        // names kept from earlier colors
var subtitleOrange: NSColor { Theme.title }
var neonColor: NSColor { Theme.highlight }    // navigator / paragraph-mode accents use the theme's Highlight
var highlightOrange: NSColor { Theme.highlight }
// Highlight text color: any theme's Highlight, or the older #FF8800 / neon yellow.
func isNeon(_ v: Any?) -> Bool {
    guard let c = (v as? NSColor)?.usingColorSpace(.sRGB) else { return false }
    return ThemeLogic.isHighlight(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
}
enum TitleStyle { case text, bar }   // .text = pink letters; .bar = white letters on a full-width pink bar
let titleStyle: TitleStyle = .text

final class RuleLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    var rules: [NSRange] = []      // character ranges of "---" lines shown as rules
    var doubles: Set<Int> = []     // start locations of rules that are "===" (double line)
    var titles: [NSRange] = []     // ## title lines: pink bar across the whole width
    var hiddenMarkers: [NSRange] = []   // "##" markers to lay out with zero width
    var hiddenListPrefixes: [NSRange] = []   // leading tabs of list lines (pasted/old text; dropped on the next edit)
    var listMarkers: [NSRange] = []          // whole "\t\t12. " of each list line (the caret goes after it)
    var hiddenStyleMarkers: [NSRange] = []   // **, *, <u>, </u>, ==, ~~ off the caret line

    override init() { super.init(); delegate = self }
    required init?(coder: NSCoder) { super.init(coder: coder); delegate = self }

    // Show title text in capitals without changing the stored letters: swap each glyph
    // for the uppercase letter's glyph (same width in a monospaced font).
    func layoutManager(_ lm: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>, font aFont: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard let ts = lm.textStorage else { return 0 }
        let str = ts.string as NSString
        var out = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
        var outProps = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        var changed = false
        for i in 0..<glyphRange.length {
            let ci = characterIndexes[i]
            if isHidden(ci) {
                outProps[i] = .controlCharacter; changed = true; continue   // laid out with zero width below
            }
            guard ci < str.length, ts.attribute(titleKey, at: ci, effectiveRange: nil) != nil else { continue }
            let c = str.character(at: ci)
            let up = Array(String(utf16CodeUnits: [c], count: 1).uppercased().utf16)
            guard up.count == 1, up[0] != c else { continue }
            var u = up[0]; var g: CGGlyph = 0
            if CTFontGetGlyphsForCharacters(aFont as CTFont, &u, &g, 1) { out[i] = g; changed = true }
        }
        guard changed else { return 0 }
        lm.setGlyphs(out, properties: outProps, characterIndexes: characterIndexes, font: aFont, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    func isHidden(_ ci: Int) -> Bool {
        hiddenMarkers.contains(where: { NSLocationInRange(ci, $0) }) ||
        hiddenListPrefixes.contains(where: { NSLocationInRange(ci, $0) }) ||
        hiddenStyleMarkers.contains(where: { NSLocationInRange(ci, $0) })
    }

    // Hidden marker characters take no space at all (.null glyphs still left a gap).
    func layoutManager(_ lm: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        isHidden(charIndex) ? .zeroAdvancement : action
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        let width = firstTextView?.bounds.width ?? 0
        titlePink.setFill()
        for r in titles where r.length > 0 && titleStyle == .bar {
            let gr = glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            guard NSIntersectionRange(gr, glyphsToShow).length > 0 else { continue }
            enumerateLineFragments(forGlyphRange: gr) { rect, _, _, _, _ in
                NSRect(x: 0, y: origin.y + rect.minY, width: max(width, origin.x + rect.maxX), height: rect.height).fill()
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let container = textContainers.first else { return }
        Theme.rule.setFill()
        for r in rules {
            let g = glyphIndexForCharacter(at: r.location)
            guard NSIntersectionRange(NSRange(location: g, length: 3), glyphsToShow).length > 0 else { continue }
            let frag = lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            let pad = container.lineFragmentPadding
            let x = origin.x + frag.minX + pad, w = frag.width - pad * 2
            let mid = (origin.y + frag.midY).rounded(.down)
            if doubles.contains(r.location) {
                NSRect(x: x, y: mid - 2, width: w, height: 1).fill()
                NSRect(x: x, y: mid + 2, width: w, height: 1).fill()
            } else {
                NSRect(x: x, y: mid, width: w, height: 1).fill()
            }
        }
    }
}

// BEGIN MarkerLogic
// Text styles are stored as markers in the text itself:
//   **bold**  *italic*  <u>underline</u>  ==highlight==  ~~strikethrough~~
// A pair must be on one line; the opening marker is followed by a non-space and the
// closing marker is preceded by a non-space. Unpaired markers are plain text.
enum MarkerLogic {
    enum Style: CaseIterable { case bold, italic, underline, highlight, strike }
    struct Span { let style: Style; let open: NSRange; let close: NSRange; let content: NSRange }

    static let tokens: [Style: (open: String, close: String)] = [
        .bold: ("**", "**"), .italic: ("*", "*"), .underline: ("<u>", "</u>"),
        .highlight: ("==", "=="), .strike: ("~~", "~~")]

    // The pieces of a selection to wrap in markers: one per line, trimmed of surrounding spaces, never
    // empty and never twice (a selection that ends at the very end of the note used to repeat its last line).
    static func segments(in text: NSString, selection sel: NSRange) -> [NSRange] {
        var segments: [NSRange] = []
        var pos = sel.location
        while pos <= NSMaxRange(sel) && pos <= text.length {
            var a = 0, b = 0, c = 0
            text.getParagraphStart(&a, end: &b, contentsEnd: &c, for: NSRange(location: pos, length: 0))
            var seg = NSIntersectionRange(NSRange(location: a, length: c - a), sel)
            if seg.length == 0 && !(a == c && sel.location <= a) { seg = NSRange(location: NSNotFound, length: 0) }
            if seg.location != NSNotFound {
                // A heading's "# " / "## " and a list item's "12. " are not styled text: the markers go after them.
                // (Wrapping them turned the heading into a plain line, so its CAPITALS showed as lowercase.)
                let line = text.substring(with: NSRange(location: a, length: c - a))
                let prefix = HeadingLogic.kind(line)?.markerLen ?? ListLogic.item(line)?.markerLen ?? 0
                if seg.location < a + prefix { let cut = min(a + prefix - seg.location, seg.length); seg.location += cut; seg.length -= cut }
                while seg.length > 0, let u = UnicodeScalar(text.character(at: seg.location)), CharacterSet.whitespaces.contains(u) { seg.location += 1; seg.length -= 1 }
                while seg.length > 0, let u = UnicodeScalar(text.character(at: NSMaxRange(seg) - 1)), CharacterSet.whitespaces.contains(u) { seg.length -= 1 }
                if seg.length > 0, seg.location >= (segments.last.map { NSMaxRange($0) } ?? 0) { segments.append(seg) }
            }
            if b <= pos { break }
            pos = b
        }
        return segments
    }

    // ⌘B ⌘I ⌘U ⇧⌘H ⇧⌘X on a selection: the markers go round each selected line's text (after a heading's "# " or a
    // list's "12. "), or come off if every line already has them. Only markers are added or removed: the
    // letters (and their case) are never changed. Returns the range to replace, its new text and the new selection.
    static func toggleSelection(_ text: NSString, selection sel: NSRange, style: Style) -> (whole: NSRange, text: String, selection: NSRange)? {
        let (open, close) = tokens[style]!
        let ol = (open as NSString).length, cl = (close as NSString).length
        let segments = MarkerLogic.segments(in: text, selection: sel)
        guard !segments.isEmpty else { return nil }

        func wrappedInside(_ r: NSRange) -> Bool {
            r.length >= ol + cl && text.substring(with: NSRange(location: r.location, length: ol)) == open
                && text.substring(with: NSRange(location: NSMaxRange(r) - cl, length: cl)) == close
        }
        func wrappedOutside(_ r: NSRange) -> Bool {
            r.location >= ol && NSMaxRange(r) + cl <= text.length
                && text.substring(with: NSRange(location: r.location - ol, length: ol)) == open
                && text.substring(with: NSRange(location: NSMaxRange(r), length: cl)) == close
        }
        let remove = segments.allSatisfy { wrappedInside($0) || wrappedOutside($0) }

        // Rebuild the whole touched range as one replacement (= one undo step).
        var first = segments.first!.location, last = NSMaxRange(segments.last!)
        if remove, let f = segments.first, !wrappedInside(f), wrappedOutside(f) { first -= ol }
        if remove, let l = segments.last, !wrappedInside(l), wrappedOutside(l) { last += cl }
        let whole = NSRange(location: first, length: last - first)
        var out = ""
        var cursor = whole.location
        var newSel: NSRange? = nil
        for seg in segments {
            var r = seg
            if remove && !wrappedInside(seg) { r = NSRange(location: seg.location - ol, length: seg.length + ol + cl) }
            out += text.substring(with: NSRange(location: cursor, length: r.location - cursor))
            let inner: String
            if remove { inner = text.substring(with: NSRange(location: r.location + ol, length: r.length - ol - cl)) }
            else { inner = open + text.substring(with: r) + close }
            let start = whole.location + (out as NSString).length
            out += inner
            if segments.count == 1 {
                newSel = remove ? NSRange(location: start, length: (inner as NSString).length)
                                : NSRange(location: start + ol, length: (inner as NSString).length - ol - cl)
            }
            cursor = NSMaxRange(r)
        }
        out += text.substring(with: NSRange(location: cursor, length: NSMaxRange(whole) - cursor))
        return (whole, out, newSel ?? NSRange(location: whole.location, length: (out as NSString).length))

    }

    // All styled spans in one line (ranges are UTF-16 offsets within the line).
    static func spans(_ line: String) -> [Span] {
        let s = line as NSString
        let n = s.length
        var reserved = [Bool](repeating: false, count: n)
        func isSpace(_ i: Int) -> Bool {
            guard i >= 0, i < n else { return true }
            // Half of a surrogate pair (emoji etc.) is not a space.
            guard let u = UnicodeScalar(s.character(at: i)) else { return false }
            return CharacterSet.whitespacesAndNewlines.contains(u)
        }
        func at(_ i: Int, _ t: String) -> Bool {
            let len = (t as NSString).length
            guard i >= 0, i + len <= n else { return false }
            for k in 0..<len where reserved[i + k] { return false }
            return s.substring(with: NSRange(location: i, length: len)) == t
        }
        func occurrences(_ t: String) -> [Int] {
            var out: [Int] = []
            let len = (t as NSString).length
            var i = 0
            while i < n { if at(i, t) { out.append(i); i += len } else { i += 1 } }
            return out
        }
        var result: [Span] = []
        func pair(_ style: Style, opens: [Int], closes: [Int]) {
            let (o, c) = tokens[style]!
            let ol = (o as NSString).length, cl = (c as NSString).length
            let symmetric = o == c                   // same token opens and closes (<u> with no </u> is not a pair: used to crash)
            let events = (opens.map { ($0, true) } + closes.map { ($0, false) }).sorted { $0.0 < $1.0 }
            var open: Int? = nil
            for (pos, isOpenTok) in events {
                let mayClose = symmetric || !isOpenTok
                let mayOpen = symmetric || isOpenTok
                if let start = open, mayClose, pos >= start + ol + 1, !isSpace(pos - 1) {
                    result.append(Span(style: style, open: NSRange(location: start, length: ol),
                                       close: NSRange(location: pos, length: cl),
                                       content: NSRange(location: start + ol, length: pos - start - ol)))
                    for k in start..<(start + ol) { reserved[k] = true }
                    for k in pos..<(pos + cl) { reserved[k] = true }
                    open = nil
                } else if open == nil, mayOpen, !isSpace(pos + ol) {
                    open = pos
                }
            }
        }
        // ** before *: every "**" is taken out of the running for single "*".
        let doubles = occurrences("**")
        pair(.bold, opens: doubles, closes: [])
        for d in doubles { reserved[d] = true; if d + 1 < n { reserved[d + 1] = true } }
        pair(.strike, opens: occurrences("~~"), closes: [])
        pair(.highlight, opens: occurrences("=="), closes: [])
        pair(.underline, opens: occurrences("<u>"), closes: occurrences("</u>"))
        pair(.italic, opens: occurrences("*"), closes: [])
        return result
    }

    static func isNeonColor(_ v: Any?) -> Bool {
        guard let c = (v as? NSColor)?.usingColorSpace(.sRGB) else { return false }
        return abs(c.redComponent - 0.902) < 0.02 && abs(c.greenComponent - 1) < 0.02 && c.blueComponent < 0.02
    }

    // Old notes.rtf -> text with markers (one-time conversion).
    static func convert(_ a: NSAttributedString) -> String {
        let str = a.string as NSString
        var out = ""
        var pos = 0
        while pos < str.length {
            var start = 0, end = 0, contentsEnd = 0
            str.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: pos, length: 0))
            let lineRange = NSRange(location: start, length: contentsEnd - start)
            out += convertLine(a.attributedSubstring(from: lineRange))
            out += str.substring(with: NSRange(location: contentsEnd, length: end - contentsEnd))
            pos = end
        }
        return out
    }

    static func convertLine(_ a: NSAttributedString) -> String {
        let s = a.string as NSString
        let n = s.length
        guard n > 0 else { return "" }
        let isHeading = a.string.hasPrefix("##") || a.string.hasPrefix("%%")   // their bold/size came from ##/%%
        let fm = NSFontManager.shared
        var flags = [Set<Style>](repeating: [], count: n)
        a.enumerateAttributes(in: NSRange(location: 0, length: n)) { at, r, _ in
            var f: Set<Style> = []
            if let font = at[.font] as? NSFont {
                let t = fm.traits(of: font)
                if t.contains(.boldFontMask) && !isHeading { f.insert(.bold) }
                if t.contains(.italicFontMask) { f.insert(.italic) }
            }
            if ((at[.underlineStyle] as? Int) ?? 0) != 0 { f.insert(.underline) }
            if ((at[.strikethroughStyle] as? Int) ?? 0) != 0 { f.insert(.strike) }
            if at[.backgroundColor] != nil || isNeonColor(at[.foregroundColor]) { f.insert(.highlight) }
            for i in r.location..<NSMaxRange(r) { flags[i] = f }
        }
        func space(_ i: Int) -> Bool {
            guard let u = UnicodeScalar(s.character(at: i)) else { return false }
            return CharacterSet.whitespacesAndNewlines.contains(u)
        }
        // (position, text, isClose, spanLength)
        var inserts: [(Int, String, Bool, Int)] = []
        for style in [Style.bold, .italic, .underline, .strike, .highlight] {
            var i = 0
            while i < n {
                guard flags[i].contains(style) else { i += 1; continue }
                var j = i
                while j < n && flags[j].contains(style) { j += 1 }
                var a0 = i, b0 = j
                while a0 < b0 && space(a0) { a0 += 1 }
                while b0 > a0 && space(b0 - 1) { b0 -= 1 }
                if b0 > a0 {
                    inserts.append((a0, tokens[style]!.open, false, b0 - a0))
                    inserts.append((b0, tokens[style]!.close, true, b0 - a0))
                }
                i = j
            }
        }
        inserts.sort { x, y in
            if x.0 != y.0 { return x.0 < y.0 }
            if x.2 != y.2 { return x.2 }                 // closes before opens
            return x.2 ? x.3 < y.3 : x.3 > y.3           // close inner first, open outer first
        }
        var out = ""
        var k = 0
        for i in 0...n {
            while k < inserts.count && inserts[k].0 == i { out += inserts[k].1; k += 1 }
            if i < n { out += s.substring(with: NSRange(location: i, length: 1)) }
        }
        return out
    }

}

// Headings: a line starting with "#" = title, "##" = subtitle; the space after is optional ("#x", "# x").
// Three or more # ("### x", "###x") and " # x" stay plain. All text is left-aligned. Old alignment markers "#< " / "#> " (and "##< " / "##> ")
// still read as titles, so pasted old text works; the format-5 migration rewrites them in notes.txt.
enum HeadingLogic {
    enum Kind { case title, subtitle }
    // (kind, marker length incl. the space) or nil for a plain line
    static func kind(_ line: String) -> (kind: Kind, markerLen: Int)? {
        for (hashes, k) in [("##", Kind.subtitle), ("#", Kind.title)] where line.hasPrefix(hashes) {
            let rest = line.dropFirst(hashes.count)
            if rest.hasPrefix("#") { return nil }                                               // ### or more: plain
            if rest.hasPrefix(" ") { return (k, hashes.count + 1) }
            if rest.hasPrefix("< ") || rest.hasPrefix("> ") { return (k, hashes.count + 2) }   // old alignment marker
            return (k, hashes.count)                                                            // no space: "#Hello"
        }
        return nil
    }
    static func marker(_ k: Kind) -> String { k == .subtitle ? "## " : "# " }
    // Old "#< " / "#> " / "##< " / "##> " markers -> "# " / "## " (line endings kept; other lines unchanged).
    static func dropAlign(_ text: String) -> String {
        mapLines(text) { line in
            guard let h = kind(line), h.markerLen == (h.kind == .subtitle ? 4 : 3) else { return line }   // only "#< " / "##> " etc.
            return marker(h.kind) + (line as NSString).substring(from: h.markerLen)
        }
    }
    static func mapLines(_ text: String, _ f: (String) -> String) -> String {
        let ns = text as NSString
        var out = "", pos = 0
        while pos < ns.length {
            var a = 0, b = 0, c = 0
            ns.getParagraphStart(&a, end: &b, contentsEnd: &c, for: NSRange(location: pos, length: 0))
            out += f(ns.substring(with: NSRange(location: a, length: c - a)))
            out += ns.substring(with: NSRange(location: c, length: b - c))
            pos = b
        }
        return out
    }
    // Old -> new marker for one line: "##"/"## " -> "# ", "%%"/"%% " -> "## ".
    static func convertLine(_ line: String) -> String {
        for (old, new) in [("##", "# "), ("%%", "## ")] where line.hasPrefix(old) {
            var rest = line.dropFirst(old.count)
            if rest.hasPrefix(" ") { rest = rest.dropFirst() }
            return new + rest
        }
        return line
    }
    // Whole note, one line at a time (line endings kept).
    static func convert(_ text: String) -> String {
        let ns = text as NSString
        var out = ""
        var pos = 0
        while pos < ns.length {
            var a = 0, b = 0, c = 0
            ns.getParagraphStart(&a, end: &b, contentsEnd: &c, for: NSRange(location: pos, length: 0))
            out += convertLine(ns.substring(with: NSRange(location: a, length: c - a)))
            out += ns.substring(with: NSRange(location: c, length: b - c))
            pos = b
        }
        return out
    }
}

// Post to X (fn M / ⌃⌘X): the selected text opens in X's compose window (https://x.com/intent/post?text=...) in the
// default browser. The user reviews it and presses Post himself: FloatNote never posts, and needs no X login or key.
enum TweetLogic {
    static let limit = 280
    // The selection as readable text: style markers (** * <u> == ~~), # / ## title markers and "---" / "===" lines
    // are gone (rules become blank lines); list items keep their "- " / "3. "; everything else stays as typed.
    // Leading/trailing blank lines are dropped.
    static func clean(_ selection: String) -> String {
        let t = ExportLogic.cleanText(ExportLogic.parse(selection))
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    // X's own weighting: most Latin text counts 1 per character; emoji, CJK and other wide characters count 2.
    // (Links count 23 on X; not special-cased here, X shows its own count anyway.)
    static func weightedLength(_ s: String) -> Int {
        func narrow(_ v: UInt32) -> Bool {
            v <= 0x10FF || (0x2000...0x200D).contains(v) || (0x2010...0x201F).contains(v) || (0x2032...0x2037).contains(v)
        }
        return s.reduce(0) { $0 + ($1.unicodeScalars.allSatisfy { narrow($0.value) } ? 1 : 2) }   // per character (emoji sequences = one)
    }
    static func isOverLimit(_ text: String) -> Bool { weightedLength(text) > limit }
    // Percent-encodes everything except RFC 3986 unreserved characters (so & # % + ? = newlines and emoji are safe).
    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? ""
    }
    static func url(for text: String) -> URL? { URL(string: "https://x.com/intent/post?text=" + encode(text)) }
    // Browsers and servers cope with URLs up to roughly this long; beyond it the post is not opened (status says so).
    static let maxURLLength = 7500
    enum Plan: Equatable { case nothing, tooLong, open(URL, over: Bool) }
    static func plan(selection: String?) -> Plan {
        let text = clean(selection ?? "")
        guard !text.isEmpty else { return .nothing }
        guard let u = url(for: text), u.absoluteString.count <= maxURLLength else { return .tooLong }
        return .open(u, over: isOverLimit(text))
    }
}

// Fullscreen info strip: moving the mouse near the top edge fades in "Fri, Oct 16 · 4:05 AM · 123 words · 87%".
// Pure rules and formatting here; the AppDelegate reads the clock, the battery and the mouse.
enum InfoStripLogic {
    static let showBand: CGFloat = 70          // mouse this close to the top edge of the screen: show
    static let hideBand: CGFloat = 110         // ...and it stays until the mouse is this far down (no flicker)
    // Words: whitespace-separated, counted on the visible text only (style markers, # / ## title markers, "---" / "==="
    // rules and the "- " / "3. " list markers are not words).
    static func wordCount(_ note: String) -> Int {
        ExportLogic.parse(note).reduce(0) { n, b in
            switch b.kind {
            case .rule, .doubleRule, .empty: return n
            default:
                return n + ExportLogic.plain(b).split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            }
        }
    }
    static func dateString(_ d: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = locale; f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f.string(from: d)
    }
    static func timeString(_ d: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = locale; f.timeZone = timeZone
        f.dateStyle = .none; f.timeStyle = .short
        return f.string(from: d)
    }
    static func wordsString(_ n: Int) -> String { n == 1 ? "1 word" : "\(n) words" }
    // nil percent = no battery (desktop Mac): nothing is shown for it.
    static func batteryString(percent: Int?, charging: Bool) -> String? {
        guard let p = percent else { return nil }
        return (charging ? "\u{26A1}\u{FE0E} " : "") + "\(min(max(p, 0), 100))%"
    }
    static func line(date: Date, words: Int, batteryPercent: Int?, charging: Bool,
                     locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var parts = [dateString(date, locale: locale, timeZone: timeZone), timeString(date, locale: locale, timeZone: timeZone), wordsString(words)]
        if let b = batteryString(percent: batteryPercent, charging: charging) { parts.append(b) }
        return parts.joined(separator: " \u{00B7} ")
    }
    // Shown only in fullscreen, once the transition is over, with nothing else claiming the top (list, Settings...),
    // while the mouse is near the top of the screen (nil = the mouse is on another screen).
    static func visible(was: Bool, fullscreen: Bool, transitioning: Bool, blocked: Bool, distanceFromTop: CGFloat?) -> Bool {
        guard fullscreen, !transitioning, !blocked, let d = distanceFromTop else { return false }
        return d <= (was ? hideBand : showBand)
    }
}

// Accessibility (Right Option, ⌃⌥S): the system asks once; after that FloatNote only says what is missing.
enum AccessLogic {
    static let launchHint = "Right Option needs Accessibility: System Settings > Privacy & Security"
    static let selectionHint = "Allow FloatNote in System Settings > Privacy & Security > Accessibility"
    // Show the system dialog only if access is missing and it was not shown before (it can be reached from Settings).
    static func shouldPrompt(trusted: Bool, alreadyAsked: Bool) -> Bool { !trusted && !alreadyAsked }
}

// ⌃⌥S: the text appended to the note for a captured selection.
enum ClipLogic {
    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
    static func appended(selection: String, app: String, url: String?, date: Date, note: String) -> String {
        var source = "Source: " + app
        if let u = url, !u.isEmpty { source += " | " + u }
        source += " | " + stamp(date)
        let block = "===\n\n" + selection + "\n" + source
        if note.isEmpty { return block }
        let lead = note.hasSuffix("\n") ? "" : "\n"
        return lead + block
    }
}
// ⌃⌥S: the selected text becomes a new note. Nothing (or only spaces/newlines) selected = no note.
enum SelectionNote {
    static func text(from selection: String?) -> String? {
        guard let s = selection, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
    // The text of the new note: exactly one blank line between paragraphs. A single line break becomes a paragraph
    // break, two or more blank lines collapse to one, blank lines at the start/end go. Line contents (case,
    // spaces inside a line, markers) are never changed; only the line breaks between lines are.
    static func noteText(from selection: String?) -> String? {
        guard let s = text(from: selection) else { return nil }
        let lines = s.components(separatedBy: CharacterSet.newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.joined(separator: "\n\n")
    }
    // ⌃⌥S goes to the open note. Only an empty note with no file ("nothing open": the launch's blank note, an empty
    // library) gets a new note (and fullscreen) instead.
    enum Target: Equatable { case appendToOpenNote, newNote }
    static func target(hasFile: Bool, text: String) -> Target {
        !hasFile && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .newNote : .appendToOpenNote
    }
    // The edit that adds a selection at the end of a note: replace `length` characters at `location` (the blank
    // space at the end of the note) with `text`. The block is normalized like a new note's text, and exactly one
    // blank line separates it from what is there; a note with only blank space gets no leading blank lines.
    // Nothing else in the note changes. nil = nothing (blank selection).
    static func appendEdit(existing: String, selection: String?) -> (location: Int, length: Int, text: String)? {
        guard let block = noteText(from: selection) else { return nil }
        let ns = existing as NSString
        var end = ns.length
        while end > 0, let u = UnicodeScalar(ns.character(at: end - 1)), CharacterSet.whitespacesAndNewlines.contains(u) { end -= 1 }
        if end == 0 { return (0, ns.length, block) }
        return (end, ns.length - end, "\n\n" + block)
    }
}
// Navigator filter: indices of headings to show for a query (case-insensitive substring).
// A title shows if it or any of its subtitles match; a subtitle shows only if it matches.
enum NavFilter {
    static func visible(_ items: [(text: String, sub: Bool)], query: String) -> [Int] {
        let q = query.lowercased()
        if q.isEmpty { return Array(items.indices) }
        var keep = Set<Int>()
        var parent: Int? = nil
        for (i, it) in items.enumerated() {
            if !it.sub { parent = i }
            guard it.text.lowercased().contains(q) else { continue }
            keep.insert(i)
            if it.sub, let p = parent { keep.insert(p) }
        }
        return keep.sorted()
    }
}

// Fullscreen margins and line spacing (Step 5B). Settings "fsMargins" = wide|narrow, "fsLineSpacing" = tight|loose.
enum FullscreenLogic {
    static func margins(_ v: String?) -> String { v == "narrow" ? "narrow" : "wide" }
    static func spacing(_ v: String?) -> String { v == "loose" ? "loose" : "tight" }
    // Each side's margin: stored "wide" 25% of the screen width (Narrow column in Settings), "narrow" 10% (Wide column).
    static func margin(screenWidth w: CGFloat, _ setting: String?) -> CGFloat { w * (margins(setting) == "narrow" ? 0.10 : 0.25) }
    // lineHeightMultiple: 0 = the font's own spacing (box, and Tight); Loose = 1.6x, fullscreen only.
    // Side inset of the ⌘O notes list: 8 in the box; in fullscreen the note's centred column.
    static func listInset(width: CGFloat, fullscreen: Bool, _ setting: String?) -> CGFloat {
        fullscreen ? max(8, margin(screenWidth: width, setting)) : 8
    }
    static func lineMultiple(_ setting: String?, fullscreen: Bool) -> CGFloat { fullscreen && spacing(setting) == "loose" ? 1.6 : 0 }
    // May fullscreen be toggled now? The note: when its text is focused. The ⌘O list: yes (it stays open), except
    // while the rename field or the delete confirmation is up. Never in the navigator.
    static func canToggle(listOpen: Bool, renaming: Bool, askDelete: Bool, navOpen: Bool, textFocused: Bool) -> Bool {
        if navOpen { return false }
        return listOpen ? (!renaming && !askDelete) : textFocused
    }
    // Window-level keys the ⌘O list passes on instead of swallowing: fn+F (fullscreen) and ⌘W (minimize; in fullscreen it
    // leaves fullscreen first). keyCode 3 = F, 13 = W.
    static func listShortcut(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String? {
        let mods = flags.intersection([.command, .control, .option, .shift])
        if keyCode == 3, flags.contains(.function), mods.isEmpty { return "fullscreen" }
        if keyCode == 13, mods == [.command] { return "minimize" }
        return nil
    }
}

// Font choices (Step 4): setting value -> font names to try, in order.
enum FontLogic {
    static let settings = ["serif", "sans", "retro"]
    static func normalize(_ v: String?) -> String { settings.contains(v ?? "") ? v! : "retro" }
    static func names(_ v: String?) -> [String] {
        switch normalize(v) {
        case "serif": return ["TimesNewRomanPSMT", "Times New Roman"]
        case "sans": return ["Helvetica"]
        default: return ["CourierPrimeSans-Regular", "Courier Prime Sans", "Courier"]
        }
    }
    static func label(_ v: String) -> String { ["serif": "Serif", "sans": "Sans-serif", "retro": "Retro"][v] ?? "Retro" }
}

// Color themes (Step 3): Background, Text, Title, Highlight as 0xRRGGBB.
struct ThemeSpec: Equatable { let name: String; let dark: Bool; let bg: UInt32; let text: UInt32; let title: UInt32; let highlight: UInt32; var bold: UInt32? = nil }
enum ThemeLogic {
    // Six themes (Oct 2026 redesign, see floatnote-themes-proposal.md). Dark: Graphite (grayscale), Harbor (default), Arcade.
    // Light: Fog (grayscale), Parchment, Sorbet. `bold` = nil: white on dark themes, the text color on light ones.
    static let all: [ThemeSpec] = [
        ThemeSpec(name: "Graphite", dark: true, bg: 0x151515, text: 0xC8C8C8, title: 0x909090, highlight: 0xFFB454, bold: 0xE6E6E6),
        ThemeSpec(name: "Fog", dark: false, bg: 0xF3F3F3, text: 0x1F1F1F, title: 0x666666, highlight: 0x000000),
        ThemeSpec(name: "Parchment", dark: false, bg: 0xFFFCF0, text: 0x100F0F, title: 0x1C6C66, highlight: 0xBC5215),
        ThemeSpec(name: "Sorbet", dark: false, bg: 0xFFF3F8, text: 0x2E1A47, title: 0xC2185B, highlight: 0x0050D0),
        ThemeSpec(name: "Arcade", dark: true, bg: 0x1C1330, text: 0xF1E9FF, title: 0xFF7EDB, highlight: 0x36F9F6),
        ThemeSpec(name: "Harbor", dark: true, bg: 0x0A0D14, text: 0xCBD5F0, title: 0x7AA2F7, highlight: 0x5DE4C7)]
    // Bold text color: the theme's own, else white (dark) / the text color (light). Never equal to the highlight (tested).
    static func boldColor(_ t: ThemeSpec) -> UInt32 { t.bold ?? (t.dark ? 0xFFFFFF : t.text) }
    // Hints, labels and dates: the text color at 60% (dark) / 65% (light) so they stay readable.
    static let minOpacity: CGFloat = 0.4      // slider / , . floor of the box background opacity
    static func hintAlpha(dark: Bool) -> CGFloat { dark ? 0.60 : 0.65 }
    // Highlight colors of earlier versions: text highlighted under an old theme still counts as highlighted.
    static let legacyHighlights: [UInt32] = [0xFF7C4D, 0xD9480F, 0xE01E1E, 0xF07BFF, 0xB5FF3B, 0x3DA9FF, 0xFF8800, 0xE6FF00]
    // Old theme names (before the redesign) -> their replacement.
    static let renamed: [String: String] = ["Dark": "Graphite", "Light": "Fog", "Newsprint": "Parchment", "Plum Jam": "Sorbet", "Moss": "Arcade"]
    static func named(_ n: String?) -> ThemeSpec { all.first { $0.name == n } ?? all[0] }
    // Saved theme if valid; else an old "appearance" = light maps to Light; else Harbor (new users: black + blue).
    static let defaultTheme = "Harbor"
    static func migrate(theme: String?, appearance: String?) -> String {
        if let t = theme, all.contains(where: { $0.name == t }) { return t }
        if let t = theme, let n = renamed[t] { return n }
        return appearance?.lowercased() == "light" ? "Fog" : defaultTheme
    }
    static func rgb(_ h: UInt32) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        (CGFloat((h >> 16) & 0xFF) / 255, CGFloat((h >> 8) & 0xFF) / 255, CGFloat(h & 0xFF) / 255)
    }
    static func hex(_ h: UInt32) -> String { String(format: "#%06X", h) }
    static func index(of name: String) -> Int { all.firstIndex { $0.name == name } ?? 0 }
    // Highlight text: any theme's Highlight plus the older #FF8800 and #E6FF00.
    static func isHighlight(r: CGFloat, g: CGFloat, b: CGFloat) -> Bool {
        (all.map { $0.highlight } + legacyHighlights).contains { h in
            let c = rgb(h); return abs(c.r - r) < 0.02 && abs(c.g - g) < 0.02 && abs(c.b - b) < 0.02
        }
    }
}

// Right Option tapped alone (keycode 61): press and release with nothing else in between.
struct RightOptionTap {
    static let window: TimeInterval = 0.4
    var key: UInt16            // 61 Right Option; also used for Right Command (54)
    private var downAt: TimeInterval?
    init(key: UInt16 = 61) { self.key = key }
    // A flagsChanged event. Returns true when it completes a clean tap.
    mutating func flags(keyCode: UInt16, rightOptionDown: Bool, otherModifiers: Bool, time: TimeInterval) -> Bool {
        // rightOptionDown = "the watched key is down" (named for the first use).
        if keyCode == key && rightOptionDown && !otherModifiers { downAt = time; return false }
        if keyCode == key && !rightOptionDown, let t = downAt {
            downAt = nil
            return !otherModifiers && time - t <= RightOptionTap.window
        }
        downAt = nil          // any other modifier change cancels
        return false
    }
    mutating func interrupt() { downAt = nil }   // a key or mouse press in between
}

// Dash lists: a line that starts with "- " (dash and a space) is a list item too, with the same hanging indent; Return
// continues with "- ". A dash without a space ("--", "---", "-5", "->") is not a list. The file keeps the plain "- item".
// Numbered lists (format 4): one level only. A list line is a plain number, ". " and the text ("1. Prune").
// Numbers are real text, rewritten only as part of the edit that changes the list (one undo step).
// Leading tabs (pasted text, older notes) are read but dropped when the list is renumbered.
enum ListLogic {
    struct Item { let number: Int; let tabs: Int; let markerLen: Int; let contentEmpty: Bool; var bullet = false }

    static func item(_ line: String) -> Item? {
        let ns = line as NSString
        var i = 0
        while i < ns.length && ns.character(at: i) == 9 { i += 1 }
        if i + 1 < ns.length, ns.character(at: i) == 45, ns.character(at: i + 1) == 32 {      // "- "
            return Item(number: 0, tabs: i, markerLen: i + 2, contentEmpty: i + 2 == ns.length, bullet: true)
        }
        var j = i
        while j < ns.length, ns.character(at: j) >= 48, ns.character(at: j) <= 57 { j += 1 }
        guard j > i, j - i <= 9, j + 1 < ns.length,
              ns.character(at: j) == 46, ns.character(at: j + 1) == 32,
              let n = Int(ns.substring(with: NSRange(location: i, length: j - i))) else { return nil }
        return Item(number: n, tabs: i, markerLen: j + 2, contentEmpty: j + 2 == ns.length)
    }

    static func marker(_ number: Int) -> String { "\(number). " }

    // Correct marker for every line (nil = not a list line). A list is a run of list lines; any other
    // line (also an empty one) ends it. The first item's number is the start (type "4. " to start at 4).
    static func markers(_ lines: [String]) -> [String?] {
        var out: [String?] = []
        var n = 0, inList = false
        for line in lines {
            guard let it = item(line) else { out.append(nil); inList = false; continue }
            if it.bullet { out.append("- "); inList = false; continue }      // dash items are never numbered
            n = inList ? n + 1 : it.number
            inList = true
            out.append(marker(n))
        }
        return out
    }

    // Lines with their line endings (so a note can be rebuilt exactly).
    static func split(_ text: String) -> [(line: String, end: String)] {
        let ns = text as NSString
        var out: [(String, String)] = [], pos = 0
        while pos < ns.length {
            var a = 0, b = 0, c = 0
            ns.getParagraphStart(&a, end: &b, contentsEnd: &c, for: NSRange(location: pos, length: 0))
            out.append((ns.substring(with: NSRange(location: a, length: c - a)), ns.substring(with: NSRange(location: c, length: b - c))))
            pos = b
        }
        if text.isEmpty || text.hasSuffix("\n") { out.append(("", "")) }
        return out
    }

    // The whole note with every list numbered correctly (only markers change).
    static func renumber(_ text: String) -> String {
        let lines = split(text)
        let want = markers(lines.map { $0.line })
        var out = ""
        for (k, l) in lines.enumerated() {
            if let m = want[k], let it = item(l.line) { out += m + (l.line as NSString).substring(from: it.markerLen) }
            else { out += l.line }
            out += l.end
        }
        return out
    }

    // ---- Edits. Each returns the plain new text and selection; finish() renumbers and maps the selection.
    static func lineBounds(_ ns: NSString, _ loc: Int) -> (start: Int, contentsEnd: Int, end: Int) {
        var a = 0, b = 0, c = 0
        ns.getParagraphStart(&a, end: &b, contentsEnd: &c, for: NSRange(location: min(loc, ns.length), length: 0))
        return (a, c, b)
    }
    static func lineIndex(_ lines: [(line: String, end: String)], _ loc: Int) -> (index: Int, start: Int) {
        var pos = 0
        for (k, l) in lines.enumerated() {
            let len = (l.line as NSString).length + (l.end as NSString).length
            if loc < pos + len || k == lines.count - 1 { return (k, pos) }
            pos += len
        }
        return (0, 0)
    }
    // A location in `from` moved to the same spot in `to` (same lines; only list markers differ).
    static func mapLoc(_ from: String, _ to: String, _ loc: Int) -> Int {
        let a = split(from), b = split(to)
        guard a.count == b.count else { return min(loc, (to as NSString).length) }
        let (k, startA) = lineIndex(a, loc)
        var startB = 0
        for i in 0..<k { startB += (b[i].line as NSString).length + (b[i].end as NSString).length }
        let off = loc - startA
        let mlA = item(a[k].line)?.markerLen ?? 0, mlB = item(b[k].line)?.markerLen ?? 0
        let newOff = off >= mlA ? off - mlA + mlB : min(off, mlB)
        return min(startB + min(newOff, (b[k].line as NSString).length + (b[k].end as NSString).length), (to as NSString).length)
    }
    static func mapSel(_ from: String, _ to: String, _ sel: NSRange) -> NSRange {
        let a = mapLoc(from, to, sel.location), b = mapLoc(from, to, NSMaxRange(sel))
        return NSRange(location: a, length: max(0, b - a))
    }
    static func finish(_ plain: String, _ sel: NSRange, old: String? = nil, at: Int? = nil) -> (text: String, sel: NSRange) {
        let src = keepStart(plain, old: old, at: at)
        let fixed = renumber(src)
        return (fixed, fixed == plain ? sel : mapSel(plain, fixed, sel))
    }
    // First line (index) of the list block containing line k, or nil if line k isn't a list line.
    static func blockStart(_ lines: [(line: String, end: String)], _ k: Int) -> Int? {
        guard k < lines.count, item(lines[k].line) != nil else { return nil }
        var i = k
        while i > 0, item(lines[i - 1].line) != nil { i -= 1 }
        return i
    }
    // If an edit at `at` removed a list's first item, the next item takes over the list's start number
    // (deleting "1." leaves 1, 2 instead of 2, 3). A typed "4. " on a fresh line still starts at 4.
    static func keepStart(_ plain: String, old: String?, at: Int?) -> String {
        guard let old = old, let at = at else { return plain }
        let o = split(old), n = split(plain)
        let (ko, _) = lineIndex(o, at), (kn, _) = lineIndex(n, at)
        guard let bo = blockStart(o, ko), let bn = blockStart(n, kn) ?? blockStart(n, kn + 1) else { return plain }
        var startO = 0
        for i in 0..<bo { startO += (o[i].line as NSString).length + (o[i].end as NSString).length }
        var startN = 0
        for i in 0..<bn { startN += (n[i].line as NSString).length + (n[i].end as NSString).length }
        guard startO <= at, startN >= at, let first = item(o[bo].line), let cur = item(n[bn].line),
              !first.bullet, !cur.bullet, cur.number != first.number
        else { return plain }
        var out = ""
        for (k, l) in n.enumerated() {
            out += k == bn ? marker(first.number) + (l.line as NSString).substring(from: cur.markerLen) : l.line
            out += l.end
        }
        return out
    }
    // Smallest replacement turning a into b.
    static func diff(_ a: String, _ b: String) -> (range: NSRange, with: String) {
        let x = a as NSString, y = b as NSString
        var p = 0
        while p < x.length && p < y.length && x.character(at: p) == y.character(at: p) { p += 1 }
        var q = 0
        while q < x.length - p && q < y.length - p && x.character(at: x.length - 1 - q) == y.character(at: y.length - 1 - q) { q += 1 }
        // keep surrogate pairs whole
        while p > 0, (p < x.length && UTF16.isTrailSurrogate(x.character(at: p))) || (p < y.length && UTF16.isTrailSurrogate(y.character(at: p))) { p -= 1 }
        q = min(q, x.length - p, y.length - p)
        return (NSRange(location: p, length: x.length - p - q), y.substring(with: NSRange(location: p, length: y.length - p - q)))
    }

    // Return. Item with text: split it; the new item gets the next number. Empty item: the list ends
    // (the line becomes an empty plain line).
    static func returnEdit(_ text: String, sel: NSRange) -> (text: String, sel: NSRange)? {
        let ns = text as NSString
        let lb = lineBounds(ns, sel.location)
        guard NSMaxRange(sel) <= lb.contentsEnd, let it = item(ns.substring(with: NSRange(location: lb.start, length: lb.contentsEnd - lb.start)))
        else { return nil }
        if it.contentEmpty && sel.length == 0 {
            let out = ns.replacingCharacters(in: NSRange(location: lb.start, length: it.markerLen), with: "")
            return (out, NSRange(location: lb.start, length: 0))
        }
        let at = max(sel.location, lb.start + it.markerLen)
        let ins = "\n" + (it.bullet ? "- " : marker(it.number + 1))
        let out = ns.replacingCharacters(in: NSRange(location: at, length: max(0, NSMaxRange(sel) - at)), with: ins)
        return (out, NSRange(location: at + (ins as NSString).length, length: 0))
    }

    // Backspace at the start of an item's text: the line becomes plain text.
    static func backspaceEdit(_ text: String, caret: Int) -> (text: String, sel: NSRange)? {
        let ns = text as NSString
        let lb = lineBounds(ns, caret)
        guard let it = item(ns.substring(with: NSRange(location: lb.start, length: lb.contentsEnd - lb.start))),
              caret == lb.start + it.markerLen else { return nil }
        let out = ns.replacingCharacters(in: NSRange(location: lb.start, length: it.markerLen), with: "")
        return (out, NSRange(location: lb.start, length: 0))
    }

    // Old format (before format 3): "1.1.2. text" path markers (old notes may also have leading tabs).
    static func convertOld(_ text: String) -> String {
        let lines = split(text)
        var out = ""
        for l in lines {
            let line = l.line
            if let m = line.range(of: "^\t*([0-9]+\\.){1,3} ", options: .regularExpression) {
                let marker = line[m].trimmingCharacters(in: CharacterSet(charactersIn: "\t "))
                let parts = marker.split(separator: ".").compactMap { Int($0) }
                if let last = parts.last {
                    out += self.marker(last) + line[m.upperBound...] + l.end
                    continue
                }
            }
            out += line + l.end
        }
        return renumber(out)
    }
}

// Clicks on list lines in the note: a double click strikes the whole item through (again = off), ⌘+click or a triple
// click highlights it (again = off). A triple click is click 2 (strike, already applied, immediately) then click 3:
// click 3 takes that strike back and highlights, so the net result of a triple click is the highlight only. The markers go after the item's "- " / "12. " exactly like the Strike / Highlight keys put them.
// Other lines and other clicks are not touched (a double click elsewhere still selects a word).
enum ListClick {
    enum Action: Equatable { case none, strike, highlight, triple }
    static func action(clickCount: Int, flags: NSEvent.ModifierFlags) -> Action {
        let mods = flags.intersection([.command, .control, .option, .shift])
        if mods == [.command] { return .highlight }
        if mods.isEmpty && clickCount == 2 { return .strike }
        if mods.isEmpty && clickCount == 3 { return .triple }
        return .none
    }
    // The edit for a click on the line holding `loc`; nil unless that line is a list item with text.
    // `strikeApplied`: for a triple click, the strike made by click 2 is still on the item: it is taken back first.
    static func toggle(_ text: NSString, at loc: Int, _ action: Action, strikeApplied: Bool = false) -> (whole: NSRange, text: String, caret: Int)? {
        guard action != .none, loc >= 0, loc <= text.length else { return nil }
        if action == .triple {
            guard let hl = toggle(text, at: loc, .highlight) else { return nil }
            if !strikeApplied { return hl }
            // un-strike, then highlight: both on the one line, as a single replacement
            guard let un = toggle(text, at: loc, .strike) else { return hl }
            let lb = ListLogic.lineBounds(text, loc)
            let t1 = text.replacingCharacters(in: un.whole, with: un.text) as NSString
            guard let h2 = toggle(t1, at: lb.start, .highlight) else { return hl }
            let t2 = t1.replacingCharacters(in: h2.whole, with: h2.text) as NSString
            let lb2 = ListLogic.lineBounds(t2, lb.start)
            return (NSRange(location: lb.start, length: lb.contentsEnd - lb.start),
                    t2.substring(with: NSRange(location: lb2.start, length: lb2.contentsEnd - lb2.start)),
                    lb.start + (lb2.contentsEnd - lb2.start))
        }
        let lb = ListLogic.lineBounds(text, loc)
        let line = text.substring(with: NSRange(location: lb.start, length: lb.contentsEnd - lb.start))
        guard let it = ListLogic.item(line), !it.contentEmpty,
              !line.dropFirst(it.markerLen).allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
        let style: MarkerLogic.Style = action == .strike ? .strike : .highlight        // (.triple never gets here)
        guard let t = MarkerLogic.toggleSelection(text, selection: NSRange(location: lb.start, length: lb.contentsEnd - lb.start), style: style)
        else { return nil }
        return (t.whole, t.text, t.whole.location + (t.text as NSString).length)
    }
}

// Copy out (⌃⌘G). One parser (built on the display's own HeadingLogic / ListLogic / MarkerLogic
// and its "---"/"===" rule test) -> blocks; two pure renderers: HTML (Google Docs) and clean text.
enum ExportLogic {
    static let titleRed = "#FF2020"      // titlePink / subtitleOrange
    static let neonYellow = "#FF8800"    // highlightOrange (name kept)
    enum Kind: Equatable { case title, subtitle, paragraph, listItem(number: Int), bulletItem, rule, doubleRule, empty }
    struct Block { let kind: Kind; let text: String; let spans: [MarkerLogic.Span] }

    static func parse(_ note: String) -> [Block] {
        var out: [Block] = []
        (note as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (note as NSString).length),
                                               options: .byParagraphs) { sub, _, _, _ in
            // Trailing spaces/tabs are invisible in the box but paste as stray spaces (and as a
            // hard line break in other editors), so they are dropped from the export.
            var line = sub ?? ""
            while let last = line.last, last == " " || last == "\t" { line.removeLast() }
            func block(_ k: Kind, _ t: String) -> Block { Block(kind: k, text: t, spans: MarkerLogic.spans(t)) }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { out.append(Block(kind: .empty, text: "", spans: [])) }
            else if line == "---" { out.append(Block(kind: .rule, text: "", spans: [])) }
            else if line == "===" { out.append(Block(kind: .doubleRule, text: "", spans: [])) }
            else if let h = HeadingLogic.kind(line) {
                out.append(block(h.kind == .title ? .title : .subtitle, (line as NSString).substring(from: h.markerLen)))
            } else if let it = ListLogic.item(line) {
                out.append(block(it.bullet ? .bulletItem : .listItem(number: it.number),
                                 (line as NSString).substring(from: it.markerLen)))
            } else { out.append(block(.paragraph, line)) }
        }
        return out
    }

    static func isList(_ k: Kind) -> Bool { if case .listItem = k { return true }; return k == .bulletItem }

    // Clean text: every marker removed. Titles as typed, list items keep their visible number ("3. "),
    // "---" / "===" lines become empty lines. One output line per note line.
    static func plain(_ b: Block) -> String {
        let s = NSMutableString(string: b.text)
        for r in b.spans.flatMap({ [$0.open, $0.close] }).sorted(by: { $0.location > $1.location }) { s.deleteCharacters(in: r) }
        return s as String
    }

    static func cleanText(_ blocks: [Block]) -> String {
        blocks.map { b -> String in
            switch b.kind {
            case .empty, .rule, .doubleRule: return ""
            case let .listItem(number): return "\(number). " + plain(b)
            case .bulletItem: return "- " + plain(b)
            default: return plain(b)
            }
        }.joined(separator: "\n")
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    // Styled runs: marker characters dropped, each run wrapped in its styles' tags.
    static func inlineHTML(_ b: Block, upper: Bool = false) -> String {
        let s = b.text as NSString
        var styles = [Set<MarkerLogic.Style>](repeating: [], count: s.length)
        var hidden = [Bool](repeating: false, count: s.length)
        for sp in b.spans {
            for k in sp.open.location..<NSMaxRange(sp.open) { hidden[k] = true }
            for k in sp.close.location..<NSMaxRange(sp.close) { hidden[k] = true }
            for k in sp.content.location..<NSMaxRange(sp.content) { styles[k].insert(sp.style) }
        }
        var out = ""
        var i = 0
        while i < s.length {
            if hidden[i] { i += 1; continue }
            var j = i
            while j < s.length, !hidden[j], styles[j] == styles[i] { j += 1 }
            let raw = s.substring(with: NSRange(location: i, length: j - i))
            var t = escape(upper ? raw.uppercased() : raw)
            let st = styles[i]
            if st.contains(.highlight) { t = "<span style=\"background-color:\(neonYellow)\">\(t)</span>" }
            if st.contains(.strike) { t = "<span style=\"text-decoration:line-through\">\(t)</span>" }
            if st.contains(.underline) { t = "<u>\(t)</u>" }
            if st.contains(.italic) { t = "<i>\(t)</i>" }
            if st.contains(.bold) { t = "<b>\(t)</b>" }
            out += t
            i = j
        }
        return out
    }

    // No text-align anywhere: all text is left-aligned.
    static func html(_ blocks: [Block]) -> String {
        var body = ""
        var listTag: String? = nil                      // "ol" / "ul" while inside a list (one level)
        func closeList() { if let t = listTag { body += "</li></\(t)>"; listTag = nil } }
        func listItem(_ tag: String, start: Int = 1, style: String) {
            if listTag == tag { body += "</li>" }
            else {
                closeList()
                body += "<\(tag) style=\"list-style-type:\(style)\"" + (tag == "ol" && start != 1 ? " start=\"\(start)\"" : "") + ">"
                listTag = tag
            }
            body += "<li style=\"list-style-type:\(style)\">"
        }
        var lastEmpty = true          // also skips leading empties
        for b in blocks {
            if case let .listItem(number) = b.kind {
                listItem("ol", start: number, style: "decimal")
                body += inlineHTML(b)
                lastEmpty = false
                continue
            }
            if b.kind == .bulletItem {
                listItem("ul", style: "disc")
                body += inlineHTML(b)
                lastEmpty = false
                continue
            }
            closeList()
            switch b.kind {
            case .empty:
                if !lastEmpty { body += "<p><br></p>" }
                lastEmpty = true; continue
            case .title:
                body += "<h1><span style=\"color:\(titleRed);font-weight:bold\">\(inlineHTML(b, upper: true))</span></h1>"
            case .subtitle:
                body += "<h2><span style=\"color:\(titleRed);font-weight:bold\">\(inlineHTML(b, upper: true))</span></h2>"
            case .rule: body += "<hr>"
            case .doubleRule: body += "<hr><hr>"
            case .paragraph: body += "<p>" + inlineHTML(b) + "</p>"
            case .listItem, .bulletItem: break
            }
            lastEmpty = false        // no whitespace between blocks: Docs can paste it as a stray space
        }
        closeList()
        if body.hasSuffix("<p><br></p>") { body.removeLast("<p><br></p>".count) }
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>" + body + "</body></html>"
    }
}
// Paragraph mode: join the split lines back with single spaces (trimmed, empty lines skipped), keeping attributes.
enum ParaLogic {
    // Paragraph mode, display only: the space after each sentence line = one blank line of the text (its font's line
    // height, times the fullscreen line spacing when that is wider), so sentences sit one empty line apart.
    // Nothing is added to the text: leaving the mode still joins the sentences with single spaces.
    static let sentenceLineSpacing: CGFloat = 4
    static func sentenceGap(font: NSFont, lineMultiple: CGFloat = 0) -> CGFloat {
        let line = NSLayoutManager().defaultLineHeight(for: font)
        return ceil(line * max(lineMultiple, 1))
    }
    // Hidden list tabs are found by styleLists, which does not run in paragraph mode.
    // Their ranges point into the full note, so in the split view they would hide unrelated characters.
    static func listPrefixesToHide(_ computed: [NSRange], paraMode: Bool) -> [NSRange] { paraMode ? [] : computed }
    static func rejoin(_ edited: NSAttributedString) -> NSMutableAttributedString {
        let joined = NSMutableAttributedString()
        (edited.string as NSString).enumerateSubstrings(in: NSRange(location: 0, length: edited.length), options: .byParagraphs) { _, r, _, _ in
            let piece = NSMutableAttributedString(attributedString: edited.attributedSubstring(from: r))
            while piece.length > 0, let u = UnicodeScalar((piece.string as NSString).character(at: piece.length - 1)),
                  CharacterSet.whitespaces.contains(u) { piece.deleteCharacters(in: NSRange(location: piece.length - 1, length: 1)) }
            while piece.length > 0, let u = UnicodeScalar((piece.string as NSString).character(at: 0)),
                  CharacterSet.whitespaces.contains(u) { piece.deleteCharacters(in: NSRange(location: 0, length: 1)) }
            guard piece.length > 0 else { return }
            if joined.length > 0 {
                joined.append(NSAttributedString(string: " ", attributes: joined.attributes(at: joined.length - 1, effectiveRange: nil)))
            }
            joined.append(piece)
        }
        return joined
    }
}

// MARK: Shortcut list (Step 8) — data only; the cheat sheet (⌘/) reads it (and a future palette, ⌘K).
// The key handlers do not read this list. `run` is an action id that AppDelegate.runShortcut(_:) performs
// (it calls the same function the key runs now); nil = context-only key.
// When you add or change a shortcut, change this list too.
struct Shortcut: Equatable {
    let id: String, keys: String, name: String, group: String, scope: String, run: String?
    var onSheet = false            // shown on the cheat sheet (⌘/)
    var sheetKeys = ""             // keys as the sheet shows them (one row can cover two entries)
    var sheetText = ""             // the sheet's row text
}
enum ShortcutList {
    static let groups = ["All apps", "Notes", "Text styles", "Structure", "Find", "Views", "Send text out", "Window mode"]
    static let scopes = ["global", "note", "windowMode", "fullscreen", "navigator", "settings", "notesList"]
    static func s(_ id: String, _ keys: String, _ name: String, _ group: String, _ scope: String, _ run: String? = nil) -> Shortcut {
        Shortcut(id: id, keys: keys, name: name, group: group, scope: scope, run: run)
    }
    // Cheat sheet rows, by entry id: (keys shown, text). Only these entries are on the sheet, in list order.
    // findPrev has no row of its own: the findNext row covers both.
    static let sheet: [String: (keys: String, text: String)] = [
        "focusTap": ("R Option", "Shows / hides"),
        "windowModeTap": ("R Command", "Window mode"),
        "sendSelection": ("⌃⌥S", "Selection to note"),
        "highlight": ("fn L", "Highlight"),
        "strike": ("fn X", "Strikethrough"),
        "titleRules": ("fn T", "Title lines"),
        "find": ("⌘F", "Find"),
        "replace": ("fn R", "Find + replace"),
        "findNext": ("⌘G / ⇧⌘G", "Matches"),
        "useSelection": ("⌘E", "Selected find"),
        "navigator": ("fn O", "Navigator"),
        "paragraph": ("fn P", "Paragraph mode"),
        "copyOut": ("fn J", "Google Doc"),
        "askGrok": ("fn G", "Ask Grok"),
        "wmBottomRight": ("w a s d", "Size"),
        "wmOpacity": (", .", "Opacity"),
    ]
    // fn + letter (only while FloatNote is focused; the old keys still work). Entry id -> letter.
    // A C D E F H N Q are macOS Globe shortcuts and stay unused (fn F = fullscreen).
    static let fnLetters: [String: Character] = [
        "highlight": "L", "strike": "X", "caps": "U", "titleRules": "T", "replace": "R",
        "navigator": "O", "paragraph": "P", "copyOut": "J", "askGrok": "G", "askClaude": "K", "redo": "Y", "postToX": "M",
    ]
    static let fnReserved: Set<Character> = ["A", "C", "D", "E", "F", "H", "N", "Q"]
    // The run id for an fn + letter press, if any.
    static func fnRun(_ letter: Character) -> String? {
        let up = Character(letter.uppercased())
        guard let id = fnLetters.first(where: { $0.value == up })?.key else { return nil }
        return entries.first { $0.id == id }?.run
    }
    static let all: [Shortcut] = entries.map { e in
        var e = e
        if let row = sheet[e.id] { e.onSheet = true; e.sheetKeys = row.keys; e.sheetText = row.text }
        return e
    }
    static let entries: [Shortcut] = [
        // All apps
        s("focusTap", "Right Option (tap)", "Show / hide the note", "All apps", "global", "focusTap"),
        s("windowModeTap", "Right Command (tap)", "Window mode on/off", "All apps", "global", "windowMode"),
        s("sendSelection", "⌃⌥S", "Selected text (any app) is added to the open note (no note open: a new note, in fullscreen)", "All apps", "global", "sendSelection"),
        // Notes
        s("cut", "⌘X", "Cut", "Notes", "note", "cut"),
        s("copy", "⌘C", "Copy", "Notes", "note", "copy"),
        s("paste", "⌘V", "Paste as plain text", "Notes", "note", "paste"),
        s("selectAll", "⌘A", "Select all", "Notes", "note", "selectAll"),
        s("undo", "⌘Z", "Undo", "Notes", "note", "undo"),
        s("redo", "⇧⌘Z", "Redo", "Notes", "note", "redo"),
        s("sizeUp", "⌘+", "Bigger text", "Notes", "note", "sizeUp"),
        s("sizeDown", "⌘−", "Smaller text", "Notes", "note", "sizeDown"),
        s("settings", "⌘,", "Settings", "Notes", "note", "settings"),
        s("cheatSheet", "⌘/", "Shortcuts cheat sheet", "Notes", "note", "cheatSheet"),
        s("quit", "⌘Q", "Quit FloatNote", "Notes", "note", "quit"),
        s("newNote", "⌘N", "New note", "Notes", "note", "newNote"),
        s("escape", "Esc", "Close find bar / paragraph mode / jump back", "Notes", "note"),
        // Text styles
        s("bold", "⌘B", "Bold", "Text styles", "note", "bold"),
        s("italic", "⌘I", "Italic", "Text styles", "note", "italic"),
        s("underline", "⌘U", "Underline", "Text styles", "note", "underline"),
        s("highlight", "⇧⌘H", "Highlight", "Text styles", "note", "highlight"),
        s("strike", "⇧⌘X", "Strikethrough", "Text styles", "note", "strike"),
        s("caps", "⇧⌘A", "ALL CAPS", "Text styles", "note", "caps"),
        // Structure
        s("titleRules", "⌥⌘T", "Rules above/below this title", "Structure", "note", "titleRules"),
        s("listReturn", "Return", "Next list item · on empty item: end list", "Structure", "note"),
        s("listBackspace", "⌫ at item start", "List item to plain line", "Structure", "note"),
        // Find
        s("find", "⌘F", "Find", "Find", "note", "find"),
        s("replace", "⌥⌘F", "Find and replace", "Find", "note", "replace"),
        s("findNext", "⌘G", "Next match", "Find", "note", "findNext"),
        s("findPrev", "⇧⌘G", "Previous match", "Find", "note", "findPrev"),
        s("useSelection", "⌘E", "Use selection for find", "Find", "note", "useSelection"),
        // Views
        s("navigator", "⌥⌘V", "Navigator open/close", "Views", "note", "navigator"),
        s("paragraph", "⌥⌘P", "Paragraph mode on/off", "Views", "note", "paragraph"),
        s("fullscreenFn", "fn+F", "Fullscreen on/off", "Views", "note", "fullscreen"),
        s("fullscreenEsc", "Esc", "Leave fullscreen", "Views", "fullscreen"),
        s("minimize", "⌘W", "Minimize to the Dock (Right Option or a click brings it back)", "Views", "note", "minimize"),
        s("fullscreenMinimize", "⌘W", "Leave fullscreen and minimize to the Dock", "Views", "fullscreen", "minimize"),
        s("navDown", "↓", "Next heading", "Views", "navigator"),
        s("navUp", "↑", "Previous heading", "Views", "navigator"),
        s("navJump", "Return", "Go to heading", "Views", "navigator"),
        s("navClose", "Esc", "Close (filter: clear filter)", "Views", "navigator"),
        s("navFilter", "⌘F", "Filter headings", "Views", "navigator"),
        s("navToggle", "⌥⌘V", "Close navigator", "Views", "navigator"),
        s("notesList", "⌘O", "Notes list", "Views", "note", "notesList"),
        s("listUp", "↑", "Previous note", "Views", "notesList"),
        s("listDown", "↓", "Next note", "Views", "notesList"),
        s("listOpen", "Return", "Open the note", "Views", "notesList"),
        s("listMouse", "Click / double-click", "Select / open the note under the pointer (hover shows a band)", "Views", "notesList"),
        s("listEsc", "Esc", "Clear filter / close the list", "Views", "notesList"),
        s("listFilter", "⌘F", "Filter notes", "Views", "notesList"),
        s("listRename", "← / → / R / F2", "Rename the note's file: ← starts empty, → / R / F2 keep the name (also ⌘+click or press and hold on a row). Blank = default name", "Views", "notesList"),
        s("listDelete", "⌘⌫", "Move the note to the Trash (asks first)", "Views", "notesList"),
        s("listTrashNow", "⌥⌘⌫", "Move the note to the Trash now (no asking; there is no permanent delete)", "Views", "notesList"),
        s("listClose", "⌘O", "Close the list", "Views", "notesList"),
        s("settingsClose", "⌘W / Esc", "Close Settings / cheat sheet", "Views", "settings"),
        s("settingsToggle", "⌘,", "Close Settings", "Views", "settings"),
        // Send text out
        s("copyOut", "⌃⌘G", "Copy out (Google Docs + clean text)", "Send text out", "note", "copyOut"),
        s("askGrok", "⌃⌘L", "Asks Grok about the selected text or the whole note.", "Send text out", "note", "askGrok"),
        s("askClaude", "⌃⌘K", "Asks Claude about the selected text or the whole note.", "Send text out", "note", "askClaude"),
        s("postToX", "⌃⌘X", "Opens the selected text as a new post on X in your browser (you press Post)", "Send text out", "note", "postToX"),
        // Window mode
        s("wmMove", "← → ↑ ↓ (⇧ = 4×)", "Move the box", "Window mode", "windowMode"),
        s("wmBottomRight", "w a s d (⇧ = 4×)", "Resize from bottom/right edges", "Window mode", "windowMode"),
        s("wmOpacity", ", / . (or < / >)", "Background opacity (also in fullscreen)", "Window mode", "windowMode"),
        s("wmExit", "Esc", "Leave window mode", "Window mode", "windowMode"),
    ]
    // Markers you type, shown as the last cheat sheet rows.
    static let typeSection: [(keys: String, name: String)] = [
        ("# ", "Title"), ("## ", "Subtitle"), ("---", "Single line"), ("===", "Double line"),
    ]
    // Modifier symbols at the start of a key label in macOS order: ⌃ ⌥ ⇧ ⌘.
    static func normalizeKeys(_ k: String) -> String {
        let order: [Character] = ["⌃", "⌥", "⇧", "⌘"]
        let mods = k.prefix { order.contains($0) }
        return String(mods.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }) + k.dropFirst(mods.count)
    }
    // Cheat sheet rows: onSheet entries in list order, then the marker rows. No group headers.
    static func sheetRows() -> [(keys: String, name: String)] {
        all.filter { $0.onSheet }.map { (keys: $0.sheetKeys, name: $0.sheetText) } + typeSection
    }
}
// Hidden markers (always hidden): keep the caret out of them and make Delete act on visible text.
enum HideLogic {
    // Where the caret may go. `hidden` = all hidden ranges; `heads` = title markers at line start
    // ("# ", "#< "...), where the caret goes after the marker so typing stays inside the title.
    static func snap(_ loc: Int, from old: Int, hidden: [NSRange], heads: [NSRange]) -> Int {
        var p = loc
        for _ in 0..<8 {                                   // adjacent markers ("**==") need a few passes
            var moved = false
            for r in hidden where p > r.location && p < NSMaxRange(r) {
                p = p >= old ? NSMaxRange(r) : r.location; moved = true
            }
            for r in heads where p == r.location && r.length > 0 {
                // Left arrow from just after the marker: to the end of the line above. Otherwise after the marker.
                p = (old == NSMaxRange(r) && r.location > 0) ? r.location - 1 : NSMaxRange(r); moved = true
            }
            if !moved { break }
        }
        return p
    }
    // Backspace with the caret at `loc` (no selection): the range to delete, or nil for the normal key.
    // After a title marker: the whole marker (the line becomes plain text).
    // After a hidden style marker: the visible character before the marker(s).
    static func backspace(_ loc: Int, hidden: [NSRange], heads: [NSRange]) -> NSRange? {
        if let h = heads.first(where: { NSMaxRange($0) == loc && $0.length > 0 }) { return h }
        guard hidden.contains(where: { NSMaxRange($0) == loc && $0.length > 0 }) else { return nil }
        var p = loc
        while let r = hidden.first(where: { NSMaxRange($0) == p && $0.length > 0 }) { p = r.location }
        return p > 0 ? NSRange(location: p - 1, length: 1) : NSRange(location: 0, length: 0)
    }
    // Forward delete: the visible character after hidden style marker(s) that start at `loc`.
    static func forwardDelete(_ loc: Int, hidden: [NSRange], length: Int) -> NSRange? {
        guard hidden.contains(where: { $0.location == loc && $0.length > 0 }) else { return nil }
        var p = loc
        while let r = hidden.first(where: { $0.location == p && $0.length > 0 }) { p = NSMaxRange(r) }
        return p < length ? NSRange(location: p, length: 1) : NSRange(location: length, length: 0)
    }
}
// First launch (no saved frame): the box is about 60% of the visible screen, centered.
enum DefaultFrameLogic {
    static func frame(visible v: NSRect, fraction f: CGFloat = 0.6) -> NSRect {
        let w = (v.width * f).rounded(), h = (v.height * f).rounded()
        return NSRect(x: (v.minX + (v.width - w) / 2).rounded(), y: (v.minY + (v.height - h) / 2).rounded(), width: w, height: h)
    }
}
// Style keys with no selection: nothing is inserted; the styles wait for the next typed text.
enum PendingStyleLogic {
    static let order: [MarkerLogic.Style] = [.bold, .italic, .underline, .highlight, .strike]
    static func name(_ s: MarkerLogic.Style) -> String {
        switch s { case .bold: return "Bold"; case .italic: return "Italic"; case .underline: return "Underline"
                   case .highlight: return "Highlight"; case .strike: return "Strikethrough" }
    }
    // Typed text wrapped in the pending styles' markers, and where the caret goes (just before the closers).
    static func wrap(_ typed: String, _ styles: Set<MarkerLogic.Style>) -> (text: String, caret: Int) {
        let list = order.filter { styles.contains($0) }
        let opens = list.map { MarkerLogic.tokens[$0]!.open }.joined()
        let closes = list.reversed().map { MarkerLogic.tokens[$0]!.close }.joined()
        let t = opens + typed
        return (t + closes, (t as NSString).length)
    }
    // Empty marker pairs (<u></u>, ****, ~~~~, ====) are removed, except a line that is only = or - characters (rules).
    static func stripEmptyPairs(_ text: String) -> String {
        guard text.contains("<u></u>") || text.contains("****") || text.contains("~~~~") || text.contains("====") else { return text }
        return text.components(separatedBy: "\n").map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, t.allSatisfy({ $0 == "=" || $0 == "-" }) { return line }
            var l = line
            for e in ["<u></u>", "****", "~~~~", "===="] { while l.contains(e) { l = l.replacingOccurrences(of: e, with: "") } }
            return l
        }.joined(separator: "\n")
    }
}
// Empty styled words: when a deletion empties a styled span, its marker pair goes too.
enum EmptyPairLogic {
    static let pairs: [(String, String)] = [("<u>", "</u>"), ("**", "**"), ("~~", "~~"), ("==", "=="), ("*", "*")]
    // Trigger: before the edit, some span's content lay entirely inside the deleted range (line offsets).
    static func emptiesSpan(line: String, deleted: NSRange) -> Bool {
        MarkerLogic.spans(line).contains { $0.content.length > 0 && NSIntersectionRange($0.content, deleted) == $0.content }
    }
    // Empty pairs meeting at offset `p` (open just before, close just after), removed from the inside out.
    // Returns ranges to delete (line offsets, descending) and the new caret offset.
    static func collapse(_ line: String, at p0: Int) -> (remove: [NSRange], caret: Int) {
        var ns = line as NSString, p = p0, out: [NSRange] = []
        var changed = true
        while changed {
            changed = false
            for (o, c) in pairs {
                let ol = (o as NSString).length, cl = (c as NSString).length
                guard p - ol >= 0, p + cl <= ns.length,
                      ns.substring(with: NSRange(location: p - ol, length: ol)) == o,
                      ns.substring(with: NSRange(location: p, length: cl)) == c else { continue }
                out.append(NSRange(location: p - ol, length: ol + cl))
                let m = NSMutableString(string: ns as String); m.deleteCharacters(in: NSRange(location: p - ol, length: ol + cl))
                ns = m; p -= ol; changed = true
                break
            }
        }
        return (out, p)   // ranges are in successive coordinates: apply in order
    }
    // The whole edit as one replacement: `range` (line offsets) widened to take the emptied pair(s) too.
    // nil = the edit leaves no empty pair.
    static func expand(line: String, range: NSRange, with rep: String) -> NSRange? {
        guard emptiesSpan(line: line, deleted: range) else { return nil }
        let after = (line as NSString).replacingCharacters(in: range, with: rep)
        let p = range.location + (rep as NSString).length
        let res = collapse(after, at: p)
        guard !res.remove.isEmpty else { return nil }
        let total = res.remove.reduce(0) { $0 + $1.length }
        let open = p - res.caret
        return NSRange(location: range.location - open, length: range.length + total)
    }
    // Pure helper for tests: the line after collapsing.
    static func apply(_ line: String, at p: Int) -> (String, Int) {
        let res = collapse(line, at: p)
        let m = NSMutableString(string: line)
        for r in res.remove { m.deleteCharacters(in: r) }
        return (m as String, res.caret)
    }
}
// Ask Grok (⌃⌘L): the message and the grok.com link. No API: the browser opens grok.com/?q=…
enum GrokLogic {
    // Prompt + one empty line + text; either side empty = just the other.
    static func message(prompt: String, text: String) -> String {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = text.trimmingCharacters(in: .newlines)
        if p.isEmpty { return t }
        if t.isEmpty { return p }
        return p + "\n\n" + t
    }
    // Query-value encoding: only RFC 3986 unreserved ASCII stays as is (so & + = # ? / space newline are encoded).
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    static func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "" }
    static func url(_ message: String) -> URL? { URL(string: "https://grok.com/?q=" + encode(message)) }
    // Ask Claude (⌃⌘K): same message and encoding, claude.ai/new?q= (prefills the prompt; you press send).
    static func claudeURL(_ message: String) -> URL? { URL(string: "https://claude.ai/new?q=" + encode(message)) }
}
// F2: the library folder's note files and the names of new ones.
enum NoteLibrary {
    static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    // "Note 23 -- 03OCT26.txt"
    static func fileName(number: Int, date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let c = calendar.dateComponents([.day, .month, .year], from: date)
        return String(format: "Note %d -- %02d%@%02d.txt", number, c.day ?? 1, months[(c.month ?? 1) - 1], (c.year ?? 2000) % 100)
    }
    // The number in "Note <number> -- ..." (nil for other names).
    static func number(in name: String) -> Int? {
        guard name.hasPrefix("Note ") else { return nil }
        let from = name.index(name.startIndex, offsetBy: 5)
        guard let r = name.range(of: " -- ", range: from..<name.endIndex) else { return nil }   // "Note -- x.txt" used to crash here
        let digits = name[from..<r.lowerBound]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }
    // nextNoteNumber at launch: starts at 1, never goes back, always above the largest number used.
    static func nextNumber(stored: Int, names: [String]) -> Int {
        let largest = names.compactMap(number).max() ?? 0
        return max(stored, 1, largest + 1)
    }
    // A note needs a file once it has a character. A note that has a file keeps it.
    static func needsFile(text: String, hasFile: Bool) -> Bool { hasFile || !text.isEmpty }
    // .txt files directly in the folder (no subfolders, no hidden files such as save temp files).
    static func noteFiles(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .creationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []
        return items.filter { $0.pathExtension.lowercased() == "txt"
            && ((try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false) }
    }
    // F3 row name: the first line with words, markers removed; else "Empty note".
    static func rowName(_ text: String) -> String {
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" || line == "===" { continue }
            if let h = HeadingLogic.kind(line) { line = (line as NSString).substring(from: h.markerLen) }
            for m in ["**", "==", "~~", "<u>", "</u>", "*"] { line = line.replacingOccurrences(of: m, with: "") }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) { return line }
        }
        return "Empty note"
    }
    // F3 row date: "14 Oct", or "14 Oct 2025" when not this year.
    static func rowDate(_ date: Date, now: Date = Date(), calendar: Calendar = Calendar.current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar; f.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        f.dateFormat = sameYear ? "d MMM" : "d MMM yyyy"
        return f.string(from: date)
    }
    // After a row is removed the cursor stays at the same index (= the next note); the last row -> the previous one.
    static func cursorAfterDelete(cursor: Int, remaining: Int) -> Int { min(cursor, max(remaining - 1, 0)) }
    // ⌘⌫ in the notes list: the note file goes to the macOS Trash (Finder: Put Back). `mover` is for tests.
    static func deleteNoteFile(_ url: URL, mover: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws { try mover(url) }
    // F5: drag to import. Only .txt and .md; read as UTF-8 (nil = can't read). The source is only read.
    static func canImport(_ url: URL) -> Bool { ["txt", "md"].contains(url.pathExtension.lowercased()) }
    static func readImport(_ url: URL) -> String? { readText(url) }
    // Reading a note or an import: UTF-8 first, then (so the text is not lost) UTF-16 with a byte order mark, then
    // Windows Western. nil = unreadable (missing, no permission, not downloaded from iCloud yet, or over `maxBytes`).
    // Callers must NOT treat nil as an empty note: saving over it would destroy the file.
    static let maxBytes = 50_000_000
    static func readText(_ url: URL, maxBytes: Int = NoteLibrary.maxBytes) -> String? {
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maxBytes { return nil }
        guard let data = try? Data(contentsOf: url), data.count <= maxBytes else { return nil }
        return decode(data)
    }
    static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if data.count >= 2, (data[0] == 0xFF && data[1] == 0xFE) || (data[0] == 0xFE && data[1] == 0xFF),
           let s = String(data: data, encoding: .utf16) { return s }
        return String(data: data, encoding: .windowsCP1252)
    }
    // The first line is all a list row needs: read only the start of the file (a big note is not read in full for ⌘O).
    static func readStart(_ url: URL, bytes: Int = 8192) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: bytes) else { return nil }
        if let s = String(data: data, encoding: .utf8) { return s }
        // a cut in the middle of a character: drop up to 3 trailing bytes and try again, else decode as far as possible
        for cut in 1...3 where data.count > cut { if let s = String(data: data.dropLast(cut), encoding: .utf8) { return s } }
        return decode(data) ?? String(decoding: data, as: UTF8.self)
    }
    // F4: a new note = no file and no text. ⌘N on a new note does nothing.
    static func isNewNote(hasFile: Bool, text: String) -> Bool { !hasFile && text.isEmpty }
    static func modDate(_ u: URL) -> Date {
        var u = u; u.removeAllCachedResourceValues()
        return (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }
    // ---- Created date (the ⌘O list's date, order and day separators) ----
    // The day in "Note N -- DDMONYY.txt" is the authoritative created day for notes the app made (nil for other
    // names). It is shown as noon that day (local), so a day never slips across midnight / DST.
    static func filenameDate(_ name: String, calendar: Calendar = .current) -> Date? {
        guard number(in: name) != nil, let tok = dateToken(in: name) else { return nil }
        let stamp = tok
        guard let day = Int(stamp.prefix(2)), let year = Int(stamp.suffix(2)),
              let m = months.firstIndex(of: stamp.dropFirst(2).prefix(3).uppercased()) else { return nil }
        var c = DateComponents(); c.year = 2000 + year; c.month = m + 1; c.day = day; c.hour = 12
        guard let d = calendar.date(from: c), calendar.component(.day, from: d) == day else { return nil }
        return d
    }
    // The "DDMONYY" at the end of a note file name: "Note 5 -- 14OCT26.txt" and "Note 5 -- Plan -- 14OCT26.txt" both
    // give "14OCT26". The date is always the LAST " -- " part, so a custom name may hold anything (it never holds " -- ").
    static func dateToken(in name: String) -> String? {
        guard name.lowercased().hasSuffix(".txt"), let r = name.range(of: " -- ", options: .backwards) else { return nil }
        let stamp = String(name[r.upperBound...].dropLast(4))
        guard stamp.count == 7, Int(stamp.prefix(2)) != nil, Int(stamp.suffix(2)) != nil,
              stamp.dropFirst(2).prefix(3).allSatisfy({ $0.isASCII && $0.isLetter }),
              months.contains(stamp.dropFirst(2).prefix(3).uppercased()) else { return nil }
        return stamp
    }
    // ---- Custom names (⌘O rename): the FILE is renamed; the first line of the note is never touched ----
    // Stored in the file name: "Note 5 -- Garden plan -- 14OCT26.txt" (number and date stay, so numbering, the created day
    // and the list order keep working). The list shows "Garden plan". Other names:
    //  - "Note 5 -- 14OCT26.txt": no custom name (the list shows the note's first line, as always);
    //  - any other file (renamed in Finder, imported, ...): its file name without ".txt" is the name; created date from the
    //    file's creation date. Only the legacy "notes.txt" keeps showing its first line.
    static func customName(inFileName name: String) -> String? {
        guard name.lowercased().hasSuffix(".txt") else { return nil }
        let base = String(name.dropLast(4))
        guard number(in: name) != nil, let r = name.range(of: " -- ") else { return base == "notes" || base.isEmpty ? nil : base }
        var rest = String(name[r.upperBound...].dropLast(4))
        if let tok = dateToken(in: name) {
            rest = String(rest.dropLast(tok.count))
            if rest.hasSuffix(" -- ") { rest = String(rest.dropLast(4)) }
        }
        rest = rest.trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }
    // The list row text for a file: the custom name from the file name (no read at all), else the note's first line.
    static func rowTitle(_ url: URL) -> String {
        let name = url.lastPathComponent
        if let custom = customName(inFileName: name) { return custom }
        return rowName(readStart(url) ?? "")
    }
    // What the list shows: the custom name when there is one, else the first line (rowName).
    static func displayName(fileName: String, text: String) -> String {
        customName(inFileName: fileName) ?? rowName(text)
    }
    // A name typed by the user -> safe for a file name: no / : \ or control characters, no " -- ", no leading dot,
    // no trailing ".txt", at most 80 characters. Empty result = cancel.
    static func sanitizedName(_ typed: String) -> String {
        var t = typed.components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters).union(.newlines)).joined(separator: " ")
        while t.contains(" -- ") { t = t.replacingOccurrences(of: " -- ", with: " - ") }
        t = t.trimmingCharacters(in: .whitespaces)
        while t.hasPrefix(".") { t.removeFirst() }
        if t.lowercased().hasSuffix(".txt") { t = String(t.dropLast(4)) }
        t = t.trimmingCharacters(in: .whitespaces)
        if t.count > 80 { t = String(t.prefix(80)).trimmingCharacters(in: .whitespaces) }
        return t
    }
    // New file name for a rename: keeps "Note N" and the date token; other files become "<name>.txt".
    // A blank name removes the custom name: back to "Note N -- DDMONYY.txt" (the date from the old name, else `created`).
    // Files that are not "Note N" files have no default to go back to: blank = nil (nothing changes).
    static func renamedFileName(old: String, newName: String, created: Date? = nil) -> String? {
        let n = sanitizedName(newName)
        guard !n.isEmpty else {
            guard let num = number(in: old), customName(inFileName: old) != nil else { return nil }
            if let tok = dateToken(in: old) { return "Note \(num) -- \(tok).txt" }
            return fileName(number: num, date: created ?? Date())
        }
        if let num = number(in: old) {
            let tok = dateToken(in: old).map { " -- " + $0 } ?? ""
            return "Note \(num) -- \(n)\(tok).txt"
        }
        return n + ".txt"
    }
    // Renames the file (same folder; name collisions get " 2", " 3"...). Returns the new URL, or nil = nothing changed
    // (empty name, same name, or the rename failed). Creation date, content and everything else stay as they are.
    static func renameNote(_ url: URL, to newName: String) -> URL? {
        guard let target = renamedFileName(old: url.lastPathComponent, newName: newName, created: createdDate(url)), target != url.lastPathComponent else { return nil }
        let dir = url.deletingLastPathComponent(), fm = FileManager.default
        var final = target, k = 2
        func taken(_ n: String) -> Bool {
            let u = dir.appendingPathComponent(n)
            return fm.fileExists(atPath: u.path) && u.path.lowercased() != url.path.lowercased()
        }
        while taken(final) {
            if customName(inFileName: target) == nil { return nil }      // the default name is taken by another file: leave it
            let base = String(target.dropLast(4)), tok = dateToken(in: target)
            if let tok = tok, base.hasSuffix(" -- " + tok) { final = String(base.dropLast(tok.count + 4)) + " \(k) -- \(tok).txt" }
            else { final = base + " \(k).txt" }
            k += 1
        }
        guard final != url.lastPathComponent else { return nil }
        let dst = dir.appendingPathComponent(final)
        guard rename(url.path, dst.path) == 0 else { return nil }
        return dst
    }
    // File creation date (nil if the filesystem has none).
    static func creationDate(_ u: URL) -> Date? {
        var u = u; u.removeAllCachedResourceValues()     // a URL kept around (the open note's) must not answer from a stale cache
        return (try? u.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }
    // Created date: the filename's day when present (app-made notes), else the file's creation date (imports),
    // else the modification date.
    static func createdDate(_ u: URL, calendar: Calendar = .current) -> Date {
        filenameDate(u.lastPathComponent, calendar: calendar) ?? creationDate(u) ?? modDate(u)
    }
    // List order: newest created day first; within a day the higher note number first (it was made later), then
    // the later creation time, then name.
    static func sortedForList(_ items: [(url: URL, created: Date)], calendar: Calendar = .current) -> [(url: URL, created: Date)] {
        items.sorted { a, b in
            let da = calendar.startOfDay(for: a.created), db = calendar.startOfDay(for: b.created)
            if da != db { return da > db }
            let na = number(in: a.url.lastPathComponent) ?? -1, nb = number(in: b.url.lastPathComponent) ?? -1
            if na != nb { return na > nb }
            if a.created != b.created { return a.created > b.created }
            return a.url.lastPathComponent < b.url.lastPathComponent
        }
    }
    // Write to a temporary file in the same folder, then rename it over the note. The rename gives the file a
    // new creation date, so the old one is copied onto the temp file first: edits never change it.
    static func writeAtomically(_ text: String, to url: URL) -> Bool {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).saving-\(UUID().uuidString)")
        do {
            let created = creationDate(url)
            try Data(text.utf8).write(to: tmp, options: [.withoutOverwriting])
            if let h = try? FileHandle(forWritingTo: tmp) { try? h.synchronize(); try? h.close() }     // on disk before it replaces the note
            if let created = created { try? FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: tmp.path) }
            if rename(tmp.path, url.path) != 0 { throw CocoaError(.fileWriteUnknown) }
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
    }
    static func mostRecent(_ files: [URL]) -> URL? {
        files.max { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return da < db
        }
    }
}

// F1 save timing. The clock is an input (seconds), so tests drive it.
// Save 1 s after the last change; while changes keep coming, at least every 5 s.
struct SaveScheduler {
    static let quiet: Double = 1, maxWait: Double = 5
    private(set) var firstChange: Double?          // first unsaved change
    private(set) var lastChange: Double?
    var pending: Bool { lastChange != nil }
    mutating func changed(at t: Double) { if firstChange == nil { firstChange = t }; lastChange = t }
    // When the next save is due (nil = nothing to save).
    var dueAt: Double? {
        guard let f = firstChange, let l = lastChange else { return nil }
        return min(l + Self.quiet, f + Self.maxWait)
    }
    func isDue(at t: Double) -> Bool { dueAt.map { t >= $0 - 1e-9 } ?? false }
    mutating func saved() { firstChange = nil; lastChange = nil }
}
// The built-in tutorial note (FloatNote's own marker format).
enum TutorialNote {
    static let text = #"""
# <u>Welcome to FloatNote</u>

FloatNote is a note that floats above your other apps. It saves your text automatically.
This note is your tutorial. Change it and try things. Press ⌘N for a clean note.
Keys with fn: if fn types a letter on your keyboard, use the key in brackets.

==Don't miss Paragraph mode== (fn P): FloatNote's signature feature. It turns a long paragraph into one sentence per line, so you can fix it fast. See ==Paragraph mode== under Tools.
The three highlights, marked with a colored band below: ==Paragraph mode==, ==Copy out== and ==Move the box==.

===


# <u>Writing</u>

## Styles
Select a word, then press a key:
1. ⌘B **bold**
2. ⌘I *italic*
3. ⌘U <u>underline</u>
4. fn X (⇧⌘X) ~~strikethrough~~
5. fn L (⇧⌘H) ==highlight==
6. fn U (⇧⌘A) ALL CAPS
Press the same key again to remove the style.
⌘+ and ⌘− make the text larger or smaller.
Try it: select this word, banana, and press fn L.


## Give it shape
Start a line with:
1. # and a space: a title
2. ## and a space: a subtitle
3. 1. and a space: a numbered list
4. - and a space: a bullet list
In a list, Return adds the next item. Return on an empty item stops the list.
Double-click a list item to strike it through; triple-click (or ⌘+click) it to highlight it. Do it again to undo.
A line with only --- draws a line. A line with only === draws a double line.
On a title, ⌥⌘T adds a line above and below it. The title then has its own area.
Try it: click at the end of this line. Press Return, then type ## and a space and a word.


---


# <u>The box</u>

## Hide and show
Tap Right Option (the Option key on the right). The box fades, and clicks go through it. Tap it again and the box comes back.
Esc also fades the box, and takes you back to your last app.
⌘W sends the box to the Dock. Tap Right Option or click it in the Dock to bring it back.
Try it: tap Right Option two times.


## ==Move the box==
Tap Right Command (the Command key on the right) for window mode. A pink border shows that it is on. You cannot type in window mode.
1. ← → ↑ ↓: move the box
2. w and s: shorter and taller
3. a and d: narrower and wider
4. , and . (or < and >): more or less see-through
5. Hold ⇧ for larger steps
Press Esc or tap Right Command again to stop.
The background lets your screen show through. The text stays solid. You can also set this in ⌘, Settings > Opacity.
Try it: tap Right Command. Press → three times and s two times. Then press Esc.
Why it matters: put the box exactly where you need it, next to what you read or write, and see through it.
Try it, step by step:
1. Tap Right Command. A pink border and -- WINDOW -- show window mode is on.
2. Press ← four times: the box moves left. Hold ⇧ and press ↓: it moves 4 times as far.
3. Press s two times: taller. Press d two times: wider. w and a make it shorter and narrower again.
4. Press , three times: the background gets more see-through. Press . three times: more solid again. Each press is 10%.
5. Press Esc (or tap Right Command). Window mode is off and you can type again. The new place and size are kept for next time.


## Fullscreen
fn F shows this note on the full screen, as one column of text in its own Space.
1. Esc or fn F: back to the box
2. Right Option: go to your last app, and back again
3. ⌘, Settings: column width and line spacing
Move the mouse to the top edge to see the date, time, word count and battery, very faintly.
Try it: press fn F, type a line, then press Esc.


---


# <u>Your notes</u>

1. ⌘N: a new note
2. ⌘O: all your notes, newest first. ↑ ↓ and Return open a note; or click a row (double-click opens). ← or → renames the file (blank = back to the default name).
3. In that list, ⌘⌫ moves a note to the macOS Trash (FloatNote asks first). ⌥⌘⌫ does it at once.
4. Drag a .txt or .md file onto the box. FloatNote copies it into a new note.
Your notes are .txt files in Documents/FloatNote.
Try it: press ⌘O, then Esc.


---


# <u>In and out</u>

## Copy in from any app
Select text in Safari or any other app and press ⌃⌥S. The text is added to the end of the note you have open, one blank line between paragraphs. With no note open, it becomes a new note in fullscreen.
Try it: select a sentence in your browser and press ⌃⌥S.


## ==Copy out== and send text out
1. fn J (⌃⌘G): copy for Google Docs. Paste it there and the styles stay.
2. fn G (⌃⌘L): ask Grok about the note
3. fn K (⌃⌘K): ask Claude about the note
4. fn M (⌃⌘X): post the selected text on X
For Grok and Claude, type a question and press Return. Your browser opens with the question and the note, or only the selected text. You press send. Esc cancels.
For X, select text first. X opens in your browser with the text ready (style marks removed) and you press Post yourself. FloatNote never posts for you.
Try it: press fn K, type "Summarize", then press Esc.
Why it matters: write here, then paste anywhere, with nothing to clean up.
What Copy out (fn J) puts on the clipboard:
1. For Google Docs and other rich editors: titles, bold, italic, underline, strikethrough, highlight and lists, with their colors.
2. For plain-text apps: clean text. The style marks are removed, and list numbers stay as you see them.
3. No selection: the whole note. A selection: every line it touches, whole.
4. In Paragraph mode: the paragraph, joined back into one.
Practise on these lines:
**Plan** for Friday: ==send the slides== and ~~call Sam~~.
Try it, step by step:
1. Click in the Plan line and select a word or two of it.
2. Press fn J (or ⌃⌘G). The whole line is copied.
3. Paste it into a Google Doc: bold, highlight and strikethrough are kept.
4. Paste it into a plain-text app, like Notes in plain text or a chat: you get the words without the marks.
5. Press fn G (Grok) or fn K (Claude), type a question and press Return. Your browser opens with your question and the text. You press send.
Set up (optional): Ask Grok and Ask Claude open grok.com and claude.ai in your default browser. Sign in there once, and fn G / fn K land ready to send. ⌘, Settings has Open grok.com and Open claude.ai buttons for this. One, both or neither is fine: FloatNote works without them.


---


# <u>Tools</u>

## Find your way
1. fn O (⌥⌘V): the navigator. It shows all titles. ↑ ↓ and Return go to a title.
2. ⌘F: find. fn R (⌥⌘F): find and replace.
Try it: press fn O, then ↓ and Return.


## ==Paragraph mode==
Long paragraphs are hard to edit. fn P (⌥⌘P) shows the paragraph at your cursor with one sentence on each line.
1. Edit each sentence on its own line.
2. To move a sentence, cut its line (⌘X) and paste it (⌘V) on a different line.
3. Esc or fn P: the lines join into one paragraph again.
4. After that, one ⌘Z undoes all of the edit.
Practise on this paragraph:
The fox ran fast. It was late for dinner. Its friends were already at the table. Nobody saved it any soup.
Try it: click in the paragraph and press fn P. Move the last sentence to the top. Then press Esc.

Now a real one. This email paragraph is a mess:
Thanks for the meeting today, it was really useful. Also the budget is due Friday. We should probably maybe talk about the launch date again because I think it is too early. I will send the slides tonight. Let me know what you think about all of this.
Try it, step by step:
1. Click anywhere in the email paragraph above.
2. Press fn P (or ⌥⌘P). A colored border and -- PARAGRAPH -- show it is on. Each sentence now has its own line.
3. Use ↑ and ↓ to move from sentence to sentence.
4. Edit: change "We should probably maybe talk" to "Let's talk".
5. Reorder: put the cursor on the budget line, select the line, press ⌘X, then paste it with ⌘V at the start of the last line.
6. Add: at the end of the first line press Return and type a new sentence, like "Here is a quick update."
7. Press fn J (⌃⌘G) while you are still in Paragraph mode: Copy out gives you the whole paragraph, joined back up.
8. Press Esc. The lines join into one paragraph again, one space between sentences, and the note is saved.
9. Changed your mind? Press ⌘Z once: the whole edit is undone in one step.


---


# <u>Settings and shortcuts</u>

⌘, opens Settings: font, text size, theme, opacity and fullscreen. The Tutorial button there gives you a fresh copy of this note.
⌘/ shows all shortcuts on one sheet.
The sheet has two pages: page 1 has the essentials. Press → for page 2 with every shortcut, and ← to go back.


---


# <u>Trash</u>

Empty notes clean themselves up. When you leave a note with no text, FloatNote moves it to the macOS Trash.
When you leave a tutorial note, FloatNote asks first: Return moves it to the Trash, Esc keeps it as a normal note.
To get a note back, open the Trash in Finder, select the file and choose Put Back.
⌘⌫ in the notes list (⌘O) also moves the note to the Trash, after you confirm.
⌥⌘⌫ in the notes list moves a note to the Trash at once, without asking. FloatNote has no permanent delete.
To remove notes from the Trash for good, use Empty Trash in Finder, or select a file in the Trash and choose Delete Immediately.


===

Have fun.
"""#
    // First launch ever: no tutorial shown yet and no notes in the library.
    static func shouldCreateAtLaunch(shown: Bool, noteCount: Int) -> Bool { !shown && noteCount == 0 }
}
// Cheat sheet page 2 (→ from page 1): every ShortcutList entry, in sections (group + where it works),
// fn and ⌘ keys together, sections split into balanced columns (whole sections, list order).
enum ShortcutPages {
    struct Section: Equatable { let title: String; let rows: [Row] }
    struct Row: Equatable { let id: String; let keys: String; let name: String }
    static let pageCount = 2
    // ← / → on the sheet: the new page (stays within 0..<pageCount).
    static func turn(_ page: Int, right: Bool) -> Int { min(max(page + (right ? 1 : -1), 0), pageCount - 1) }
    static func hint(_ page: Int) -> String { page == 0 ? "more shortcuts →" : "← 2/2" }
    // Page 1's prompt pulses until page 2 has been opened once (saved as "cheatPage2Seen"), then stays steady.
    static func pulses(page: Int, page2Seen: Bool) -> Bool { page == 0 && !page2Seen }
    static func title(group: String, scope: String) -> String {
        switch scope {
        case "fullscreen": return "In fullscreen"
        case "navigator": return "In the navigator"
        case "notesList": return "In the notes list (⌘O)"
        case "settings": return "In Settings and this sheet"
        default: return group
        }
    }
    static func keys(_ e: Shortcut) -> String {
        let k = ShortcutList.normalizeKeys(e.keys)
        if let l = ShortcutList.fnLetters[e.id] { return "fn \(l) / " + k }
        return k
    }
    static func sections() -> [Section] {
        var out: [(key: String, title: String, rows: [Row])] = []
        for e in ShortcutList.all {
            let key = e.group + "|" + e.scope
            let row = Row(id: e.id, keys: keys(e), name: e.name)
            if let last = out.last, last.key == key {
                out[out.count - 1].rows.append(row)
            } else {
                out.append((key, title(group: e.group, scope: e.scope), [row]))
            }
        }
        return out.map { Section(title: $0.title, rows: $0.rows) }
    }
    static func lines(_ s: Section) -> Int { s.rows.count + 1 }   // header + rows
    // Contiguous split of the sections into `cols` columns with the smallest tallest column.
    static func columns(_ secs: [Section], cols: Int = 3) -> [[Section]] {
        let n = secs.count
        guard cols > 1, n > cols else { return secs.map { [$0] } }
        var best: [Int] = [], bestMax = Int.max
        func h(_ a: Int, _ b: Int) -> Int { secs[a..<b].reduce(0) { $0 + lines($1) } }
        func go(_ start: Int, _ left: Int, _ cuts: [Int]) {
            if left == 1 {
                let all = cuts + [n]
                var prev = 0, mx = 0
                for c in all { mx = max(mx, h(prev, c)); prev = c }
                if mx < bestMax { bestMax = mx; best = all }
                return
            }
            if start >= n { return }
            for c in (start + 1)..<n { go(c, left - 1, cuts + [c]) }
        }
        go(0, cols, [])
        var out: [[Section]] = []
        var prev = 0
        for c in best { out.append(Array(secs[prev..<c])); prev = c }
        return out
    }
}

// At-rest (faded, click-through) opacity: light themes 2.5% (a light box shows more), dark themes 5%.
enum RestAlphaLogic {
    static func rest(dark: Bool) -> CGFloat { dark ? 0.05 : 0.025 }
}
// New notes start on a title line: the first typed text in an empty new note goes in as "# " + text.
// Return on the still-empty first line drops the title (plain body text, nothing inserted).
enum NewNoteTitleLogic {
    enum Action: Equatable { case normal, swallow, insert(String, caret: Int) }
    static func edit(pending: Bool, docEmpty: Bool, range: NSRange, rep: String) -> Action {
        guard pending, docEmpty, range.location == 0, range.length == 0, !rep.isEmpty else { return .normal }
        if rep == "\n" || rep == "\r" { return .swallow }
        if rep.contains("\n") { return .normal }                       // a multi-line paste goes in as is
        let t = "# " + rep
        return .insert(t, caret: (t as NSString).length)
    }
}
// Library cleanup. Empty notes (only whitespace, or only "#" / "##") are moved to the Trash silently when
// you leave them, on quit and on launch. Tutorial notes are tracked by file name (UserDefaults
// "tutorialFiles") and are only removed after the user confirms. Never anything else.
enum NoteCleanup {
    static let hintLimit = 20
    static func isEmpty(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "#" || t == "##"
    }
    static func isEmptyFile(_ url: URL) -> Bool {
        guard let t = NoteLibrary.readText(url) else { return false }   // unreadable: keep
        return isEmpty(t)
    }
    // Launch: the empty note files in the folder (except `keep`).
    static func emptyFiles(_ files: [URL], keep: URL? = nil) -> [URL] {
        files.filter { $0.standardizedFileURL != keep?.standardizedFileURL && isEmptyFile($0) }
    }
    // Tracked tutorial files that still exist (except `keep`), in tracking order.
    static func tutorialLeftovers(tracked: [String], files: [URL], keep: URL? = nil) -> [URL] {
        let byName = Dictionary(files.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { a, _ in a })
        return tracked.compactMap { byName[$0] }.filter { $0.standardizedFileURL != keep?.standardizedFileURL }
    }
    static func showTutorialHint(noteCount: Int) -> Bool { noteCount < hintLimit }
    // While a tutorial note is open the background is at least 90% (legible); not saved.
    static func tutorialOpacity(saved: CGFloat) -> CGFloat { max(saved, 0.9) }
    static func trash(_ url: URL) -> Bool { (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil }
}
// Window mode opacity keys: , and . by key position (layout-safe), or < and > (the same keys with Shift).
// Same 10% step either way. Returns -1 / +1 for a key that changes opacity, else nil.
enum OpacityKeyLogic {
    static func direction(keyCode: UInt16, characters: String?) -> Int? {
        if keyCode == 43 || characters == "<" || characters == "," { return -1 }   // kVK_ANSI_Comma
        if keyCode == 47 || characters == ">" || characters == "." { return 1 }    // kVK_ANSI_Period
        return nil
    }
}
// ⌘O notes list: text 1.3x the note's size (rounded), with row spacing and padding scaled to match.
enum NotesListSize {
    static let scale: CGFloat = 1.3
    static func font(_ base: CGFloat) -> CGFloat { (base * scale).rounded() }
    static func rowSpacing(_ base: CGFloat) -> CGFloat { (base * 0.35).rounded() }      // extra space between rows
    static func topInset(fullscreen: Bool) -> CGFloat { fullscreen ? 80 : (4 * scale).rounded() }
}
// ⌘O notes list day groups: a hairline (theme text at 18%) with a little space around it goes between rows
// whose created dates (what the list sorts by and the date column shows) fall on different local days.
// Separators are display only: the cursor moves over rows, so ↑↓, filter and delete never land on one.
enum NotesListDays {
    enum Line: Equatable { case row(Int), separator }
    static let separatorAlpha: CGFloat = 0.18
    static func lines(_ dates: [Date], calendar: Calendar = .current) -> [Line] {
        var out: [Line] = []
        for (i, d) in dates.enumerated() {
            if i > 0, !calendar.isDate(d, inSameDayAs: dates[i - 1]) { out.append(.separator) }
            out.append(.row(i))
        }
        return out
    }
    // ↑↓: next row index (separators are not rows, so they are skipped); stays inside 0..<count.
    static func move(_ cursor: Int, by delta: Int, count: Int) -> Int { count == 0 ? 0 : min(max(cursor + delta, 0), count - 1) }
}
// ⌘O notes list, mouse: which row a point is on, and what a click does. Rows are the note lines only: header lines,
// day separators and the empty space around them are not rows. A point counts for a row up to `pad` above/below
// its line (half the row spacing), so there is no dead strip between neighbouring rows.
enum NotesListMouse {
    enum Action: Equatable { case none, select(Int), open(Int) }
    static func row(atY y: CGFloat, rects: [CGRect], pad: CGFloat) -> Int? {
        rects.firstIndex { y >= $0.minY - pad && y < $0.maxY + pad }
    }
    // One click selects the row (as ↑↓ do), a double click opens it (as Return does). Nothing under the pointer: nothing.
    static func action(hit: Int?, clickCount: Int, rowCount: Int) -> Action {
        guard let h = hit, h >= 0, h < rowCount else { return .none }
        return clickCount >= 2 ? .open(h) : .select(h)
    }
}
// Tutorial highlights: while a tracked tutorial note is open, these section titles get a violet band
// (outside every theme, readable on light and dark). Display only: no marker, nothing in the file or Copy out.
enum TutorialHighlight {
    static let titles = ["Paragraph mode", "Copy out", "Move the box"]
    static let color: UInt32 = 0x8B5CF6
    static func isHighlight(titleLine: String) -> Bool { titles.contains { titleLine.contains($0) } }
}
// Settings > Help: the sites Ask Grok / Ask Claude open, for signing in (optional).
enum AskSites {
    static let grok = URL(string: "https://grok.com/")
    static let claude = URL(string: "https://claude.ai/")
}
// When FloatNote hides, these extra windows/fields close too (Settings saves as it changes).
enum HideCloseLogic {
    static func toClose(settingsOpen: Bool, cheatOpen: Bool, askOpen: Bool) -> [String] {
        (settingsOpen ? ["settings"] : []) + (cheatOpen ? ["cheatSheet"] : []) + (askOpen ? ["askField"] : [])
    }
}
// END MarkerLogic

// The Ask Grok field's keys: Return sends, Esc closes (only the field), ↑ recalls the last prompt.
final class GrokFieldHandler: NSObject, NSTextFieldDelegate {
    weak var owner: AppDelegate?
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)): owner?.submitGrokPrompt(); return true
        case #selector(NSResponder.cancelOperation(_:)): owner?.closeGrokPrompt(); return true
        case #selector(NSResponder.moveUp(_:)):
            if let last = appDefaults.string(forKey: "lastGrokPrompt") {
                textView.string = last; textView.setSelectedRange(NSRange(location: (last as NSString).length, length: 0))
            }
            return true
        default: return false
        }
    }
}

// The inline rename field in the ⌘O list: Return renames, Esc cancels, leaving the field (a click elsewhere) renames.
final class ListRenameHandler: NSObject, NSTextFieldDelegate {
    weak var owner: AppDelegate?
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)): owner?.finishListRename(commit: true); return true
        case #selector(NSResponder.cancelOperation(_:)): owner?.finishListRename(commit: false); return true
        default: return false
        }
    }
    func controlTextDidEndEditing(_ obj: Notification) { owner?.finishListRename(commit: true) }
}

// The ⌘O list's text view: a faint hover band under the pointer (drawn, not part of the text, so it follows
// scrolling and never moves the list), and clicks on rows. Keys still go through AppDelegate.notesListKey.
final class NotesListTextView: NSTextView {
    var rowRanges: [NSRange] = []             // character range of each note row (without its line break)
    var rowPad: CGFloat = 4
    var mouseEnabled = true                   // off while the delete confirmation is up
    var selectedRow: Int?                     // the keyboard selection: has its own highlight, no hover band
    var onClick: ((Int, Int) -> Void)?        // (row, clickCount)
    var renaming = false                      // the inline rename field is up: a click elsewhere in the list ends it (renames)
    var onClickAway: (() -> Void)?
    var onRename: ((Int) -> Void)?            // ⌘+click, press and hold (~0.5 s, no drag), or a hard press on a row
    private var pressTimer: Timer?
    private var pressStart = NSPoint.zero
    func cancelPress() { pressTimer?.invalidate(); pressTimer = nil }
    var hoverRow: Int? { didSet { if hoverRow != oldValue { needsDisplay = true } } }

    override var mouseDownCanMoveWindow: Bool {   // over a row a click is a click; elsewhere the list drags the window as before
        guard let e = NSApp.currentEvent, e.type == .leftMouseDown else { return super.mouseDownCanMoveWindow }
        return hitRow(at: convert(e.locationInWindow, from: nil)) == nil
    }
    func rowRects() -> [CGRect] {
        guard let lm = layoutManager, let tc = textContainer else { return [] }
        let o = textContainerOrigin
        return rowRanges.map { r in
            let g = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            let b = lm.boundingRect(forGlyphRange: g, in: tc)
            return CGRect(x: o.x - 4, y: b.minY + o.y, width: max(bounds.width - 2 * o.x + 8, 0), height: b.height)
        }
    }
    func hitRow(at p: NSPoint) -> Int? {
        guard mouseEnabled else { return nil }
        return NotesListMouse.row(atY: p.y, rects: rowRects(), pad: rowPad)
    }
    func refreshHover() {
        guard let w = window else { hoverRow = nil; return }
        let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        hoverRow = visibleRect.contains(p) ? hitRow(at: p) : nil
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas where a.owner === self { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseMoved(with event: NSEvent) { hoverRow = hitRow(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { hoverRow = nil }
    override func mouseDown(with event: NSEvent) {
        if renaming { onClickAway?(); return }
        guard let i = hitRow(at: convert(event.locationInWindow, from: nil)) else { super.mouseDown(with: event); return }
        cancelPress()
        if event.modifierFlags.contains(.command) { onRename?(i); return }          // ⌘+click: rename this row
        onClick?(i, event.clickCount)
        pressStart = event.locationInWindow
        pressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in   // held: rename
            self?.pressTimer = nil
            self?.onRename?(i)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        if pressTimer != nil, hypot(event.locationInWindow.x - pressStart.x, event.locationInWindow.y - pressStart.y) > 4 { cancelPress() }
    }
    override func mouseUp(with event: NSEvent) { cancelPress() }
    override func pressureChange(with event: NSEvent) {        // trackpad hard press (force click) on a row
        guard event.stage == 2, pressTimer != nil, let i = hitRow(at: convert(event.locationInWindow, from: nil)) else { return }
        cancelPress(); onRename?(i)
    }
    override func draw(_ dirtyRect: NSRect) {
        if let h = hoverRow, h != selectedRow, mouseEnabled {
            let rects = rowRects()
            if rects.indices.contains(h) {
                Theme.text.withAlphaComponent(currentTheme.dark ? 0.08 : 0.07).setFill()
                NSBezierPath(roundedRect: rects[h], xRadius: 3, yRadius: 3).fill()
            }
        }
        super.draw(dirtyRect)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    var panel: NotePanel!
    var textView: NSTextView!
    var status: NSTextField!
    var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App hidden or another app taken over: Settings and the cheat sheet close (the box's Ask field stays).
        for n in [NSApplication.didHideNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                self?.closeOnHide(includeAsk: false)
            }
        }
        // Only ever run one copy.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        buildWindow()
        registerHotKey()
        // First launch without Accessibility: the Right Option tap can't work. Say so (the system dialog comes once).
        if !AXIsProcessTrusted() {
            askAccessibilityOnce()
            flashStatus(AccessLogic.launchHint, 10)
        } else if !selectionHotKeyOK {
            flashStatus("⌃⌥S is used by another app", 8)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveNow(wait: true)                              // on the main thread; waits until written
        if let u = noteFileURL, NoteCleanup.isEmptyFile(u), NoteCleanup.trash(u) { untrackTutorial(u) }   // tutorials: asked next launch
    }

    // MARK: window

    func buildWindow() {
        panel = NotePanel(contentRect: NSRect(origin: .zero, size: boxSize),
                          styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.appearance = Theme.appearance
        panel.isOpaque = false
        panel.backgroundColor = Theme.bg.withAlphaComponent(boxOpacity)
        panel.minSize = NSSize(width: 180, height: 90)

        let font = noteFont(fontSize)

        let content = panel.contentView!
        let textArea = panel.contentLayoutRect          // everything below the (invisible) title bar
        let stripHeight = content.bounds.height - textArea.maxY

        // Tiny status line in the strip at the top (only used for warnings).
        status = NSTextField(labelWithString: "")
        status.font = NSFont(descriptor: font.fontDescriptor, size: 9) ?? .systemFont(ofSize: 9)
        status.textColor = Theme.hint
        status.alignment = .right
        status.frame = NSRect(x: 12, y: textArea.maxY + (stripHeight - 13) / 2,
                              width: content.bounds.width - 24, height: 13)
        status.autoresizingMask = [.width, .minYMargin]
        content.addSubview(status)


        let scroll = NSTextView.scrollableTextView()
        scroll.frame = textArea
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.scrollerStyle = .overlay
        scroll.scrollerKnobStyle = .light
        content.addSubview(scroll)


        textView = (scroll.documentView as! NSTextView)
        object_setClass(textView, DropTextView.self)      // F5: same text view, plus file drops (adds no stored properties)
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = true                       // find & replace (Task 7)
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 8, height: 2)
        textView.textContainer?.replaceLayoutManager(RuleLayoutManager())
        let loaded = loadNotes(font)
        let cleaned = PendingStyleLogic.stripEmptyPairs(loaded.string)
        textView.textStorage?.setAttributedString(cleaned == loaded.string ? loaded : NSAttributedString(string: cleaned, attributes: loaded.attributes(at: 0, effectiveRange: nil)))
        lastSavedText = textView.textStorage?.string
        if let ts = textView.textStorage {   // white text; neon stays; old background highlights become neon text
            let all = NSRange(location: 0, length: ts.length)
            ts.enumerateAttributes(in: all) { a, r, _ in
                if a[.backgroundColor] != nil || isNeon(a[.foregroundColor]) {
                    ts.removeAttribute(.backgroundColor, range: r)
                    ts.addAttribute(.foregroundColor, value: highlightOrange, range: r)
                } else {
                    ts.addAttribute(.foregroundColor, value: bodyColor, range: r)
                }
            }
        }
        textView.insertionPointColor = Theme.text
        textView.typingAttributes = [.font: font, .foregroundColor: bodyColor]
        textView.selectedTextAttributes = [.backgroundColor: Theme.selection, .foregroundColor: Theme.bold]
        textView.delegate = self
        refreshRules()
        onFontSize = { [weak self] step in self?.changeFontSize(step) }
        onStyle = { [weak self] key in self?.toggleStyle(key) }
        // ⌥⌘T: add/remove the --- lines around the title the caret is on.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.panel,
                  event.keyCode == UInt16(kVK_ANSI_T),
                  event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.command, .option],
                  self.panel.firstResponder === self.textView, self.textView.isEditable else { return event }
            self.toggleTitleRulesHere()
            return nil
        }
        // Find and replace: ⌘F ⌥⌘F ⌘G ⇧⌘G ⌘E go to the note's built-in find bar.
        onFind = { [weak self] action in self?.findAction(action) }
        onExport = { [weak self] in self?.copyOut() }
        onSettings = { [weak self] in          // ⌘, toggles Settings
            if let w = self?.settingsWindow, w.isVisible { w.performClose(nil) } else { self?.showSettings() }
        }
        // Esc while the find bar is open closes only the find bar (also when typing in its fields).
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.panel, !self.navOpen, !self.windowMode,
                  event.keyCode == 53, self.findBarOpen else { return event }
            self.findAction(.hideFindInterface)
            return nil
        }
        // ⌘O: notes list (F3). While it's open it gets every key.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.panel else { return event }
            if self.listOpen { if self.listRenaming { return event }; self.notesListKey(event); return nil }   // renaming: the field gets the keys
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard event.keyCode == UInt16(kVK_ANSI_O), mods == [.command], !self.navOpen, self.grokField == nil else { return event }
            self.openNotesList()
            return nil
        }
        // ⌥⌘V: navigator (⌘V alone still pastes).
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.panel, !self.listOpen else { return event }
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if self.navOpen, self.fnLetterRun(event) == nil {
                // Find shortcuts close the navigator (no jump), then run.
                let find: NSTextFinder.Action?
                if Int(event.keyCode) == kVK_ANSI_F && mods == [.command] { self.startNavFilter(); return nil }   // ⌘F: filter the tree
                switch (Int(event.keyCode), mods) {
                case (kVK_ANSI_F, [.command, .option]): find = .showReplaceInterface
                case (kVK_ANSI_G, [.command]): find = .nextMatch
                case (kVK_ANSI_G, [.command, .shift]): find = .previousMatch
                case (kVK_ANSI_E, [.command]): find = .setSearchString
                default: find = nil
                }
                if let a = find { self.closeNavigator(jump: false); self.findAction(a); return nil }
                if event.keyCode == UInt16(kVK_ANSI_V) && mods == [.command, .option] { self.closeNavigator(jump: false); return nil }
                self.navigatorKey(event)
                return nil
            }
            guard event.keyCode == UInt16(kVK_ANSI_V), mods == [.command, .option],
                  self.panel.firstResponder === self.textView else { return event }
            self.openNavigator()
            return nil
        }
        // fn+F (Globe+F): fullscreen writing mode. macOS may send it as toggleFullScreen: instead (see NotePanel).
        onFullscreen = { [weak self] in
            guard let self = self,
                  FullscreenLogic.canToggle(listOpen: self.listOpen, renaming: self.listRenaming, askDelete: self.listAskDelete,
                                            navOpen: self.navOpen,
                                            textFocused: self.panel.firstResponder === self.textView && self.textView.isEditable) else { return }
            if self.fullOn { self.exitFullscreen() } else { self.enterFullscreen() }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.panel,
                  event.keyCode == UInt16(kVK_ANSI_F) else { return event }
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard event.modifierFlags.contains(.function) && mods.isEmpty else { return event }
            onFullscreen?()
            return nil
        }
        // ⌥⌘P: paragraph edit mode (one sentence per line).
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.panel,
                  event.keyCode == UInt16(kVK_ANSI_P),
                  event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.command, .option],
                  self.panel.firstResponder === self.textView, self.textView.isEditable else { return event }
            if self.paraMode { self.exitParagraphMode() } else { self.enterParagraphMode() }
            return nil
        }
        onCheatSheet = { [weak self] in self?.toggleCheatSheet() }
        // fn + letter shortcuts (ShortcutList.fnLetters). Letters only, so arrows/Home/End (which also
        // carry .function) and fn F pass through; the letter is never typed.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window === self.panel, self.grokField == nil,
                  let run = self.fnLetterRun(event) else { return event }
            if self.windowMode { self.setWindowMode(false) }
            if self.navOpen && run != "navigator" { self.closeNavigator(jump: false) }
            self.runShortcut(run)
            return nil
        }
        onAskGrok = { [weak self] in self?.showGrokPrompt() }
        onAskClaude = { [weak self] in self?.showGrokPrompt(claude: true) }
        onPostToX = { [weak self] in self?.postSelectionToX() }
        onNewNote = { [weak self] in self?.newNote() }
        // ⌘W (box focused): minimize to the Dock with the genie animation. Fullscreen: leave it first (as Esc
        // does); once macOS has left the Space (didExitFullScreen → finishExitFullscreen → afterFSExit) and the
        // box is back at its frame, minimize the same way.
        onMinimize = { [weak self] in
            guard let self = self else { return }
            if self.fsTransition { return }
            if self.fullOn {
                self.afterFSExit = { [weak self] in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.minimizeToDock() }   // after the frame animation
                }
                self.exitFullscreen()
            } else { self.minimizeToDock() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: panel, queue: .main) { [weak self] _ in
            self?.finishRestoreFromDock()
        }
        onDropFiles = { [weak self] urls in self?.importFiles(urls) }
        onNoteClick = { [weak self] event in self?.noteClick(event) ?? false }

        // Remember position/size between launches; first launch goes top-right.
        if let saved = appDefaults.string(forKey: "frame") {
            panel.setFrame(clampOnScreen(NSRectFromString(saved)), display: false)
        } else if panel.setFrameUsingName("FloatNote") {
            panel.setFrame(clampOnScreen(panel.frame), display: false)
        } else if let screen = NSScreen.main?.visibleFrame {
            panel.setFrame(DefaultFrameLogic.frame(visible: screen), display: false)   // ~60% of the screen, centered
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                if self.fsTransition { return }                                // mid enter/exit animation
                if self.fullOn { self.layoutFullscreenColumn(); return }   // don't remember the fullscreen frame
                appDefaults.set(NSStringFromRect(self.panel.frame), forKey: "frame")
            }
        }
        // Launch passively: the app you're in keeps focus and the cursor. Right Option brings the box in.
        panel.alphaValue = launchAlpha
        panel.ignoresMouseEvents = true                  // same as the faded state
        panel.orderFrontRegardless()
        refreshRules()
        textView.scrollToEndOfDocument(nil)
        titlePending = noteFileURL == nil && textView.string.isEmpty   // the launch's new note starts on a title line
        refreshTutorialHint()
        applyTutorialOpacity()                           // first-launch tutorial: 90% background
        if !askQueue.isEmpty { DispatchQueue.main.async { [weak self] in self?.showNextAsk() } }
        if launchedTutorial {                            // first launch ever: the tutorial comes forward, from the top
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            DispatchQueue.main.async { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.focusBox()
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            self?.fnHeld = false
            self?.saveNow()                              // the box goes into the background
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.saveNow(wait: true)                    // the Mac goes to sleep
        }
        launching = true
        if NSApp.isActive { NSApp.deactivate() }         // `open` may activate us; give focus back
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.launching = false }
    }

    var launching = false
    var fnHeld = false                                   // fn / Globe is down (from flagsChanged)
    // An fn + letter press: fn held (tracked) or the event's own .function flag.
    func fnLetterRun(_ event: NSEvent) -> String? {
        guard fnHeld || event.modifierFlags.contains(.function),
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              !listOpen,
              let ch = event.charactersIgnoringModifiers?.uppercased().first, ch.isLetter, ch.isASCII else { return nil }
        return ShortcutList.fnRun(ch)
    }
    func applicationDidResignActive(_ notification: Notification) { fnHeld = false; saveNow() }   // app to background
    func applicationDidBecomeActive(_ notification: Notification) {
        guard launching else { return }                  // only the activation from being launched
        NSApp.deactivate()
        panel.orderFrontRegardless()
    }

    // MARK: shortcut + focus

    // Right Option tapped alone: show the box / hide it (no app switch; fullscreen: see toggleFocus).
    var rightOptTap = RightOptionTap()
    var rightCmdTap = RightOptionTap(key: 54)
    func installRightOptionTap() {
        let handleFlags: (NSEvent) -> Void = { [weak self] e in
            guard let self = self else { return }
            let raw = e.modifierFlags.rawValue
            let rightDown = raw & 0x40 != 0                     // NX_DEVICERALTKEYMASK
            let others = e.modifierFlags.intersection([.command, .control, .shift, .capsLock, .function]).isEmpty == false
                || raw & 0x20 != 0                               // left Option (NX_DEVICELALTKEYMASK)
            if self.rightOptTap.flags(keyCode: e.keyCode, rightOptionDown: rightDown, otherModifiers: others,
                                      time: e.timestamp) {
                self.toggleFocus()
            }
            // Right Command tapped alone: window mode on/off.
            let rCmd = raw & 0x10 != 0                          // NX_DEVICERCMDKEYMASK
            let cmdOthers = e.modifierFlags.intersection([.option, .control, .shift, .capsLock, .function]).isEmpty == false
                || raw & 0x08 != 0                               // left Command (NX_DEVICELCMDKEYMASK)
            if self.rightCmdTap.flags(keyCode: e.keyCode, rightOptionDown: rCmd, otherModifiers: cmdOthers,
                                      time: e.timestamp) {
                if !self.fullOn { self.toggleWindowMode() }
                // Fullscreen: window mode for opacity only, fullscreen stays. Dimmed fullscreen ignores it.
                else if !self.panel.ignoresMouseEvents { self.setWindowMode(!self.windowMode) }
            }
        }
        let other: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handleFlags)
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            // fn / Globe held (keyCode 63 = fn, 179 = Globe): letter keyDowns may not carry .function.
            if e.keyCode == 63 || e.keyCode == 179 { self?.fnHeld = e.modifierFlags.contains(.function) }
            else if !e.modifierFlags.contains(.function) { self?.fnHeld = false }
            handleFlags(e); return e
        }
        NSEvent.addGlobalMonitorForEvents(matching: other) { [weak self] _ in self?.rightOptTap.interrupt(); self?.rightCmdTap.interrupt() }
        NSEvent.addLocalMonitorForEvents(matching: other) { [weak self] e in self?.rightOptTap.interrupt(); self?.rightCmdTap.interrupt(); return e }
    }

    // Performs a ShortcutList `run` id the same way its key does now (for the future cheat sheet / palette).
    func runShortcut(_ id: String) {
        let tv = textView!
        switch id {
        case "focusTap": toggleFocus()
        case "windowMode": toggleWindowMode()
        case "sendSelection": sendSelection()
        case "postToX": onPostToX?()
        case "cut": tv.cut(nil)
        case "copy": tv.copy(nil)
        case "paste": tv.pasteAsPlainText(nil)
        case "selectAll": tv.selectAll(nil)
        case "undo": if let u = tv.undoManager, u.canUndo { u.undo() }
        case "redo": if let u = tv.undoManager, u.canRedo { u.redo() }
        case "sizeUp": onFontSize?(1)
        case "sizeDown": onFontSize?(-1)
        case "settings": onSettings?()
        case "cheatSheet": onCheatSheet?()
        case "quit": NSApp.terminate(nil)
        case "bold": onStyle?("b")
        case "italic": onStyle?("i")
        case "underline": onStyle?("u")
        case "highlight": onStyle?("h")
        case "strike": onStyle?("s")
        case "caps": onStyle?("caps")
        case "titleRules": toggleTitleRulesHere()
        case "find": onFind?(.showFindInterface)
        case "replace": onFind?(.showReplaceInterface)
        case "findNext": onFind?(.nextMatch)
        case "findPrev": onFind?(.previousMatch)
        case "useSelection": onFind?(.setSearchString)
        case "navigator": if navOpen { closeNavigator(jump: false) } else { openNavigator() }
        case "paragraph": if paraMode { exitParagraphMode() } else { enterParagraphMode() }
        case "fullscreen": onFullscreen?()
        case "copyOut": onExport?()
        case "askGrok": onAskGrok?()
        case "askClaude": onAskClaude?()
        case "newNote": newNote()
        case "minimize": onMinimize?()
        case "notesList": if listOpen { closeNotesList() } else { openNotesList() }
        default: break
        }
    }

    var selectionHotKeyOK = true
    func registerHotKey() {
        installRightOptionTap()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if hk.id == 12 { onSendSelection?() }
            return OSStatus(noErr)
        }, 1, &spec, nil, nil)

        // ⌃⌥S: send the front app's selected text to the end of the note.
        onSendSelection = { [weak self] in self?.sendSelection() }
        var sRef: EventHotKeyRef?
        let st = RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(controlKey | optionKey),
                                     EventHotKeyID(signature: OSType(0x464E5445), id: 12),
                                     GetApplicationEventTarget(), 0, &sRef)
        selectionHotKeyOK = st == noErr                   // false: another app already owns ⌃⌥S
    }

    // MARK: Cheat sheet (Step 9, ⌘/)
    var cheatPanel: CheatSheetPanel?
    var cheatMonitors: [Any] = []
    var cheatReturnFocus = false

    func toggleCheatSheet() {
        if let c = cheatPanel, c.isVisible { closeCheatSheet(); return }
        cheatReturnFocus = panel.isKeyWindow
        let screen = panel.screen ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Page 1: two columns of whole groups (fits any laptop screen). → page 2.
        cheatPage = 0
        let view = shortcutSheetView()
        addPageHint(view, page: 0)
        let size = view.frame.size
        let c = cheatPanel ?? CheatSheetPanel(contentRect: NSRect(origin: .zero, size: size),
                                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        c.onClose = { [weak self] in self?.closeCheatSheet() }
        c.onTurn = { [weak self] right in self?.turnCheatPage(right) }
        c.isReleasedWhenClosed = false
        c.appearance = Theme.appearance
        c.backgroundColor = Theme.bg
        c.hasShadow = true
        c.level = NSWindow.Level(rawValue: max(panel.level.rawValue, NSWindow.Level.floating.rawValue) + 1)
        c.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]   // shows on the fullscreen Space too
        c.contentView = view
        view.wantsLayer = true; view.layer?.cornerRadius = 10
        c.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2, width: size.width, height: size.height), display: true)
        cheatPanel = c
        c.makeKeyAndOrderFront(nil)
        // A click anywhere outside the sheet closes it.
        cheatMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeCheatSheet() } as Any)
        cheatMonitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            if e.window !== self?.cheatPanel { self?.closeCheatSheet() }; return e } as Any)
    }

    var cheatPage = 0
    var titlePending = false                         // empty new note: first typed text is a title
    var launchedTutorial = false                     // set when the first launch created the tutorial note
    // ← / → on the cheat sheet: page 1 (the sheet) or page 2 (every shortcut). Recentred on the same screen.
    func turnCheatPage(_ right: Bool) {
        guard let c = cheatPanel, c.isVisible else { return }
        let next = ShortcutPages.turn(cheatPage, right: right)
        guard next != cheatPage else { return }
        cheatPage = next
        if next == 1 { appDefaults.set(true, forKey: "cheatPage2Seen") }   // page 1's prompt stops pulsing
        let vf = (c.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let view = next == 0 ? shortcutSheetView() : shortcutPage2View(maxHeight: vf.height - 40)
        addPageHint(view, page: next)
        view.wantsLayer = true; view.layer?.cornerRadius = 10
        let size = view.frame.size
        c.contentView = view
        c.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2, width: size.width, height: size.height), display: true)
    }

    func closeCheatSheet() {
        for m in cheatMonitors { NSEvent.removeMonitor(m) }
        cheatMonitors = []
        guard let c = cheatPanel, c.isVisible else { return }
        c.orderOut(nil)
        if cheatReturnFocus || fullOn {                    // focus back to the note
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(textView)
        }
    }

    // MARK: Settings window (Task 10)

    var settingsWindow: SettingsWindow?

    func showSettings() {
        if settingsWindow == nil {
            let w = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 674),
                                   styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Settings"
            w.isReleasedWhenClosed = false
            w.titlebarAppearsTransparent = true
            w.appearance = Theme.appearance
            w.isOpaque = false
            w.backgroundColor = Theme.bg.withAlphaComponent(boxOpacity)   // the box's look
            // Fixed sizes so the layout holds at any note text size.
            let body = typewriterFonts.lazy.compactMap { NSFont(name: $0, size: 13) }.first
                ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
            let titleFont = NSFontManager.shared.convert(NSFontManager.shared.convert(body, toSize: 28), toHaveTrait: .boldFontMask)
            let title = NSTextField(labelWithString: "SETTINGS")
            title.font = titleFont; title.textColor = Theme.title; title.alignment = .center
            title.frame = NSRect(x: 20, y: 604, width: 560, height: titleFont.boundingRectForFont.height + 4)
            let label = NSTextField(labelWithString: "THEME")
            label.font = body; label.textColor = Theme.hint
            label.frame = NSRect(x: 50, y: 568, width: 500, height: 18)
            let list = ThemeListView(frame: NSRect(x: 50, y: 558 - CGFloat(ThemeLogic.all.count) * 36, width: 500, height: CGFloat(ThemeLogic.all.count) * 36))
            list.rowH = 36
            list.font = body
            list.onPick = { [weak self] name in self?.setTheme(name) }
            w.contentView?.addSubview(title); w.contentView?.addSubview(label); w.contentView?.addSubview(list)
            settingsTitle = title; settingsLabel = label; settingsList = list
            // Text size: − 13pt + (same as ⌘− ⌘+)
            func rowLabel(_ t: String, _ y: CGFloat) -> NSTextField {
                let l = NSTextField(labelWithString: t); l.font = body; l.textColor = Theme.hint
                l.frame = NSRect(x: 50, y: y, width: 150, height: 18); w.contentView?.addSubview(l); settingsLabels.append(l); return l
            }
            func button(_ t: String, _ x: CGFloat, _ y: CGFloat, _ wd: CGFloat, _ act: @escaping () -> Void) -> SettingsButton {
                let b = SettingsButton(frame: NSRect(x: x, y: y - 3, width: wd, height: 24)); b.font = body; b.text = t; b.action2 = act
                w.contentView?.addSubview(b); settingsButtons.append(b); return b
            }
            _ = rowLabel("FONT", 284)
            var fx: CGFloat = 220
            for v in FontLogic.settings {
                let wd: CGFloat = v == "sans" ? 100 : 70
                let b = button(FontLogic.label(v), fx, 284, wd) { [weak self] in self?.setNoteFont(v) }
                b.font = noteFont(13, v)                    // each name in its own font
                settingsFontButtons[v] = b
                fx += wd + 10
            }
            _ = rowLabel("TEXT SIZE", 238)
            _ = button("−", 220, 238, 28) { [weak self] in self?.changeFontSize(-1) }
            let sizeVal = NSTextField(labelWithString: ""); sizeVal.font = body; sizeVal.alignment = .center
            sizeVal.frame = NSRect(x: 252, y: 238, width: 56, height: 18); w.contentView?.addSubview(sizeVal); settingsSize = sizeVal
            _ = button("+", 312, 238, 28) { [weak self] in self?.changeFontSize(1) }
            // Background opacity: slider + % (same as < > in window mode)
            _ = rowLabel("OPACITY", 192)
            let sl = NSSlider(value: Double(boxOpacity), minValue: Double(minBoxOpacity), maxValue: 1.0, target: self, action: #selector(opacitySlid(_:)))
            sl.isContinuous = true; sl.frame = NSRect(x: 220, y: 189, width: 240, height: 24)
            w.contentView?.addSubview(sl); settingsSlider = sl
            let opVal = NSTextField(labelWithString: ""); opVal.font = body
            opVal.frame = NSRect(x: 474, y: 192, width: 60, height: 18); w.contentView?.addSubview(opVal); settingsOpacity = opVal
            // Fullscreen section (Step 5B)
            let fsHead = NSTextField(labelWithString: "FULLSCREEN"); fsHead.font = body; fsHead.textColor = Theme.title
            fsHead.frame = NSRect(x: 50, y: 136, width: 200, height: 18); w.contentView?.addSubview(fsHead); settingsFSHead = fsHead
            // Shown as column width: Narrow column = stored "wide" margins (25%), Wide column = stored "narrow" (10%).
            _ = rowLabel("COLUMN", 96)
            settingsFS["wide"] = button("Narrow", 220, 96, 74) { [weak self] in self?.setFullscreenMargins("wide") }
            settingsFS["narrow"] = button("Wide", 304, 96, 64) { [weak self] in self?.setFullscreenMargins("narrow") }
            _ = rowLabel("LINE SPACING", 50)
            settingsFS["tight"] = button("Tight", 220, 50, 64) { [weak self] in self?.setFullscreenSpacing("tight") }
            settingsFS["loose"] = button("Loose", 294, 50, 74) { [weak self] in self?.setFullscreenSpacing("loose") }
            // Help: a fresh copy of the tutorial as a new note (never overwrites).
            _ = rowLabel("HELP", 16)
            _ = button("Tutorial", 220, 16, 94) { [weak self] in self?.openTutorialNote() }
            // Optional: sign in once so Ask Grok (fn G) / Ask Claude (fn K) open ready to send.
            _ = button("Open grok.com", 324, 16, 120) { if let u = AskSites.grok { NSWorkspace.shared.open(u) } }
            _ = button("Open claude.ai", 454, 16, 126) { if let u = AskSites.claude { NSWorkspace.shared.open(u) } }
            updateSettingsControls()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {                  // back to the box and its note
                    self.panel.makeKeyAndOrderFront(nil)
                    self.panel.makeFirstResponder(self.textView)
                }
            }
            settingsWindow = w
        }
        guard let w = settingsWindow else { return }
        w.backgroundColor = Theme.bg.withAlphaComponent(boxOpacity)
        w.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)   // always above the box (incl. fullscreen)
        w.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]  // opens over the fullscreen Space too
        if !w.isVisible {                                 // place it each time it opens (fixed 600x674)
            let screen = panel.screen ?? NSScreen.main
            var f = NSRect(x: 0, y: 0, width: 600, height: 674)
            if fullOn, let sf = screen?.frame {
                f.origin = NSPoint(x: sf.midX - 300, y: sf.midY - 337)
            } else {
                f.origin = NSPoint(x: panel.frame.midX - 300, y: panel.frame.midY - 337)
                if let v = screen?.visibleFrame {
                    f.origin.x = min(max(f.origin.x, v.minX), v.maxX - f.width)
                    f.origin.y = min(max(f.origin.y, v.minY), v.maxY - f.height)
                }
            }
            w.setFrame(f, display: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(settingsList)                // Esc / ⌘W reach the window
    }

    var settingsTitle: NSTextField?
    var settingsLabels: [NSTextField] = []
    var settingsButtons: [SettingsButton] = []
    var settingsSize: NSTextField?
    var settingsSlider: NSSlider?
    var settingsOpacity: NSTextField?
    var settingsFontButtons: [String: SettingsButton] = [:]
    var settingsFS: [String: SettingsButton] = [:]
    var settingsFSHead: NSTextField?

    func setNoteFont(_ v: String) {
        let v = FontLogic.normalize(v)
        guard v != noteFontSetting else { return }
        noteFontSetting = v
        appDefaults.set(v, forKey: "font")
        textView.typingAttributes[.font] = noteFont(fontSize)
        refreshRules()                                    // restyle rebuilds every font from the new base
        textView.needsDisplay = true
        updateSettingsControls()
    }

    @objc func opacitySlid(_ sender: NSSlider) { setOpacity(CGFloat(sender.doubleValue)) }

    // Settings controls show the current values (called after any change, from a shortcut or a control).
    func updateSettingsControls() {
        guard settingsWindow != nil else { return }
        settingsSize?.stringValue = "\(Int(fontSize))pt"; settingsSize?.textColor = Theme.text
        settingsOpacity?.stringValue = "\(Int((boxOpacity * 100).rounded()))%"; settingsOpacity?.textColor = Theme.text
        if let sl = settingsSlider, abs(sl.doubleValue - Double(boxOpacity)) > 0.001 { sl.doubleValue = Double(boxOpacity) }
        for (v, b) in settingsFontButtons { b.active = v == noteFontSetting }
        let fm = FullscreenLogic.margins(appDefaults.string(forKey: "fsMargins"))
        let fsp = FullscreenLogic.spacing(appDefaults.string(forKey: "fsLineSpacing"))
        for (v, b) in settingsFS { b.active = v == fm || v == fsp }
        settingsFSHead?.textColor = Theme.title
        for l in settingsLabels { l.textColor = Theme.hint }
        for b in settingsButtons { b.needsDisplay = true }
    }
    var settingsLabel: NSTextField?
    var settingsList: ThemeListView?

    // Pick a theme: save it and recolor everything now.
    func setTheme(_ name: String) {
        guard name != currentTheme.name else { return }
        currentTheme = ThemeLogic.named(name)
        appDefaults.set(currentTheme.name, forKey: "theme")
        applyTheme()
    }

    func applyTheme() {
        panel.appearance = Theme.appearance
        panel.backgroundColor = Theme.bg.withAlphaComponent(boxOpacity)
        panel.invalidateShadow()
        status.textColor = Theme.hint
        fullLabel?.textColor = Theme.hint
        paraLabel?.textColor = neonColor
        if paraMode { panel.contentView?.layer?.borderColor = neonColor.withAlphaComponent(0.9).cgColor }
        textView.insertionPointColor = Theme.text
        textView.selectedTextAttributes = [.backgroundColor: Theme.selection, .foregroundColor: Theme.bold]
        textView.typingAttributes[.foregroundColor] = bodyColor
        refreshRules()                                    // restyle: body, bold, highlight, titles, list numbers
        textView.needsDisplay = true
        navScroll?.backgroundColor = Theme.bg
        if navOpen { renderNavigator() }
        if let w = settingsWindow {
            w.appearance = Theme.appearance
            w.backgroundColor = Theme.bg.withAlphaComponent(boxOpacity)
            settingsTitle?.textColor = Theme.title
            settingsLabel?.textColor = Theme.hint
            settingsList?.needsDisplay = true
            updateSettingsControls()
        }
    }

    // MARK: copy out (⌃⌘G): HTML for Google Docs + clean text

    // Lines the selection touches; no selection = whole note.
    // Paragraph mode: the edited sentences rejoined into one paragraph (as leaving the mode would), selection ignored.
    func exportText() -> String {
        if paraMode { return ParaLogic.rejoin(NSAttributedString(attributedString: textView.textStorage ?? NSTextStorage())).string }
        let sel = textView.selectedRange()
        if sel.length == 0 { return textView.string }
        let s = textView.string as NSString
        return s.substring(with: s.paragraphRange(for: sel))
    }

    func copyOut() {
        let blocks = ExportLogic.parse(exportText())
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(ExportLogic.html(blocks), forType: .html)
        pb.setString(ExportLogic.cleanText(blocks), forType: .string)
        flashStatus("Copied out")
    }

    // MARK: ask Grok (⌃⌘L): one-line prompt at the bottom of the box, then grok.com/?q= in the browser

    var grokField: NSTextField?
    var grokText = ""                                       // clean text captured when the field opened
    let grokHandler = GrokFieldHandler()

    var askClaude = false                                   // the open field asks Claude instead of Grok
    func showGrokPrompt(claude: Bool = false) {
        if windowMode { setWindowMode(false) }
        if let f = grokField {
            askClaude = claude
            f.placeholderAttributedString = NSAttributedString(string: claude ? "Ask Claude…" : "Ask Grok…",
                attributes: [.foregroundColor: Theme.hint, .font: textView.font ?? NSFont.systemFont(ofSize: 13)])
            panel.makeFirstResponder(f); return
        }
        askClaude = claude
        grokText = ExportLogic.cleanText(ExportLogic.parse(exportText()))   // same clean text as ⌃⌘G
        guard let content = panel.contentView else { return }
        let f = NSTextField(string: "")
        f.placeholderAttributedString = NSAttributedString(string: claude ? "Ask Claude…" : "Ask Grok…",
            attributes: [.foregroundColor: Theme.hint, .font: textView.font ?? NSFont.systemFont(ofSize: 13)])
        f.font = textView.font
        f.textColor = Theme.text
        f.backgroundColor = Theme.bg
        f.drawsBackground = true
        f.isBordered = false
        f.focusRingType = .none
        f.cell?.usesSingleLineMode = true
        f.cell?.isScrollable = true
        f.wantsLayer = true
        f.layer?.borderWidth = 1
        f.layer?.borderColor = Theme.text.withAlphaComponent(0.25).cgColor
        f.layer?.cornerRadius = 4
        let h = ceil((f.font ?? NSFont.systemFont(ofSize: 13)).boundingRectForFont.height) + 6
        f.frame = NSRect(x: 10, y: 8, width: content.bounds.width - 20, height: h)
        f.autoresizingMask = [.width, .maxYMargin]
        grokHandler.owner = self
        f.delegate = grokHandler
        content.addSubview(f, positioned: .above, relativeTo: nil)
        grokField = f
        panel.makeFirstResponder(f)
    }

    func closeGrokPrompt() {
        grokField?.removeFromSuperview()
        grokField = nil
        grokText = ""
        panel.makeFirstResponder(textView)
    }

    func submitGrokPrompt() {
        let prompt = grokField?.stringValue ?? ""
        if !prompt.trimmingCharacters(in: .whitespaces).isEmpty { appDefaults.set(prompt, forKey: "lastGrokPrompt") }
        let msg = GrokLogic.message(prompt: prompt, text: grokText)
        closeGrokPrompt()
        guard !msg.isEmpty, let url = askClaude ? GrokLogic.claudeURL(msg) : GrokLogic.url(msg) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: find and replace (Task 7)

    var findBarOpen: Bool { textView.enclosingScrollView?.isFindBarVisible ?? false }

    func findAction(_ action: NSTextFinder.Action) {
        if windowMode { setWindowMode(false) }
        let item = NSMenuItem()
        item.tag = action.rawValue
        if action == .hideFindInterface {
            let keep = textView.selectedRanges
            textView.performTextFinderAction(item)
            panel.makeFirstResponder(textView)        // back to the note, match still selected
            textView.selectedRanges = keep
            return
        }
        textView.performTextFinderAction(item)
        if action == .showFindInterface || action == .showReplaceInterface { fitBoxForFindBar(replace: action == .showReplaceInterface) }
    }

    // Grow the box (top-left anchored, on screen) so the find bar fits. Never shrinks it.
    func fitBoxForFindBar(replace: Bool) {
        guard !fullOn, let sv = textView.enclosingScrollView else { return }
        sv.layoutSubtreeIfNeeded()
        let bar = sv.findBarView
        let measured = bar?.fittingSize.width ?? 0
        let needW = max(measured + 16, replace ? 460 : 320)
        let barH = bar?.frame.height ?? (replace ? 56 : 28)
        let needH = barH + 4 * (textView.font?.boundingRectForFont.height ?? 18) + 40
        var f = panel.frame
        guard f.width < needW || f.height < needH else { return }
        let top = f.maxY
        f.size.width = max(f.width, needW)
        f.size.height = max(f.height, needH)
        f.origin.y = top - f.height
        f = clampOnScreen(f)
        panel.setFrame(f, display: true, animate: false)
    }

    // MARK: send selection (⌃⌥S)

    // fn M / ⌃⌘X: the selected text opens as a new post in X (default browser). Nothing is posted by the app.
    // The box steps aside (fades, stays where it is) and the browser comes forward; the previous app is not re-activated.
    func postSelectionToX() {
        let sel = textView.selectedRange()
        let text = sel.length > 0 ? (textView.string as NSString).substring(with: sel) : nil
        switch TweetLogic.plan(selection: text) {
        case .nothing: flashStatus("Select text first", 1.5)
        case .tooLong: flashStatus("Too long to send (shorten the selection)", 2.5)
        case let .open(url, over):
            let go = { [weak self] in
                guard let self = self else { return }
                self.handBack(switchApp: false)
                NSWorkspace.shared.open(url)               // default browser, to the compose window; the user presses Post
            }
            if over { flashStatus("Over 280 characters", 1.2); DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: go) }
            else { go() }
        }
    }

    func flashStatus(_ msg: String, _ seconds: TimeInterval = 1) {
        setStatus(msg)
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self = self, self.status.stringValue.hasSuffix(msg) else { return }
            self.setStatus("")
        }
    }

    // ⌃⌥S (any app, also inside FloatNote): the selected text becomes a NEW note (standard name and date, saved at
    // once), opened in fullscreen. Selection: FloatNote's own text view when FloatNote is the active app; else the
    // front app's AXSelectedText, else Cmd+C with the clipboard restored. Nothing selected: nothing happens.
    func sendSelection() {
        if NSApp.isActive {
            let r = textView.selectedRange()
            if panel.isKeyWindow, r.length > 0, let ts = textView.textStorage, NSMaxRange(r) <= ts.length {
                // text selected inside FloatNote itself: adding it to its own note would only repeat it, so it becomes a new note
                newNoteFromSelection((ts.string as NSString).substring(with: r))
            } else { flashStatus("No selection") }
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current else { return }
        guard AXIsProcessTrusted() else {
            askAccessibilityOnce()
            flashStatus(AccessLogic.selectionHint, 6)
            return
        }
        if let text = axSelectedText(), SelectionNote.text(from: text) != nil {
            captureSelection(text)
            return
        }
        copySelectionViaPasteboard { [weak self] text in
            guard let self = self else { return }
            if let t = SelectionNote.text(from: text) { self.captureSelection(t) } else { self.flashStatus("No selection") }
        }
    }

    // The system's Accessibility dialog, once ever; later presses only show the hint.
    func askAccessibilityOnce() {
        guard AccessLogic.shouldPrompt(trusted: AXIsProcessTrusted(), alreadyAsked: appDefaults.bool(forKey: "accessibilityAsked")) else { return }
        appDefaults.set(true, forKey: "accessibilityAsked")
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    // ⌃⌥S from another app: into the open note; a new note (fullscreen) only when no note is open.
    func captureSelection(_ text: String) {
        switch SelectionNote.target(hasFile: noteFileURL != nil, text: textView.string) {
        case .newNote: newNoteFromSelection(text)
        case .appendToOpenNote: appendSelection(text)
        }
    }

    // Adds the selection at the end of the open note: same file (name and created date unchanged), saved at once
    // (atomic), editor in sync, one undo step. The box is not activated and nothing pops up: "Added to ..." shows in
    // the box if it is showing, else the next time it is shown.
    func appendSelection(_ text: String) {
        if paraMode { exitParagraphMode() }
        guard let ts = textView.textStorage, let edit = SelectionNote.appendEdit(existing: ts.string, selection: text) else { return }
        let range = NSRange(location: edit.location, length: edit.length)
        let oldEnd = ts.length, sel = textView.selectedRange()
        var plain: [NSAttributedString.Key: Any] = textView.typingAttributes
        plain[titleKey] = nil
        guard textView.shouldChangeText(in: range, replacementString: edit.text) else { return }
        ts.replaceCharacters(in: range, with: NSAttributedString(string: edit.text, attributes: plain))
        textView.didChangeText()
        textView.undoManager?.setActionName("Add selection")
        if sel.location >= oldEnd - edit.length { textView.setSelectedRange(NSRange(location: ts.length, length: 0)); textView.scrollRangeToVisible(textView.selectedRange()) }
        saveNow()
        let name = noteFileURL.map { NoteLibrary.displayName(fileName: $0.lastPathComponent, text: ts.string) } ?? "the note"
        let msg = "Added to " + (name.count > 28 ? String(name.prefix(27)) + "…" : name)
        if panel.isVisible, !panel.isMiniaturized, panel.alphaValue >= 0.5 { flashStatus(msg, 2.5) } else { pendingStatus = msg }
    }
    var pendingStatus: String?                           // shown when the box is next shown (it was hidden when the text came in)
    func showPendingStatus() {
        guard let m = pendingStatus else { return }
        pendingStatus = nil
        flashStatus(m, 2.5)
    }

    func newNoteFromSelection(_ text: String) {
        guard let clean = SelectionNote.noteText(from: text) else { return }
        saveNow(wait: true)                              // the note you were in is saved first
        if listOpen { closeNotesList() }
        if paraMode { exitParagraphMode() }
        if navOpen { closeNavigator(jump: false) }
        guard let dst = newNoteFile(), NoteLibrary.writeAtomically(clean, to: dst) else { flashStatus("Not saved", 3); return }
        showNote(dst)                                    // file name = Note N -- DDMONYY.txt (today), created now
        if panel.isMiniaturized { restoreFromDock() }
        if fullOn {                                      // already fullscreen: just come forward, ready to type
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(textView)
        } else if panel.isMiniaturized {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.enterFullscreen() }
        } else {
            enterFullscreen()
        }
    }

    func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused, CFGetTypeID(el) == AXUIElementGetTypeID() else { return nil }
        var sel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el as! AXUIElement, kAXSelectedTextAttribute as CFString, &sel) == .success
        else { return nil }
        return sel as? String
    }

    func copySelectionViaPasteboard(_ done: @escaping (String?) -> Void) {
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
            return d
        }
        let start = pb.changeCount
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
        let began = Date()
        Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            let changed = pb.changeCount != start
            guard changed || Date().timeIntervalSince(began) >= 0.3 else { return }
            timer.invalidate()
            guard changed else { done(nil); return }
            let text = pb.string(forType: .string)
            pb.clearContents()
            let items: [NSPasteboardItem] = saved.map { d in
                let it = NSPasteboardItem()
                for (t, v) in d { it.setData(v, forType: t) }
                return it
            }
            if !items.isEmpty { pb.writeObjects(items) }
            done(text)
        }
    }

    // MARK: moving + resizing

    var windowMode = false
    var modeLabel: NSTextField?
    var keyMonitor: Any?

    // MARK: navigator (⌥⌘V) — a read-only tree of ## titles and %% subtitles

    struct NavEntry { let text: String; let sub: Bool; let jumpTo: Int; let start: Int }
    var navOpen = false
    var navEntries: [NavEntry] = []      // what's shown (filtered)
    var navAll: [NavEntry] = []          // every heading
    var navFiltering = false             // ⌘F filter line active
    var navQuery = ""
    var navCursor = 0
    var navScroll: NSScrollView?
    var navView: NSTextView?

    func headings() -> [NavEntry] {
        guard let ts = textView.textStorage else { return [] }
        var out: [NavEntry] = []
        let text = ts.string as NSString
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byParagraphs) { sub, r, _, _ in
            guard let sub = sub else { return }
            if let h = HeadingLogic.kind(sub) {
                let name = String((sub as NSString).substring(from: h.markerLen))
                out.append(NavEntry(text: name.uppercased(), sub: h.kind == .subtitle, jumpTo: NSMaxRange(r), start: r.location))
            }
        }
        return out
    }

    func openNavigator() {
        if paraMode { exitParagraphMode() }
        if windowMode { setWindowMode(false) }
        navAll = headings(); navEntries = navAll
        navFiltering = false; navQuery = ""
        let caret = textView.selectedRange().location
        navCursor = max(navEntries.lastIndex(where: { $0.start <= caret }) ?? 0, 0)
        if navScroll == nil {
            let sv = NSTextView.scrollableTextView()
            sv.drawsBackground = true
            sv.backgroundColor = Theme.bg
            sv.borderType = .noBorder
            sv.scrollerStyle = .overlay
            sv.autoresizingMask = [.width, .height]
            let tv = sv.documentView as! NSTextView
            tv.isEditable = false
            tv.isSelectable = false
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 8, height: 4)
            navScroll = sv; navView = tv
        }
        guard let sv = navScroll, let main = textView.enclosingScrollView else { return }
        sv.frame = main.frame
        panel.contentView?.addSubview(sv, positioned: .above, relativeTo: main)
        navOpen = true
        renderNavigator()
    }

    func closeNavigator(jump: Bool) {
        navOpen = false
        navScroll?.removeFromSuperview()
        panel.makeFirstResponder(textView)
        if jump, navEntries.indices.contains(navCursor) {
            let loc = min(navEntries[navCursor].jumpTo, textView.textStorage?.length ?? 0)
            textView.setSelectedRange(NSRange(location: loc, length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
        }
    }

    func renderNavigator() {
        guard let tv = navView, let ts = tv.textStorage else { return }
        let font = typewriterFonts.lazy.compactMap { NSFont(name: $0, size: fontSize) }.first
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let gray = Theme.hint
        let dimRed = titlePink.withAlphaComponent(0.7)
        let out = NSMutableAttributedString()
        func add(_ s: String, _ c: NSColor, bg: NSColor? = nil) {
            var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c]
            if let bg = bg { a[.backgroundColor] = bg }
            out.append(NSAttributedString(string: s, attributes: a))
        }
        add("-- NAVIGATOR --\n", neonColor)
        if navFiltering { add("/ " + navQuery + "\u{258F}\n", neonColor) }
        add("note/\n", gray)
        var cursorRange = NSRange(location: 0, length: 0)
        if navEntries.isEmpty { add(navFiltering && !navAll.isEmpty ? "(no matches)\n" : "(no titles)\n", gray) }
        let firstTitle = navEntries.firstIndex(where: { !$0.sub }) ?? navEntries.count
        let isRoot: (Int) -> Bool = { i in !self.navEntries[i].sub || i < firstTitle }
        let rootIdx = navEntries.indices.filter(isRoot)
        for (i, e) in navEntries.enumerated() {
            var prefix: String
            if isRoot(i) {
                prefix = (i == rootIdx.last ? "└── " : "├── ")
            } else {
                let parent = navEntries[..<i].lastIndex(where: { !$0.sub })!
                let parentLast = parent == rootIdx.last
                let lastChild = i + 1 >= navEntries.count || !navEntries[i + 1].sub
                prefix = (parentLast ? "    " : "│   ") + (lastChild ? "└── " : "├── ")
            }
            let selected = i == navCursor
            let start = out.length
            add(selected ? "> " : "  ", selected ? neonColor : gray)
            add(prefix, gray)
            add(e.text, e.sub ? dimRed : titlePink, bg: selected ? Theme.text.withAlphaComponent(0.15) : nil)
            add("\n", gray)
            if selected { cursorRange = NSRange(location: start, length: out.length - start) }
        }
        ts.setAttributedString(out)
        if cursorRange.length > 0 { tv.scrollRangeToVisible(cursorRange) } else { tv.scrollToBeginningOfDocument(nil) }
    }

    // Re-filter, keeping the selected heading selected when it's still visible.
    func applyNavFilter() {
        let keepStart = navEntries.indices.contains(navCursor) ? navEntries[navCursor].start : nil
        let idx = NavFilter.visible(navAll.map { ($0.text, $0.sub) }, query: navFiltering ? navQuery : "")
        navEntries = idx.map { navAll[$0] }
        navCursor = navEntries.firstIndex(where: { $0.start == keepStart }) ?? 0
        renderNavigator()
    }

    func startNavFilter() {
        navFiltering = true
        applyNavFilter()
    }

    func navigatorKey(_ event: NSEvent) {
        if navFiltering {
            let last = max(navEntries.count - 1, 0)
            switch event.keyCode {
            case 53: navFiltering = false; navQuery = ""; applyNavFilter(); return    // Esc: clear + close filter
            case 36, 76: closeNavigator(jump: true); return
            case 125: navCursor = min(navCursor + 1, last); renderNavigator(); return
            case 126: navCursor = max(navCursor - 1, 0); renderNavigator(); return
            case 51: if !navQuery.isEmpty { navQuery.removeLast(); applyNavFilter() }; return   // Backspace
            default: break
            }
            let mods = event.modifierFlags.intersection([.command, .control])
            if mods.isEmpty, let t = event.characters, !t.isEmpty,
               t.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }) {
                navQuery += t; applyNavFilter()
            }
            return
        }
        let ch = event.charactersIgnoringModifiers ?? ""
        let last = max(navEntries.count - 1, 0)
        switch (event.keyCode, ch) {
        case (53, _): closeNavigator(jump: false); return
        case (36, _), (76, _): closeNavigator(jump: true); return
        case (125, _): navCursor = min(navCursor + 1, last)
        case (126, _): navCursor = max(navCursor - 1, 0)
        default: return
        }
        renderNavigator()
    }

    // MARK: notes list (⌘O, F3) — same overlay and look as the navigator

    struct ListRow { let url: URL; let name: String; let date: String; var created: Date = .distantPast }
    var listOpen = false
    var listAll: [ListRow] = []
    var listRows: [ListRow] = []          // shown (filtered)
    var listFiltering = false
    var listQuery = ""
    var listCursor = 0
    var listAskDelete = false
    var listScroll: NSScrollView?
    var listView: NotesListTextView?

    func loadListRows() {
        // Date shown, order and day separators all use the created date (see NoteLibrary.createdDate).
        listAll = NoteLibrary.sortedForList(NoteLibrary.noteFiles(in: libraryFolder).map { (url: $0, created: NoteLibrary.createdDate($0)) })
            .map { u, d in ListRow(url: u, name: NoteLibrary.rowTitle(u), date: NoteLibrary.rowDate(d), created: d) }
    }

    func openNotesList() {
        if paraMode { exitParagraphMode() }
        if windowMode { setWindowMode(false) }
        if navOpen { closeNavigator(jump: false) }
        saveNow(wait: true)                               // so the open note's row shows its latest text
        loadListRows()
        listFiltering = false; listQuery = ""; listAskDelete = false
        listRows = listAll
        listCursor = listRows.firstIndex { $0.url.standardizedFileURL == noteFileURL?.standardizedFileURL } ?? 0
        if listScroll == nil {
            let sv = NotesListTextView.scrollableTextView()
            sv.drawsBackground = true
            sv.borderType = .noBorder
            sv.scrollerStyle = .overlay
            sv.autoresizingMask = [.width, .height]
            let tv = sv.documentView as! NotesListTextView
            tv.isEditable = false
            tv.isSelectable = false
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 8, height: 4)
            tv.onClick = { [weak self] row, count in self?.listMouse(row: row, clickCount: count) }
            tv.onRename = { [weak self] row in self?.startListRename(row) }
            tv.onClickAway = { [weak self] in self?.finishListRename(commit: true) }
            sv.contentView.postsBoundsChangedNotifications = true      // hover follows the content while scrolling
            NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: sv.contentView, queue: .main) { [weak self] _ in
                self?.listView?.refreshHover()
            }
            listScroll = sv; listView = tv
            sv.postsFrameChangedNotifications = true      // re-lay out on resize / entering or leaving fullscreen
            NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: sv, queue: .main) { [weak self] _ in
                if self?.listOpen == true { self?.renderNotesList() }
            }
        }
        guard let sv = listScroll, let main = textView.enclosingScrollView else { return }
        sv.backgroundColor = Theme.bg
        sv.frame = main.frame
        sv.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(sv, positioned: .above, relativeTo: main)
        listOpen = true
        infoStripRefresh()                               // the list claims the top: strip away
        panel.acceptsMouseMovedEvents = true             // hover band in the list
        panel.makeFirstResponder(listView)               // keys meant for the note don't reach it
        renderNotesList()
    }

    // ⌘O rename: an inline field over the row, prefilled with the name the list shows (← starts empty). Return renames the
    // FILE (see NoteLibrary.renameNote), Esc cancels, a click elsewhere renames, a blank name removes the custom name (back
    // to the default first-line display; for files without one, nothing changes). The note's text is never touched.
    var listRenaming = false
    var renameField: NSTextField?
    var renameURL: URL?
    let renameHandler = ListRenameHandler()

    enum RenameStart { case keep, clear }                   // keep: name prefilled, caret at the end; clear: empty field
    func startListRename(_ row: Int, _ start: RenameStart = .keep) {
        guard listOpen, !listAskDelete, !listRenaming, listRows.indices.contains(row), let lv = listView else { return }
        listCursor = row
        renderNotesList()
        let rects = lv.rowRects()
        guard rects.indices.contains(row) else { return }
        let r = rects[row]
        let f = NSTextField(string: start == .clear ? "" : listRows[row].name)
        let size = NotesListSize.font(fontSize)
        f.font = typewriterFonts.lazy.compactMap { NSFont(name: $0, size: size) }.first ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        f.textColor = Theme.bold
        f.backgroundColor = Theme.bg
        f.drawsBackground = true
        f.isBordered = false
        f.focusRingType = .none
        f.cell?.usesSingleLineMode = true
        f.cell?.isScrollable = true
        f.wantsLayer = true
        f.layer?.borderWidth = 1
        f.layer?.borderColor = Theme.text.withAlphaComponent(0.35).cgColor
        f.layer?.cornerRadius = 3
        f.frame = NSRect(x: r.minX, y: r.minY - 1, width: r.width, height: r.height + 2)
        renameHandler.owner = self
        f.delegate = renameHandler
        renameURL = listRows[row].url
        listRenaming = true
        renameField = f
        lv.mouseEnabled = false; lv.hoverRow = nil; lv.renaming = true
        lv.addSubview(f)
        panel.makeFirstResponder(f)
        let end = (f.stringValue as NSString).length
        f.currentEditor()?.selectedRange = NSRange(location: end, length: 0)       // caret at the end
    }

    func finishListRename(commit: Bool) {
        guard listRenaming, let f = renameField, let url = renameURL else { return }
        listRenaming = false                              // first: removing the field ends its editing again
        let typed = f.stringValue
        renameField = nil; renameURL = nil
        f.removeFromSuperview()
        panel.makeFirstResponder(listView)
        listView?.mouseEnabled = !listAskDelete
        listView?.renaming = false
        guard commit else { return }
        renameNote(url, to: typed)
    }

    func renameNote(_ url: URL, to typed: String) {
        let isOpen = url.standardizedFileURL == noteFileURL?.standardizedFileURL
        if isOpen { saveNow(wait: true) }                  // the buffer is on disk before the file moves
        saveQueue.sync {}
        guard let dst = NoteLibrary.renameNote(url, to: typed) else {
            if !NoteLibrary.sanitizedName(typed).isEmpty,
               NoteLibrary.renamedFileName(old: url.lastPathComponent, newName: typed) != url.lastPathComponent { flashStatus("Not renamed", 2) }
            renderNotesList(); return
        }
        if isOpen { noteFileURL = dst }                    // the open note keeps saving to its new path
        if tutorialFiles.contains(url.lastPathComponent) {
            tutorialFiles = tutorialFiles.map { $0 == url.lastPathComponent ? dst.lastPathComponent : $0 }
        }
        func renamed(_ r: ListRow) -> ListRow {
            guard r.url == url else { return r }
            return ListRow(url: dst, name: NoteLibrary.rowTitle(dst), date: r.date, created: r.created)
        }
        listAll = listAll.map(renamed); listRows = listRows.map(renamed)
        renderNotesList()
    }

    // A click in the list: select (as ↑↓), double click opens (as Return). Not while the delete confirmation is up.
    func listMouse(row: Int, clickCount: Int) {
        guard listOpen, !listAskDelete, !listRenaming else { return }
        switch NotesListMouse.action(hit: row, clickCount: clickCount, rowCount: listRows.count) {
        case .select(let i): listCursor = i; renderNotesList()
        case .open(let i): listCursor = i; openSelectedNote()
        case .none: break
        }
    }

    func closeNotesList() {
        if listRenaming { finishListRename(commit: false) }
        panel.acceptsMouseMovedEvents = fullOn           // fullscreen keeps it for the info strip
        listView?.hoverRow = nil
        listOpen = false
        listAskDelete = false
        listScroll?.removeFromSuperview()
        panel.makeFirstResponder(textView)
    }

    // The ⌘O list follows the note's area when the box goes fullscreen / back / is resized: same frame, rows laid out again.
    func relayoutNotesList() {
        guard listOpen, let sv = listScroll, let main = textView.enclosingScrollView else { return }
        if sv.frame != main.frame { sv.frame = main.frame }
        renderNotesList()
        if listRenaming, let f = renameField, let u = renameURL, let i = listRows.firstIndex(where: { $0.url == u }),
           let rects = listView?.rowRects(), rects.indices.contains(i) {
            let r = rects[i]
            f.frame = NSRect(x: r.minX, y: r.minY - 1, width: r.width, height: r.height + 2)
        }
    }

    func renderNotesList() {
        guard let tv = listView, let ts = tv.textStorage, let sv = listScroll else { return }
        // Fullscreen: same centred column as the note, so the dates sit at the column's right edge.
        tv.textContainerInset = NSSize(width: FullscreenLogic.listInset(width: sv.contentSize.width, fullscreen: fullOn,
                                                                        appDefaults.string(forKey: "fsMargins")),
                                       height: NotesListSize.topInset(fullscreen: fullOn))
        let listSize = NotesListSize.font(fontSize)          // bigger than the note text (1.3x)
        let font = typewriterFonts.lazy.compactMap { NSFont(name: $0, size: listSize) }.first
            ?? .monospacedSystemFont(ofSize: listSize, weight: .regular)
        let gray = Theme.hint
        // Date on the right: a right tab stop at the text width.
        let width = sv.contentSize.width - 2 * tv.textContainerInset.width - 2 * (tv.textContainer?.lineFragmentPadding ?? 5) - 4
        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .right, location: max(width, 60))]
        para.lineBreakMode = .byTruncatingTail
        para.paragraphSpacing = NotesListSize.rowSpacing(listSize)
        let out = NSMutableAttributedString()
        func add(_ s: String, _ c: NSColor, bg: NSColor? = nil) {
            var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c, .paragraphStyle: para]
            if let bg = bg { a[.backgroundColor] = bg }
            out.append(NSAttributedString(string: s, attributes: a))
        }
        add("-- NOTES --\n", neonColor)
        if listFiltering { add("/ " + listQuery + "\u{258F}\n", neonColor) }
        if listAskDelete, listRows.indices.contains(listCursor) {
            add("Move \"\(listRows[listCursor].name)\" to the Trash?\n", titlePink)
            add("Return = Move to Trash   Esc = Cancel\n", gray)
        }
        var cursorRange = NSRange(location: 0, length: 0)
        var rowRanges: [NSRange] = []
        if listRows.isEmpty { add(listFiltering && !listAll.isEmpty ? "(no matches)\n" : "(no notes)\n", gray) }
        // Keep the name short enough that the date fits on the same line.
        let charW = max(("M" as NSString).size(withAttributes: [.font: font]).width, 1)
        // Day separator: a hairline image as wide as the text column, with space above and below.
        let sepColor = Theme.text.withAlphaComponent(NotesListDays.separatorAlpha)
        let sepW = max(width, 60)
        let sepPara = NSMutableParagraphStyle()
        sepPara.paragraphSpacingBefore = (listSize * 0.15).rounded()
        sepPara.paragraphSpacing = (listSize * 0.45).rounded()
        func addSeparator() {
            let img = NSImage(size: NSSize(width: sepW, height: 1), flipped: false) { rect in
                sepColor.setFill(); NSRect(x: 0, y: 0, width: rect.width, height: 0.5).fill(); return true
            }
            let att = NSTextAttachment(); att.image = img
            att.bounds = NSRect(x: 0, y: 0, width: sepW, height: 1)
            let a = NSMutableAttributedString(attachment: att)
            a.append(NSAttributedString(string: "\n"))
            a.addAttributes([.paragraphStyle: sepPara, .font: NSFont.systemFont(ofSize: 2)], range: NSRange(location: 0, length: a.length))
            out.append(a)
        }
        for line in NotesListDays.lines(listRows.map { $0.created }) {
            guard case .row(let i) = line else { addSeparator(); continue }
            let r = listRows[i]
            let selected = i == listCursor
            let room = max(Int((width - 2 * charW) / charW) - r.date.count - 3, 4)
            let name = r.name.count > room ? String(r.name.prefix(room - 1)) + "…" : r.name
            let start = out.length
            add(selected ? "> " : "  ", selected ? neonColor : gray)
            add(name, selected ? Theme.bold : Theme.text, bg: selected ? Theme.text.withAlphaComponent(0.15) : nil)
            add("\t" + r.date + "\n", gray)
            rowRanges.append(NSRange(location: start, length: out.length - start - 1))     // without the line break
            if selected { cursorRange = NSRange(location: start, length: out.length - start) }
        }
        ts.setAttributedString(out)
        let lv: NotesListTextView = tv
        lv.rowRanges = rowRanges
        lv.rowPad = (NotesListSize.rowSpacing(listSize) / 2).rounded(.up) + 1
        lv.mouseEnabled = !listAskDelete
        lv.selectedRow = listRows.indices.contains(listCursor) ? listCursor : nil
        lv.hoverRow = nil
        DispatchQueue.main.async { lv.refreshHover() }
        if cursorRange.length > 0 { tv.scrollRangeToVisible(cursorRange) } else { tv.scrollToBeginningOfDocument(nil) }
    }

    func applyListFilter() {
        let keep = listRows.indices.contains(listCursor) ? listRows[listCursor].url : nil
        let q = listFiltering ? listQuery.lowercased() : ""
        listRows = q.isEmpty ? listAll : listAll.filter { $0.name.lowercased().contains(q) }
        listCursor = listRows.firstIndex { $0.url == keep } ?? 0
        renderNotesList()
    }

    func notesListKey(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if listAskDelete {                                 // the confirmation: Return deletes, Esc cancels
            switch event.keyCode {
            case 36, 76: deleteSelectedNote()
            case 53: listAskDelete = false; renderNotesList()
            default: break
            }
            return
        }
        switch FullscreenLogic.listShortcut(keyCode: event.keyCode, flags: event.modifierFlags) {
        case "fullscreen"?: onFullscreen?(); return        // the list stays open and re-lays out at the new size
        case "minimize"?: onMinimize?(); return
        default: break
        }
        if mods == [.command] {
            switch Int(event.keyCode) {
            case kVK_ANSI_O: closeNotesList()
            case kVK_ANSI_F: listFiltering = true; applyListFilter()
            case kVK_Delete: if listRows.indices.contains(listCursor) { listAskDelete = true; renderNotesList() }
            default: break
            }
            return
        }
        if mods == [.command, .option], Int(event.keyCode) == kVK_Delete {      // ⌥⌘⌫: to the Trash now, no asking
            if listRows.indices.contains(listCursor) { deleteSelectedNote() }
            return
        }
        if event.keyCode == 120 { startListRename(listCursor); return }          // F2: rename
        if event.keyCode == UInt16(kVK_ANSI_R), mods.isEmpty, !listFiltering { startListRename(listCursor); return }   // R (not while filtering)
        switch event.keyCode {
        case 53:                                           // Esc: clear the filter text, else close
            if listFiltering && !listQuery.isEmpty { listQuery = ""; applyListFilter() }
            else if listFiltering { listFiltering = false; applyListFilter(); closeNotesList() }
            else { closeNotesList() }
            return
        case 36, 76: openSelectedNote(); return
        case 123 where mods.isEmpty: startListRename(listCursor, .clear); return      // ←: rename from scratch (blank = default name)
        case 124 where mods.isEmpty: startListRename(listCursor, .keep); return       // →: rename, add on to the current name
        case 125: listCursor = NotesListDays.move(listCursor, by: 1, count: listRows.count); renderNotesList(); return
        case 126: listCursor = NotesListDays.move(listCursor, by: -1, count: listRows.count); renderNotesList(); return
        case 51: if listFiltering, !listQuery.isEmpty { listQuery.removeLast(); applyListFilter() }; return
        default: break
        }
        if listFiltering, mods.subtracting(.shift).isEmpty, let t = event.characters, !t.isEmpty,
           t.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }) {
            listQuery += t; applyListFilter()
        }
    }

    // Show a note in the box (or a new note with no file when url is nil). Saves the open note first.
    func showNote(_ url: URL?) {
        saveNow(wait: true)
        // A file that can't be read (not downloaded from iCloud yet, no permission, too big) is never shown as an empty
        // note: typing into it would overwrite the real file. The note you are in stays open.
        var loaded: String? = ""
        if let url = url { loaded = NoteLibrary.readText(url) }
        guard let raw = loaded else { flashStatus("Can't open that note (unreadable or too big)", 4); return }
        let left = noteFileURL
        defer { cleanupLeft(left); applyTutorialOpacity() }                      // after the switch: empty -> Trash, tutorial -> ask
        let text = PendingStyleLogic.stripEmptyPairs(raw)
        noteFileURL = url
        lastSavedText = text
        titlePending = url == nil                        // ⌘N / new note: starts on a title line
        saveTimes.saved()
        saveTimer?.invalidate(); saveTimer = nil
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: textView.typingAttributes))
        textView.undoManager?.removeAllActions()
        refreshRules()
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))   // cursor at the end
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    // Settings > Tutorial: a fresh tutorial note with the next name, opened in the box.
    // MARK: library cleanup (empty notes silently, tutorial notes after asking)
    var tutorialFiles: [String] {
        get { appDefaults.stringArray(forKey: "tutorialFiles") ?? [] }
        set { appDefaults.set(newValue, forKey: "tutorialFiles") }
    }
    func untrackTutorial(_ url: URL) { tutorialFiles.removeAll { $0 == url.lastPathComponent } }
    var tutorialHint: NSButton?
    var askQueue: [URL] = []                             // tutorial notes waiting for "Delete this tutorial note?"
    var askLabel: NSTextField?
    var askMonitor: Any?

    // The note you just left: empty -> Trash (silent); a tracked tutorial -> ask.
    func cleanupLeft(_ url: URL?) {
        guard let url = url, url.standardizedFileURL != noteFileURL?.standardizedFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        if NoteCleanup.isEmptyFile(url) {
            if NoteCleanup.trash(url) { untrackTutorial(url) }
        } else if tutorialFiles.contains(url.lastPathComponent) {
            if !askQueue.contains(url) { askQueue.append(url) }
            showNextAsk()
        }
        refreshTutorialHint()
    }
    func showNextAsk() {
        askQueue.removeAll { !FileManager.default.fileExists(atPath: $0.path) || $0.standardizedFileURL == noteFileURL?.standardizedFileURL }
        guard askQueue.first != nil, let content = panel?.contentView else { hideAsk(); return }
        if askLabel == nil {
            let l = NSTextField(labelWithString: "")
            l.font = status.font; l.alignment = .right
            l.frame = status.frame; l.autoresizingMask = [.width, .minYMargin]
            content.addSubview(l); askLabel = l
        }
        askLabel?.stringValue = "Delete this tutorial note? Return: to the Trash · Esc: keep"
        askLabel?.textColor = Theme.text
        askLabel?.isHidden = false
        status.isHidden = true
        if askMonitor == nil {
            askMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self = self, e.window === self.panel, let url = self.askQueue.first,
                      e.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return e }
                switch e.keyCode {
                case 36, 76:                                // Return: to the Trash
                    if NoteCleanup.trash(url) { self.untrackTutorial(url); self.flashStatus("Tutorial note moved to the Trash", 2) }
                    else { self.flashStatus("Not deleted", 2) }
                case 53: self.untrackTutorial(url)          // Esc: keep it as a normal note
                default: return e
                }
                self.askQueue.removeFirst()
                self.refreshTutorialHint()
                self.showNextAsk()
                return nil
            }
        }
    }
    func hideAsk() {
        askLabel?.isHidden = true
        status.isHidden = false
        if let m = askMonitor { NSEvent.removeMonitor(m); askMonitor = nil }
    }
    // A faint "Tutorial" button in the bottom-right corner while the library has fewer than 20 notes.
    func refreshTutorialHint() {
        guard let content = panel?.contentView else { return }
        let n = NoteLibrary.noteFiles(in: libraryFolder).count
        if tutorialHint == nil {
            let b = NSButton(title: "Tutorial", target: self, action: #selector(tutorialHintClicked))
            b.isBordered = false
            b.font = NSFont.systemFont(ofSize: 9)
            b.sizeToFit()
            b.frame.origin = NSPoint(x: content.bounds.width - b.frame.width - 10, y: 4)
            b.autoresizingMask = [.minXMargin, .maxYMargin]
            content.addSubview(b, positioned: .above, relativeTo: nil)
            tutorialHint = b
        }
        tutorialHint?.attributedTitle = NSAttributedString(string: "Tutorial",
            attributes: [.foregroundColor: Theme.hint.withAlphaComponent(0.5), .font: NSFont.systemFont(ofSize: 9)])
        tutorialHint?.isHidden = fullOn || !NoteCleanup.showTutorialHint(noteCount: n)
    }
    @objc func tutorialHintClicked() { openTutorialNote() }
    // Tutorial note open: background at least 90% for legibility (in memory only; the saved setting stays).
    var opacityBeforeTutorial: CGFloat?
    func applyTutorialOpacity() {
        let onTutorial = noteFileURL.map { tutorialFiles.contains($0.lastPathComponent) } ?? false
        if onTutorial {
            if opacityBeforeTutorial == nil { opacityBeforeTutorial = boxOpacity }
            boxOpacity = NoteCleanup.tutorialOpacity(saved: opacityBeforeTutorial!)
        } else if let saved = opacityBeforeTutorial {
            boxOpacity = saved; opacityBeforeTutorial = nil
        } else { return }
        panel.backgroundColor = Theme.bg.withAlphaComponent(boxOpacity)
        panel.invalidateShadow()
        updateSettingsControls()
    }

    func openTutorialNote() {
        if paraMode { exitParagraphMode() }
        if listOpen { closeNotesList() }
        saveNow(wait: true)
        guard let url = newNoteFile(), AppDelegate.writeAtomically(TutorialNote.text, to: url) else { flashStatus("Not saved", 3); return }
        appDefaults.set(true, forKey: "tutorialShown")
        tutorialFiles.append(url.lastPathComponent)      // tracked: asked about when you leave it
        showNote(url)
        textView.setSelectedRange(NSRange(location: 0, length: 0))      // start at the top
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        settingsWindow?.performClose(nil)
    }

    // ⌘N (F4): save the open note, then show a new note with no file. Nothing to do on a new note.
    func newNote() {
        if paraMode { exitParagraphMode() }
        if navOpen { closeNavigator(jump: false) }
        if listOpen { closeNotesList() }
        guard !NoteLibrary.isNewNote(hasFile: noteFileURL != nil, text: currentNoteText() ?? "") else { return }
        showNote(nil)                                    // saves first, clears the undo history
    }

    // F5: copy each dropped .txt/.md file's text into a new note file; open the last one.
    // The original files are only read: never changed, moved or deleted.
    func importFiles(_ urls: [URL]) {
        saveNow(wait: true)                              // save the open note first (F1)
        var last: URL?
        var error: String?
        for src in urls {
            guard NoteLibrary.canImport(src) else { error = "Only .txt and .md files"; continue }
            guard let text = NoteLibrary.readImport(src) else { error = "Could not read the file"; continue }
            guard let dst = newNoteFile(), AppDelegate.writeAtomically(text, to: dst) else { error = "Not saved"; continue }
            last = dst
        }
        if let dst = last { showNote(dst) }
        if let e = error { flashStatus(e, 3) }
    }

    func openSelectedNote() {
        guard listRows.indices.contains(listCursor) else { closeNotesList(); return }
        let url = listRows[listCursor].url
        closeNotesList()
        showNote(url)
    }

    func deleteSelectedNote() {
        listAskDelete = false
        guard listRows.indices.contains(listCursor) else { renderNotesList(); return }
        let url = listRows[listCursor].url
        let wasOpen = url.standardizedFileURL == noteFileURL?.standardizedFileURL
        saveQueue.sync {}                                  // no write to this file still queued
        if wasOpen { saveTimer?.invalidate(); saveTimer = nil; saveTimes.saved() }
        do { try NoteLibrary.deleteNoteFile(url) } catch { flashStatus("Not deleted"); renderNotesList(); return }  // to the Trash (never a permanent delete)
        untrackTutorial(url); refreshTutorialHint()
        listAll.removeAll { $0.url == url }
        listRows.removeAll { $0.url == url }
        listCursor = NoteLibrary.cursorAfterDelete(cursor: listCursor, remaining: listRows.count)   // the next note
        if wasOpen {                                       // F2: a new note with no file
            noteFileURL = nil
            lastSavedText = ""
            textView.textStorage?.setAttributedString(NSAttributedString(string: "", attributes: textView.typingAttributes))
            textView.undoManager?.removeAllActions()
            refreshRules()
        }
        renderNotesList()
    }

    // MARK: fullscreen writing (fn+F; Esc leaves)
    var fullOn = false
    var fullSavedFrame = NSRect.zero
    var fullLabel: NSTextField?

    // Native macOS fullscreen (its own Space: three-finger swipe / ⌃← ⌃→ work). The panel is switched to a
    // normal, activating, fullscreen-capable window for the duration and switched back on exit.
    var fsTransition = false
    var fsObservers: [Any] = []

    func enterFullscreen() {
        guard !fullOn else { return }
        if windowMode { setWindowMode(false) }
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current { previousApp = front }
        fullSavedFrame = panel.frame
        fullOn = true
        fsTransition = true
        panel.styleMask.remove(.nonactivatingPanel)
        panel.level = .normal
        panel.collectionBehavior = [.fullScreenPrimary, .managed]
        panel.backgroundColor = Theme.bg.withAlphaComponent(boxOpacity)   // the saved opacity setting
        if fsObservers.isEmpty {
            let nc = NotificationCenter.default
            fsObservers.append(nc.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: panel, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                self.fsTransition = false
                self.layoutFullscreenColumn()
                self.textView.scrollRangeToVisible(self.textView.selectedRange())
                self.installInfoStripTracking()
            })
            fsObservers.append(nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: panel, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                if self.fullOn { self.exitFullscreen(); return }   // left via macOS (e.g. menu or green button)
                self.finishExitFullscreen()
            })
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        if !listOpen { panel.makeFirstResponder(textView) }       // the ⌘O list keeps the keys when it is open
        panel.nativeToggleFullScreen()
        layoutFullscreenColumn()
        if fullLabel == nil {
            let l = NSTextField(labelWithString: "-- FULLSCREEN --")
            l.font = NSFont(descriptor: status.font!.fontDescriptor, size: 9)
            l.textColor = Theme.hint
            l.alignment = .center
            l.autoresizingMask = [.width, .minYMargin]
            panel.contentView?.addSubview(l)
            fullLabel = l
        }
        if let c = panel.contentView {
            fullLabel?.frame = NSRect(x: 0, y: c.bounds.height - 30, width: c.bounds.width, height: 13)
        }
        fullLabel?.isHidden = false
        textView.scrollRangeToVisible(textView.selectedRange())
        refreshTutorialHint()                            // hidden in fullscreen
    }

    // Centered column: at most 720pt or 65% of the screen, 80pt top/bottom.
    func layoutFullscreenColumn() {
        relayoutNotesList()
        guard fullOn, let sv = textView.enclosingScrollView else { return }
        let width = sv.contentSize.width
        let m = FullscreenLogic.margin(screenWidth: width, appDefaults.string(forKey: "fsMargins"))
        textView.textContainerInset = NSSize(width: max(8, m), height: 80)
        refreshRules()
    }

    // Fullscreen settings (Column and Line spacing rows in Settings). The old fsColumnWidth is ignored.
    func setFullscreenMargins(_ v: String) {
        appDefaults.set(FullscreenLogic.margins(v), forKey: "fsMargins")
        layoutFullscreenColumn()
        updateSettingsControls()
    }
    func setFullscreenSpacing(_ v: String) {
        appDefaults.set(FullscreenLogic.spacing(v), forKey: "fsLineSpacing")
        refreshRules()
        updateSettingsControls()
    }

    func exitFullscreen() {
        guard fullOn else { return }
        fullOn = false
        removeInfoStripTracking()
        fullLabel?.isHidden = true
        textView.textContainerInset = NSSize(width: 8, height: 2)
        refreshRules()                                    // box line spacing back
        if panel.styleMask.contains(.fullScreen) { fsTransition = true; panel.nativeToggleFullScreen() }
        else { finishExitFullscreen() }
    }

    // MARK: fullscreen info strip (mouse near the top edge)
    // Monitors exist only while in fullscreen (the global one also sees the mouse over macOS's menu bar, which
    // slides over the top when the pointer reaches the edge). The clock/battery timer runs only while the strip shows.
    var infoStrip: NSTextField?
    var infoShown = false
    var infoTimer: Timer?
    var infoMonitors: [Any] = []

    func installInfoStripTracking() {
        guard fullOn, infoMonitors.isEmpty else { return }
        panel.acceptsMouseMovedEvents = true
        infoMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.infoStripRefresh() } as Any)
        infoMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] e in self?.infoStripRefresh(); return e } as Any)
    }

    func removeInfoStripTracking() {
        for m in infoMonitors { NSEvent.removeMonitor(m) }
        infoMonitors = []
        setInfoStrip(visible: false, animated: false)
        if !listOpen { panel.acceptsMouseMovedEvents = false }
    }

    var infoBlocked: Bool {
        listOpen || findBarOpen || windowMode || navOpen || grokField != nil
            || (settingsWindow?.isVisible ?? false) || (cheatPanel?.isVisible ?? false)
            || panel.ignoresMouseEvents || panel.alphaValue < 0.5 || !panel.isVisible || !panel.isOnActiveSpace
    }

    func infoStripRefresh() {
        guard fullOn || infoShown else { return }
        var dist: CGFloat? = nil
        if let sf = panel.screen?.frame ?? NSScreen.main?.frame {
            let m = NSEvent.mouseLocation
            if sf.contains(m) || m.y > sf.maxY - 1 && m.x >= sf.minX && m.x <= sf.maxX { dist = max(0, sf.maxY - m.y) }
        }
        let show = InfoStripLogic.visible(was: infoShown, fullscreen: fullOn, transitioning: fsTransition, blocked: infoBlocked, distanceFromTop: dist)
        if show != infoShown { setInfoStrip(visible: show, animated: true) }
        else if show { updateInfoStripText() }
    }

    func setInfoStrip(visible: Bool, animated: Bool) {
        infoShown = visible
        if visible {
            if infoStrip == nil {
                let l = PassThroughLabel(labelWithString: "")
                l.font = NSFont(descriptor: status.font!.fontDescriptor, size: 12)
                l.alignment = .right
                l.autoresizingMask = [.width, .minYMargin]
                l.alphaValue = 0
                panel.contentView?.addSubview(l, positioned: .above, relativeTo: nil)
                infoStrip = l
            }
            if let c = panel.contentView {
                infoStrip?.frame = NSRect(x: 24, y: c.bounds.height - 58, width: c.bounds.width - 48, height: 16)   // below the menu bar, outside the text column
            }
            infoStrip?.textColor = Theme.hint
            updateInfoStripText()
            // one tick per minute, aligned to the minute: the time and battery only change then
            infoTimer?.invalidate()
            let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(second: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(60)
            let t = Timer(fire: next, interval: 60, repeats: true) { [weak self] _ in self?.infoStripRefresh() }
            RunLoop.main.add(t, forMode: .common)
            infoTimer = t
        } else {
            infoTimer?.invalidate(); infoTimer = nil
        }
        guard let strip = infoStrip else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = visible ? 0.25 : 0.35
                strip.animator().alphaValue = visible ? 1 : 0
            }
        } else { strip.alphaValue = visible ? 1 : 0 }
    }

    func updateInfoStripText() {
        guard infoShown else { return }
        let b = readBattery()
        infoStrip?.stringValue = InfoStripLogic.line(date: Date(), words: InfoStripLogic.wordCount(textView.string),
                                                     batteryPercent: b?.percent, charging: b?.charging ?? false)
    }

    // Internal battery via IOKit power sources; nil on a Mac without one.
    func readBattery() -> (percent: Int, charging: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let mx = d[kIOPSMaxCapacityKey] as? Int, mx > 0 else { continue }
            return (Int((Double(cur) * 100 / Double(mx)).rounded()), (d[kIOPSIsChargingKey] as? Bool) ?? false)
        }
        return nil
    }

    // After macOS leaves the fullscreen Space: back to the floating, non-activating box at its old frame.
    func finishExitFullscreen() {
        fsTransition = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = .floating
        panel.styleMask.insert(.nonactivatingPanel)
        panel.backgroundColor = Theme.bg.withAlphaComponent(boxOpacity)
        panel.setFrame(fullSavedFrame, display: true, animate: true)
        relayoutNotesList()
        textView.scrollRangeToVisible(textView.selectedRange())
        refreshTutorialHint()
        if let next = afterFSExit { afterFSExit = nil; DispatchQueue.main.async { next() } }
    }
    var afterFSExit: (() -> Void)?

    // MARK: paragraph mode
    var paraMode = false
    var paraStash: NSAttributedString?
    var paraRange = NSRange(location: 0, length: 0)
    let paraUndo = UndoManager()
    var paraLabel: NSTextField?

    // While in paragraph mode the box gets its own undo history.
    func undoManager(for view: NSTextView) -> UndoManager? { paraMode ? paraUndo : nil }

    func enterParagraphMode() {
        guard let ts = textView.textStorage, ts.length > 0 else { return }
        let text = ts.string as NSString
        var range = text.paragraphRange(for: textView.selectedRange())
        // drop the final newline so it stays outside the edited part
        while range.length > 0, let u = UnicodeScalar(text.character(at: NSMaxRange(range) - 1)),
              CharacterSet.newlines.contains(u) { range.length -= 1 }
        guard range.length > 0 else { return }

        let original = ts.attributedSubstring(from: range)
        let str = original.string
        let tok = NLTokenizer(unit: .sentence)
        tok.string = str
        let split = NSMutableAttributedString()
        for r in tok.tokens(for: str.startIndex..<str.endIndex) {
            let ns = NSRange(r, in: str)
            let piece = NSMutableAttributedString(attributedString: original.attributedSubstring(from: ns))
            // trim whitespace/newlines at both ends, keeping attributes
            while piece.length > 0, let u = UnicodeScalar((piece.string as NSString).character(at: piece.length - 1)),
                  CharacterSet.whitespacesAndNewlines.contains(u) { piece.deleteCharacters(in: NSRange(location: piece.length - 1, length: 1)) }
            while piece.length > 0, let u = UnicodeScalar((piece.string as NSString).character(at: 0)),
                  CharacterSet.whitespacesAndNewlines.contains(u) { piece.deleteCharacters(in: NSRange(location: 0, length: 1)) }
            guard piece.length > 0 else { continue }
            if split.length > 0 {
                split.append(NSAttributedString(string: "\n", attributes: split.attributes(at: split.length - 1, effectiveRange: nil)))
            }
            split.append(piece)
        }
        guard split.length > 0 else { return }
        // Breathing room between sentences (only in this view; removed on exit).
        let roomy = NSMutableParagraphStyle()
        roomy.setParagraphStyle((ts.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle) ?? .default)
        roomy.paragraphSpacing = ParaLogic.sentenceGap(font: textView.font ?? noteFont(fontSize),
            lineMultiple: FullscreenLogic.lineMultiple(appDefaults.string(forKey: "fsLineSpacing"), fullscreen: fullOn))   // one blank line
        roomy.lineSpacing = ParaLogic.sentenceLineSpacing
        split.addAttribute(.paragraphStyle, value: roomy, range: NSRange(location: 0, length: split.length))

        paraStash = NSAttributedString(attributedString: ts)
        paraRange = range
        paraMode = true
        paraUndo.removeAllActions()
        ts.setAttributedString(split)
        textView.typingAttributes[.paragraphStyle] = roomy
        refreshRules()
        textView.setSelectedRange(NSRange(location: ts.length, length: 0))
        showParaIndicator(true)
    }

    func exitParagraphMode() {
        guard paraMode, let stash = paraStash, let ts = textView.textStorage else { return }
        let joined = ParaLogic.rejoin(NSAttributedString(attributedString: ts))

        // Back to the original paragraph's own spacing/alignment.
        let origStyle = (stash.attribute(.paragraphStyle, at: paraRange.location, effectiveRange: nil) as? NSParagraphStyle) ?? .default
        if joined.length > 0 { joined.addAttribute(.paragraphStyle, value: origStyle, range: NSRange(location: 0, length: joined.length)) }
        paraMode = false
        paraStash = nil
        showParaIndicator(false)
        ts.setAttributedString(stash)              // back to the note exactly as it was (matches main undo history)
        // Put the edited paragraph in as one undoable step.
        if textView.shouldChangeText(in: paraRange, replacementString: joined.string) {
            ts.replaceCharacters(in: paraRange, with: joined)
            textView.didChangeText()
            textView.undoManager?.setActionName("Edit Paragraph")
        }
        textView.setSelectedRange(NSRange(location: paraRange.location + joined.length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        refreshRules()
        saveNow()                                        // leaving paragraph mode: save immediately
    }

    func showParaIndicator(_ on: Bool) {
        let content = panel.contentView!
        content.wantsLayer = true
        content.layer?.borderWidth = on ? 1.5 : 0
        content.layer?.borderColor = neonColor.withAlphaComponent(0.9).cgColor
        content.layer?.cornerRadius = 10
        if paraLabel == nil {
            let l = NSTextField(labelWithString: "-- PARAGRAPH --")
            l.font = NSFont(descriptor: status.font!.fontDescriptor, size: 9)
            l.textColor = neonColor
            l.frame = NSRect(x: 12, y: status.frame.minY, width: 140, height: 13)
            l.autoresizingMask = [.minYMargin]
            content.addSubview(l)
            paraLabel = l
        }
        paraLabel?.isHidden = !on
    }

    func toggleWindowMode() {
        if paraMode { exitParagraphMode() }
        if navOpen { closeNavigator(jump: false) }
        if fullOn {                                      // in fullscreen: leave the Space first, then window mode
            let wasOn = windowMode                       // same result as before: on -> off, off -> on
            if windowMode { setWindowMode(false) }
            if !wasOn { afterFSExit = { [weak self] in self?.focusBox(); self?.setWindowMode(true) } }
            exitFullscreen(); return
        }
        if windowMode { setWindowMode(false) } else { focusBox(); setWindowMode(true) }
    }

    var modeHint: NSTextField?
    func setWindowMode(_ on: Bool) {
        windowMode = on
        textView.isEditable = on ? false : true
        let content = panel.contentView!
        content.wantsLayer = true
        content.layer?.borderWidth = on ? 1.5 : 0
        content.layer?.borderColor = NSColor.systemPink.withAlphaComponent(0.8).cgColor
        content.layer?.cornerRadius = 10
        if modeLabel == nil {
            let l = NSTextField(labelWithString: "-- WINDOW --")
            l.font = NSFont(descriptor: status.font!.fontDescriptor, size: 9)
            l.textColor = NSColor.systemPink
            l.frame = NSRect(x: 12, y: status.frame.minY, width: 120, height: 13)
            l.autoresizingMask = [.minYMargin]
            content.addSubview(l)
            modeLabel = l
        }
        modeLabel?.isHidden = !on
        // Step 9: hint line under -- WINDOW -- (fullscreen window mode only changes opacity).
        if modeHint == nil {
            let l = NSTextField(labelWithString: "")
            l.font = NSFont(descriptor: status.font!.fontDescriptor, size: 9)
            l.autoresizingMask = [.minYMargin]
            content.addSubview(l)
            modeHint = l
        }
        modeHint?.stringValue = fullOn ? ", . opacity · Esc done" : "arrows move · wasd resize · Esc done"
        modeHint?.textColor = Theme.hint
        if let m = modeLabel { modeHint?.frame = NSRect(x: m.frame.minX, y: m.frame.minY - 13, width: 300, height: 13) }
        modeHint?.isHidden = !on
        if on && keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.windowMode, event.window === self.panel else { return event }
                if event.modifierFlags.contains(.command) { return event }
                if self.fnLetterRun(event) != nil { return event }  // fn + letter
                self.windowKey(event)
                return nil
            }
        }
    }

    func windowKey(_ event: NSEvent) {
        if event.keyCode == 53 { setWindowMode(false); return }  // Esc
        // , . (no Shift needed) or < >: background opacity, 10% per press.
        if let dir = OpacityKeyLogic.direction(keyCode: event.keyCode, characters: event.characters) {
            setOpacity(boxOpacity + CGFloat(dir) * 0.1)
            return
        }
        guard let ch = event.characters, ch.count == 1 else { return }
        if fullOn { return }                                   // fullscreen window mode: opacity only, frame stays
        let n: CGFloat = 1
        let step: CGFloat = 40
        var f = panel.frame
        // Arrow keys move (Shift = 4x).
        if [123, 124, 125, 126].contains(event.keyCode) {
            let d = step * n * (event.modifierFlags.contains(.shift) ? 4 : 1)
            switch event.keyCode {
            case 123: f.origin.x -= d
            case 124: f.origin.x += d
            case 125: f.origin.y -= d
            default:  f.origin.y += d
            }
            panel.setFrame(clampOnScreen(f), display: true, animate: true)
            return
        }
        switch ch {
        case "w", "W": let h = max(panel.minSize.height, f.height - step * n * (ch == "W" ? 4 : 1)); f.origin.y += f.height - h; f.size.height = h
        case "s", "S": let h = f.height + step * n * (ch == "S" ? 4 : 1); f.origin.y -= h - f.height; f.size.height = h
        case "a", "A": f.size.width = max(panel.minSize.width, f.width - step * n * (ch == "A" ? 4 : 1))
        case "d", "D": f.size.width += step * n * (ch == "D" ? 4 : 1)
        default: return
        }
        f.size.width = max(f.width, panel.minSize.width)
        f.size.height = max(f.height, panel.minSize.height)
        panel.setFrame(clampOnScreen(f), display: true, animate: true)
    }

    // Keep the box fully inside the visible area of the screen it's mostly on.
    func clampOnScreen(_ rect: NSRect) -> NSRect {
        let screen = NSScreen.screens.max { a, b in
            let ia = a.frame.intersection(rect), ib = b.frame.intersection(rect)
            return ia.width * ia.height < ib.width * ib.height
        } ?? NSScreen.main
        guard let v = screen?.visibleFrame else { return rect }
        var r = rect
        r.size.width = min(max(r.width, panel.minSize.width), v.width)
        r.size.height = min(max(r.height, panel.minSize.height), v.height)
        r.origin.x = min(max(r.minX, v.minX), v.maxX - r.width)
        r.origin.y = min(max(r.minY, v.minY), v.maxY - r.height)
        return r
    }


    // switchApp: false (Right Option tap) only hides the box; it doesn't activate any other app.
    // MARK: ⌘W minimize to the Dock
    // FloatNote is an accessory app (no Dock icon). While minimized it is switched to .regular so the
    // minimized box (and the app icon) sit in the Dock; it goes back to .accessory once restored.
    func minimizeToDock() {
        guard !panel.isMiniaturized else { return }
        closeOnHide()
        if findBarOpen { findAction(.hideFindInterface) }
        if paraMode { exitParagraphMode() }
        if navOpen { closeNavigator(jump: false) }
        if windowMode { setWindowMode(false) }
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current { previousApp = front }
        NSApp.setActivationPolicy(.regular)
        panel.styleMask.remove(.nonactivatingPanel)
        panel.styleMask.insert(.miniaturizable)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        panel.miniaturize(nil)
        if let prev = previousApp, prev != NSRunningApplication.current { prev.activate(options: []) }
    }

    // Right Option, a click on the minimized box or on the Dock icon: bring it back.
    func restoreFromDock() {
        NSApp.activate(ignoringOtherApps: true)
        panel.deminiaturize(nil)              // didDeminiaturize → finishRestoreFromDock
    }

    func finishRestoreFromDock() {
        panel.styleMask.remove(.miniaturizable)
        panel.styleMask.insert(.nonactivatingPanel)
        NSApp.setActivationPolicy(.accessory)
        panel.alphaValue = 1
        focusBox()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(listOpen && !listRenaming ? listView : textView)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if panel.isMiniaturized { restoreFromDock() }
        return false
    }

    func toggleFocus() {
        if panel.isMiniaturized { restoreFromDock(); return }
        if fullOn {                         // Right Option with the fullscreen Space
            if panel.isKeyWindow && NSApp.isActive {
                if findBarOpen { findAction(.hideFindInterface) }
                if paraMode { exitParagraphMode() }
                if navOpen { closeNavigator(jump: false) }
                if windowMode { setWindowMode(false) }
                closeOnHide()
                if let prev = previousApp, prev != NSRunningApplication.current { prev.activate(options: []) }
                else { NSApp.hide(nil) }
            } else {
                NSApp.activate(ignoringOtherApps: true)    // switches to the fullscreen Space
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(textView)
                showPendingStatus()
            }
            return
        }
        if panel.isVisible && panel.isKeyWindow && !panel.ignoresMouseEvents { handBack(switchApp: false) } else { focusBox() }
    }

    func focusBox() {
        // The panel never activates FloatNote, so the app you were in stays frontmost underneath.
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            previousApp = front
        }
        panel.ignoresMouseEvents = false
        fade(to: 1)
        panel.makeKeyAndOrderFront(nil)
        if !listOpen { panel.makeFirstResponder(textView) }
        showPendingStatus()
    }

    func fade(to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = alpha
        }
    }

    // Hiding FloatNote also closes Settings, the cheat sheet and the Ask field.
    func closeOnHide(includeAsk: Bool = true) {
        for item in HideCloseLogic.toClose(settingsOpen: settingsWindow?.isVisible ?? false,
                                           cheatOpen: cheatPanel?.isVisible ?? false,
                                           askOpen: includeAsk && grokField != nil) {
            switch item {
            case "settings": settingsWindow?.performClose(nil)
            case "cheatSheet": closeCheatSheet()
            default: closeGrokPrompt()
            }
        }
    }

    func handBack(switchApp: Bool = true) {
        closeOnHide()
        if findBarOpen { findAction(.hideFindInterface) }
        // Ordering the panel out returns the keyboard to the app you were in; then show it again, unfocused.
        if paraMode { exitParagraphMode() }
        if navOpen { closeNavigator(jump: false) }
        // Right Option hide (switchApp false) keeps fullscreen; the next tap brings it back as it was.
        if fullOn && switchApp {                         // finish jumping back once macOS has left the Space
            afterFSExit = { [weak self] in self?.handBack(switchApp: true) }
            exitFullscreen(); return
        }
        if windowMode { setWindowMode(false) }
        panel.ignoresMouseEvents = true                  // click-through while you work elsewhere
        fade(to: RestAlphaLogic.rest(dark: currentTheme.dark))   // light themes 2.5%, dark 5%
        panel.orderOut(nil)
        panel.orderFrontRegardless()                     // shown again, but no longer key: typing can't reach it
        guard switchApp else { return }
        if NSApp.isActive { NSApp.deactivate() }
        previousApp?.activate(options: [])
    }

    // Background opacity (minBoxOpacity–1.0, saved). Used by < > in window mode and the Settings slider.
    func setOpacity(_ value: CGFloat) {
        opacityBeforeTutorial = nil                      // the user's own choice: saved and kept
        boxOpacity = (min(max(value, minBoxOpacity), 1.0) * 100).rounded() / 100
        appDefaults.set(Double(boxOpacity), forKey: "opacity")
        panel.backgroundColor = Theme.bg.withAlphaComponent(boxOpacity)
        panel.invalidateShadow()
        settingsWindow?.backgroundColor = Theme.bg.withAlphaComponent(boxOpacity)
        updateSettingsControls()
    }

    func changeFontSize(_ step: CGFloat) {
        fontSize = min(max(fontSize + step, 8), 48)
        appDefaults.set(Double(fontSize), forKey: "fontSize")
        let font = noteFont(fontSize)
        let fm = NSFontManager.shared
        if let ts = textView.textStorage {
            ts.beginEditing()
            ts.enumerateAttribute(.font, in: NSRange(location: 0, length: ts.length)) { value, range, _ in
                let f = (value as? NSFont) ?? font
                ts.addAttribute(.font, value: fm.convert(f, toSize: fontSize), range: range)
            }
            ts.endEditing()
        }
        let typing = (textView.typingAttributes[.font] as? NSFont) ?? font
        textView.typingAttributes[.font] = fm.convert(typing, toSize: fontSize)
        refreshRules()
        updateSettingsControls()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // Esc (text views sometimes report it as "complete" instead of "cancel")
        if selector == #selector(NSResponder.cancelOperation(_:)) || selector == #selector(NSTextView.complete(_:)) {
            if paraMode { exitParagraphMode() } else if fullOn { exitFullscreen() } else { handBack() }
            return true
        }
        if !paraMode, selector == #selector(NSResponder.deleteBackward(_:)), listBackspace() { return true }
        if selector == #selector(NSResponder.deleteBackward(_:)), deleteAroundHidden(forward: false) { return true }
        if selector == #selector(NSResponder.deleteForward(_:)), deleteAroundHidden(forward: true) { return true }
        if paraMode { return false }   // plain editing in paragraph mode
        if selector == #selector(NSResponder.insertNewline(_:)), listReturn() { return true }
        // Lists have one level: Tab / ⇧Tab on a list line do nothing.
        if selector == #selector(NSResponder.insertTab(_:)) || selector == #selector(NSResponder.insertBacktab(_:)), onListLine() { return true }
        if selector == #selector(NSResponder.insertNewline(_:)), plainReturnAfterTitle() { return true }
        return false
    }

    // MARK: saving



    // MARK: numbered lists
    
    let listLeft: CGFloat = 8

    // Level = number of parts - 1. Only the last part is shown; the rest is hidden.

    // Renumber every contiguous list block, give items their indents and blue numbers.
    // Lists: a fixed number column (kern pads "1. " and "12. " alike) with a hanging indent, Title-colored
    // numbers, hidden leading tabs (until the next edit drops them). Attributes only; never changes the text.
    func styleLists() {
        guard let ts = textView.textStorage else { return }
        let base = noteFont(fontSize)
        let text = ts.string as NSString
        let colW = ("00. " as NSString).size(withAttributes: [.font: base]).width
        let colB = ("0. " as NSString).size(withAttributes: [.font: base]).width       // dash items: a narrower column
        var tabs: [NSRange] = [], markers: [NSRange] = []
        ts.beginEditing()
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byParagraphs) { sub, r, enclosing, _ in
            guard let sub = sub, enclosing.length > 0 else { return }
            let cur = (ts.attribute(.paragraphStyle, at: enclosing.location, effectiveRange: nil) as? NSParagraphStyle) ?? .default
            let ps = NSMutableParagraphStyle(); ps.setParagraphStyle(cur)
            if let it = ListLogic.item(sub) {
                ps.firstLineHeadIndent = self.listLeft
                let col = it.bullet ? colB : colW
                ps.headIndent = ps.firstLineHeadIndent + col
                if it.tabs > 0 { tabs.append(NSRange(location: r.location, length: it.tabs)) }
                markers.append(NSRange(location: r.location, length: it.markerLen))
                let num = NSRange(location: r.location + it.tabs, length: it.markerLen - it.tabs - 1)   // "12."
                ts.enumerateAttribute(.foregroundColor, in: num) { v, cr, _ in
                    if !isNeon(v) { ts.addAttribute(.foregroundColor, value: Theme.title, range: cr) }
                }
                let w = (text.substring(with: NSRange(location: num.location, length: num.length + 1)) as NSString)
                    .size(withAttributes: [.font: base]).width
                if col > w { ts.addAttribute(.kern, value: col - w, range: NSRange(location: r.location + it.markerLen - 1, length: 1)) }
            } else if cur.headIndent != 0 || cur.firstLineHeadIndent != 0 {
                ps.firstLineHeadIndent = 0; ps.headIndent = 0
            } else { return }
            if ps != cur { ts.addAttribute(.paragraphStyle, value: ps, range: enclosing) }
        }
        ts.endEditing()
        if let lm = textView.layoutManager as? RuleLayoutManager {
            let old = lm.hiddenListPrefixes
            lm.hiddenListPrefixes = tabs
            lm.listMarkers = markers
            for r in old + tabs where NSMaxRange(r) <= ts.length {
                lm.invalidateGlyphs(forCharacterRange: r, changeInLength: 0, actualCharacterRange: nil)
            }
        }
    }

    // List keys: compute the whole change, renumber, and apply it as ONE edit (one undo step).
    func commitListEdit(_ plain: String, _ sel: NSRange, name: String = "Typing", at: Int? = nil) {
        let (fixed, fsel) = ListLogic.finish(plain, sel, old: textView.string, at: at)
        let (r, rep) = ListLogic.diff(textView.string, fixed)
        if r.length > 0 || !rep.isEmpty { replaceWhole(r, with: rep, name: name) }
        textView.setSelectedRange(NSRange(location: min(fsel.location, textView.string.utf16.count),
                                          length: min(fsel.length, max(0, textView.string.utf16.count - fsel.location))))
    }
    func listReturn() -> Bool {
        guard let e = ListLogic.returnEdit(textView.string, sel: textView.selectedRange()) else { return false }
        commitListEdit(e.text, e.sel); return true
    }
    func onListLine() -> Bool {
        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        let lb = ListLogic.lineBounds(ns, sel.location)
        return ListLogic.item(ns.substring(with: NSRange(location: lb.start, length: lb.contentsEnd - lb.start))) != nil
    }
    func listBackspace() -> Bool {
        let sel = textView.selectedRange()
        guard sel.length == 0, let e = ListLogic.backspaceEdit(textView.string, caret: sel.location) else { return false }
        commitListEdit(e.text, e.sel, name: "Delete"); return true
    }

    // Return on a ## / %% line: a normal newline, but the new line starts in plain body style.
    func plainReturnAfterTitle() -> Bool {
        guard let ts = textView.textStorage else { return false }
        let text = ts.string as NSString
        let sel = textView.selectedRange()
        var start = 0, end = 0, contentsEnd = 0
        text.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: sel.location, length: 0))
        let line = text.substring(with: NSRange(location: start, length: contentsEnd - start))
        guard HeadingLogic.kind(line) != nil else { return false }
        let base = noteFont(fontSize)
        let plain: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: bodyColor,
                                                    .paragraphStyle: NSParagraphStyle.default]
        textView.typingAttributes = plain
        textView.insertText("\n", replacementRange: sel)
        // The newline belongs to the title line; make sure the new line's text starts plain.
        textView.typingAttributes = plain
        return true
    }

    // ⌥⌘T on a ## title: remove its --- lines if it has them, otherwise add them.
    func toggleTitleRulesHere() {
        guard let ts = textView.textStorage else { return }
        let text = ts.string as NSString
        func para(at i: Int) -> (start: Int, end: Int, contentsEnd: Int, text: String) {
            var a = 0, b = 0, c = 0
            text.getParagraphStart(&a, end: &b, contentsEnd: &c, for: NSRange(location: i, length: 0))
            return (a, b, c, text.substring(with: NSRange(location: a, length: c - a)))
        }
        let t = para(at: textView.selectedRange().location)
        guard HeadingLogic.kind(t.text)?.kind == .title else { return }
        let hasAbove = t.start > 0 && para(at: t.start - 1).text == "---"
        var belowEnd: Int? = nil      // where the lower --- line's text ends
        if t.end < text.length && t.end > t.contentsEnd {
            let n1 = para(at: t.end)
            if n1.text == "---" { belowEnd = n1.contentsEnd }
            else if n1.text.isEmpty, n1.end < text.length, n1.end > n1.contentsEnd, para(at: n1.end).text == "---" {
                belowEnd = para(at: n1.end).contentsEnd
            }
        }
        guard hasAbove && belowEnd != nil else {
            textView.setSelectedRange(NSRange(location: t.contentsEnd, length: 0))
            _ = titleReturn()                  // adds whatever is missing, as Return does
            return
        }
        let undo = textView.undoManager
        textView.breakUndoCoalescing()
        undo?.beginUndoGrouping()
        textView.insertText("", replacementRange: NSRange(location: t.contentsEnd, length: belowEnd! - t.contentsEnd))
        let aboveStart = para(at: t.start - 1).start
        textView.insertText("", replacementRange: NSRange(location: aboveStart, length: t.start - aboveStart))
        undo?.endUndoGrouping()
        undo?.setActionName("Title Rules")
        textView.setSelectedRange(NSRange(location: t.contentsEnd - (t.start - aboveStart), length: 0))
    }

    var titleRulesOn: Bool {
        get { appDefaults.object(forKey: "titleRules") as? Bool ?? true }
        set { appDefaults.set(newValue, forKey: "titleRules") }
    }

    func toggleTitleRules() {
        titleRulesOn.toggle()
        let msg = "title lines: " + (titleRulesOn ? "on" : "off")
        setStatus(msg)
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self = self, self.status.stringValue.hasSuffix(msg) else { return }
            self.setStatus("")
        }
    }

    // Return on a ## title: --- above, then title, a fresh line, ---. One ⌘Z undoes it.
    func titleReturn() -> Bool {
        guard let ts = textView.textStorage else { return false }
        let text = ts.string as NSString
        let sel = textView.selectedRange()
        guard sel.length == 0 else { return false }
        var start = 0, end = 0, contentsEnd = 0
        text.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: sel.location, length: 0))
        guard HeadingLogic.kind(text.substring(with: NSRange(location: start, length: contentsEnd - start)))?.kind == .title else { return false }

        let base = noteFont(fontSize)
        let plainAttrs: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: bodyColor]
        func para(at i: Int) -> String {
            var s0 = 0, e0 = 0, c0 = 0
            text.getParagraphStart(&s0, end: &e0, contentsEnd: &c0, for: NSRange(location: i, length: 0))
            return text.substring(with: NSRange(location: s0, length: c0 - s0))
        }
        func insert(_ str: String, at i: Int) {
            textView.typingAttributes = plainAttrs
            textView.insertText(str, replacementRange: NSRange(location: i, length: 0))
        }

        let undo = textView.undoManager
        textView.breakUndoCoalescing()
        undo?.beginUndoGrouping()
        // Below: an empty line (caret), then --- unless one is already right after the title.
        let closed = end < text.length && end > contentsEnd && para(at: end) == "---"
        insert(closed ? "\n" : "\n\n---", at: contentsEnd)
        var caret = contentsEnd + 1
        // Above: --- unless the line before is already one.
        if start == 0 || para(at: start - 1) != "---" {
            insert("---\n", at: start)
            caret += 4
        }
        undo?.endUndoGrouping()
        undo?.setActionName("Title Rules")
        textView.typingAttributes = plainAttrs
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        return true
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        let sel = textView.selectedRange()
        if !pendingStyles.isEmpty && (sel.length > 0 || sel.location != pendingLoc) { pendingStyles = [] }   // moved away: forget
        refreshRules()
    }
    // Style keys pressed with no selection (⌘B ⌘I ⌘U, highlight, strike): applied to the next typed text.
    var pendingStyles: Set<MarkerLogic.Style> = []
    var pendingLoc = -1

    // Hidden markers: the caret never sits inside one (skipped while text is being changed).
    var textEditing = false
    // all = hidden ranges; heads = title markers (Backspace removes them whole); snapHeads also keeps the
    // caret out of list markers (it goes to the item text).
    func hiddenRanges() -> (all: [NSRange], heads: [NSRange], snapHeads: [NSRange]) {
        guard let lm = textView.layoutManager as? RuleLayoutManager else { return ([], [], []) }
        return (lm.hiddenMarkers + lm.hiddenStyleMarkers + lm.hiddenListPrefixes, lm.hiddenMarkers, lm.hiddenMarkers + lm.listMarkers)
    }
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        textEditing = true
        // Any text edit (typing, paste, cut, delete, replace) is checked once, before it happens:
        //  - a deletion that empties a styled word also takes the emptied markers;
        //  - lists touched by the edit are renumbered.
        // If either applies, the edit is replaced by ONE combined edit (one undo step, exact undo/redo).
        // Not during undo/redo or our own replacement.
        guard !collapsingPairs, let rep = replacementString, let um = textView.undoManager,
              !um.isUndoing, !um.isRedoing else { return true }
        // New note: the first typed text becomes a title; Return on the empty first line = plain body text.
        if titlePending {
            let action = NewNoteTitleLogic.edit(pending: true, docEmpty: textView.string.isEmpty, range: range, rep: rep)
            titlePending = false
            switch action {
            case .normal: break
            case .swallow: flashStatus("Body text"); textEditing = false; return false
            case .insert(let t, let caret):
                textEditing = false
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let ts = self.textView.textStorage, ts.length == 0 else { return }
                    self.collapsingPairs = true
                    defer { self.collapsingPairs = false }
                    let r = NSRange(location: 0, length: 0)
                    guard self.textView.shouldChangeText(in: r, replacementString: t) else { return }
                    ts.replaceCharacters(in: r, with: NSAttributedString(string: t, attributes: self.textView.typingAttributes))
                    self.textView.didChangeText()
                    self.textView.undoManager?.setActionName("Typing")
                    self.textView.setSelectedRange(NSRange(location: caret, length: 0))
                }
                return false
            }
        }
        // Pending styles: the typed text goes in wrapped in their markers (caret stays inside the span).
        if !pendingStyles.isEmpty {
            let styles = pendingStyles
            pendingStyles = []
            if range.length == 0, range.location == pendingLoc, !rep.isEmpty, !rep.contains("\n") {
                let w = PendingStyleLogic.wrap(rep, styles)
                let at = range.location
                textEditing = false
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let ts = self.textView.textStorage, at <= ts.length else { return }
                    self.collapsingPairs = true
                    defer { self.collapsingPairs = false }
                    let r = NSRange(location: at, length: 0)
                    guard self.textView.shouldChangeText(in: r, replacementString: w.text) else { return }
                    ts.replaceCharacters(in: r, with: NSAttributedString(string: w.text, attributes: self.textView.typingAttributes))
                    self.textView.didChangeText()
                    self.textView.undoManager?.setActionName("Typing")
                    self.textView.setSelectedRange(NSRange(location: at + w.caret, length: 0))
                }
                return false
            }
        }
        let old = textView.string
        let text = old as NSString
        var g = range, widened = false
        if range.length > 0, (rep as NSString).length < range.length {
            var a = 0, b = 0, c = 0
            text.getParagraphStart(&a, end: &b, contentsEnd: &c, for: NSRange(location: range.location, length: 0))
            if NSMaxRange(range) <= c {
                let local = NSRange(location: range.location - a, length: range.length)
                if let wide = EmptyPairLogic.expand(line: text.substring(with: NSRange(location: a, length: c - a)), range: local, with: rep) {
                    g = NSRange(location: a + wide.location, length: wide.length); widened = true
                }
            }
        }
        let plain = text.replacingCharacters(in: g, with: rep)
        let caret = NSRange(location: g.location + (rep as NSString).length, length: 0)
        let listsChange = !paraMode && ListLogic.finish(plain, caret, old: old, at: g.location).text != plain
        guard widened || listsChange else { return true }
        textEditing = false
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.textView.string == old else { return }   // something else changed it first
            if self.paraMode { self.replaceWhole(g, with: rep) } else { self.commitListEdit(plain, caret, at: g.location) }
        }
        return false
    }
    var collapsingPairs = false
    func replaceWhole(_ g: NSRange, with rep: String, name: String = "Delete") {
        guard let ts = textView.textStorage, NSMaxRange(g) <= ts.length else { return }
        collapsingPairs = true
        defer { collapsingPairs = false }
        guard textView.shouldChangeText(in: g, replacementString: rep) else { return }
        let attrs = ts.attributes(at: min(g.location, max(ts.length - 1, 0)), effectiveRange: nil)
        ts.replaceCharacters(in: g, with: NSAttributedString(string: rep, attributes: attrs))
        textView.didChangeText()
        textView.undoManager?.setActionName(name)
        textView.setSelectedRange(NSRange(location: g.location + (rep as NSString).length, length: 0))
    }
    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange,
                  toCharacterRange new: NSRange) -> NSRange {
        guard !textEditing else { return new }
        let h = hiddenRanges()
        if new.length == 0 {
            return NSRange(location: HideLogic.snap(new.location, from: old.location, hidden: h.all + h.snapHeads, heads: h.snapHeads), length: 0)
        }
        // Selections: ends only move out of the middle of a marker (whole-line selections keep the marker).
        let a = HideLogic.snap(new.location, from: new.location + 1, hidden: h.all, heads: [])
        let b = HideLogic.snap(NSMaxRange(new), from: NSMaxRange(new) - 1, hidden: h.all, heads: [])
        return NSRange(location: a, length: max(0, b - a))
    }
    func snapCaretAfterEdit() {
        let sel = textView.selectedRange()
        guard sel.length == 0 else { return }
        let h = hiddenRanges()
        let p = HideLogic.snap(sel.location, from: sel.location, hidden: h.all + h.snapHeads, heads: h.snapHeads)
        if p != sel.location { textView.setSelectedRange(NSRange(location: p, length: 0)) }
    }
    // Delete keys next to hidden markers act on visible text (one undo step).
    func deleteAroundHidden(forward: Bool) -> Bool {
        let sel = textView.selectedRange()
        guard sel.length == 0, let ts = textView.textStorage else { return false }
        let h = hiddenRanges()
        let range = forward ? HideLogic.forwardDelete(sel.location, hidden: h.all, length: ts.length)
                            : HideLogic.backspace(sel.location, hidden: h.all, heads: h.heads)
        guard let r = range else { return false }
        guard r.length > 0 else { return true }            // nothing visible to delete
        guard textView.shouldChangeText(in: r, replacementString: "") else { return true }
        ts.replaceCharacters(in: r, with: "")
        let caret = forward ? sel.location : (h.heads.contains(r) ? r.location : sel.location - 1)
        textView.setSelectedRange(NSRange(location: min(caret, ts.length), length: 0))
        textView.didChangeText()                           // may also drop an emptied marker pair
        return true
    }

    // MARK: style markers (**bold** *italic* <u>underline</u> ==highlight== ~~strike~~)

    // Whole-note settings (were per-paragraph / per-title in notes.rtf).


    // Draw the note from its markers: reset to plain, style text between markers, hide markers off the caret line.
    func applyMarkers() {
        guard let ts = textView.textStorage, let lm = textView.layoutManager as? RuleLayoutManager else { return }
        let text = ts.string as NSString
        let all = NSRange(location: 0, length: text.length)
        let fm = NSFontManager.shared
        let base = noteFont(fontSize)
        var hidden: [NSRange] = []
        ts.beginEditing()
        ts.addAttribute(.font, value: base, range: all)
        ts.removeAttribute(.underlineStyle, range: all)
        ts.removeAttribute(.strikethroughStyle, range: all)
        ts.removeAttribute(.backgroundColor, range: all)
        ts.removeAttribute(.kern, range: all)
        ts.removeAttribute(.strokeWidth, range: all)
        ts.enumerateAttribute(.foregroundColor, in: all) { v, r, _ in          // list numbers keep their blue
            ts.addAttribute(.foregroundColor, value: bodyColor, range: r)
        }
        let align = NSTextAlignment.left                   // all text is left-aligned
        let mult = FullscreenLogic.lineMultiple(appDefaults.string(forKey: "fsLineSpacing"), fullscreen: fullOn)
        ts.enumerateAttribute(.paragraphStyle, in: all) { v, r, _ in
            let cur = (v as? NSParagraphStyle) ?? .default
            if cur.alignment != align || cur.lineHeightMultiple != mult {    // keeps indents/spacing; adds fullscreen spacing
                let ps = NSMutableParagraphStyle(); ps.setParagraphStyle(cur); ps.alignment = align; ps.lineHeightMultiple = mult
                ts.addAttribute(.paragraphStyle, value: ps, range: r)
            }
        }
        text.enumerateSubstrings(in: all, options: .byParagraphs) { sub, r, _, _ in
            guard let sub = sub else { return }
            for span in MarkerLogic.spans(sub) {
                let c = NSRange(location: r.location + span.content.location, length: span.content.length)
                switch span.style {
                case .bold, .italic:
                    let trait: NSFontTraitMask = span.style == .bold ? .boldFontMask : .italicFontMask
                    ts.enumerateAttribute(.font, in: c) { f, fr, _ in
                        ts.addAttribute(.font, value: fm.convert((f as? NSFont) ?? base, toHaveTrait: trait), range: fr)
                    }
                    if span.style == .bold {
                        // Extra synthetic weight (stroke follows the text color; widths unchanged) and pure white.
                        ts.addAttribute(.strokeWidth, value: -3.0, range: c)
                        ts.enumerateAttribute(.foregroundColor, in: c) { v, cr, _ in
                            if !isNeon(v) { ts.addAttribute(.foregroundColor, value: Theme.bold, range: cr) }
                        }
                    }
                case .underline: ts.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: c)
                case .strike: ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: c)
                case .highlight: ts.addAttribute(.foregroundColor, value: highlightOrange, range: c)
                }
                hidden.append(NSRange(location: r.location + span.open.location, length: span.open.length))
                hidden.append(NSRange(location: r.location + span.close.location, length: span.close.length))
            }
        }
        ts.endEditing()
        let old = lm.hiddenStyleMarkers
        lm.hiddenStyleMarkers = hidden
        for r in old + hidden where NSMaxRange(r) <= ts.length {
            lm.invalidateGlyphs(forCharacterRange: r, changeInLength: 0, actualCharacterRange: nil)
        }
        textView.typingAttributes[.font] = base
        textView.typingAttributes[.foregroundColor] = bodyColor
        textView.typingAttributes[.underlineStyle] = nil
        textView.typingAttributes[.strikethroughStyle] = nil
    }

    // ⌘B / ⌘I / ⌘U / ⇧⌘H / ⇧⌘X: add the markers around the selection (each line), remove them if
    // already there. No selection: nothing is inserted; the style waits for the next typed text.
    func toggleMarker(_ style: MarkerLogic.Style) {
        guard let ts = textView.textStorage else { return }
        let text = ts.string as NSString
        let sel = textView.selectedRange()

        if sel.length == 0 {
            // No selection: insert nothing. Caret at the end of this style's span: step out of it (style off).
            var a = 0, b = 0, c = 0
            text.getParagraphStart(&a, end: &b, contentsEnd: &c, for: sel)
            let local = sel.location - a
            if pendingStyles.isEmpty, let span = MarkerLogic.spans(text.substring(with: NSRange(location: a, length: c - a)))
                .first(where: { $0.style == style && NSMaxRange($0.content) == local }) {
                textView.setSelectedRange(NSRange(location: a + NSMaxRange(span.close), length: 0))
                flashStatus("\(PendingStyleLogic.name(style)) off")
                return
            }
            // Otherwise the style waits for the next typed text.
            if pendingLoc != sel.location { pendingStyles = [] }
            if pendingStyles.contains(style) { pendingStyles.remove(style) } else { pendingStyles.insert(style) }
            pendingLoc = sel.location
            flashStatus("\(PendingStyleLogic.name(style)) \(pendingStyles.contains(style) ? "on" : "off")")
            return
        }

        guard let t = MarkerLogic.toggleSelection(text, selection: sel, style: style) else { return }
        replaceStyled(t.whole, with: t.text, selecting: t.selection)
    }

    // One undoable "Style" edit: the replacement goes in with plain body attributes (refreshRules restyles).
    func replaceStyled(_ whole: NSRange, with out: String, selecting sel: NSRange) {
        guard let ts = textView.textStorage else { return }
        var plain: [NSAttributedString.Key: Any] = textView.typingAttributes
        plain[titleKey] = nil
        guard textView.shouldChangeText(in: whole, replacementString: out) else { return }
        ts.replaceCharacters(in: whole, with: NSAttributedString(string: out, attributes: plain))
        textView.didChangeText()
        textView.undoManager?.setActionName("Style")
        textView.setSelectedRange(sel)
    }

    // A mouse press in the note: on a list item line, double click = strike the item, ⌘+click or triple click = highlight it.
    // Returns true when handled; everything else (word selection, caret, drag, other ⌘+clicks) is left alone.
    func noteClick(_ event: NSEvent) -> Bool {
        guard event.window === panel, !listOpen, !navOpen, !paraMode, textView.isEditable,
              let lm = textView.layoutManager, let tc = textView.textContainer, lm.numberOfGlyphs > 0 else { return false }
        let action = ListClick.action(clickCount: event.clickCount, flags: event.modifierFlags)
        guard action != .none else { lastStrikeClick = nil; return false }
        let pt = textView.convert(event.locationInWindow, from: nil)
        let origin = textView.textContainerOrigin
        let p = NSPoint(x: pt.x - origin.x, y: pt.y - origin.y)
        let gi = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: nil)
        let frag = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
        guard p.y >= frag.minY, p.y < frag.maxY else { return false }            // a click below the last line is no line
        let loc = lm.characterIndexForGlyph(at: gi)
        let ns = textView.string as NSString
        let lineStart = ListLogic.lineBounds(ns, loc).start
        // a triple click: click 2 struck this item (still unchanged since) -> take that strike back, then highlight
        let struck = action == .triple && lastStrikeClick?.lineStart == lineStart && lastStrikeClick?.text == textView.string
        guard let t = ListClick.toggle(ns, at: loc, action, strikeApplied: struck) else { lastStrikeClick = nil; return false }
        replaceStyled(t.whole, with: t.text, selecting: NSRange(location: t.caret, length: 0))
        lastStrikeClick = action == .strike ? (lineStart, textView.string) : nil
        return true
    }
    var lastStrikeClick: (lineStart: Int, text: String)?

    // Find "---" paragraphs; hide their characters and draw a line, unless the caret is on them.
    func refreshRules() {
        // Paragraph mode: drop the full note's hidden list prefixes (stale offsets hid letters, e.g. "was tired" -> "watired").
        if let lm = textView.layoutManager as? RuleLayoutManager, let ts = textView.textStorage,
           ParaLogic.listPrefixesToHide(lm.hiddenListPrefixes, paraMode: paraMode).isEmpty, !lm.hiddenListPrefixes.isEmpty {
            lm.hiddenListPrefixes = []
            lm.invalidateGlyphs(forCharacterRange: NSRange(location: 0, length: ts.length), changeInLength: 0, actualCharacterRange: nil)
        }
        applyMarkers()
        if !paraMode { styleLists() }
        guard let lm = textView.layoutManager as? RuleLayoutManager, let ts = textView.textStorage else { return }
        let text = ts.string as NSString
        let all = NSRange(location: 0, length: text.length)
        let sel = textView.selectedRange()
        var rules: [NSRange] = []
        var doubles: Set<Int> = []
        var titles: [(line: NSRange, marker: NSRange, caretHere: Bool, sub: Bool)] = []
        text.enumerateSubstrings(in: all, options: .byParagraphs) { sub, r, _, _ in
            guard let sub = sub else { return }
            let caretHere = sel.location >= r.location && sel.location <= NSMaxRange(r) ||
                            NSIntersectionRange(sel, r).length > 0
            if let h = HeadingLogic.kind(sub) {               // "# " title, "## " subtitle
                titles.append((r, NSRange(location: r.location, length: h.markerLen), caretHere, h.kind == .subtitle))
                return
            }
            guard sub == "---" || sub == "===" else { return }
            rules.append(r); if sub == "===" { doubles.insert(r.location) }   // always drawn as a rule
        }

        let newHidden = titles.map { $0.marker }                 // markers always hidden, also on the caret line
        let oldHidden = lm.hiddenMarkers
        lm.hiddenMarkers = newHidden
        for r in oldHidden + newHidden where NSMaxRange(r) <= text.length {
            lm.invalidateGlyphs(forCharacterRange: r, changeInLength: 0, actualCharacterRange: nil)
        }
        // ## titles: bigger bold font (real attribute, tagged so we can undo it), drawn pink.
        let fm = NSFontManager.shared
        let titleLines = titles.map { $0.line }
        ts.beginEditing()
        ts.enumerateAttribute(titleKey, in: all) { v, r, _ in       // un-title lines that lost their ##
            guard v != nil, !titleLines.contains(where: { NSIntersectionRange($0, r).length > 0 }) else { return }
            ts.enumerateAttribute(.font, in: r) { f, fr, _ in
                if let f = f as? NSFont {
                    ts.addAttribute(.font, value: fm.convert(fm.convert(f, toNotHaveTrait: .boldFontMask), toSize: fontSize), range: fr)
                }
            }
            let para = text.paragraphRange(for: r)
            let old = (ts.attribute(.paragraphStyle, at: para.location, effectiveRange: nil) as? NSParagraphStyle) ?? .default
            let ps = NSMutableParagraphStyle(); ps.setParagraphStyle(old)
            ps.alignment = .left
            ts.addAttribute(.paragraphStyle, value: ps, range: para)
            ts.removeAttribute(titleKey, range: r)
            lm.invalidateGlyphs(forCharacterRange: r, changeInLength: 0, actualCharacterRange: nil)   // drop the capitals shown for titles
        }
        for t in titles where t.line.length > 0 {
            ts.enumerateAttribute(.font, in: t.line) { f, fr, _ in
                let base = (f as? NSFont) ?? NSFont.systemFont(ofSize: fontSize)
                let want = fm.convert(fm.convert(base, toHaveTrait: .boldFontMask), toSize: fontSize + (t.sub ? 10 : 20))
                if base != want { ts.addAttribute(.font, value: want, range: fr) }
            }
            ts.addAttribute(titleKey, value: true, range: t.line)
            let para = text.paragraphRange(for: t.line)
            let old = (ts.attribute(.paragraphStyle, at: para.location, effectiveRange: nil) as? NSParagraphStyle) ?? .default
            if old.alignment != .left {
                let ps = NSMutableParagraphStyle(); ps.setParagraphStyle(old); ps.alignment = .left
                ts.addAttribute(.paragraphStyle, value: ps, range: para)
            }
            lm.invalidateGlyphs(forCharacterRange: t.line, changeInLength: 0, actualCharacterRange: nil)
        }
        // Tutorial note only: violet bands behind the highlight section titles.
        ts.enumerateAttribute(bandKey, in: all) { v, r, _ in
            if v != nil { ts.removeAttribute(.backgroundColor, range: r); ts.removeAttribute(bandKey, range: r) }
        }
        if !paraMode, let u = noteFileURL, tutorialFiles.contains(u.lastPathComponent) {
            for t in titles where t.line.length > 0 && TutorialHighlight.isHighlight(titleLine: text.substring(with: t.line)) {
                let band = text.paragraphRange(for: t.line)
                ts.addAttribute(.backgroundColor, value: themeColor(TutorialHighlight.color, 0.30), range: band)
                ts.addAttribute(bandKey, value: true, range: band)
            }
        }
        ts.endEditing()
        // Don't carry the title look into a normal line you start typing on.
        if textView.typingAttributes[titleKey] != nil, !titles.contains(where: { $0.caretHere }) {
            textView.typingAttributes[titleKey] = nil
            if let f = textView.typingAttributes[.font] as? NSFont {
                textView.typingAttributes[.font] = fm.convert(fm.convert(f, toNotHaveTrait: .boldFontMask), toSize: fontSize)
            }
        }
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
        for r in rules {
            lm.addTemporaryAttribute(.foregroundColor, value: NSColor.clear, forCharacterRange: r)
            lm.addTemporaryAttribute(.backgroundColor, value: NSColor.clear, forCharacterRange: r)
        }
        for t in titles where t.line.length > 0 {
            let color = t.sub ? subtitleOrange : (titleStyle == .bar ? NSColor.white : titlePink)
            ts.enumerateAttribute(.foregroundColor, in: t.line) { v, r, _ in     // neon (⇧⌘H) text keeps its color
                if !isNeon(v) { lm.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: r) }
            }
        }
        lm.rules = rules
        lm.doubles = doubles
        lm.titles = titles.filter { !$0.sub }.map { $0.line }        // bar style: # only
        textView.needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        textEditing = false
        refreshRules()
        snapCaretAfterEdit()
        noteChanged()
        if infoShown { updateInfoStripText() }             // live word count while the strip is up
        // Replace All (find bar): save immediately. The action name is set right after this call.
        DispatchQueue.main.async { [weak self] in
            if self?.textView.undoManager?.undoActionName == "Replace All" { self?.saveNow() }
        }
        if settingsWindow?.isVisible == true { updateSettingsControls() }
    }

    // notes.txt is the only note file (styles are markers in the text).
    func loadNotes(_ font: NSFont) -> NSAttributedString {
        // F2 launch: make the library folder, fix nextNoteNumber, open the most recently changed note
        // (none = a new note with no file).
        let fm = FileManager.default
        try? fm.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        var files = NoteLibrary.noteFiles(in: libraryFolder)
        // Leftovers: empty notes go to the Trash (silent); tracked tutorial notes are asked about.
        for u in NoteCleanup.emptyFiles(files) where NoteCleanup.trash(u) { untrackTutorial(u) }
        files = NoteLibrary.noteFiles(in: libraryFolder)
        tutorialFiles = tutorialFiles.filter { n in files.contains { $0.lastPathComponent == n } }
        askQueue = NoteCleanup.tutorialLeftovers(tracked: tutorialFiles, files: files)
        let d = appDefaults
        d.set(NoteLibrary.nextNumber(stored: d.integer(forKey: "nextNoteNumber"), names: files.map { $0.lastPathComponent }),
              forKey: "nextNoteNumber")
        noteFileURL = nil                                // F4: every launch starts with a new note (⌘O opens older ones)
        // First launch ever: open the tutorial as a normal note instead of an empty one.
        if TutorialNote.shouldCreateAtLaunch(shown: d.bool(forKey: "tutorialShown"), noteCount: files.count),
           let url = newNoteFile(), AppDelegate.writeAtomically(TutorialNote.text, to: url) {
            d.set(true, forKey: "tutorialShown")
            tutorialFiles.append(url.lastPathComponent)
            launchedTutorial = true
            noteFileURL = url
            return NSAttributedString(string: TutorialNote.text, attributes: [.font: font, .foregroundColor: bodyColor])
        }
        // Every launch starts with a new, empty note (older notes are in ⌘O). The one-time format migrations of early
        // versions (notes.rtf, heading and list markers) never ran any more, since no note is open here: removed.
        return NSAttributedString(string: "", attributes: [.font: font, .foregroundColor: bodyColor])
    }

    // ⌘B / ⌘I / ⌘U: toggle on the selection, or on what you type next.
    func toggleStyle(_ key: String) {
        guard panel.firstResponder === textView, textView.isEditable, let ts = textView.textStorage else { return }
        if key == "caps" { toggleCaps(); return }
        if key == "titleRules" { toggleTitleRules(); return }
        switch key {
        case "b": toggleMarker(.bold); return
        case "i": toggleMarker(.italic); return
        case "u": toggleMarker(.underline); return
        case "h": toggleMarker(.highlight); return
        case "s": toggleMarker(.strike); return
        default: break
        }
        let fm = NSFontManager.shared
        let range = textView.selectedRange()
        let base = (textView.typingAttributes[.font] as? NSFont) ?? .systemFont(ofSize: fontSize)
        let first: [NSAttributedString.Key: Any] = range.length > 0 ? ts.attributes(at: range.location, effectiveRange: nil) : textView.typingAttributes

        func restyle(_ attrs: [NSAttributedString.Key: Any], _ turnOn: Bool) -> [NSAttributedString.Key: Any] {
            var a = attrs
            if key == "u" {
                a[.underlineStyle] = turnOn ? NSUnderlineStyle.single.rawValue : nil
            } else if key == "s" {
                a[.strikethroughStyle] = turnOn ? NSUnderlineStyle.single.rawValue : nil
            } else if key == "h" {
                a[.backgroundColor] = nil
                a[.foregroundColor] = turnOn ? highlightOrange : bodyColor   // restyle passes re-color titles/numbers
            } else {
                let trait: NSFontTraitMask = key == "b" ? .boldFontMask : .italicFontMask
                let f = (a[.font] as? NSFont) ?? base
                a[.font] = turnOn ? fm.convert(f, toHaveTrait: trait) : fm.convert(f, toNotHaveTrait: trait)
            }
            return a
        }
        let isOn: Bool
        if key == "u" { isOn = ((first[.underlineStyle] as? Int) ?? 0) != 0 }
        else if key == "s" { isOn = ((first[.strikethroughStyle] as? Int) ?? 0) != 0 }
        else if key == "h" { isOn = isNeon(first[.foregroundColor]) || first[.backgroundColor] != nil }
        else {
            let trait: NSFontTraitMask = key == "b" ? .boldFontMask : .italicFontMask
            isOn = fm.traits(of: (first[.font] as? NSFont) ?? base).contains(trait)
        }

        if range.length == 0 {
            textView.typingAttributes = restyle(textView.typingAttributes, !isOn)
            return
        }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        ts.beginEditing()
        ts.enumerateAttributes(in: range) { attrs, r, _ in ts.setAttributes(restyle(attrs, !isOn), range: r) }
        ts.endEditing()
        textView.didChangeText()
    }

    // ⇧⌘A: ALL CAPS the selection (or the word at/just before the caret); lowercase if already all caps.
    func toggleCaps() {
        guard let ts = textView.textStorage else { return }
        let text = ts.string as NSString
        var range = textView.selectedRange()
        let hadSelection = range.length > 0
        if !hadSelection {
            let isWord: (unichar) -> Bool = { c in
                guard let u = UnicodeScalar(c) else { return false }
                return CharacterSet.alphanumerics.contains(u) || c == 39 /* ' */
            }
            var start = range.location, end = range.location
            while start > 0, isWord(text.character(at: start - 1)) { start -= 1 }
            while end < text.length, isWord(text.character(at: end)) { end += 1 }
            range = NSRange(location: start, length: end - start)
        }
        guard range.length > 0 else { return }
        let original = text.substring(with: range)
        let upper = original == original.uppercased() && original != original.lowercased()
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        ts.enumerateAttributes(in: range) { attrs, r, _ in runs.append((r, attrs)) }
        var newLength = 0
        ts.beginEditing()
        for (r, attrs) in runs.reversed() {
            let piece = text.substring(with: r)
            let changed = upper ? piece.lowercased() : piece.uppercased()
            ts.replaceCharacters(in: r, with: NSAttributedString(string: changed, attributes: attrs))
            newLength += (changed as NSString).length
        }
        ts.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName(upper ? "Lowercase" : "Uppercase")
        let caret = textView.selectedRange().location
        if hadSelection {
            textView.setSelectedRange(NSRange(location: range.location, length: newLength))
        } else {
            let delta = newLength - range.length
            textView.setSelectedRange(NSRange(location: caret >= NSMaxRange(range) ? caret + delta : min(caret, range.location + newLength), length: 0))
        }
    }

    // MARK: saving (F1)

    var noteFileURL: URL?                                // the path of the open note (nil = a new note with no file yet)
    var saveTimes = SaveScheduler()
    var saveTimer: Timer?
    var retryTimer: Timer?
    var lastSavedText: String?                           // what the file holds (nil = unknown)
    var saveFailed = false
    var saveError: NSTextField?
    let saveQueue = DispatchQueue(label: "FloatNote.save")    // one serial queue for all writes
    let clock = { ProcessInfo.processInfo.systemUptime }

    // The note text to save. Paragraph mode shows a split view; the stashed full note is saved.
    func currentNoteText() -> String? {
        (paraMode ? paraStash : textView?.textStorage).map { $0.string }
    }

    // A typing change: save on the timer rules.
    func noteChanged() {
        saveTimes.changed(at: clock())
        armSaveTimer()
    }

    func armSaveTimer() {
        saveTimer?.invalidate()
        guard let due = saveTimes.dueAt else { saveTimer = nil; return }
        saveTimer = Timer.scheduledTimer(withTimeInterval: max(0, due - clock()), repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.saveTimes.isDue(at: self.clock()) { self.saveNow() } else { self.armSaveTimer() }
        }
    }

    // Save now (feature changes, background, sleep, timer). wait = block until written (quit).
    func saveNow(wait: Bool = false) {
        saveTimer?.invalidate(); saveTimer = nil
        saveTimes.saved()
        guard let text = currentNoteText() else { return }
        if text == lastSavedText && !saveFailed { return }        // no change since the last save
        // F2: a new note gets its file with its first character; a note with no characters gets none.
        if noteFileURL == nil {
            guard NoteLibrary.needsFile(text: text, hasFile: false) else { return }
            guard let url = newNoteFile() else { saveFinished(text, ok: false); return }
            noteFileURL = url
        }
        guard let url = noteFileURL else { return }
        let work = {
            let ok = AppDelegate.writeAtomically(PendingStyleLogic.stripEmptyPairs(text), to: url)   // never save empty marker pairs
            let done: () -> Void = { [weak self] in self?.saveFinished(text, ok: ok) }
            if Thread.isMainThread { done() } else { DispatchQueue.main.async(execute: done) }
        }
        if wait { saveQueue.sync(execute: work) } else { saveQueue.async(execute: work) }
    }

    // A new file name from nextNoteNumber; the number is used up even if that name already exists.
    func newNoteFile() -> URL? {
        let d = appDefaults
        try? FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        for _ in 0..<1000 {
            let n = max(d.integer(forKey: "nextNoteNumber"), 1)
            d.set(n + 1, forKey: "nextNoteNumber")
            let url = libraryFolder.appendingPathComponent(NoteLibrary.fileName(number: n, date: Date()))
            if !FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    // Write to a temporary file in the same folder, then rename it over the note (keeps its creation date).
    static func writeAtomically(_ text: String, to url: URL) -> Bool { NoteLibrary.writeAtomically(text, to: url) }

    func saveFinished(_ text: String, ok: Bool) {
        if ok {
            lastSavedText = text
            saveFailed = false
            retryTimer?.invalidate(); retryTimer = nil
            saveError?.isHidden = true
            return
        }
        saveFailed = true
        showSaveError()
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in self?.saveNow() }
    }

    func showSaveError() {
        if saveError == nil, let content = panel.contentView {
            let l = NSTextField(labelWithString: "Not saved")
            l.font = status.font
            l.textColor = .systemRed
            l.frame = NSRect(x: 12, y: status.frame.minY, width: 120, height: 13)
            l.autoresizingMask = [.minYMargin]
            content.addSubview(l, positioned: .above, relativeTo: nil)
            saveError = l
        }
        saveError?.isHidden = false
    }

    func setStatus(_ text: String) {
        status?.stringValue = text
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
