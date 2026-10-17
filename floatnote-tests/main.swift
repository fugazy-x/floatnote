import Cocoa

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS  " : "FAIL  ") + name + (ok || detail.isEmpty ? "" : "  -> " + detail))
    if !ok { failures += 1 }
}
func styles(_ line: String) -> [MarkerLogic.Style] {
    MarkerLogic.spans(line).sorted { $0.open.location < $1.open.location }.map { $0.style }
}
func contents(_ line: String) -> [String] {
    MarkerLogic.spans(line).sorted { $0.open.location < $1.open.location }
        .map { (line as NSString).substring(with: $0.content) }
}

// Marker finder
var r = styles("**bold** and *italic*")
check("bold + italic", r == [.bold, .italic], "\(r)")
check("bold/italic contents", contents("**bold** and *italic*") == ["bold", "italic"], "\(contents("**bold** and *italic*"))")
r = styles("5 * 3 * 2");                   check("5 * 3 * 2 -> none", r.isEmpty, "\(r)")
r = styles("**word");                      check("**word -> none", r.isEmpty, "\(r)")
r = styles("~~old~~ ==new== <u>under</u>"); check("strike, highlight, underline", r == [.strike, .highlight, .underline], "\(r)")
check("strike/highlight/underline contents", contents("~~old~~ ==new== <u>under</u>") == ["old", "new", "under"])
r = styles("**==word==**");                check("bold + highlight nested", Set(r) == [.bold, .highlight] && r.count == 2, "\(r)")
check("nested contents", Set(contents("**==word==**")) == ["==word==", "word"], "\(contents("**==word==**"))")
r = styles("** not bold**");               check("opening followed by space -> none", r.isEmpty, "\(r)")
r = styles("**a**\n**b**".components(separatedBy: "\n")[0]); check("pair within one line", r == [.bold])

// RTF -> markers conversion
let base = NSFont(name: "CourierPrimeSans-Regular", size: 13) ?? NSFont(name: "Courier", size: 13)!
let fm = NSFontManager.shared
let neon = NSColor(srgbRed: 0.902, green: 1.0, blue: 0.0, alpha: 1.0)
let doc = NSMutableAttributedString()
func add(_ t: String, _ extra: [NSAttributedString.Key: Any] = [:], font: NSFont? = nil) {
    var a: [NSAttributedString.Key: Any] = [.font: font ?? base, .foregroundColor: NSColor.white]
    for (k, v) in extra { a[k] = v }
    doc.append(NSAttributedString(string: t, attributes: a))
}
add("## Title\n", font: fm.convert(base, toHaveTrait: .boldFontMask))
add("bold", font: fm.convert(base, toHaveTrait: .boldFontMask)); add(" ")
add("it", font: fm.convert(base, toHaveTrait: .italicFontMask)); add(" ")
add("un", [.underlineStyle: NSUnderlineStyle.single.rawValue]); add(" ")
add("st", [.strikethroughStyle: NSUnderlineStyle.single.rawValue]); add(" ")
add("hi", [.foregroundColor: neon]); add(" ")
add("bg", [.backgroundColor: NSColor.yellow]); add("\n")
add("plain line")
let rtf = doc.rtf(from: NSRange(location: 0, length: doc.length), documentAttributes: [:])!
let back = NSAttributedString(rtf: rtf, documentAttributes: nil)!
let converted = MarkerLogic.convert(back)
let expected = "## Title\n**bold** *it* <u>un</u> ~~st~~ ==hi== ==bg==\nplain line"
check("RTF conversion", converted == expected, "got: \(converted.debugDescription)")
// round trip: converted markers parse back to the same styles
let line2 = converted.components(separatedBy: "\n")[1]
check("converted line re-parses", styles(line2) == [.bold, .italic, .underline, .strike, .highlight, .highlight], "\(styles(line2))")

// Heading line rules (Task 2)
check("\"# A\" is a title", HeadingLogic.kind("# A")?.kind == .title)
check("\"## B\" is a subtitle", HeadingLogic.kind("## B")?.kind == .subtitle)
check("\"### C\" is plain", HeadingLogic.kind("### C") == nil)
check("\"#D\" is a title (no space needed)", HeadingLogic.kind("#D").map { $0.kind == .title && $0.markerLen == 1 } ?? false)
check("\"##D\" is a subtitle", HeadingLogic.kind("##D").map { $0.kind == .subtitle && $0.markerLen == 2 } ?? false)
check("\"###D\" is plain", HeadingLogic.kind("###D") == nil && HeadingLogic.kind("####") == nil)
check("#Hello: clean text + row name", ExportLogic.cleanText(ExportLogic.parse("#Hello\n##Sub\nx")) .hasPrefix("Hello\nSub") && NoteLibrary.rowName("##Sub **x**") == "Sub x", ExportLogic.cleanText(ExportLogic.parse("#Hello\n##Sub\nx")))
check("\" # E\" is plain", HeadingLogic.kind(" # E") == nil)
// Heading conversion
check("##A -> # A", HeadingLogic.convertLine("##A") == "# A", HeadingLogic.convertLine("##A"))
check("## A -> # A", HeadingLogic.convertLine("## A") == "# A", HeadingLogic.convertLine("## A"))
check("%%B -> ## B", HeadingLogic.convertLine("%%B") == "## B", HeadingLogic.convertLine("%%B"))
check("%% B -> ## B", HeadingLogic.convertLine("%% B") == "## B", HeadingLogic.convertLine("%% B"))
check("Plain unchanged", HeadingLogic.convertLine("Plain") == "Plain")
let note = "##A\n%% B\nPlain\n\n## C\r\n%%D"
check("whole note, one pass per line", HeadingLogic.convert(note) == "# A\n## B\nPlain\n\n# C\r\n## D", HeadingLogic.convert(note).debugDescription)

// ⌃⌥S append format
let d = DateComponents(calendar: Calendar.current, year: 2026, month: 10, day: 13, hour: 9, minute: 5).date!
check("clip with URL", ClipLogic.appended(selection: "Hi", app: "Safari", url: "https://a.b", date: d, note: "Note") == "\n===\n\nHi\nSource: Safari | https://a.b | 2026-10-13 09:05")
check("clip no URL", ClipLogic.appended(selection: "Hi", app: "Notes", url: nil, date: d, note: "Note\n") == "===\n\nHi\nSource: Notes | 2026-10-13 09:05")
check("clip empty note", ClipLogic.appended(selection: "Hi", app: "Notes", url: nil, date: d, note: "") == "===\n\nHi\nSource: Notes | 2026-10-13 09:05")
check("clip two lines", ClipLogic.appended(selection: "A\nB", app: "Mail", url: nil, date: d, note: "") == "===\n\nA\nB\nSource: Mail | 2026-10-13 09:05")

// Right Option tap
var tap = RightOptionTap()
_ = tap.flags(keyCode: 61, rightOptionDown: true, otherModifiers: false, time: 1.0)
check("right option tap", tap.flags(keyCode: 61, rightOptionDown: false, otherModifiers: false, time: 1.2))
_ = tap.flags(keyCode: 61, rightOptionDown: true, otherModifiers: false, time: 2.0)
check("slow tap ignored", !tap.flags(keyCode: 61, rightOptionDown: false, otherModifiers: false, time: 2.5))
_ = tap.flags(keyCode: 61, rightOptionDown: true, otherModifiers: false, time: 3.0); tap.interrupt()
check("option+key ignored", !tap.flags(keyCode: 61, rightOptionDown: false, otherModifiers: false, time: 3.1))
_ = tap.flags(keyCode: 58, rightOptionDown: false, otherModifiers: true, time: 4.0)
check("left option ignored", !tap.flags(keyCode: 58, rightOptionDown: false, otherModifiers: false, time: 4.1))
_ = tap.flags(keyCode: 61, rightOptionDown: true, otherModifiers: false, time: 5.0)
_ = tap.flags(keyCode: 56, rightOptionDown: true, otherModifiers: true, time: 5.05)
check("with shift ignored", !tap.flags(keyCode: 61, rightOptionDown: false, otherModifiers: false, time: 5.1))

// Navigator filter
let navItems: [(text: String, sub: Bool)] = [("CHESS", false), ("ITALIAN GAME", true), ("SICILIAN", true), ("WEEKLY PLAN", false), ("MONDAY", true)]
check("filter empty shows all", NavFilter.visible(navItems, query: "") == [0, 1, 2, 3, 4])
check("filter subtitle keeps parent", NavFilter.visible(navItems, query: "sicil") == [0, 2])
check("filter title only", NavFilter.visible(navItems, query: "weekly") == [3])
check("filter case-insensitive, both groups", NavFilter.visible(navItems, query: "an") == [0, 1, 2, 3])
check("filter no match", NavFilter.visible(navItems, query: "zzz").isEmpty)

// Task 8: export
let testNote = """
# Interview notes
## Questions
1. First question with **bold** and *italic*
2. Sub-question with ==highlight==
3. Third level with ~~old text~~
4. Second question with <u>underline</u>
---
Plain line one.
Plain line two.
===
"""
let blocks = ExportLogic.parse(testNote)
check("parse kinds", blocks.map { $0.kind } == [.title, .subtitle, .listItem(number: 1), .listItem(number: 2),
      .listItem(number: 3), .listItem(number: 4), .rule, .paragraph, .paragraph, .doubleRule], "\(blocks.map { $0.kind })")
check("parse spans", blocks[2].spans.count == 2 && blocks[3].spans.first?.style == .highlight && blocks[4].spans.first?.style == .strike
      && blocks[5].spans.first?.style == .underline)
// Clean text (⌃⌘G plain-text flavor)
let clean = ExportLogic.cleanText(blocks)
check("clean text equals expected", clean == "Interview notes\nQuestions\n1. First question with bold and italic\n2. Sub-question with highlight\n3. Third level with old text\n4. Second question with underline\n\nPlain line one.\nPlain line two.\n", clean.debugDescription)
let clean2 = ExportLogic.cleanText(ExportLogic.parse("#< **Big** title\n##> Sub\n---\n3. ==hi== <u>u</u> ~~s~~ *i*\n===\nend"))
check("clean text: title, list, bold, highlight, underline, rule", clean2 == "Big title\nSub\n\n3. hi u s i\n\nend", clean2.debugDescription)
check("clean text: no markers remain", !["**", "==", "~~", "<u>", "</u>", "# ", "#<", "#>", "---", "==="].contains { clean2.contains($0) || clean.contains($0) })
check("clean text: unpaired markers stay", ExportLogic.cleanText(ExportLogic.parse("5 * 3 * 2 **open")) == "5 * 3 * 2 **open")
let html = ExportLogic.html(blocks)
for piece in ["<meta charset=\"utf-8\">",
              "<h1><span style=\"color:#FF2020;font-weight:bold\">INTERVIEW NOTES</span></h1>",
              "<h2><span style=\"color:#FF2020;font-weight:bold\">QUESTIONS</span></h2>",
              "<b>bold</b>", "<i>italic</i>", "<u>underline</u>",
              "<span style=\"text-decoration:line-through\">old text</span>",
              "<span style=\"background-color:#FF8800\">highlight</span>",
              "<hr>", "<hr><hr>", "<ol style=\"list-style-type:decimal\"><li style=\"list-style-type:decimal\">First",
              "<li style=\"list-style-type:decimal\">Sub-question", "<li style=\"list-style-type:decimal\">Third",
              "<p>Plain line one.</p>"] {
    check("html has " + piece, html.contains(piece))
}
check("html no <style> block", !html.contains("<style"))
check("html escapes", ExportLogic.html(ExportLogic.parse("a & <b>")).contains("<p>a &amp; &lt;b&gt;</p>"))
check("html title escape stays lowercase entity", ExportLogic.html(ExportLogic.parse("# a & b")).contains("A &amp; B"))
check("html empty line", ExportLogic.html(ExportLogic.parse("a\n\nb")).contains("<p><br></p>"))
check("html no text-align anywhere", !ExportLogic.html(ExportLogic.parse("# T\n## S\na\n1. b")).contains("text-align"))
try? html.write(toFile: NSHomeDirectory() + "/Downloads/sample-export.html", atomically: true, encoding: .utf8)

// Paragraph rejoin (paragraph mode exit + export)
check("rejoin sentences", ParaLogic.rejoin(NSAttributedString(string: "One.  \n  Two **b**.\n\nThree.")).string == "One. Two **b**. Three.")
check("rejoin export clean", ExportLogic.cleanText(ExportLogic.parse(ParaLogic.rejoin(NSAttributedString(string: "A ==x==.\nB.")).string)) == "A x. B.")

// Task 8 regressions (real-note-like lines)
let orchard = "## Tasks\n1. Prune the plum trees\n2. Start with the old plum rows\n3. Check each branch for rot\n4. Move to the young trees\n5. Pick the plums"
check("real list clean text", ExportLogic.cleanText(ExportLogic.parse(orchard)) == "Tasks\n1. Prune the plum trees\n2. Start with the old plum rows\n3. Check each branch for rot\n4. Move to the young trees\n5. Pick the plums")
let partial = "2. Start with the old plum rows\n3. Check each branch for rot\n4. Move to the young trees"
check("selection starting mid-list keeps its numbers", ExportLogic.cleanText(ExportLogic.parse(partial)) == partial)
let h = ExportLogic.html(ExportLogic.parse(orchard + "\n\nPlain."))
check("html no whitespace between blocks", !h.contains(">\n") && !h.contains("> <"))
check("html every li decimal", h.components(separatedBy: "<li>").count == 1)
check("no stray chars in html text", h.replacingOccurrences(of: "<[^>]+>", with: "|", options: .regularExpression).split(separator: "|").allSatisfy { !$0.hasPrefix(" ") && !$0.hasSuffix(" ") })

// Export edge cases
func body(_ t: String) -> String {
    let h = ExportLogic.html(ExportLogic.parse(t))
    return h.components(separatedBy: "<body>")[1].replacingOccurrences(of: "</body></html>", with: "")
}
func unescapeHTML(_ s: String) -> String {
    s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
}
// Visible text of a line as the box shows it: style markers removed.
func visibleText(_ line: String) -> String {
    let ns = NSMutableString(string: line)
    let cut = MarkerLogic.spans(line).flatMap { [$0.open, $0.close] }.sorted { $0.location > $1.location }
    for r in cut { ns.deleteCharacters(in: r) }
    return ns as String
}
check("***bold italic***", body("***bold italic***") == "<p><b><i>bold italic</i></b></p>", body("***bold italic***"))
check("bold with italic inside", body("**bold *ital* bold**") == "<p><b>bold </b><b><i>ital</i></b><b> bold</b></p>")
check("markers at start and end", body("**start** mid **end**") == "<p><b>start</b> mid <b>end</b></p>")
check("unclosed markers stay text", body("**open only") == "<p>**open only</p>" && body("<u>open") == "<p>&lt;u&gt;open</p>")
check("adjacent spans", body("~~s~~==h==<u>u</u>") == "<p><span style=\"text-decoration:line-through\">s</span><span style=\"background-color:#FF8800\">h</span><u>u</u></p>")
check("adjacent bold", body("**a****b**") == "<p><b>a</b><b>b</b></p>")
check("title with styles + escape", body("# **Big** & <x>").contains("<b>BIG</b> &amp; &lt;X&gt;"))
check("single * and = stay", body("5 * 3 = 15 and a=b") == "<p>5 * 3 = 15 and a=b</p>")
check("emoji before closing marker", body("Café 🍑 **naïve 🍐**") == "<p>Café 🍑 <b>naïve 🍐</b></p>", body("Café 🍑 **naïve 🍐**"))
check("emoji after opening marker", body("**🍐 pear**") == "<p><b>🍐 pear</b></p>")
check("&<> escaped in every block", body("# a&<>\n## b&<>\n1. c&<>\nd&<>") .components(separatedBy: "&amp;&lt;&gt;").count == 5)
check("trailing spaces dropped", ExportLogic.cleanText(ExportLogic.parse("trailing   \n1. item  ")) == "trailing\n1. item" && !body("x  ").contains("x "))
check("CRLF", ExportLogic.cleanText(ExportLogic.parse("a\r\n1. b\r\n2. c\r\n")) == "a\n1. b\n2. c")
let samples = ["***bold italic***", "**bold *ital* bold**", "Café 🍑 **naïve 🍐** ~~x~~", "a <u>u</u> & ==h== *i*", "5 * 3 = 15", "**a****b**", "x **open"]
for line in samples {
    let text = unescapeHTML(body(line).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
    check("no chars lost/duplicated: " + line, text == visibleText(line), text.debugDescription + " vs " + visibleText(line).debugDescription)
    check("clean text = visible text: " + line, ExportLogic.cleanText(ExportLogic.parse(line)) == visibleText(line))
}

// Right Command tap (same detector, key 54)
var ctap = RightOptionTap(key: 54)
_ = ctap.flags(keyCode: 54, rightOptionDown: true, otherModifiers: false, time: 1.0)
check("right command tap", ctap.flags(keyCode: 54, rightOptionDown: false, otherModifiers: false, time: 1.2))
_ = ctap.flags(keyCode: 54, rightOptionDown: true, otherModifiers: false, time: 2.0)
check("cmd slow tap ignored", !ctap.flags(keyCode: 54, rightOptionDown: false, otherModifiers: false, time: 2.5))
_ = ctap.flags(keyCode: 54, rightOptionDown: true, otherModifiers: false, time: 3.0); ctap.interrupt()
check("cmd+key ignored", !ctap.flags(keyCode: 54, rightOptionDown: false, otherModifiers: false, time: 3.1))
_ = ctap.flags(keyCode: 55, rightOptionDown: false, otherModifiers: true, time: 4.0)
check("left command ignored", !ctap.flags(keyCode: 55, rightOptionDown: false, otherModifiers: false, time: 4.1))
_ = ctap.flags(keyCode: 54, rightOptionDown: true, otherModifiers: false, time: 5.0)
_ = ctap.flags(keyCode: 56, rightOptionDown: true, otherModifiers: true, time: 5.05)
check("cmd with shift ignored", !ctap.flags(keyCode: 54, rightOptionDown: false, otherModifiers: false, time: 5.1))
_ = ctap.flags(keyCode: 61, rightOptionDown: true, otherModifiers: false, time: 6.0)
check("option key doesn't trigger cmd tap", !ctap.flags(keyCode: 61, rightOptionDown: false, otherModifiers: false, time: 6.1))

// Themes
check("six themes", ThemeLogic.all.map { $0.name } == ["Graphite", "Fog", "Parchment", "Sorbet", "Arcade", "Harbor"])
check("lookup", ThemeLogic.named("Arcade").highlight == 0x36F9F6 && ThemeLogic.named("Harbor").dark && !ThemeLogic.named("Sorbet").dark)
check("unknown name -> first theme", ThemeLogic.named("Nope").name == "Graphite" && ThemeLogic.named(nil).name == "Graphite")
check("themes: exact values", ThemeLogic.named("Graphite") == ThemeSpec(name: "Graphite", dark: true, bg: 0x151515, text: 0xC8C8C8, title: 0x909090, highlight: 0xFFB454, bold: 0xE6E6E6)
      && ThemeLogic.named("Fog") == ThemeSpec(name: "Fog", dark: false, bg: 0xF3F3F3, text: 0x1F1F1F, title: 0x666666, highlight: 0x000000)
      && ThemeLogic.named("Harbor") == ThemeSpec(name: "Harbor", dark: true, bg: 0x0A0D14, text: 0xCBD5F0, title: 0x7AA2F7, highlight: 0x5DE4C7)
      && ThemeLogic.named("Parchment") == ThemeSpec(name: "Parchment", dark: false, bg: 0xFFFCF0, text: 0x100F0F, title: 0x1C6C66, highlight: 0xBC5215)
      && ThemeLogic.named("Arcade") == ThemeSpec(name: "Arcade", dark: true, bg: 0x1C1330, text: 0xF1E9FF, title: 0xFF7EDB, highlight: 0x36F9F6)
      && ThemeLogic.named("Sorbet") == ThemeSpec(name: "Sorbet", dark: false, bg: 0xFFF3F8, text: 0x2E1A47, title: 0xC2185B, highlight: 0x0050D0))
check("dark flags: Graphite, Arcade, Harbor dark; Fog, Parchment, Sorbet light", ThemeLogic.all.filter { $0.dark }.map { $0.name } == ["Graphite", "Arcade", "Harbor"])
check("no ↑/↓ theme keys in shortcut list", !ShortcutList.all.contains { $0.scope == "settings" && $0.keys.contains("↑") })
check("migrate default: new users get Harbor", ThemeLogic.migrate(theme: nil, appearance: nil) == "Harbor" && ThemeLogic.defaultTheme == "Harbor")
check("migrate old names", [("Dark", "Graphite"), ("Light", "Fog"), ("Newsprint", "Parchment"), ("Plum Jam", "Sorbet"), ("Moss", "Arcade"), ("Harbor", "Harbor")].allSatisfy { ThemeLogic.migrate(theme: $0.0, appearance: nil) == $0.1 })
check("migrate appearance light -> Fog", ThemeLogic.migrate(theme: nil, appearance: "light") == "Fog")
check("migrate keeps a saved new theme", ThemeLogic.migrate(theme: "Sorbet", appearance: "light") == "Sorbet")
check("migrate bad saved theme", ThemeLogic.migrate(theme: "Bogus", appearance: nil) == "Harbor")
check("every migrated name exists", ThemeLogic.renamed.values.allSatisfy { v in ThemeLogic.all.contains { $0.name == v } })
check("hex + rgb", ThemeLogic.hex(0x7D5A7E) == "#7D5A7E" && ThemeLogic.rgb(0xFF8000).g > 0.5 && ThemeLogic.rgb(0xFF8000).b == 0)
let hlc = ThemeLogic.rgb(0xF07BFF)
check("highlight recognized (new + all old colors)", ThemeLogic.isHighlight(r: hlc.r, g: hlc.g, b: hlc.b) && ThemeLogic.isHighlight(r: 1, g: 136.0/255, b: 0) && ThemeLogic.isHighlight(r: 0.902, g: 1, b: 0))
check("old theme highlights still count as highlights", [0xFF7C4D, 0xD9480F, 0xE01E1E, 0xF07BFF, 0xB5FF3B, 0x3DA9FF, 0xFF8800, 0xE6FF00].allSatisfy { h in let c = ThemeLogic.rgb(UInt32(h)); return ThemeLogic.isHighlight(r: c.r, g: c.g, b: c.b) })
check("new theme highlights count as highlights", ThemeLogic.all.allSatisfy { t in let c = ThemeLogic.rgb(t.highlight); return ThemeLogic.isHighlight(r: c.r, g: c.g, b: c.b) })
func lum(_ h: UInt32) -> Double {
    let c = ThemeLogic.rgb(h); func f(_ v: CGFloat) -> Double { let x = Double(v); return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
    return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b)
}
func contrast(_ a: UInt32, _ b: UInt32) -> Double { let x = lum(a), y = lum(b); return (max(x, y) + 0.05) / (min(x, y) + 0.05) }
for t in ThemeLogic.all {
    check(t.name + ": body text >= 10:1", contrast(t.text, t.bg) >= 10, "\(contrast(t.text, t.bg))")
    check(t.name + ": title >= 4.5:1", contrast(t.title, t.bg) >= 4.5, "\(contrast(t.title, t.bg))")
    check(t.name + ": highlight >= 4.5:1", contrast(t.highlight, t.bg) >= 4.5, "\(contrast(t.highlight, t.bg))")
    let bold = ThemeLogic.boldColor(t)
    check(t.name + ": bold >= 10:1 and differs from the highlight", contrast(bold, t.bg) >= 10 && bold != t.highlight)
    // hint = text at 60% / 65% over the background
    let a = ThemeLogic.hintAlpha(dark: t.dark), tc = ThemeLogic.rgb(t.text), bc = ThemeLogic.rgb(t.bg)
    func mixc(_ f: CGFloat, _ b: CGFloat) -> UInt32 { UInt32((f * a + b * (1 - a)) * 255 + 0.5) }
    let hint = mixc(tc.r, bc.r) << 16 | mixc(tc.g, bc.g) << 8 | mixc(tc.b, bc.b)
    check(t.name + ": hint >= 4.5:1", contrast(hint, t.bg) >= 4.5, "\(contrast(hint, t.bg))")
    // body text, titles and bold text must never be mistaken for highlighted text (highlights are found by color)
    for (what, h) in [("text", t.text), ("title", t.title), ("bold", bold)] {
        let c = ThemeLogic.rgb(h)
        check(t.name + ": " + what + " is not read as a highlight", !ThemeLogic.isHighlight(r: c.r, g: c.g, b: c.b))
    }
}
check("hint alpha 60% dark / 65% light", ThemeLogic.hintAlpha(dark: true) == 0.60 && ThemeLogic.hintAlpha(dark: false) == 0.65)
check("bold: Graphite own, other dark white, light = text", ThemeLogic.boldColor(ThemeLogic.named("Graphite")) == 0xE6E6E6 && ThemeLogic.boldColor(ThemeLogic.named("Harbor")) == 0xFFFFFF && ThemeLogic.boldColor(ThemeLogic.named("Fog")) == 0x1F1F1F)
check("opacity floor is 40% (aligned with the 10% keys); at-rest 5%/2.5% untouched", ThemeLogic.minOpacity == 0.4 && RestAlphaLogic.rest(dark: true) == 0.05 && RestAlphaLogic.rest(dark: false) == 0.025)

// Font setting
check("font default retro", FontLogic.normalize(nil) == "retro" && FontLogic.normalize("comic") == "retro")
check("font values kept", FontLogic.normalize("serif") == "serif" && FontLogic.normalize("sans") == "sans")
check("font names", FontLogic.names("serif").first == "TimesNewRomanPSMT" && FontLogic.names("sans") == ["Helvetica"] && FontLogic.names("retro").first == "CourierPrimeSans-Regular")
check("font bad value -> retro names", FontLogic.names("x") == FontLogic.names("retro"))
check("font labels", FontLogic.settings.map(FontLogic.label) == ["Serif", "Sans-serif", "Retro"])

// Fullscreen margins / spacing
check("fs Narrow column (stored wide) default, 25% margins", FullscreenLogic.margin(screenWidth: 1600, nil) == 400 && FullscreenLogic.margins("x") == "wide")
check("fs Wide column (stored narrow), 10% margins", FullscreenLogic.margin(screenWidth: 1600, "narrow") == 160)
check("fs spacing default tight", FullscreenLogic.lineMultiple(nil, fullscreen: true) == 0 && FullscreenLogic.spacing("x") == "tight")
check("fs spacing loose 1.6 in fullscreen only", FullscreenLogic.lineMultiple("loose", fullscreen: true) == 1.6 && FullscreenLogic.lineMultiple("loose", fullscreen: false) == 0)

// Shortcut list (Step 8)
do {
    let L = ShortcutList.all
    check("shortcuts: ⌘W in fullscreen leaves it and minimizes", L.contains { $0.id == "fullscreenMinimize" && $0.keys == "⌘W" && $0.scope == "fullscreen" && $0.run == "minimize" })
    check("shortcuts: ⌘W minimizes to the Dock", L.contains { $0.id == "minimize" && $0.keys == "⌘W" && $0.scope == "note" && $0.run == "minimize" })
    check("shortcuts: non-empty fields", L.allSatisfy { !$0.id.isEmpty && !$0.keys.isEmpty && !$0.name.isEmpty && !$0.group.isEmpty && !$0.scope.isEmpty })
    check("shortcuts: valid groups", L.allSatisfy { ShortcutList.groups.contains($0.group) })
    check("shortcuts: valid scopes", L.allSatisfy { ShortcutList.scopes.contains($0.scope) })
    check("shortcuts: unique ids", Set(L.map { $0.id }).count == L.count)
    let pairs = L.map { $0.scope + "|" + $0.keys }
    check("shortcuts: no duplicate keys within a scope", Set(pairs).count == pairs.count)
    check("shortcuts: ⌘/ is the cheat sheet, ⌘K still free", L.filter { $0.keys == "⌘/" }.map { $0.id } == ["cheatSheet"] && !L.contains { $0.keys == "⌘K" })
    check("keys: modifier order normalized", ShortcutList.normalizeKeys("⌘⇧⌥⌃X") == "⌃⌥⇧⌘X" && ShortcutList.normalizeKeys("⌘⌃F") == "⌃⌘F" && ShortcutList.normalizeKeys("Esc") == "Esc" && ShortcutList.normalizeKeys("⇧Tab") == "⇧Tab")
    check("keys: list already in ⌃⌥⇧⌘ order", L.allSatisfy { ShortcutList.normalizeKeys($0.keys) == $0.keys })
    let rows = ShortcutList.sheetRows()
    let want = [("R Option", "Shows / hides"), ("R Command", "Window mode"), ("⌃⌥S", "Selection to note"), ("fn L", "Highlight"), ("fn X", "Strikethrough"),
                ("fn T", "Title lines"), ("⌘F", "Find"), ("fn R", "Find + replace"), ("⌘G / ⇧⌘G", "Matches"),
                ("⌘E", "Selected find"), ("fn O", "Navigator"), ("fn P", "Paragraph mode"), ("fn J", "Google Doc"), ("fn G", "Ask Grok"), ("w a s d", "Size"),
                (", .", "Opacity"), ("# ", "Title"), ("## ", "Subtitle"), ("---", "Single line"), ("===", "Double line")]
    check("sheet: exactly these 20 rows in order", rows.count == 20 && zip(rows, want).allSatisfy { $0.keys == $1.0 && $0.name == $1.1 }, "\(rows)")
    check("sheet: no group header rows", !rows.contains { $0.keys.isEmpty })
    check("sheet: labels trimmed", rows.allSatisfy { $0.name == $0.name.trimmingCharacters(in: .whitespaces) })
    check("sheet: 16 onSheet entries; others stay in the list", L.filter { $0.onSheet }.count == 16 && L.count > 16 && L.contains { $0.id == "findPrev" && !$0.onSheet } && L.contains { $0.id == "bold" && !$0.onSheet })
    check("shortcuts: ⇧⌘E and window-mode 1–9 gone", !L.contains { $0.keys == "⇧⌘E" || $0.keys == "1–9" })
    let removed = ["⌃⌥N", "⌃⌥W", "⌃⌘M", "⌃⌘F", "⇧⌘K", "⇧⌘Return", "⌘0", "⌥⌘9", "⌥⌘0", "i j k l (⇧ = 4×)", "+ / −", "] / [", "g", "G", "↓ / j", "↑ / k", "Return / l", "Esc / q", "Esc / Return"]
    check("shortcuts: removed keys gone", !L.contains { removed.contains($0.keys) })
    check("shortcuts: ⌃⌘G is Copy out", L.first { $0.keys == "⌃⌘G" }?.name.hasPrefix("Copy out") == true)
    check("shortcuts: run ids non-empty when set", L.allSatisfy { $0.run.map { !$0.isEmpty } ?? true })
}

// Paragraph mode regression (stale hidden ranges + edit round trips)
do {
    let pf = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), lh = NSLayoutManager().defaultLineHeight(for: pf)
    check("para: gap between sentences = one blank line (font line height), more than the old 12 pt", ParaLogic.sentenceGap(font: pf) >= lh && ParaLogic.sentenceGap(font: pf) < lh + 1 && ParaLogic.sentenceGap(font: pf) > 12)
    check("para: fullscreen loose spacing widens the gap; tight keeps it", ParaLogic.sentenceGap(font: pf, lineMultiple: 1.6) > ParaLogic.sentenceGap(font: pf) && ParaLogic.sentenceGap(font: pf, lineMultiple: 0) == ParaLogic.sentenceGap(font: pf, lineMultiple: 1))
    check("para: spacing is display only: rejoin still uses single spaces", ParaLogic.rejoin(NSAttributedString(string: "One.\nTwo.\nThree.")).string == "One. Two. Three.")
    check("para: no list prefixes hidden in paragraph mode", ParaLogic.listPrefixesToHide([NSRange(location: 3, length: 2)], paraMode: true).isEmpty)
    check("para: list prefixes kept outside paragraph mode", ParaLogic.listPrefixesToHide([NSRange(location: 3, length: 2)], paraMode: false) == [NSRange(location: 3, length: 2)])
    func rj(_ s: String) -> String { ParaLogic.rejoin(NSAttributedString(string: s)).string }
    var lines = ["The morning was cold.", "Lunch was short.", "The afternoon went faster than expected.", "Everyone was tired."]
    check("para: untouched round trip", rj(lines.joined(separator: "\n")) == lines.joined(separator: " "))
    // Many sequential edits on the split text, rejoin after each one.
    var edits: [(String, (inout [String]) -> Void)] = [
        ("type at end of last-but-one", { $0[2] += "ssfsf" }),
        ("delete in last", { $0[3] = "Everyone tired." }),
        ("insert in middle", { $0[1] = "Lunch was very short." }),
        ("add a sentence", { $0.insert("Rain came.", at: 2) }),
        ("remove a sentence", { $0.remove(at: 0) }),
        ("edit first char", { $0[0] = "l" + $0[0].dropFirst() }),
        ("type at very end", { $0[$0.count - 1] += " Done." }),
        ("emoji + accents", { $0[1] += " naïve 🍐" }),
    ]
    for (name, e) in edits {
        e(&lines)
        let got = rj(lines.joined(separator: "\n"))
        check("para edit: \(name)", got == lines.joined(separator: " "), got)
    }
    check("para: char count preserved", rj(lines.joined(separator: "\n")).count == lines.joined(separator: " ").count)
    check("para: empty lines dropped, spaces trimmed", rj("  A.  \n\n B. ") == "A. B.")
    edits.removeAll()
}
// No alignment (format 5): old "#< " / "#> " markers
do {
    typealias H = HeadingLogic
    check("heading: '# A' title", H.kind("# A")?.kind == .title && H.kind("# A")?.markerLen == 2)
    check("heading: old '#< A' still a title", H.kind("#< A")?.kind == .title && H.kind("#< A")?.markerLen == 3)
    check("heading: old '##> B' still a subtitle", H.kind("##> B")?.kind == .subtitle && H.kind("##> B")?.markerLen == 4)
    check("heading: plain lines stay plain", H.kind("### C") == nil && H.kind(" # E") == nil && H.kind("####") == nil)
    let old = "#< <u>Plums</u>\nbody #< x\n##> Sizes\r\n# Mid\n## Sub\n1. one\n"
    check("migrate: alignment markers dropped", H.dropAlign(old) == "# <u>Plums</u>\nbody #< x\n## Sizes\r\n# Mid\n## Sub\n1. one\n", H.dropAlign(old).debugDescription)
    check("migrate: idempotent", H.dropAlign(H.dropAlign(old)) == H.dropAlign(old))
    check("migrate: no headings unchanged", H.dropAlign("a\n#x\n### y") == "a\n#x\n### y")
    check("clean text strips old markers", ExportLogic.cleanText(ExportLogic.parse("#< Left\n##> Sub")) == "Left\nSub")
    let html = ExportLogic.html(ExportLogic.parse("#< Left\n##> Sub\n# Mid"))
    check("export docs: plain h1/h2, no text-align", html.contains("<h1><span") && html.contains("<h2><span") && !html.contains("text-align"))
}
// Hidden markers: caret snapping and delete keys
do {
    typealias L = HideLogic
    func R(_ a: Int, _ n: Int) -> NSRange { NSRange(location: a, length: n) }
    // "x **bold** y": markers at 2..<4 and 8..<10
    let st = [R(2, 2), R(8, 2)]
    check("snap: right arrow into marker goes past it", L.snap(3, from: 2, hidden: st, heads: []) == 4)
    check("snap: left arrow into marker goes before it", L.snap(9, from: 10, hidden: st, heads: []) == 8)
    check("snap: outside markers unchanged", L.snap(6, from: 5, hidden: st, heads: []) == 6 && L.snap(4, from: 3, hidden: st, heads: []) == 4)
    // "ab\n#< Title": head marker 3..<6
    let hd = [R(3, 3)]
    check("snap: click at title line start -> after marker", L.snap(3, from: 0, hidden: hd, heads: hd) == 6)
    check("snap: inside title marker -> after it", L.snap(4, from: 0, hidden: hd, heads: hd) == 6)
    check("snap: left arrow from title text start -> line above", L.snap(5, from: 6, hidden: hd, heads: hd) == 2)
    check("snap: title at note start stays after marker", L.snap(0, from: 2, hidden: [R(0, 2)], heads: [R(0, 2)]) == 2)
    // adjacent markers "**==w==**": 0..<2, 2..<4, 5..<7, 7..<9
    let adj = [R(0, 2), R(2, 2), R(5, 2), R(7, 2)]
    check("snap: adjacent markers forward", L.snap(1, from: 0, hidden: adj, heads: []) == 2 && L.snap(3, from: 2, hidden: adj, heads: []) == 4)
    check("snap: adjacent markers backward", L.snap(8, from: 9, hidden: adj, heads: []) == 7 && L.snap(6, from: 7, hidden: adj, heads: []) == 5)
    check("backspace after title marker removes whole marker", L.backspace(6, hidden: hd, heads: hd) == R(3, 3))
    check("backspace after closing marker deletes visible char", L.backspace(10, hidden: st, heads: []) == R(7, 1))
    check("backspace after opening marker deletes char before it", L.backspace(4, hidden: st, heads: []) == R(1, 1))
    check("backspace after chained markers", L.backspace(9, hidden: adj, heads: []) == R(4, 1))
    check("backspace elsewhere is normal", L.backspace(6, hidden: st, heads: []) == nil)
    check("forward delete before opening marker deletes first visible char", L.forwardDelete(2, hidden: st, length: 12) == R(4, 1))
    check("forward delete before closing marker deletes char after it", L.forwardDelete(8, hidden: st, length: 12) == R(10, 1))
    check("forward delete elsewhere normal", L.forwardDelete(5, hidden: st, length: 12) == nil)
}
// Empty styled words
do {
    typealias E = EmptyPairLogic
    check("empty: **** removed", E.apply("a **** b", at: 4) == ("a  b", 2))
    check("empty: italic ** removed", E.apply("a ** b", at: 3) == ("a  b", 2))
    check("empty: ==== ~~~~ <u></u>", E.apply("x====y", at: 3).0 == "xy" && E.apply("x~~~~y", at: 3).0 == "xy" && E.apply("x<u></u>y", at: 4).0 == "xy")
    check("empty: nested **====** fully removed", E.apply("a **====** b", at: 6) == ("a  b", 2))
    check("empty: bold italic ****** removed", E.apply("******", at: 3) == ("", 0))
    check("empty: non-empty pair untouched", E.apply("**w**", at: 2).0 == "**w**" && E.apply("**w**", at: 3).0 == "**w**")
    check("trigger: deleting whole content", E.emptiesSpan(line: "a **w** b", deleted: NSRange(location: 4, length: 1)))
    check("trigger: deleting part of content", !E.emptiesSpan(line: "a **wo** b", deleted: NSRange(location: 4, length: 1)))
    check("trigger: typing an opening ** is not a deletion target", !E.emptiesSpan(line: "a ** b", deleted: NSRange(location: 5, length: 1)))
    check("trigger: nested inner content", E.emptiesSpan(line: "**==w==**", deleted: NSRange(location: 4, length: 1)))
}
// Undo/redo with emptied styled words (real NSTextView + UndoManager)
do {
    final class UD: NSObject, NSTextViewDelegate {
        let um = UndoManager()
        func undoManager(for view: NSTextView) -> UndoManager? { um }
    }
    let d = UD(); d.um.groupsByEvent = false
    let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    tv.delegate = d; tv.allowsUndo = true
    func edit(_ r: NSRange, _ rep: String) {          // what the app does: widen, then one replacement
        let line = tv.string as NSString
        var a = 0, b = 0, c = 0
        line.getParagraphStart(&a, end: &b, contentsEnd: &c, for: NSRange(location: r.location, length: 0))
        let local = NSRange(location: r.location - a, length: r.length)
        let wide = NSMaxRange(r) > c ? r : EmptyPairLogic.expand(line: line.substring(with: NSRange(location: a, length: c - a)), range: local, with: rep)
            .map { NSRange(location: a + $0.location, length: $0.length) } ?? r   // multi-line: as the app (no widening)
        d.um.beginUndoGrouping()
        if tv.shouldChangeText(in: wide, replacementString: rep) {
            tv.textStorage!.replaceCharacters(in: wide, with: rep); tv.didChangeText()
        }
        d.um.endUndoGrouping()
        tv.breakUndoCoalescing()
    }
    let orig = "intro\n##< <u>Pears</u>\nend"
    tv.string = orig; d.um.removeAllActions()
    edit(NSRange(location: 13, length: 5), "")                        // select "Pears", delete
    check("undo: delete styled title text leaves plain title marker", tv.string == "intro\n##< \nend", tv.string)
    d.um.undo(); check("undo: restores exactly", tv.string == orig, tv.string)
    d.um.redo(); check("redo: reapplies exactly", tv.string == "intro\n##< \nend", tv.string)
    d.um.undo(); check("undo again: exact", tv.string == orig, tv.string)
    // Backspace letter by letter through Pears, then undo all
    for i in stride(from: 17, through: 13, by: -1) { edit(NSRange(location: i, length: 1), "") }
    check("backspace through: empty pair gone", tv.string == "intro\n##< \nend", tv.string)
    d.um.undo(); check("undo last backspace: one letter back, markers back", tv.string == "intro\n##< <u>P</u>\nend", tv.string)
    for _ in 0..<4 { d.um.undo() }
    check("undo all backspaces: exact original", tv.string == orig, tv.string)
    // Whole line delete and select-all delete
    edit(NSRange(location: 6, length: 16), ""); d.um.undo()
    check("whole line delete + undo exact", tv.string == orig, tv.string)
    edit(NSRange(location: 0, length: (orig as NSString).length), ""); d.um.undo()
    check("select-all delete + undo exact", tv.string == orig, tv.string)
    // Nested **==w==**
    tv.string = "a **==w==** b"; d.um.removeAllActions()
    edit(NSRange(location: 6, length: 1), "")
    check("nested: one edit removes all", tv.string == "a  b", tv.string)
    d.um.undo(); check("nested: undo exact", tv.string == "a **==w==** b", tv.string)
    // Round trips across all content: (note, range to delete, replacement, expected after)
    let body = "# Plan\n#> Right title\nSome **bold** and *it* and ==hi== and ~~old~~ and <u>un</u>.\n**==both==** end\n1. one\n\t1. two\n\t\t1. three\n---\n===\n===\nclip text\nSource: App | 2026-10-14 05:00"
    let bn = body as NSString
    func rng(_ s: String) -> NSRange { bn.range(of: s) }
    let cases: [(String, NSRange, String, String?)] = [
        ("bold word", rng("bold"), "", nil),
        ("italic word", NSRange(location: rng("*it*").location + 1, length: 2), "", nil),
        ("highlight word", NSRange(location: rng("==hi==").location + 2, length: 2), "", nil),
        ("strike word", NSRange(location: rng("~~old~~").location + 2, length: 3), "", nil),
        ("underline word", NSRange(location: rng("<u>un</u>").location + 3, length: 2), "", nil),
        ("nested word", NSRange(location: rng("**==both==**").location + 4, length: 4), "", nil),
        ("replace styled word with text", rng("bold"), "x", nil),
        ("part of styled word", NSRange(location: rng("bold").location, length: 2), "", nil),
        ("whole body line", bn.paragraphRange(for: rng("Some **")), "", nil),
        ("aligned title text", NSRange(location: rng("Right title").location, length: 11), "", nil),
        ("list level 1", bn.paragraphRange(for: rng("1. one")), "", nil),
        ("list level 3 text", rng("three"), "", nil),
        ("rule ---", bn.paragraphRange(for: rng("---")), "", nil),
        ("double rule", NSRange(location: rng("===\n===").location, length: 4), "", nil),
        ("clip lines", NSRange(location: rng("clip text").location, length: bn.length - rng("clip text").location), "", nil),
        ("select all", NSRange(location: 0, length: bn.length), "", ""),
        ("find-replace style text", rng("hi"), "yo", nil),
    ]
    for (name, r, rep, want) in cases {
        tv.string = body; d.um.removeAllActions()
        edit(r, rep)
        let after = tv.string
        if let w = want { check("rt \(name): result", after == w, after) }
        check("rt \(name): no empty pair left", !["****", "<u></u>", "~~~~", "===="].contains { (after as NSString).range(of: $0).location != NSNotFound && !(body as NSString).contains($0) }, after)
        d.um.undo(); check("rt \(name): undo exact", tv.string == body, tv.string)
        d.um.redo(); check("rt \(name): redo exact", tv.string == after, tv.string)
        d.um.undo(); check("rt \(name): undo again exact", tv.string == body, tv.string)
    }
}
// Numbered lists (format 4: one level)
do {
    typealias L = ListLogic
    check("list: item parse", L.item("1. a")?.number == 1 && L.item("12. x")?.markerLen == 4 && L.item("\t3. x")?.tabs == 1)
    check("list: not items", L.item("1.a") == nil && L.item("1.") == nil && L.item("a. b") == nil && L.item(" 1. b") == nil && L.item("1.1. b") == nil)
    check("list: empty item", L.item("3. ")?.contentEmpty == true && L.item("3. x")?.contentEmpty == false)
    check("list: counts up", L.renumber("1. a\n1. b\n7. c") == "1. a\n2. b\n3. c")
    check("list: custom start", L.renumber("4. a\n1. b") == "4. a\n5. b")
    check("list: tabs dropped, one level", L.renumber("1. a\n\t1. b\n\t\t1. c\n2. d") == "1. a\n2. b\n3. c\n4. d")
    check("list: blank line ends list", L.renumber("1. a\n2. b\n\n5. c\n1. d") == "1. a\n2. b\n\n5. c\n6. d")
    check("list: text line ends list", L.renumber("1. a\nx\n1. b") == "1. a\nx\n1. b")
    check("list: numbers 10+", L.renumber(String(repeating: "1. x\n", count: 11)).hasSuffix("10. x\n11. x\n"))
    check("list: non-list text unchanged", L.renumber("# T\nplain\n\n**b**") == "# T\nplain\n\n**b**")
    check("list: line endings kept", L.renumber("1. a\r\n1. b\n") == "1. a\r\n2. b\n")
    let old = "## Tasks\n1. Prune\n1.1. Old rows\n1.1.1. Rot\n1.2. Young\n2. Pick\n2.1. Sort\n3. Ship\n\nplain 1.1. not"
    check("migrate old paths -> flat", L.convertOld(old) == "## Tasks\n1. Prune\n2. Old rows\n3. Rot\n4. Young\n5. Pick\n6. Sort\n7. Ship\n\nplain 1.1. not", L.convertOld(old).debugDescription)
    check("migrate nested tabs -> flat (format 3 -> 4)", L.renumber("1. Prune\n\t1. Old\n\t\t1. Rot\n\t2. Young\n2. Pick") == "1. Prune\n2. Old\n3. Rot\n4. Young\n5. Pick")
    check("migrate: no lists unchanged", L.renumber("# A\nb\n\nc") == "# A\nb\n\nc")
    check("export clean flat", ExportLogic.cleanText(ExportLogic.parse("1. a\n2. b\n3. c")) == "1. a\n2. b\n3. c")
    let h = ExportLogic.html(ExportLogic.parse("4. a\n5. b"))
    check("export docs flat + start", h.contains("start=\"4\"") && h.components(separatedBy: "<ol").count == 2, h)
}

// Dash lists ("- item"): same hanging indent and Return/Backspace behaviour as numbered lists, plain text in the file
do {
    typealias L = ListLogic
    check("dash: item parse", L.item("- a")?.bullet == true && L.item("- a")?.markerLen == 2 && L.item("\t- a")?.tabs == 1 && L.item("\t- a")?.markerLen == 3)
    check("dash: numbered items are not bullets", L.item("1. a")?.bullet == false && L.item("1. a")?.number == 1)
    check("dash: not items (--, ---, ->, -5, no space, leading space, mid-line)", ["-a", "--", "---", "-> x", "-5", "-", " - a", "a - b", "-- a", "–- a"].allSatisfy { L.item($0) == nil })
    check("dash: empty item", L.item("- ")?.contentEmpty == true && L.item("- x")?.contentEmpty == false)
    check("dash: renumber leaves dash items alone", L.renumber("- a\n- b\n- c") == "- a\n- b\n- c")
    check("dash: tabs dropped like numbered lists", L.renumber("\t- a\n- b") == "- a\n- b")
    check("dash: a numbered list restarts after dash items", L.renumber("1. a\n- b\n1. c\n1. d") == "1. a\n- b\n1. c\n2. d")
    check("dash: --- and === lines stay rules, negative numbers untouched", L.renumber("---\n===\n-5 degrees\n-> next") == "---\n===\n-5 degrees\n-> next")
    check("dash: file text stays plain", L.renumber("# T\n- one\n- two\n\nplain") == "# T\n- one\n- two\n\nplain")
    let r1 = L.returnEdit("- a", sel: NSRange(location: 3, length: 0))
    check("dash: Return at the end starts the next '- '", r1?.text == "- a\n- " && r1?.sel == NSRange(location: 6, length: 0), "\(String(describing: r1))")
    let r2 = L.returnEdit("- ab", sel: NSRange(location: 3, length: 0))
    check("dash: Return in the middle splits the item", r2?.text == "- a\n- b" && r2?.sel == NSRange(location: 6, length: 0), "\(String(describing: r2))")
    let r3 = L.returnEdit("x\n- ", sel: NSRange(location: 4, length: 0))
    check("dash: Return on an empty item ends the list (dash removed)", r3?.text == "x\n" && r3?.sel == NSRange(location: 2, length: 0), "\(String(describing: r3))")
    let r4 = L.returnEdit("- a\n- b", sel: NSRange(location: 3, length: 0))
    check("dash: Return after the first of two keeps the rest", r4?.text == "- a\n- \n- b", "\(String(describing: r4))")
    let b1 = L.backspaceEdit("- a", caret: 2)
    check("dash: Backspace at the start of the text removes the dash", b1?.text == "a" && b1?.sel == NSRange(location: 0, length: 0))
    check("dash: Backspace inside the text is a normal key", L.backspaceEdit("- ab", caret: 3) == nil)
    check("dash: numbered Return still counts up", L.returnEdit("1. a", sel: NSRange(location: 4, length: 0))?.text == "1. a\n2. ")
    // finish() (what typing runs) keeps the caret
    let f = L.finish("\t- a", NSRange(location: 4, length: 0))
    check("dash: finish keeps the caret on the text", f.text == "- a" && f.sel == NSRange(location: 3, length: 0), "\(f)")
    // copy out
    check("dash: copy out text", ExportLogic.cleanText(ExportLogic.parse("- a\n- **b**\n1. c")) == "- a\n- b\n1. c")
    let hh = ExportLogic.html(ExportLogic.parse("- a\n- b\n\n1. c"))
    check("dash: copy out Docs = bullet list, then numbered", hh.contains("<ul style=\"list-style-type:disc\"><li style=\"list-style-type:disc\">a</li><li style=\"list-style-type:disc\">b</li></ul>") && hh.contains("<ol"), hh)
    check("dash: parse kinds", ExportLogic.parse("- a")[0].kind == .bulletItem && ExportLogic.isList(.bulletItem) && ExportLogic.parse("1. a")[0].kind == .listItem(number: 1))
    // style markers go after the "- " (and after "12. "), titles keep priority
    let sel = NSRange(location: 0, length: 7)
    let st = MarkerLogic.toggleSelection("- hello" as NSString, selection: sel, style: .strike)
    check("dash: strike markers after '- '", st.map { ("- hello" as NSString).replacingCharacters(in: $0.whole, with: $0.text) } == "- ~~hello~~", "\(String(describing: st))")
    let hl = MarkerLogic.toggleSelection("- hello" as NSString, selection: sel, style: .highlight)
    check("dash: highlight markers after '- '", hl.map { ("- hello" as NSString).replacingCharacters(in: $0.whole, with: $0.text) } == "- ==hello==")
    check("dash: '# - x' is a title, not a list", L.item("# - x") == nil && HeadingLogic.kind("# - x") != nil)
    check("dash: pasted block of dashes keeps its text", L.renumber("- a\n- b\n  - c") == "- a\n- b\n  - c")
}

// Clicks on list lines: double click strikes the item, ⌘+click highlights it
do {
    typealias C = ListClick
    check("click: double click = strike, ⌘+click = highlight", C.action(clickCount: 2, flags: []) == .strike && C.action(clickCount: 1, flags: [.command]) == .highlight && C.action(clickCount: 2, flags: [.command]) == .highlight)
    check("click: triple click = highlight (after the double click's strike)", C.action(clickCount: 3, flags: []) == .triple && C.action(clickCount: 3, flags: [.shift]) == .none && C.action(clickCount: 4, flags: []) == .none)
    check("click: single click, other modifiers do nothing", C.action(clickCount: 1, flags: []) == .none && C.action(clickCount: 2, flags: [.shift]) == .none && C.action(clickCount: 1, flags: [.command, .shift]) == .none && C.action(clickCount: 1, flags: [.option]) == .none)
    let note = "# Title\n- one two\n3. three\nplain words\n- " as NSString
    func apply(_ s: NSString, at loc: Int, _ a: C.Action) -> String? {
        guard let t = C.toggle(s, at: loc, a) else { return nil }
        return s.replacingCharacters(in: t.whole, with: t.text)
    }
    let l1 = note.range(of: "- one two").location
    check("click: strike a dash item (marker after '- ')", apply(note, at: l1 + 4, .strike) == "# Title\n- ~~one two~~\n3. three\nplain words\n- ")
    check("click: clicking the marker counts too", apply(note, at: l1, .strike) == "# Title\n- ~~one two~~\n3. three\nplain words\n- " && apply(note, at: l1 + 1, .strike) != nil)
    let l2 = note.range(of: "3. three").location
    check("click: strike a numbered item (marker after '3. ')", apply(note, at: l2 + 5, .strike) == "# Title\n- one two\n3. ~~three~~\nplain words\n- ")
    check("click: ⌘+click highlights after the marker", apply(note, at: l1 + 5, .highlight) == "# Title\n- ==one two==\n3. three\nplain words\n- " && apply(note, at: l2, .highlight) == "# Title\n- one two\n3. ==three==\nplain words\n- ")
    let struck = "- ~~one two~~" as NSString
    check("click: toggling again removes it", apply(struck, at: 5, .strike) == "- one two")
    let hlOn = "5. ==done==" as NSString
    check("click: highlight toggles off too", apply(hlOn, at: 4, .highlight) == "5. done")
    check("click: both styles can sit together", apply("- ~~a b~~" as NSString, at: 3, .highlight) != nil)
    check("click: only list lines (title, plain text, empty item, rule do nothing)", apply(note, at: 2, .strike) == nil && apply(note, at: note.range(of: "plain").location + 2, .strike) == nil && apply(note, at: note.length, .strike) == nil && apply("---" as NSString, at: 1, .strike) == nil && apply("-> a" as NSString, at: 2, .strike) == nil && apply("- " as NSString, at: 1, .highlight) == nil)
    check("click: letters and case never change", apply("- HeLLo WoRLD" as NSString, at: 5, .strike)?.replacingOccurrences(of: "~~", with: "") == "- HeLLo WoRLD")
    // A triple click = click 2 (double click: strike toggles, already applied) + click 3 (take the strike back, highlight)
    func triple(_ s: String, at loc: Int) -> (afterClick2: String, afterClick3: String)? {
        let n = s as NSString
        guard let c2 = C.toggle(n, at: loc, .strike) else { return nil }
        let after2 = n.replacingCharacters(in: c2.whole, with: c2.text) as NSString
        guard let c3 = C.toggle(after2, at: loc, .triple, strikeApplied: true) else { return nil }
        return (after2 as String, after2.replacingCharacters(in: c3.whole, with: c3.text))
    }
    check("triple: plain dash item ends highlighted, not struck", triple("- one two", at: 4)?.afterClick3 == "- ==one two==" && triple("- one two", at: 4)?.afterClick2 == "- ~~one two~~")
    check("triple: plain numbered item ends highlighted, not struck", triple("3. three", at: 5)?.afterClick3 == "3. ==three==")
    check("triple: an already struck item stays struck (and gets the highlight)", triple("- ~~one~~", at: 4)?.afterClick3 == "- ==~~one~~==", "\(String(describing: triple("- ~~one~~", at: 4)))")
    check("triple again: highlight comes off, strike state as before", triple("- ==one two==", at: 5)?.afterClick3 == "- one two" && triple("- ==~~one~~==", at: 6)?.afterClick3 == "- ~~one~~")
    check("triple: marker area and inside the note, other lines untouched", {
        let note = "# T\n- a b\n- c d\nplain"
        let n = note as NSString
        let loc = n.range(of: "- c d").location
        guard let r = triple(note, at: loc) else { return false }
        return r.afterClick3 == note.replacingOccurrences(of: "- c d", with: "- ==c d==")
    }())
    check("triple: only list lines (title, plain, empty item)", triple("# Title", at: 2) == nil && triple("plain words", at: 3) == nil && triple("- ", at: 1) == nil)
    check("triple: without the strike (click 2 not seen) it only highlights", { () -> Bool in
        guard let t = C.toggle("- one" as NSString, at: 3, .triple, strikeApplied: false) else { return false }
        return ("- one" as NSString).replacingCharacters(in: t.whole, with: t.text) == "- ==one=="
    }())
    check("triple: one replacement on one line, caret at the item's end", { () -> Bool in
        let n = "a\n- one\nb" as NSString
        let after2 = n.replacingCharacters(in: C.toggle(n, at: 4, .strike)!.whole, with: C.toggle(n, at: 4, .strike)!.text) as NSString
        guard let c3 = C.toggle(after2, at: 4, .triple, strikeApplied: true) else { return false }
        let out = after2.replacingCharacters(in: c3.whole, with: c3.text)
        return out == "a\n- ==one==\nb" && c3.caret == (out as NSString).range(of: "==one==").upperBound
    }())
    let t = C.toggle("- one" as NSString, at: 3, .strike)
    check("click: caret ends after the item", t != nil && t!.caret == 9 && t!.whole == NSRange(location: 2, length: 3), "\(String(describing: t))")
}

// Post to X: the selection opens in X's compose window; markers stripped, URL-encoded, length check
do {
    typealias T = TweetLogic
    check("x: markers stripped, text kept", T.clean("# Big **bold** and *it* ==hi== ~~no~~ <u>u</u>") == "Big bold and it hi no u")
    check("x: subtitle marker + rules", T.clean("## Sub\nbody\n---\nmore\n===\nend") == "Sub\nbody\n\nmore\n\nend")
    check("x: list markers kept as typed", T.clean("- a\n- **b**\n1. c\n2. d") == "- a\n- b\n1. c\n2. d")
    check("x: case, punctuation and inner blank lines kept", T.clean("HeLLo, World!\n\nSecond paragraph.") == "HeLLo, World!\n\nSecond paragraph.")
    check("x: outer blank lines trimmed", T.clean("\n\n  hi  \n\n") == "hi")
    check("x: only markers = nothing", T.clean("****") == "" || T.plan(selection: "---\n===") == .nothing)
    check("x: encode newline, & # % + ? = space", T.encode("a&b #c 100% +1 ?x=y\nz") == "a%26b%20%23c%20100%25%20%2B1%20%3Fx%3Dy%0Az")
    check("x: encode emoji + accents as UTF-8", T.encode("café 😀") == "caf%C3%A9%20%F0%9F%98%80")
    check("x: unreserved characters stay", T.encode("A-z_0.9~") == "A-z_0.9~")
    check("x: url", T.url(for: "hi there")?.absoluteString == "https://x.com/intent/post?text=hi%20there")
    check("x: url survives round trip", { () -> Bool in
        let t = "Tom & Jerry #1 100% = fun?\nNew line 😀 café"
        guard let u = T.url(for: t), let c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return false }
        return c.host == "x.com" && c.path == "/intent/post" && c.queryItems?.first?.name == "text" && c.queryItems?.first?.value == t
    }())
    check("x: 280 is fine, 281 is over", !T.isOverLimit(String(repeating: "a", count: 280)) && T.isOverLimit(String(repeating: "a", count: 281)))
    check("x: emoji and CJK count 2", T.weightedLength("😀") == 2 && T.weightedLength("日本") == 4 && T.weightedLength("abc é") == 5 && T.weightedLength("👨‍👩‍👧") == 2)
    check("x: 141 emoji are over, 140 are not", T.isOverLimit(String(repeating: "😀", count: 141)) && !T.isOverLimit(String(repeating: "😀", count: 140)))
    check("x: plan nothing for no / blank selection", T.plan(selection: nil) == .nothing && T.plan(selection: "  \n ") == .nothing)
    if case let .open(u, over) = T.plan(selection: "short **post**") { check("x: plan opens, not over", !over && u.absoluteString == "https://x.com/intent/post?text=short%20post") } else { check("x: plan opens", false) }
    if case let .open(_, over) = T.plan(selection: String(repeating: "word ", count: 80)) { check("x: long selection still opens, flagged over", over) } else { check("x: long selection opens", false) }
    check("x: huge selection is refused, not truncated", T.plan(selection: String(repeating: "é", count: 5000)) == .tooLong)
    check("x: shortcut ⌃⌘X + fn M, unique, not reserved", ShortcutList.entries.contains { $0.id == "postToX" && $0.keys == "⌃⌘X" && $0.run == "postToX" } && ShortcutList.fnLetters["postToX"] == "M" && !ShortcutList.fnReserved.contains("M") && ShortcutList.entries.filter { $0.scope == "note" && $0.keys == "⌃⌘X" }.count == 1)
    check("x: not on page 1 (page 1 stays balanced)", !(ShortcutList.all.first { $0.id == "postToX" }?.onSheet ?? true))
}

// Fullscreen info strip: word count, date/time/battery text, visibility rule
do {
    typealias I = InfoStripLogic
    check("strip: plain words", I.wordCount("one two  three\nfour") == 4 && I.wordCount("") == 0 && I.wordCount("  \n ") == 0)
    check("strip: style markers are not words", I.wordCount("**bold** ==hi== ~~no~~ *it* <u>u</u> x") == 6 && I.wordCount("**a** ==b==") == 2)
    check("strip: title markers", I.wordCount("# My Title\n## Sub title\nbody here") == 6)
    check("strip: list markers", I.wordCount("- apple pie\n- plain\n1. first thing\n2. second") == 6)
    check("strip: rules and blank lines", I.wordCount("---\nhello\n===\n\nworld") == 2)
    check("strip: styled words inside a list item", I.wordCount("- ==two words==") == 2)
    let us = Locale(identifier: "en_US"), ny = TimeZone(identifier: "America/New_York")!
    var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 16; c.hour = 4; c.minute = 5
    var cal = Calendar(identifier: .gregorian); cal.timeZone = ny
    let d = cal.date(from: c)!
    check("strip: date string", I.dateString(d, locale: us, timeZone: ny) == "Fri, Oct 16")
    check("strip: time string", I.timeString(d, locale: us, timeZone: ny).replacingOccurrences(of: "\u{202F}", with: " ") == "4:05 AM")
    check("strip: words string", I.wordsString(1) == "1 word" && I.wordsString(0) == "0 words" && I.wordsString(1234) == "1234 words")
    check("strip: battery string", I.batteryString(percent: 87, charging: false) == "87%" && I.batteryString(percent: 87, charging: true) == "\u{26A1}\u{FE0E} 87%"
          && I.batteryString(percent: nil, charging: true) == nil && I.batteryString(percent: 130, charging: false) == "100%" && I.batteryString(percent: -2, charging: false) == "0%")
    check("strip: full line", I.line(date: d, words: 12, batteryPercent: 87, charging: false, locale: us, timeZone: ny).replacingOccurrences(of: "\u{202F}", with: " ") == "Fri, Oct 16 \u{00B7} 4:05 AM \u{00B7} 12 words \u{00B7} 87%")
    check("strip: no battery = no battery part", I.line(date: d, words: 1, batteryPercent: nil, charging: false, locale: us, timeZone: ny).replacingOccurrences(of: "\u{202F}", with: " ") == "Fri, Oct 16 \u{00B7} 4:05 AM \u{00B7} 1 word")
    func vis(was: Bool = false, fs: Bool = true, tr: Bool = false, bl: Bool = false, d: CGFloat?) -> Bool { I.visible(was: was, fullscreen: fs, transitioning: tr, blocked: bl, distanceFromTop: d) }
    check("strip: shows near the top", vis(d: 0) && vis(d: 70) && !vis(d: 71) && !vis(d: 300))
    check("strip: stays until the hide distance (no flicker)", vis(was: true, d: 100) && vis(was: true, d: 110) && !vis(was: true, d: 111))
    check("strip: never outside fullscreen", !vis(fs: false, d: 0) && !vis(was: true, fs: false, d: 0))
    check("strip: not during the fullscreen transition", !vis(tr: true, d: 0))
    check("strip: not while the list / Settings / sheet block it", !vis(bl: true, d: 0) && !vis(was: true, bl: true, d: 0))
    check("strip: mouse on another screen = hidden", !vis(d: nil) && !vis(was: true, d: nil))
}

// Launch hardening: crashes found by fuzzing, unreadable files, encodings, first-run Accessibility
do {
    let N = NoteLibrary.self
    // crash 1: "<u>" twice with no "</u>" paired the two "<u>" and indexed past the line (a typed line could crash the app)
    check("harden: <u> without </u> is no pair (no crash)", MarkerLogic.spans("<u>a <u>b").isEmpty && MarkerLogic.spans("x <u>y").isEmpty)
    check("harden: <u>..</u> still pairs", MarkerLogic.spans("<u>a</u> <u>b</u>").count == 2)
    check("harden: ** ~~ == still pair themselves", MarkerLogic.spans("**a** ~~b~~ ==c==").count == 3)
    // crash 2: a file called "Note -- x.txt" put the range start after its end
    check("harden: 'Note -- x.txt' is not a numbered note", N.number(in: "Note -- x.txt") == nil && N.number(in: "Note  -- x.txt") == nil && N.number(in: "Note ") == nil && N.number(in: "Note") == nil)
    check("harden: odd file names parse without crashing", ["Note -- x.txt", "Note -- -- .txt", "Note 5 -- .txt", "Note 5 -- -- 14OCT26.txt", "-- .txt", ".txt", "Note 5 ", " -- "].allSatisfy {
        _ = N.customName(inFileName: $0); _ = N.dateToken(in: $0); _ = N.filenameDate($0); _ = N.displayName(fileName: $0, text: "x"); return true })
    check("harden: Finder name 'Note -- x.txt' lists as its own name", N.customName(inFileName: "Note -- x.txt") == "Note -- x")
    // reading: never an empty note for a file that could not be read
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fn-harden-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    func put(_ name: String, _ bytes: [UInt8]) -> URL { let u = dir.appendingPathComponent(name); try? Data(bytes).write(to: u); return u }
    check("harden: UTF-8 reads", N.readText(put("a.txt", Array("héllo 😀\n".utf8))) == "héllo 😀\n")
    check("harden: empty file reads as empty (not nil)", N.readText(put("e.txt", [])) == "")
    check("harden: Windows-1252 file is read, not lost", N.readText(put("w.txt", [0x63, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x78, 0x94])) == "café “x”")
    check("harden: UTF-16 with BOM is read", N.readText(put("u16.txt", [0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00])) == "hi")
    check("harden: missing file = nil, not empty", N.readText(dir.appendingPathComponent("missing.txt")) == nil)
    check("harden: over the size limit = nil", N.readText(put("big.txt", Array(repeating: 0x61, count: 100)), maxBytes: 50) == nil && N.readText(put("big2.txt", Array(repeating: 0x61, count: 50)), maxBytes: 50) != nil)
    check("harden: import uses the same reader", N.readImport(put("imp.md", [0x63, 0xE9])) == "cé")
    // list rows read only the start of a note, and nothing for a custom name
    let big = put("Note 7 -- 14OCT26.txt", Array("First line here\n".utf8) + Array(repeating: 0x61, count: 200_000))
    check("harden: row title = first line of a big note", N.rowTitle(big) == "First line here")
    let cut = put("Note 8 -- 14OCT26.txt", Array("\n".utf8) + Array(repeating: 0xC3, count: 1) + Array(repeating: 0xA9, count: 1) + Array(repeating: 0x61, count: 9000))
    check("harden: row title survives a cut at the read limit", N.rowTitle(cut).hasPrefix("é"))
    check("harden: custom name needs no file read", N.rowTitle(dir.appendingPathComponent("Note 3 -- Garden plan -- 14OCT26.txt")) == "Garden plan")
    check("harden: unreadable default note row = Empty note, no crash", N.rowTitle(dir.appendingPathComponent("Note 4 -- 14OCT26.txt")) == "Empty note")
    // atomic save keeps content and creation date, leaves no temp file
    let sv = dir.appendingPathComponent("Note 9 -- 01JAN20.txt")
    check("harden: atomic save writes", N.writeAtomically("one", to: sv) && N.readText(sv) == "one")
    let made = Date(timeIntervalSince1970: 1_600_000_000)
    try? FileManager.default.setAttributes([.creationDate: made], ofItemAtPath: sv.path)
    check("harden: atomic save again keeps the creation date", N.writeAtomically("two", to: sv) && N.readText(sv) == "two" && abs((N.creationDate(sv) ?? .distantPast).timeIntervalSince(made)) < 1, "\(String(describing: N.creationDate(sv))) vs \(made) text=\(String(describing: N.readText(sv)))")
    check("harden: no save temp files left", ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).allSatisfy { !$0.contains(".saving-") })
    check("harden: save into a missing folder fails (no crash)", !N.writeAtomically("x", to: dir.appendingPathComponent("nope/dir/Note 1 -- 01JAN20.txt")))
    // Accessibility prompt: once
    check("harden: Accessibility dialog once", AccessLogic.shouldPrompt(trusted: false, alreadyAsked: false) && !AccessLogic.shouldPrompt(trusted: false, alreadyAsked: true) && !AccessLogic.shouldPrompt(trusted: true, alreadyAsked: false))
}
// Fuzz: random text built from marker, list, heading, unicode and file-name pieces must never crash any of the pure logic
do {
    struct Gen: RandomNumberGenerator { var s: UInt64; mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }
    var g = Gen(s: 20261017)
    let toks = ["**", "*", "==", "~~", "<u>", "</u>", "# ", "## ", "#", "- ", "-", "--", "---", "===", "1. ", "12. ", "99999999999. ", "\t", " ", "\n", "\n\n", "\r\n", "\r", "a", "word", "É", "e\u{301}", "😀", "👨‍👩‍👧", "日本", "\u{0}", "\u{200B}", "\u{202E}", "\u{FEFF}", "%", "&", "<", ">", ".", "0", "9", "Note 5 -- ", " -- ", ".txt", "14OCT26", "/", ":", "\\", "؟", "ﷺ"]
    func rs() -> String { var t = ""; for _ in 0..<Int.random(in: 0...20, using: &g) { t += toks.randomElement(using: &g)! }; return t }
    func rr(_ ns: NSString) -> NSRange { let a = Int.random(in: 0...ns.length, using: &g); return NSRange(location: a, length: Int.random(in: 0...(ns.length - a), using: &g)) }
    let N = NoteLibrary.self
    for _ in 0..<2500 {
        let t = rs(), ns = t as NSString, sel = rr(ns), loc = Int.random(in: 0...ns.length, using: &g)
        _ = MarkerLogic.spans(t); _ = MarkerLogic.segments(in: ns, selection: sel)
        for st in [MarkerLogic.Style.bold, .italic, .underline, .highlight, .strike] { _ = MarkerLogic.toggleSelection(ns, selection: sel, style: st) }
        _ = HeadingLogic.kind(t); _ = HeadingLogic.convert(t); _ = HeadingLogic.dropAlign(t)
        _ = ListLogic.item(t); _ = ListLogic.renumber(t); _ = ListLogic.convertOld(t); _ = ListLogic.returnEdit(t, sel: sel)
        _ = ListLogic.backspaceEdit(t, caret: loc); _ = ListLogic.finish(t, sel); _ = ListLogic.diff(t, rs())
        for a in [ListClick.Action.strike, .highlight, .triple] { _ = ListClick.toggle(ns, at: loc, a, strikeApplied: true) }
        let blocks = ExportLogic.parse(t); _ = ExportLogic.cleanText(blocks); _ = ExportLogic.html(blocks)
        _ = TweetLogic.plan(selection: t); _ = InfoStripLogic.wordCount(t); _ = SelectionNote.noteText(from: t)
        if let e = SelectionNote.appendEdit(existing: t, selection: rs()) { _ = ns.replacingCharacters(in: NSRange(location: e.location, length: e.length), with: e.text) }
        _ = PendingStyleLogic.stripEmptyPairs(t); _ = EmptyPairLogic.apply(t, at: loc); _ = NavFilter.visible([(t, false)], query: t)
        _ = N.rowName(t); _ = N.renamedFileName(old: "Note 5 -- " + t + " -- 14OCT26.txt", newName: t); _ = N.renamedFileName(old: t + ".txt", newName: t)
        for n in [t, t + ".txt", "Note 3 -- " + t + ".txt", "Note " + t + " -- " + t] { _ = N.number(in: n); _ = N.filenameDate(n); _ = N.customName(inFileName: n); _ = N.displayName(fileName: n, text: t) }
    }
    check("fuzz: 2500 random notes through the text logic, no crash", true)
}

// ■ (U+25A0) and friends render in FloatNote's fonts (own glyph or a system fallback; never a missing-glyph box)
do {
    func supplier(_ fontName: String, _ s: String) -> (name: String, ok: Bool) {
        let f = CTFontCreateWithName(fontName as CFString, 17, nil)
        let fb = CTFontCreateForString(f, s as CFString, CFRange(location: 0, length: (s as NSString).length))
        var ch = [UniChar](s.utf16); var g = [CGGlyph](repeating: 0, count: ch.count)
        return (CTFontCopyPostScriptName(fb) as String, CTFontGetGlyphsForCharacters(fb, &ch, &g, ch.count) && g.allSatisfy { $0 != 0 })
    }
    for name in FontLogic.names("retro") + FontLogic.names("serif") + FontLogic.names("sans") {
        for (label, ch) in [("U+25A0", "\u{25A0}"), ("U+25FC", "\u{25FC}"), ("U+2B1B", "\u{2B1B}")] {
            let r = supplier(name, ch)
            check("glyph: \(label) renders from \(name) via \(r.name)", r.ok)
        }
    }
}

// List keys: exact results + undo/redo round trips on a real NSTextView
do {
    typealias L = ListLogic
    final class UD2: NSObject, NSTextViewDelegate {
        let um = UndoManager()
        func undoManager(for view: NSTextView) -> UndoManager? { um }
    }
    let d = UD2(); d.um.groupsByEvent = false
    let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    tv.delegate = d; tv.allowsUndo = true
    var editAt: Int? = nil
    func commit(_ e: (text: String, sel: NSRange)) {
        let (fixed, _) = L.finish(e.text, e.sel, old: tv.string, at: editAt)
        let (r, rep) = L.diff(tv.string, fixed)
        d.um.beginUndoGrouping()
        if tv.shouldChangeText(in: r, replacementString: rep) { tv.textStorage!.replaceCharacters(in: r, with: rep); tv.didChangeText() }
        d.um.endUndoGrouping()
    }
    func at(_ s: String, _ m: String) -> Int { (s as NSString).range(of: m).location }
    func roundTrip(_ name: String, _ start: String, _ op: (String) -> (text: String, sel: NSRange)?, _ want: String, caret: Int? = nil) {
        tv.string = start; d.um.removeAllActions()
        guard let e = op(start) else { check("key \(name): handled", false); return }
        let f = L.finish(e.text, e.sel, old: start, at: editAt)
        check("key \(name): result", f.text == want, f.text.debugDescription)
        if let c = caret { check("key \(name): caret", f.sel.location == c, "\(f.sel.location)") }
        if f.text == start { return }
        commit(e)
        check("key \(name): applied", tv.string == want, tv.string.debugDescription)
        d.um.undo(); check("key \(name): undo exact", tv.string == start, tv.string.debugDescription)
        d.um.redo(); check("key \(name): redo exact", tv.string == want, tv.string.debugDescription)
        d.um.undo(); check("key \(name): undo again", tv.string == start)
    }
    let base = "1. a\n2. b\n3. c"
    roundTrip("Return at end of item", base, { L.returnEdit($0, sel: NSRange(location: at($0, "b") + 1, length: 0)) }, "1. a\n2. b\n3. \n4. c", caret: at(base, "b") + 5)
    roundTrip("Return mid-text splits", "1. abc\n2. z", { L.returnEdit($0, sel: NSRange(location: 4, length: 0)) }, "1. a\n2. bc\n3. z", caret: 8)
    roundTrip("Return on empty last item ends list", "1. a\n2. ", { L.returnEdit($0, sel: NSRange(location: ($0 as NSString).length, length: 0)) }, "1. a\n", caret: 5)
    roundTrip("Return on empty item mid-list splits list", "1. a\n2. \n3. b", { L.returnEdit($0, sel: NSRange(location: 8, length: 0)) }, "1. a\n\n3. b")
    roundTrip("Backspace at item start -> plain line", base, { L.backspaceEdit($0, caret: at($0, "b")) }, "1. a\nb\n3. c")
    check("Backspace mid-text not handled", L.backspaceEdit("1. ab", caret: 4) == nil)
    check("Return on plain line not handled", L.returnEdit("plain", sel: NSRange(location: 5, length: 0)) == nil)
    func generic(_ name: String, _ start: String, _ r: NSRange, _ rep: String, _ want: String) {
        let plain = (start as NSString).replacingCharacters(in: r, with: rep)
        editAt = r.location; defer { editAt = nil }
        roundTrip(name, start, { _ in (plain, NSRange(location: r.location + (rep as NSString).length, length: 0)) }, want)
    }
    generic("delete an item renumbers", "1. a\n2. b\n3. c", NSRange(location: 5, length: 5), "", "1. a\n2. c")
    generic("cut across items", "1. a\n2. b\n3. c\n4. d", NSRange(location: 4, length: 10), "", "1. a\n2. d")
    generic("paste items into list", "1. a\n2. b", NSRange(location: 4, length: 0), "\n1. x\n1. y", "1. a\n2. x\n3. y\n4. b")
    generic("paste nested items flattens", "1. a", NSRange(location: 4, length: 0), "\n\t1. x\n\t\t1. y", "1. a\n2. x\n3. y")
    generic("type '4. ' starts at 4", "", NSRange(location: 0, length: 0), "4. ", "4. ")
    generic("type '1. ' after an item continues", "1. a\n2. b\n", NSRange(location: 10, length: 0), "1. ", "1. a\n2. b\n3. ")
    generic("blank line ends list", "1. a\n2. b\n3. c", NSRange(location: 9, length: 0), "\n", "1. a\n2. b\n\n3. c")
    generic("delete first item keeps start 1", "1. a\n2. b\n3. c", NSRange(location: 0, length: 5), "", "1. b\n2. c")
    generic("delete first item keeps custom start", "4. a\n5. b", NSRange(location: 0, length: 5), "", "4. b")
    generic("styled item text kept", "1. **a**\n2. ==b==", NSRange(location: 0, length: 9), "", "1. ==b==")
    let ten = (1...9).map { "\($0). x" }.joined(separator: "\n")
    let f = L.finish(ten + "\n1. y", NSRange(location: (ten as NSString).length + 4, length: 0))
    check("caret stays after number when 1. -> 10.", f.text.hasSuffix("10. y") && f.sel.location == (f.text as NSString).length - 1, "\(f.sel.location)")
}
do {   // Ask Claude (⌃⌘K)
    let G = GrokLogic.self
    check("claude: url", G.claudeURL("Fix this\n\na & b")?.absoluteString == "https://claude.ai/new?q=Fix%20this%0A%0Aa%20%26%20b", G.claudeURL("Fix this\n\na & b")?.absoluteString ?? "nil")
    check("claude: encodes # ? = + / unicode", G.claudeURL("#?=+/é")?.absoluteString == "https://claude.ai/new?q=%23%3F%3D%2B%2F%C3%A9")
    check("claude: fn K + ⌃⌘K in the list", ShortcutList.entries.contains { $0.id == "askClaude" && $0.run == "askClaude" })
}
do {   // Ask Grok (⌃⌘L)
    let G = GrokLogic.self
    check("grok: prompt + empty line + text", G.message(prompt: "Fix this", text: "a\nb") == "Fix this\n\na\nb")
    check("grok: empty prompt = text only", G.message(prompt: "  ", text: "a") == "a")
    check("grok: empty text = prompt only", G.message(prompt: "Hi", text: "") == "Hi")
    check("grok: both empty = empty", G.message(prompt: "", text: "\n") == "")
    check("grok: encodes & + = # ? space newline", G.encode("a&b+c=d#e?f g\nh/") == "a%26b%2Bc%3Dd%23e%3Ff%20g%0Ah%2F", G.encode("a&b+c=d#e?f g\nh/"))
    check("grok: encodes unicode + %", G.encode("é%⌘") == "%C3%A9%25%E2%8C%98")
    check("grok: url round-trips", G.url("x & y\n#z")?.absoluteString == "https://grok.com/?q=x%20%26%20y%0A%23z"
          && URLComponents(url: G.url("x & y\n#z")!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "x & y\n#z")
    let clean = ExportLogic.cleanText(ExportLogic.parse("# **Title**\n1. ==hi== ~~x~~\n---\nplain *it*"))
    check("grok: clean text has no markers", !clean.contains("**") && !clean.contains("==") && !clean.contains("~~") && !clean.contains("# ") && clean.hasPrefix("Title\n1. hi"), clean)
    let long = String(repeating: "word ", count: 20000)
    check("grok: long note url builds", (G.url(long)?.absoluteString.count ?? 0) > 100000)
}
do {   // fn + letter shortcuts
    let F = ShortcutList.fnLetters
    check("fn: letters unique", Set(F.values).count == F.count)
    check("fn: no macOS-reserved letter", F.values.allSatisfy { !ShortcutList.fnReserved.contains($0) })
    check("fn: every id exists with a run action", F.keys.allSatisfy { id in ShortcutList.entries.contains { $0.id == id && $0.run != nil } })
    check("fn: map", ShortcutList.fnRun("l") == "highlight" && ShortcutList.fnRun("G") == "askGrok" && ShortcutList.fnRun("J") == "copyOut" && ShortcutList.fnRun("K") == "askClaude" && ShortcutList.fnRun("M") == "postToX" && ShortcutList.fnRun("Y") == "redo" && ShortcutList.fnRun("O") == "navigator")
    check("fn: F / S / W / arrows-like not mapped", ShortcutList.fnRun("F") == nil && ShortcutList.fnRun("S") == nil && ShortcutList.fnRun("W") == nil && ShortcutList.fnRun("A") == nil)
    check("fn: Selection as note has no fn key", F["sendSelection"] == nil)
}
extension Double { func rounded(toPlaces p: Int) -> Double { let m = pow(10.0, Double(p)); return (self * m).rounded() / m } }
do {   // F1 save timing (clock is an input)
    var a = SaveScheduler(); a.changed(at: 10)
    check("save: one change saves after 1 s", !a.isDue(at: 10.99) && a.isDue(at: 11) && a.dueAt == 11)
    // A change every 0.3 s for 12 s, clock checked every 0.1 s: no change waits more than 5 s for a save.
    var b = SaveScheduler(); var saves: [Double] = []; var oldest: Double? = nil; var worst = 0.0
    for i in 0...120 {
        let t = Double(i) / 10
        if i % 3 == 0 { b.changed(at: t); if oldest == nil { oldest = t } }
        if b.isDue(at: t) { saves.append(t); worst = max(worst, t - oldest!); oldest = nil; b.saved() }
    }
    check("save: continuous changes save at least every 5 s", saves.count >= 2 && worst <= 5.0001 && saves.first == 5.0, "\(saves) worst \(worst)")
    let c = SaveScheduler()
    check("save: no change, no save", !c.pending && c.dueAt == nil && !c.isDue(at: 1000))
    var d = SaveScheduler(); d.changed(at: 1); d.saved()
    check("save: after a save, nothing due", !d.isDue(at: 100))
}
do {   // F2 library folder
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    let oct3 = cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 12))!
    check("library: name for note 23 on 3 Oct 2026", NoteLibrary.fileName(number: 23, date: oct3, calendar: cal) == "Note 23 -- 03OCT26.txt",
          NoteLibrary.fileName(number: 23, date: oct3, calendar: cal))
    check("library: Note 40 in folder + stored 5 -> next is 41", NoteLibrary.nextNumber(stored: 5, names: ["Note 40 -- 01JAN26.txt"]) == 41)
    check("library: stored number never goes back", NoteLibrary.nextNumber(stored: 50, names: ["Note 40 -- 01JAN26.txt", "x.txt"]) == 50)
    check("library: starts at 1", NoteLibrary.nextNumber(stored: 0, names: []) == 1)
    check("library: other names ignored", NoteLibrary.number(in: "Notes 9 -- x.txt") == nil && NoteLibrary.number(in: "Note x -- y.txt") == nil && NoteLibrary.number(in: "Note 7 -- 01FEB26.txt") == 7)
    check("library: a note with no characters makes no file", !NoteLibrary.needsFile(text: "", hasFile: false))
    check("library: first character makes the file; emptied note keeps it", NoteLibrary.needsFile(text: "a", hasFile: false) && NoteLibrary.needsFile(text: "", hasFile: true))
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fn-lib-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir.appendingPathComponent("sub.txt"), withIntermediateDirectories: true)
    for (n, age) in [("a.txt", 100.0), ("b.txt", 10.0), ("c.md", 0.0), (".hidden.txt", 0.0)] {
        let u = dir.appendingPathComponent(n); try? "x".write(to: u, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: u.path)
    }
    let files = NoteLibrary.noteFiles(in: dir)
    check("library: only .txt files, no subfolders/hidden", Set(files.map { $0.lastPathComponent }) == ["a.txt", "b.txt"], "\(files)")
    check("library: opens most recently changed", NoteLibrary.mostRecent(files)?.lastPathComponent == "b.txt")
    check("library: empty folder -> no file", NoteLibrary.mostRecent([]) == nil)
    try? FileManager.default.removeItem(at: dir)
}
do {   // F3 notes list
    check("list: row name '# Budget **plan**'", NoteLibrary.rowName("# Budget **plan**") == "Budget plan", NoteLibrary.rowName("# Budget **plan**"))
    check("list: row name skips empty + ---", NoteLibrary.rowName("\n---\nHello") == "Hello")
    check("list: empty note", NoteLibrary.rowName("") == "Empty note" && NoteLibrary.rowName("\n===\n  \n") == "Empty note")
    check("list: other markers removed", NoteLibrary.rowName("## <u>a</u> ==b== ~~c~~ *d*") == "a b c d", NoteLibrary.rowName("## <u>a</u> ==b== ~~c~~ *d*"))
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
    let d1 = cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 9))!
    let d2 = cal.date(from: DateComponents(year: 2025, month: 10, day: 14, hour: 9))!
    check("list: date this year", NoteLibrary.rowDate(d1, now: now, calendar: cal) == "14 Oct", NoteLibrary.rowDate(d1, now: now, calendar: cal))
    check("list: date earlier year", NoteLibrary.rowDate(d2, now: now, calendar: cal) == "14 Oct 2025")
    let L = ShortcutList.all
    check("list: shortcut entries, not on sheet", ["notesList", "listUp", "listDown", "listOpen", "listEsc", "listFilter", "listDelete"].allSatisfy { id in L.contains { $0.id == id && !$0.onSheet } })
}
do {   // ⌘⌫ delete (same function as the notes list) — fresh temp folder only
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("floatnote-delete-test-\(UUID().uuidString)", isDirectory: true)
    precondition(!dir.path.contains("/Documents/") && !dir.path.contains("Application Support"))
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let names = ["Note 1 -- 01JAN26.txt", "Note 2 -- 02JAN26.txt", "Note 3 -- 03JAN26.txt"]
    for (i, n) in names.enumerated() { try? "text \(i)".write(to: dir.appendingPathComponent(n), atomically: true, encoding: .utf8) }
    var ok = true
    let trashDir = dir.appendingPathComponent("FakeTrash", isDirectory: true)      // never the real Trash in tests
    try? fm.createDirectory(at: trashDir, withIntermediateDirectories: true)
    do { try NoteLibrary.deleteNoteFile(dir.appendingPathComponent(names[1]), mover: { try fm.moveItem(at: $0, to: trashDir.appendingPathComponent($0.lastPathComponent)) }) } catch { ok = false }
    check("delete: moved (to the trash), not destroyed", fm.fileExists(atPath: trashDir.appendingPathComponent(names[1]).path))
    try? fm.removeItem(at: trashDir)
    let left = Set((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
    check("delete: the note is gone", ok && !fm.fileExists(atPath: dir.appendingPathComponent(names[1]).path))
    check("delete: the other two stay unchanged", left == [names[0], names[2]]
          && (try? String(contentsOf: dir.appendingPathComponent(names[0]), encoding: .utf8)) == "text 0"
          && (try? String(contentsOf: dir.appendingPathComponent(names[2]), encoding: .utf8)) == "text 2", "\(left)")
    try? fm.removeItem(at: dir)
}
do {   // F4 new note
    check("new note: ⌘N on a new note does nothing", NoteLibrary.isNewNote(hasFile: false, text: ""))
    check("new note: makes no file", !NoteLibrary.needsFile(text: "", hasFile: false))
    check("new note: ⌘N acts on a note with text or a file", !NoteLibrary.isNewNote(hasFile: false, text: "a") && !NoteLibrary.isNewNote(hasFile: true, text: ""))
    check("new note: ⌘N in the shortcut list", ShortcutList.all.contains { $0.id == "newNote" && $0.keys == "⌘N" && $0.group == "Notes" && $0.name == "New note" && !$0.onSheet })
}
do {   // F5 drag to import (temp folder only; the source is never changed)
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("floatnote-import-test-\(UUID().uuidString)", isDirectory: true)
    precondition(!dir.path.contains("/Documents/") && !dir.path.contains("Application Support"))
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    check("import: .txt and .md accepted", NoteLibrary.canImport(URL(fileURLWithPath: "/x/a.txt")) && NoteLibrary.canImport(URL(fileURLWithPath: "/x/b.MD")))
    check("import: other types refused", !NoteLibrary.canImport(URL(fileURLWithPath: "/x/a.pdf")) && !NoteLibrary.canImport(URL(fileURLWithPath: "/x/txt")))
    let src = dir.appendingPathComponent("source.md")
    try? "# Héllo\n**x**".write(to: src, atomically: true, encoding: .utf8)
    let before = try? fm.attributesOfItem(atPath: src.path)[.modificationDate] as? Date
    check("import: reads UTF-8 text", NoteLibrary.readImport(src) == "# Héllo\n**x**")
    let after = try? fm.attributesOfItem(atPath: src.path)[.modificationDate] as? Date
    check("import: source unchanged and still there", fm.fileExists(atPath: src.path) && before == after
          && (try? String(contentsOf: src, encoding: .utf8)) == "# Héllo\n**x**")
    let bad = dir.appendingPathComponent("bad.txt")
    try? Data([0xFF, 0xFE, 0xC3]).write(to: bad)
    check("import: missing -> can't read", NoteLibrary.readImport(dir.appendingPathComponent("none.txt")) == nil)
    _ = bad
    try? fm.removeItem(at: dir)
}
do {   // F6 ⌃⌥S into a new note (pure parts; nothing sent anywhere)
    let add = ClipLogic.appended(selection: "Hello", app: "Safari", url: nil, date: Date(), note: "")
    check("clip: into a new note gives it text, so it gets a file", add.contains("Hello") && NoteLibrary.needsFile(text: add, hasFile: false))
    let add2 = ClipLogic.appended(selection: "x", app: "A", url: nil, date: Date(), note: "old")
    check("clip: goes after the existing text", ("old" + add2).hasPrefix("old") && add2.contains("x"))
}
do {   // ⌘O list column in fullscreen
    check("list inset: box unchanged (8)", FullscreenLogic.listInset(width: 400, fullscreen: false, "narrow") == 8 && FullscreenLogic.listInset(width: 3000, fullscreen: false, nil) == 8)
    check("list inset: fullscreen = note column", FullscreenLogic.listInset(width: 2000, fullscreen: true, "narrow") == FullscreenLogic.margin(screenWidth: 2000, "narrow")
          && FullscreenLogic.listInset(width: 2000, fullscreen: true, "wide") == FullscreenLogic.margin(screenWidth: 2000, "wide"))
}
do {   // built-in tutorial note
    let T = TutorialNote.text
    let clean = ExportLogic.cleanText(ExportLogic.parse(T))
    check("tutorial: no visible markers left", !["**", "==", "~~", "<u>", "</u>", "*"].contains { clean.replacingOccurrences(of: "===", with: "").contains($0) }
          && !clean.components(separatedBy: "\n").contains { $0.hasPrefix("# ") || $0.hasPrefix("## ") || $0 == "---" || $0 == "===" }, clean)
    check("tutorial: has titles, styles, list", T.hasPrefix("# <u>Welcome to FloatNote</u>") && T.contains("==highlight==") && T.contains("\n1. "))
    check("tutorial: covers window mode, opacity, paragraph mode, Claude, fullscreen, delete", ["## ==Move the box==", "Settings > Opacity", "## ==Paragraph mode==", "fn K (⌃⌘K)", "## Fullscreen", "⌘⌫ moves a note"].allSatisfy { T.contains($0) })
    check("tutorial: list name", NoteLibrary.rowName(T) == "Welcome to FloatNote")
    check("tutorial: first launch ever -> create", TutorialNote.shouldCreateAtLaunch(shown: false, noteCount: 0))
    check("tutorial: not when shown before or notes exist", !TutorialNote.shouldCreateAtLaunch(shown: true, noteCount: 0)
          && !TutorialNote.shouldCreateAtLaunch(shown: false, noteCount: 3))
}
do {   // default frame + no empty style markers
    let f = DefaultFrameLogic.frame(visible: NSRect(x: 0, y: 25, width: 1000, height: 800))
    check("default frame: 60% centered", f == NSRect(x: 200, y: 185, width: 600, height: 480), "\(f)")
    let P = PendingStyleLogic.self
    check("pending: underline wraps typed text", P.wrap("a", [.underline]) == ("<u>a</u>", 4))
    check("pending: bold+highlight nest", P.wrap("x", [.highlight, .bold]) == ("**==x==**", 5))
    let w = P.wrap("word", [.strike]).text
    check("pending: wrapped text renders as a span", MarkerLogic.spans(w).count == 1)
    check("strip: empty pairs go", P.stripEmptyPairs("a<u></u>b **** c ~~~~ d ==== e") == "ab  c  d  e")
    check("strip: rules and real styles stay", P.stripEmptyPairs("====\n----\n<u>x</u> ==y==") == "====\n----\n<u>x</u> ==y==")
    check("strip: nested empties", P.stripEmptyPairs("**<u></u>**") == "")
    check("strip: no change without pairs", P.stripEmptyPairs("plain **b**") == "plain **b**")
}
do {   // cheat sheet page 2
    let P = ShortcutPages.self
    check("pages: → to 2, ← back, stays in range", P.turn(0, right: true) == 1 && P.turn(1, right: false) == 0 && P.turn(1, right: true) == 1 && P.turn(0, right: false) == 0)
    check("pages: hints", P.hint(0) == "more shortcuts →" && P.hint(1) == "← 2/2")
    let secs = P.sections()
    let ids = secs.flatMap { $0.rows.map { $0.id } }
    check("page 2: every ShortcutList entry exactly once", ids == ShortcutList.all.map { $0.id }, "\(ids.count) vs \(ShortcutList.all.count)")
    let allRows: [ShortcutPages.Row] = secs.flatMap { $0.rows }
    let claudeKeys = allRows.first { $0.id == "askClaude" }?.keys ?? ""
    let hlKeys = allRows.first { $0.id == "highlight" }?.keys ?? ""
    check("page 2: fn and ⌘ keys together", claudeKeys == "fn K / ⌃⌘K" && hlKeys == "fn L / ⇧⌘H", claudeKeys + " " + hlKeys)
    let cols = P.columns(secs)
    let hs = cols.map { $0.reduce(0) { $0 + P.lines($1) } }
    let biggest = secs.map { P.lines($0) }.max() ?? 0
    check("page 2: 3 balanced columns, whole sections in order", cols.count == 3 && cols.flatMap { $0 } == secs && (hs.max()! - hs.min()!) <= biggest, "\(hs)")
}
do {   // at-rest opacity by theme
    check("rest alpha: light 2.5%, dark 5%", RestAlphaLogic.rest(dark: false) == 0.025 && RestAlphaLogic.rest(dark: true) == 0.05)
    let T = TutorialNote.text
    check("tutorial: matches docs copy line count", T.components(separatedBy: "\n").count == 189 && T.contains("# <u>Trash</u>"))
}
do {   // new notes start on a title line
    let N = NewNoteTitleLogic.self
    let z = NSRange(location: 0, length: 0)
    check("title: first letter becomes a title", N.edit(pending: true, docEmpty: true, range: z, rep: "H") == .insert("# H", caret: 3))
    check("title: Return on the empty first line = body text, nothing inserted", N.edit(pending: true, docEmpty: true, range: z, rep: "\n") == .swallow)
    check("title: not pending / not empty / not at start = normal", N.edit(pending: false, docEmpty: true, range: z, rep: "H") == .normal
          && N.edit(pending: true, docEmpty: false, range: z, rep: "H") == .normal)
    check("title: multi-line paste goes in as is", N.edit(pending: true, docEmpty: true, range: z, rep: "a\nb") == .normal)
    check("title: typed title parses as a title", ExportLogic.parse("# H").first.map { "\($0.kind)" }?.contains("title") ?? false, "\(ExportLogic.parse("# H"))")
    check("title: an untouched new note gets no file", !NoteLibrary.needsFile(text: "", hasFile: false))
}
do {   // library cleanup (temp folder only)
    let C = NoteCleanup.self
    check("empty: whitespace, #, ## only", C.isEmpty("") && C.isEmpty(" \n\t") && C.isEmpty("# ") && C.isEmpty("##\n") && C.isEmpty("#"))
    check("empty: any real content is kept", !C.isEmpty("a") && !C.isEmpty("# A") && !C.isEmpty("---") && !C.isEmpty("###") && !C.isEmpty("1. "))
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fn-clean-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    func mk(_ n: String, _ t: String) -> URL { let u = dir.appendingPathComponent(n); try? t.write(to: u, atomically: true, encoding: .utf8); return u }
    let e1 = mk("Note 1 -- 01JAN26.txt", "# "), e2 = mk("Note 2 -- 01JAN26.txt", "  \n"), real = mk("Note 3 -- 01JAN26.txt", "#Hi")
    let tut = mk("Note 4 -- 01JAN26.txt", TutorialNote.text), other = mk("Note 5 -- 01JAN26.txt", TutorialNote.text)
    let files = NoteLibrary.noteFiles(in: dir)
    let empties = Set(C.emptyFiles(files).map { $0.lastPathComponent })
    check("cleanup: only the empty files", empties == [e1.lastPathComponent, e2.lastPathComponent], "\(empties)")
    check("cleanup: keep skips the open note", !C.emptyFiles(files, keep: e1).contains { $0.lastPathComponent == e1.lastPathComponent })
    let left = C.tutorialLeftovers(tracked: [tut.lastPathComponent, "Gone.txt"], files: files).map { $0.lastPathComponent }
    check("tutorial: only tracked files that exist (not by content)", left == [tut.lastPathComponent] && !left.contains(other.lastPathComponent))
    check("tutorial: keep skips the open note", C.tutorialLeftovers(tracked: [tut.lastPathComponent], files: files, keep: tut).isEmpty)
    check("hint: below 20 notes only", C.showTutorialHint(noteCount: 0) && C.showTutorialHint(noteCount: 19) && !C.showTutorialHint(noteCount: 20))
    _ = real
    try? FileManager.default.removeItem(at: dir)
}
do {   // permanent delete + sandbox
    let L = ShortcutList.all
    check("list: ⌥⌘⌫ Trash now + ⌘⌫ Trash (asks); no permanent delete", L.contains { $0.id == "listTrashNow" && $0.keys == "⌥⌘⌫" && $0.name.contains("Trash") && $0.name.contains("no permanent") } && L.contains { $0.id == "listDelete" && $0.name.contains("Trash") } && !L.contains { $0.id == "listDeleteForever" || $0.name.lowercased().contains("forever") })
    check("tutorial: Trash section mentions Put Back and Empty Trash", TutorialNote.text.contains("Put Back") && TutorialNote.text.contains("Empty Trash") && TutorialNote.text.contains("⌥⌘⌫"))
}
do {   // paragraph mode is the star
    let T = TutorialNote.text
    let sample = T.components(separatedBy: "\n").first { $0.hasPrefix("Thanks for the meeting") } ?? ""
    check("tutorial: teaser near the top", (T.range(of: "Don't miss Paragraph mode")?.lowerBound ?? T.endIndex) < (T.range(of: "# <u>Writing</u>")?.lowerBound ?? T.startIndex))
    check("tutorial: messy sample is one paragraph of several sentences", sample.components(separatedBy: ". ").count >= 5)
    check("tutorial: highlighted subtitle parses", HeadingLogic.kind("## ==Paragraph mode==")?.kind == .subtitle && MarkerLogic.spans("==Paragraph mode==").count == 1)
}
do {   // tutorial opacity
    let C = NoteCleanup.self
    check("tutorial opacity: at least 90%, higher saved stays", C.tutorialOpacity(saved: 0.6) == 0.9 && C.tutorialOpacity(saved: 1.0) == 1.0 && C.tutorialOpacity(saved: 0.15) == 0.9)
}
do {   // opacity keys without Shift
    let O = OpacityKeyLogic.self
    check("opacity: , and . by key position", O.direction(keyCode: 43, characters: ",") == -1 && O.direction(keyCode: 47, characters: ".") == 1)
    check("opacity: < > still work", O.direction(keyCode: 43, characters: "<") == -1 && O.direction(keyCode: 47, characters: ">") == 1)
    check("opacity: other layouts by key position", O.direction(keyCode: 43, characters: ";") == -1 && O.direction(keyCode: 47, characters: ":") == 1)
    check("opacity: other keys ignored", O.direction(keyCode: 13, characters: "w") == nil)
}
do {   // bigger notes list
    let N = NotesListSize.self
    check("notes list: 13 -> 17, 16 -> 21", N.font(13) == 17 && N.font(16) == 21)
    check("notes list: row spacing and padding scale", N.rowSpacing(17) == 6 && N.topInset(fullscreen: false) == 5 && N.topInset(fullscreen: true) == 80)
}
do {   // page 1 prompt pulses until page 2 was seen
    let P = ShortcutPages.self
    check("prompt: pulses on page 1 until page 2 seen", P.pulses(page: 0, page2Seen: false) && !P.pulses(page: 0, page2Seen: true) && !P.pulses(page: 1, page2Seen: false))
    check("tutorial: two pages of ⌘/", TutorialNote.text.contains("The sheet has two pages"))
}
do {   // tutorial highlights
    let H = TutorialHighlight.self
    let T = TutorialNote.text
    let heads = T.components(separatedBy: "\n").filter { HeadingLogic.kind($0) != nil && H.isHighlight(titleLine: $0) }
    check("highlights: three banded section titles", heads.count == 3, "\(heads)")
    check("highlights: normal titles are not banded", !H.isHighlight(titleLine: "## Fullscreen") && !H.isHighlight(titleLine: "# Shopping"))
    check("highlights: Copy out text has no band marker", !ExportLogic.cleanText(ExportLogic.parse(T)).contains("floatnote"))
}
do {   // optional Grok / Claude setup
    check("setup: sign-in sites", AskSites.grok?.absoluteString == "https://grok.com/" && AskSites.claude?.absoluteString == "https://claude.ai/")
    check("setup: tutorial says it's optional", TutorialNote.text.contains("Set up (optional)") && TutorialNote.text.contains("One, both or neither is fine"))
}
do {   // hide closes Settings, cheat sheet, Ask field
    let H = HideCloseLogic.self
    check("hide: closes what is open", H.toClose(settingsOpen: true, cheatOpen: true, askOpen: true) == ["settings", "cheatSheet", "askField"])
    check("hide: nothing open, nothing to close", H.toClose(settingsOpen: false, cheatOpen: false, askOpen: false).isEmpty)
}
do {   // ⌘O notes list: day separators
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
    func d(_ s: String) -> Date { let f = ISO8601DateFormatter(); return f.date(from: s)! }
    let D = NotesListDays.self
    let dates = [d("2026-10-14T21:00:00Z"), d("2026-10-14T05:00:00Z"), d("2026-10-14T03:00:00Z"), d("2026-10-12T15:00:00Z"), d("2026-10-12T14:00:00Z")]
    let L = D.lines(dates, calendar: cal)
    check("days: groups by local day", L == [.row(0), .row(1), .separator, .row(2), .separator, .row(3), .row(4)])
    check("days: no separator before the first row or for one day", D.lines([], calendar: cal).isEmpty && D.lines([dates[0], dates[1]], calendar: cal) == [.row(0), .row(1)])
    check("days: every row appears once, in order", L.compactMap { if case .row(let i) = $0 { return i } else { return nil } } == Array(0..<5))
    check("days: ↑↓ move by rows (separators skipped)", D.move(1, by: 1, count: 5) == 2 && D.move(2, by: -1, count: 5) == 1 && D.move(4, by: 1, count: 5) == 4 && D.move(0, by: -1, count: 5) == 0 && D.move(0, by: 1, count: 0) == 0)
    check("days: separator alpha 18%", D.separatorAlpha == 0.18)
}

do {   // ⌘O list: created date (filename day, else creation date), order, atomic saves keep it; delete cursor
    let fm = FileManager.default
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
    let N = NoteLibrary.self
    let d14 = N.filenameDate("Note 18 -- 14OCT26.txt", calendar: cal)!
    check("created: filename day 14OCT26 -> 14 Oct 2026 (noon)", cal.dateComponents([.year, .month, .day, .hour], from: d14) == DateComponents(year: 2026, month: 10, day: 14, hour: 12))
    check("created: other names have no filename date", N.filenameDate("notes.txt", calendar: cal) == nil && N.filenameDate("Note 5 -- 31FEB26.txt", calendar: cal) == nil && N.filenameDate("Note x -- 14OCT26.txt", calendar: cal) == nil && N.filenameDate("Note 5 -- 14XYZ26.txt", calendar: cal) == nil)
    check("created: shown date comes from the filename", N.rowDate(d14, now: d14, calendar: cal) == "14 Oct")
    let dir = fm.temporaryDirectory.appendingPathComponent("fn-created-\(UUID().uuidString)", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let app = dir.appendingPathComponent("Note 18 -- 14OCT26.txt"), imp = dir.appendingPathComponent("import.txt")
    _ = N.writeAtomically("a", to: app); _ = N.writeAtomically("b", to: imp)
    let old = cal.date(from: DateComponents(year: 2026, month: 9, day: 3, hour: 9))!
    try? fm.setAttributes([.creationDate: old], ofItemAtPath: imp.path)
    check("created: file without a note-name uses its creation date", cal.isDate(N.createdDate(imp, calendar: cal), inSameDayAs: old))
    check("created: app note ignores the file's own dates", cal.isDate(N.createdDate(app, calendar: cal), inSameDayAs: d14))
    // atomic save keeps the creation date
    _ = N.writeAtomically("edited once", to: imp); Thread.sleep(forTimeInterval: 1.1); _ = N.writeAtomically("edited twice", to: imp)
    let after = N.creationDate(imp)
    check("atomic save: creation date unchanged by edits", after != nil && abs(after!.timeIntervalSince(old)) < 1, "\(String(describing: after))")
    check("atomic save: text written, no temp file left", (try? String(contentsOf: imp, encoding: .utf8)) == "edited twice" && ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).allSatisfy { !$0.contains(".saving-") })
    // new file: creation date is simply now
    check("atomic save: new file gets a creation date", N.creationDate(app) != nil)
    try? fm.removeItem(at: dir)
    // order: newest created day first; same day -> higher number first; imports by creation time
    let u = { (n: String) in URL(fileURLWithPath: "/x/" + n) }
    let items: [(url: URL, created: Date)] = [
        (u("Note 3 -- 13OCT26.txt"), N.filenameDate("Note 3 -- 13OCT26.txt", calendar: cal)!),
        (u("Note 18 -- 14OCT26.txt"), N.filenameDate("Note 18 -- 14OCT26.txt", calendar: cal)!),
        (u("Note 22 -- 15OCT26.txt"), N.filenameDate("Note 22 -- 15OCT26.txt", calendar: cal)!),
        (u("Note 25 -- 15OCT26.txt"), N.filenameDate("Note 25 -- 15OCT26.txt", calendar: cal)!),
        (u("notes.txt"), cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 8))!)]
    let order = N.sortedForList(items, calendar: cal).map { $0.url.lastPathComponent }
    check("order: by created day, then note number, then time", order == ["Note 25 -- 15OCT26.txt", "Note 22 -- 15OCT26.txt", "Note 18 -- 14OCT26.txt", "notes.txt", "Note 3 -- 13OCT26.txt"], "\(order)")
    // a later edit (modified today) changes neither date nor order
    let seps = NotesListDays.lines(N.sortedForList(items, calendar: cal).map { $0.created }, calendar: cal)
    check("separators follow the created days", seps == [.row(0), .row(1), .separator, .row(2), .row(3), .separator, .row(4)])
    check("delete: cursor goes to the next note, last -> previous, empty -> 0", N.cursorAfterDelete(cursor: 1, remaining: 4) == 1 && N.cursorAfterDelete(cursor: 3, remaining: 3) == 2 && N.cursorAfterDelete(cursor: 0, remaining: 0) == 0)
}
do {   // highlight / styles never change letters or case; markers go after "# " and "1. "; last line at the end of the note
    let M = MarkerLogic.self
    func apply(_ text: String, _ select: String, _ style: MarkerLogic.Style) -> String? {
        let ns = text as NSString
        guard let t = M.toggleSelection(ns, selection: ns.range(of: select), style: style) else { return nil }
        return ns.replacingCharacters(in: t.whole, with: t.text)
    }
    func letters(_ s: String) -> String { M.tokens.values.reduce(s) { $0.replacingOccurrences(of: $1.open, with: "").replacingOccurrences(of: $1.close, with: "") } }
    let samples = ["HELLO WORLD", "Mixed Case Text", "all lower", "ÉCOLE Straße", "ABC def GHI"]
    var allSame = true, allWrapped = true, roundTrip = true
    for st in MarkerLogic.Style.allCases {
        for smp in samples {
            let text = "intro\n\(smp)\nend"
            guard let out = apply(text, smp, st) else { allWrapped = false; continue }
            let o = M.tokens[st]!
            if !out.contains(o.open + smp + o.close) { allWrapped = false }
            if letters(out) != text { allSame = false }
            if apply(out, o.open + smp + o.close, st) != text { roundTrip = false }
        }
    }
    check("highlight/bold/italic/underline/strike: letters and case unchanged (mixed, all caps, lower, accents)", allSame && allWrapped)
    check("styles: toggling twice restores the exact text", roundTrip)
    check("highlight ALL CAPS: ==HELLO WORLD==", apply("x\nHELLO WORLD\ny", "HELLO WORLD", .highlight) == "x\n==HELLO WORLD==\ny")
    check("highlight with strikethrough: both markers, case kept", apply("~~HELLO WORLD~~", "HELLO WORLD", .highlight) == "~~==HELLO WORLD==~~" && apply("==HELLO WORLD==", "HELLO WORLD", .strike) == "==~~HELLO WORLD~~==")
    check("highlight keeps ALL CAPS text uppercase (it is not the ALL CAPS toggle)", apply("MY TITLE", "MY TITLE", .highlight) == "==MY TITLE==")
    // headings and list items: the marker goes after "# ", "## " and "12. " so the line stays a heading / list item
    check("title: whole line selected -> markers after '# '", apply("# my title\nbody", "# my title", .highlight) == "# ==my title==\nbody")
    check("subtitle: whole line selected -> markers after '## '", apply("## my sub\nbody", "## my sub", .highlight) == "## ==my sub==\nbody")
    check("title + body selected: title keeps '# ', body wrapped", apply("# my title\nbody text\nz", "# my title\nbody text", .bold) == "# **my title**\n**body text**\nz")
    check("list item: markers after '1. '", apply("1. alpha beta\n2. gamma", "1. alpha beta", .highlight) == "1. ==alpha beta==\n2. gamma")
    check("heading marker alone selected: nothing to style", apply("# my title", "# ", .highlight) == nil)
    check("title toggled off again keeps its '# '", apply("# ==my title==", "my title", .highlight) == "# my title")
    // selection that ends at the very end of the note (used to repeat the last line and crash)
    let ns = "intro\nHELLO WORLD" as NSString
    check("segments: last line at the end of the note appears once", M.segments(in: ns, selection: ns.range(of: "HELLO WORLD")) == [NSRange(location: 6, length: 11)])
    check("segments: select all, three lines, each once", M.segments(in: "a\nb\nc" as NSString, selection: NSRange(location: 0, length: 5)) == [NSRange(location: 0, length: 1), NSRange(location: 2, length: 1), NSRange(location: 4, length: 1)])
    check("segments: whole note selected -> highlight does not crash and wraps each line", apply("one\ntwo", "one\ntwo", .highlight) == "==one==\n==two==")
    check("segments: blank lines inside a selection are skipped", apply("a\n\nb", "a\n\nb", .highlight) == "==a==\n\n==b==")
}
do {   // ⌃⌥S: selection -> a new note (temp folder only; no keys, no clipboard, no real notes)
    let S = SelectionNote.self, N = NoteLibrary.self, fm = FileManager.default
    check("selection note: text kept exactly (case, newlines, markers)", S.text(from: "HELLO World\n==x==\n") == "HELLO World\n==x==\n")
    check("selection note: nothing / blanks -> no note", S.text(from: nil) == nil && S.text(from: "") == nil && S.text(from: " \n\t ") == nil)
    check("⌃⌥S: one shortcut with these keys, global, run sendSelection", ShortcutList.all.filter { $0.keys == "⌃⌥S" }.map { $0.id } == ["sendSelection"] && ShortcutList.all.first { $0.id == "sendSelection" }?.scope == "global" && ShortcutList.all.first { $0.id == "sendSelection" }!.name.contains("open note"))
    check("selection note: single newlines -> one blank line", S.noteText(from: "One line.\nSecond para.\nThird.") == "One line.\n\nSecond para.\n\nThird.")
    check("selection note: one blank line stays one", S.noteText(from: "A.\n\nB.") == "A.\n\nB.")
    check("selection note: several blank lines (also spaces/tabs, \\r\\n) collapse to one", S.noteText(from: "A.\n\n\n\n  \t\nB.\r\n\r\nC.") == "A.\n\nB.\n\nC.")
    check("selection note: leading/trailing blank lines dropped", S.noteText(from: "\n\nA.\nB.\n\n") == "A.\n\nB.")
    check("selection note: line contents unchanged (case, inner/leading spaces, markers)", S.noteText(from: "  HELLO  World ==x==\n\tIndented *i*") == "  HELLO  World ==x==\n\n\tIndented *i*")
    check("selection note: one line, and blank selection", S.noteText(from: "Just one line") == "Just one line" && S.noteText(from: " \n ") == nil && S.noteText(from: nil) == nil)
    check("selection note: normalizing twice changes nothing", S.noteText(from: S.noteText(from: "a\nb\n\n\nc")) == "a\n\nb\n\nc")
    let dir = fm.temporaryDirectory.appendingPathComponent("fn-selnote-\(UUID().uuidString)", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let existing = N.fileName(number: 7, date: Date())
    _ = N.writeAtomically("older", to: dir.appendingPathComponent(existing))
    let next = N.nextNumber(stored: 1, names: [existing])
    let name = N.fileName(number: next, date: Date())
    let url = dir.appendingPathComponent(name)
    let selected = "A SELECTED BLOCK\nof Text"
    let ok = N.writeAtomically(S.text(from: selected)!, to: url)
    let cal = Calendar.current
    check("selection note: new file with the next number and today's standard name", ok && name.hasPrefix("Note 8 -- ") && N.number(in: name) == 8 && N.filenameDate(name).map { cal.isDateInToday($0) } == true, name)
    check("selection note: contains exactly the selected text; the older note is untouched", (try? String(contentsOf: url, encoding: .utf8)) == selected && (try? String(contentsOf: dir.appendingPathComponent(existing), encoding: .utf8)) == "older")
    check("selection note: created date is today (filename and file)", cal.isDateInToday(N.createdDate(url)) && (N.creationDate(url).map { abs($0.timeIntervalSinceNow) < 60 } ?? false))
    check("selection note: listed with the other notes", Set(N.noteFiles(in: dir).map { $0.lastPathComponent }) == [existing, name])
    try? fm.removeItem(at: dir)
    // ⌃⌥S now adds the selection to the OPEN note; a new note only when nothing is open
    check("⌃⌥S target: a note with a file, or with text, is appended to", S.target(hasFile: true, text: "") == .appendToOpenNote && S.target(hasFile: false, text: "hello") == .appendToOpenNote && S.target(hasFile: true, text: "x") == .appendToOpenNote)
    check("⌃⌥S target: no file and nothing typed (also only blank space) = new note", S.target(hasFile: false, text: "") == .newNote && S.target(hasFile: false, text: " \n\t ") == .newNote)
    func applied(_ existing: String, _ sel: String?) -> String? {
        guard let e = S.appendEdit(existing: existing, selection: sel) else { return nil }
        return (existing as NSString).replacingCharacters(in: NSRange(location: e.location, length: e.length), with: e.text)
    }
    check("append: one blank line between the note and the block", applied("First note.", "Added text") == "First note.\n\nAdded text")
    check("append: a trailing newline / blank lines / spaces at the end are replaced by exactly one blank line", applied("A\n", "B") == "A\n\nB" && applied("A\n\n\n\n", "B") == "A\n\nB" && applied("A  \n \n", "B") == "A\n\nB" && applied("A\n\n", "B") == "A\n\nB")
    check("append: the block is normalized like a new note (single newlines -> blank line, extra blank lines collapse)", applied("Top", "One.\nTwo.\n\n\n\nThree.") == "Top\n\nOne.\n\nTwo.\n\nThree.")
    check("append: an empty note gets no leading blank lines", applied("", "Hello\nWorld") == "Hello\n\nWorld" && applied("\n\n  \n", "Hello") == "Hello")
    check("append: case, markers and inner spaces are kept", applied("x", "  LOUD ==hi==  there") == "x\n\n  LOUD ==hi==  there")
    check("append: blank selection = no edit", S.appendEdit(existing: "x", selection: nil) == nil && S.appendEdit(existing: "x", selection: " \n ") == nil)
    check("append: emoji and accents before the end (UTF-16 offsets)", applied("Caf\u{E9} \u{1F600}\n", "z") == "Caf\u{E9} \u{1F600}\n\nz")
    check("append: titles and lists above stay untouched", applied("# Title\n1. one\n- two", "more") == "# Title\n1. one\n- two\n\nmore")
    check("append: appending twice = two blocks, one blank line each", applied(applied("A", "B")!, "C") == "A\n\nB\n\nC")
    do {   // the file: same name and creation date, atomic, content = old + block
        let d2 = fm.temporaryDirectory.appendingPathComponent("fn-append-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: d2, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: d2) }
        let f = d2.appendingPathComponent("Note 3 -- Plan -- 14OCT26.txt")
        _ = N.writeAtomically("Plan A\n", to: f)
        let born = Date(timeIntervalSince1970: 1_700_000_000)
        try? fm.setAttributes([.creationDate: born], ofItemAtPath: f.path)
        let old = N.readText(f) ?? ""
        let new = applied(old, "From the web.\nSecond line.")!
        check("append file: written atomically, same file name, created date kept, content old + block",
              N.writeAtomically(new, to: f) && N.readText(f) == "Plan A\n\nFrom the web.\n\nSecond line."
              && N.noteFiles(in: d2).map { $0.lastPathComponent } == ["Note 3 -- Plan -- 14OCT26.txt"]
              && abs((N.creationDate(f) ?? .distantPast).timeIntervalSince(born)) < 1)
    }
}
do {   // ⌘O list, mouse: hit-testing and click dispatch (pure parts; hover drawing / real clicks are not testable here)
    let M = NotesListMouse.self
    // rows of 20 pt with 6 pt between them, a 18 pt gap (day separator) before the 3rd row
    let rects = [CGRect(x: 0, y: 30, width: 100, height: 20), CGRect(x: 0, y: 56, width: 100, height: 20), CGRect(x: 0, y: 94, width: 100, height: 20)]
    check("mouse: a point on a row hits that row", M.row(atY: 40, rects: rects, pad: 4) == 0 && M.row(atY: 66, rects: rects, pad: 4) == 1 && M.row(atY: 100, rects: rects, pad: 4) == 2)
    check("mouse: no dead strip between neighbouring rows", (50..<56).allSatisfy { M.row(atY: CGFloat($0), rects: rects, pad: 4) != nil })
    check("mouse: header, above the first row and below the last hit nothing", M.row(atY: 10, rects: rects, pad: 4) == nil && M.row(atY: 200, rects: rects, pad: 4) == nil)
    check("mouse: the middle of a day separator hits nothing; its edges belong to the neighbour rows", M.row(atY: 85, rects: rects, pad: 4) == nil && M.row(atY: 78, rects: rects, pad: 4) == 1 && M.row(atY: 91, rects: rects, pad: 4) == 2)
    check("mouse: no rows (empty / no matches) -> nothing", M.row(atY: 40, rects: [], pad: 4) == nil)
    check("mouse: single click selects, double click opens", M.action(hit: 1, clickCount: 1, rowCount: 3) == .select(1) && M.action(hit: 2, clickCount: 2, rowCount: 3) == .open(2) && M.action(hit: 0, clickCount: 3, rowCount: 3) == .open(0))
    check("mouse: click on nothing / out of range does nothing", M.action(hit: nil, clickCount: 1, rowCount: 3) == .none && M.action(hit: 3, clickCount: 2, rowCount: 3) == .none && M.action(hit: -1, clickCount: 1, rowCount: 3) == .none && M.action(hit: 0, clickCount: 1, rowCount: 0) == .none)
    check("mouse: selection by click = the cursor move the arrow keys make (same index space as listRows)", NotesListDays.move(0, by: 2, count: 3) == 2)
    let N = NoteLibrary.self, cal = Calendar.current
    // ---- rename = the FILE gets a custom name (first line untouched) ----
    check("rename: customName of the plain app name is nil (list shows first line)", N.customName(inFileName: "Note 5 -- 14OCT26.txt") == nil)
    check("rename: customName of 'Note N -- name -- DATE.txt' is the name", N.customName(inFileName: "Note 5 -- Garden plan -- 14OCT26.txt") == "Garden plan")
    check("rename: a name containing dashes and digits survives", N.customName(inFileName: "Note 5 -- Q3 - plan 2026 -- 14OCT26.txt") == "Q3 - plan 2026")
    check("rename: Finder-renamed 'Note N -- name.txt' (date removed) shows the name", N.customName(inFileName: "Note 5 -- Groceries.txt") == "Groceries")
    check("rename: Finder-renamed to anything else shows the file name; notes.txt keeps the first line", N.customName(inFileName: "Budget 2026.txt") == "Budget 2026" && N.customName(inFileName: "notes.txt") == nil)
    check("rename: displayName falls back to the first line", N.displayName(fileName: "Note 5 -- 14OCT26.txt", text: "# Hello\nbody") == N.rowName("# Hello\nbody") && N.displayName(fileName: "Note 5 -- Mine -- 14OCT26.txt", text: "# Hello") == "Mine")
    check("rename: the date is still read from a renamed file", N.filenameDate("Note 5 -- Garden plan -- 14OCT26.txt", calendar: cal) == N.filenameDate("Note 5 -- 14OCT26.txt", calendar: cal) && N.filenameDate("Note 5 -- Garden plan -- 14OCT26.txt", calendar: cal) != nil)
    check("rename: a custom name looking like a date does not fool the parser", N.filenameDate("Note 5 -- 01JAN20 -- 14OCT26.txt", calendar: cal) == N.filenameDate("Note 5 -- 14OCT26.txt", calendar: cal))
    check("rename: the number is still read (numbering never reuses it)", N.number(in: "Note 7 -- Plan -- 14OCT26.txt") == 7 && N.nextNumber(stored: 1, names: ["Note 7 -- Plan -- 14OCT26.txt", "Note 3 -- 14OCT26.txt"]) == 8)
    check("rename: sanitize drops / : \\ and control chars, ' -- ', leading dots, .txt", N.sanitizedName("a/b:c\\d") == "a b c d" && N.sanitizedName("x -- y") == "x - y" && N.sanitizedName("..hidden") == "hidden" && N.sanitizedName("report.txt") == "report" && N.sanitizedName("  \n ") == "")
    check("rename: very long names are cut", N.sanitizedName(String(repeating: "a", count: 300)).count == 80)
    check("rename: blank / all-illegal on a note with no custom name changes nothing", N.renamedFileName(old: "Note 5 -- 14OCT26.txt", newName: "   ") == nil && N.renamedFileName(old: "Note 5 -- 14OCT26.txt", newName: "///") == nil)
    check("rename: blank removes the custom name (number and date stay)", N.renamedFileName(old: "Note 5 -- Plan -- 14OCT26.txt", newName: "") == "Note 5 -- 14OCT26.txt")
    check("rename: blank on a Finder-edited 'Note N -- name.txt' restores the default from the created date", N.renamedFileName(old: "Note 5 -- Groceries.txt", newName: "", created: cal.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))) == "Note 5 -- 14OCT26.txt")
    check("rename: blank on plain Finder-named files and notes.txt = cancel", N.renamedFileName(old: "Budget.txt", newName: "") == nil && N.renamedFileName(old: "notes.txt", newName: "  ") == nil)
    check("rename: new file name keeps number and date", N.renamedFileName(old: "Note 5 -- 14OCT26.txt", newName: "Plan") == "Note 5 -- Plan -- 14OCT26.txt" && N.renamedFileName(old: "Note 5 -- Plan -- 14OCT26.txt", newName: "Other") == "Note 5 -- Other -- 14OCT26.txt")
    check("rename: other files become '<name>.txt'", N.renamedFileName(old: "Budget.txt", newName: "Bills") == "Bills.txt")
    do {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fn-rename-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("Note 5 -- 14OCT26.txt"), b = dir.appendingPathComponent("Note 6 -- 14OCT26.txt")
        _ = N.writeAtomically("# First line\nbody", to: a); _ = N.writeAtomically("other", to: b)
        let born = N.creationDate(a)
        Thread.sleep(forTimeInterval: 1.1)
        let r1 = N.renameNote(a, to: "Garden plan")
        check("rename: file moved to 'Note 5 -- Garden plan -- 14OCT26.txt'", r1?.lastPathComponent == "Note 5 -- Garden plan -- 14OCT26.txt" && !FileManager.default.fileExists(atPath: a.path))
        check("rename: content (first line) untouched", (try? String(contentsOf: r1!, encoding: .utf8)) == "# First line\nbody")
        check("rename: creation date and list date unchanged", N.creationDate(r1!) == born && N.createdDate(r1!, calendar: cal) == N.createdDate(a, calendar: cal))
        _ = N.writeAtomically("# First line\nbody, edited", to: r1!)
        check("rename: saving a renamed note keeps its creation date", N.creationDate(r1!) == born)
        check("rename: same name changes nothing", N.renameNote(r1!, to: "Garden plan") == nil && FileManager.default.fileExists(atPath: r1!.path))
        let r2 = N.renameNote(b, to: "Garden plan")
        check("rename: a name collision gets ' 2' (nothing overwritten)", r2?.lastPathComponent == "Note 6 -- Garden plan -- 14OCT26.txt" && (try? String(contentsOf: r1!, encoding: .utf8)) == "# First line\nbody, edited")
        let plain = dir.appendingPathComponent("Bills.txt"), plain2 = dir.appendingPathComponent("Budget.txt")
        _ = N.writeAtomically("x", to: plain); _ = N.writeAtomically("y", to: plain2)
        let r3 = N.renameNote(plain2, to: "Bills")
        check("rename: collision on a plain name -> 'Bills 2.txt'", r3?.lastPathComponent == "Bills 2.txt" && FileManager.default.fileExists(atPath: plain.path))
        let r4 = N.renameNote(r1!, to: "garden PLAN")
        check("rename: case-only change works", r4?.lastPathComponent == "Note 5 -- garden PLAN -- 14OCT26.txt")
        let r5 = N.renameNote(r4!, to: "")
        check("rename: blank commit on disk -> default name, content and creation date intact", r5?.lastPathComponent == "Note 5 -- 14OCT26.txt" && N.customName(inFileName: r5!.lastPathComponent) == nil && N.creationDate(r5!) == born && (try? String(contentsOf: r5!, encoding: .utf8)) == "# First line\nbody, edited")
        check("rename: blank again changes nothing", N.renameNote(r5!, to: "") == nil && FileManager.default.fileExists(atPath: r5!.path))
        check("rename: blank on a plain file changes nothing", N.renameNote(r3!, to: "") == nil && FileManager.default.fileExists(atPath: r3!.path))
        _ = N.renameNote(r5!, to: "garden PLAN")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        check("rename: no stray files left behind", names.count == 4, "\(names)")
        let items: [(url: URL, created: Date)] = [r2!, r4!].map { (url: $0, created: N.createdDate($0, calendar: Calendar.current)) }
        check("rename: renamed notes still list (same day, ordered by number)", N.sortedForList(items, calendar: Calendar.current).map { N.number(in: $0.url.lastPathComponent) ?? 0 } == [6, 5])
    }
    // ---- fullscreen with the ⌘O list open ----
    let FL = FullscreenLogic.self
    check("list+fullscreen: fn+F toggles while the list is open (list stays open)", FL.canToggle(listOpen: true, renaming: false, askDelete: false, navOpen: false, textFocused: false))
    check("list+fullscreen: ignored while the rename field or the delete confirm is up", !FL.canToggle(listOpen: true, renaming: true, askDelete: false, navOpen: false, textFocused: false) && !FL.canToggle(listOpen: true, renaming: false, askDelete: true, navOpen: false, textFocused: false))
    check("list+fullscreen: the note still needs its text focused; navigator still blocks", FL.canToggle(listOpen: false, renaming: false, askDelete: false, navOpen: false, textFocused: true) && !FL.canToggle(listOpen: false, renaming: false, askDelete: false, navOpen: false, textFocused: false) && !FL.canToggle(listOpen: false, renaming: false, askDelete: false, navOpen: true, textFocused: true))
    check("list+fullscreen: list key fn+F -> fullscreen, plain f (filter typing) is not", FL.listShortcut(keyCode: 3, flags: [.function]) == "fullscreen" && FL.listShortcut(keyCode: 3, flags: []) == nil && FL.listShortcut(keyCode: 3, flags: [.function, .command]) == nil)
    check("list+fullscreen: list key ⌘W -> minimize (box or fullscreen, same rule), other ⌘ keys are not", FL.listShortcut(keyCode: 13, flags: [.command]) == "minimize" && FL.listShortcut(keyCode: 13, flags: []) == nil && FL.listShortcut(keyCode: 13, flags: [.command, .shift]) == nil && FL.listShortcut(keyCode: 0, flags: [.command]) == nil)
    check("list+fullscreen: the list column insets follow the new width", FL.listInset(width: 1000, fullscreen: true, "wide") == 250 && FL.listInset(width: 1000, fullscreen: false, "wide") == 8)
    check("rename: in the shortcut list (← → R F2), notesList scope", ShortcutList.all.contains { $0.id == "listRename" && $0.scope == "notesList" && $0.keys.contains("←") && $0.keys.contains("→") })
    check("mouse: in the shortcut list, notesList scope, not on the sheet", ShortcutList.all.contains { $0.id == "listMouse" && $0.scope == "notesList" && !$0.onSheet })
}
print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
