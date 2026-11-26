// Generates demo/greek-study-book-demo.pdf: a fictional 10-page Greek workbook for trying Fylladio
// (words to underline and highlight, blanks to fill, boxes to tick, a "scanned" page without a text layer,
// and an answer key to bookmark). Run: swift scripts/make-demo.swift
import AppKit
import CoreText

let W: CGFloat = 595, H: CGFloat = 842, M: CGFloat = 56
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "demo/greek-study-book-demo.pdf")
try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)

// MARK: Style

let ink = NSColor(white: 0.12, alpha: 1)
let soft = NSColor(white: 0.40, alpha: 1)
let blue = NSColor(srgbRed: 0.10, green: 0.33, blue: 0.62, alpha: 1)
let orange = NSColor(srgbRed: 0.88, green: 0.42, blue: 0.10, alpha: 1)
let green = NSColor(srgbRed: 0.16, green: 0.55, blue: 0.33, alpha: 1)
let purple = NSColor(srgbRed: 0.45, green: 0.27, blue: 0.62, alpha: 1)
let paleBlue = NSColor(srgbRed: 0.91, green: 0.95, blue: 0.99, alpha: 1)
let paleYellow = NSColor(srgbRed: 1.0, green: 0.97, blue: 0.86, alpha: 1)

func sans(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    NSFont(name: weight == .bold ? "HelveticaNeue-Bold" : weight == .medium ? "HelveticaNeue-Medium" : "HelveticaNeue", size: size)
        ?? .systemFont(ofSize: size, weight: weight)
}
func serif(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
    let name = bold ? "Georgia-Bold" : italic ? "Georgia-Italic" : "Georgia"
    return NSFont(name: name, size: size) ?? .systemFont(ofSize: size)
}

// MARK: Drawing helpers (top-down coordinates; the context is flipped)

var y: CGFloat = 0

@discardableResult
func text(_ s: NSAttributedString, x: CGFloat = M, width: CGFloat = W - 2 * M, at top: CGFloat? = nil, after: CGFloat = 0) -> CGFloat {
    let t = top ?? y
    let r = s.boundingRect(with: NSSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
    s.draw(with: NSRect(x: x, y: t, width: width, height: ceil(r.height) + 2), options: [.usesLineFragmentOrigin, .usesFontLeading])
    if top == nil { y = t + ceil(r.height) + after }
    return ceil(r.height)
}

func attr(_ s: String, _ font: NSFont, _ color: NSColor = ink, lineSpacing: CGFloat = 0, align: NSTextAlignment = .left) -> NSMutableAttributedString {
    let p = NSMutableParagraphStyle(); p.lineSpacing = lineSpacing; p.alignment = align
    return NSMutableAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
}

/// Paragraph where **bold** marks new words.
func rich(_ s: String, size: CGFloat = 13.5, lineSpacing: CGFloat = 7) -> NSAttributedString {
    let out = NSMutableAttributedString()
    for (i, part) in s.components(separatedBy: "**").enumerated() {
        out.append(attr(part, i % 2 == 1 ? serif(size, bold: true) : serif(size), i % 2 == 1 ? blue : ink, lineSpacing: lineSpacing))
    }
    return out
}

func fill(_ r: NSRect, _ c: NSColor, radius: CGFloat = 0) {
    c.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
}
func stroke(_ r: NSRect, _ c: NSColor, width: CGFloat = 1, radius: CGFloat = 0) {
    c.setStroke(); let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius); p.lineWidth = width; p.stroke()
}
func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ c: NSColor = soft, width: CGFloat = 0.8, dash: Bool = false) {
    c.setStroke(); let p = NSBezierPath(); p.move(to: NSPoint(x: x1, y: y1)); p.line(to: NSPoint(x: x2, y: y2)); p.lineWidth = width
    if dash { p.setLineDash([2, 2], count: 2, phase: 0) }
    p.stroke()
}
func checkbox(_ x: CGFloat, _ top: CGFloat) { stroke(NSRect(x: x, y: top + 2, width: 10, height: 10), soft, width: 0.9, radius: 1.5) }

func header(lesson: String, title: String, color: NSColor) {
    fill(NSRect(x: 0, y: 0, width: W, height: 70), color)
    text(attr(lesson.uppercased(), sans(10, .medium), NSColor.white.withAlphaComponent(0.85)), at: 20)
    text(attr(title, sans(22, .bold), .white), at: 34)
    y = 96
}

func footer(_ n: Int) {
    line(M, H - 40, W - M, H - 40, NSColor(white: 0.8, alpha: 1), width: 0.5)
    text(attr("Ελληνικά Β1 · Βιβλίο ασκήσεων (demo)", sans(8.5), soft), at: H - 34)
    text(attr("\(n)", sans(9, .medium), soft, align: .right), at: H - 34)
}

func exercise(_ n: Int, _ title: String, _ hint: String, color: NSColor) {
    let r = NSRect(x: M, y: y, width: 26, height: 20)
    fill(r, color, radius: 4)
    text(attr("\(n)", sans(12, .bold), .white, align: .center), x: M, width: 26, at: y + 3)
    text(attr(title, sans(13.5, .bold), ink), x: M + 36, width: W - 2 * M - 36, at: y + 1)
    y += 21
    text(attr(hint, serif(10.5, italic: true), soft), x: M + 36, width: W - 2 * M - 36, after: 10)
}

func numbered(_ items: [String], size: CGFloat = 12.5, gap: CGFloat = 12, indent: CGFloat = 36) {
    for (i, s) in items.enumerated() {
        text(attr("\(i + 1).", sans(size - 1, .medium), soft), x: M + indent, width: 20, at: y)
        text(attr(s, serif(size), ink), x: M + indent + 20, width: W - 2 * M - indent - 20, after: gap)
    }
}

/// "____" in a sentence becomes a drawn answer line.
func blankSentence(_ n: Int, _ s: String, indent: CGFloat = 36, blankWidth: CGFloat = 90, hintAfter: String = "") {
    text(attr("\(n).", sans(11.5, .medium), soft), x: M + indent, width: 20, at: y)
    var x = M + indent + 20
    let parts = s.components(separatedBy: "____")
    for (i, p) in parts.enumerated() {
        let a = attr(p, serif(12.5))
        let w = a.size().width
        a.draw(at: NSPoint(x: x, y: y))
        x += w
        if i < parts.count - 1 { line(x + 3, y + 15, x + 3 + blankWidth, y + 15, soft, width: 0.8); x += blankWidth + 6 }
    }
    if !hintAfter.isEmpty { attr(hintAfter, serif(11, italic: true), soft).draw(at: NSPoint(x: x + 4, y: y + 1)) }
    y += 30
}

func answerLines(_ count: Int, indent: CGFloat = 36, gap: CGFloat = 26) {
    for _ in 0..<count { y += gap; line(M + indent, y, W - M, y, NSColor(white: 0.65, alpha: 1), width: 0.6) }
    y += 14
}

// MARK: Document

let ctx = CGContext(out as CFURL, mediaBox: nil, [kCGPDFContextTitle as String: "Ελληνικά Β1 — Βιβλίο ασκήσεων (demo)",
                                                   kCGPDFContextCreator as String: "Fylladio demo generator"] as CFDictionary)!
var media = CGRect(x: 0, y: 0, width: W, height: H)

func page(_ draw: () -> Void) {
    ctx.beginPage(mediaBox: &media)
    ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    y = M
    draw()
    NSGraphicsContext.current = nil
    ctx.endPage()
}

// 1. Cover
page {
    fill(NSRect(x: 0, y: 0, width: W, height: H), NSColor(srgbRed: 0.10, green: 0.27, blue: 0.50, alpha: 1))
    fill(NSRect(x: 0, y: 560, width: W, height: 282), NSColor(srgbRed: 0.06, green: 0.19, blue: 0.37, alpha: 1))
    // a few "tiles" like a Greek meander strip
    for i in 0..<12 {
        let x = 40 + CGFloat(i) * 44
        stroke(NSRect(x: x, y: 520, width: 30, height: 22), NSColor.white.withAlphaComponent(0.35), width: 2)
        line(x + 8, 531, x + 22, 531, NSColor.white.withAlphaComponent(0.35), width: 2)
    }
    text(attr("ΕΛΛΗΝΙΚΑ", sans(58, .bold), .white), x: 56, at: 170)
    text(attr("Β1", sans(58, .bold), NSColor(srgbRed: 1, green: 0.78, blue: 0.25, alpha: 1)), x: 56, at: 236)
    text(attr("Βιβλίο ασκήσεων", serif(26, italic: true), .white), x: 58, at: 320)
    text(attr("Μαθήματα 1–2 · Γραμματική · Λεξιλόγιο · Λύσεις", sans(13), NSColor.white.withAlphaComponent(0.8)), x: 58, at: 364)
    text(attr("Demo study book for trying Fylladio.\nFictional content, free to use.", sans(11), NSColor.white.withAlphaComponent(0.7), lineSpacing: 3), x: 58, at: 640)
}

// 2. Contents
page {
    header(lesson: "Περιεχόμενα", title: "Τι θα βρείτε σε αυτό το βιβλίο", color: blue)
    let rows: [(String, String, Int)] = [
        ("Μάθημα 1", "Στη λαϊκή αγορά (κείμενο, λεξιλόγιο)", 3),
        ("", "Ασκήσεις 1–3", 4),
        ("Γραμματική", "Παρατατικός και Αόριστος", 5),
        ("", "Ασκήσεις 4–5", 6),
        ("Μάθημα 2", "Ένα γράμμα από τη Λεμεσό", 7),
        ("Λεξιλόγιο", "Αντιστοιχίσεις (σκαναρισμένη σελίδα)", 8),
        ("Επανάληψη", "Ασκήσεις 9–11", 9),
        ("Λύσεις", "Οι σωστές απαντήσεις", 10),
    ]
    y += 8
    for (a, b, p) in rows {
        text(attr(a, sans(12.5, .bold), blue), width: 110, at: y)
        let w = attr(b, serif(13)).size().width
        text(attr(b, serif(13)), x: M + 115, width: 330, at: y)
        line(M + 120 + w, y + 13, W - M - 24, y + 13, NSColor(white: 0.7, alpha: 1), width: 0.8, dash: true)
        text(attr("\(p)", sans(12.5, .medium), ink, align: .right), at: y)
        y += 30
    }
    y += 20
    fill(NSRect(x: M, y: y, width: W - 2 * M, height: 190), paleYellow, radius: 8)
    text(attr("Πώς να δουλέψετε με το βιβλίο", sans(13.5, .bold)), x: M + 18, width: W - 2 * M - 36, at: y + 16)
    y += 44
    for s in ["Διαβάστε το κείμενο και υπογραμμίστε τις λέξεις που δεν ξέρετε.",
              "Μαρκάρετε με κίτρινο τις νέες λέξεις του λεξιλογίου.",
              "Γράψτε τις απαντήσεις πάνω στις γραμμές.",
              "Τσεκάρετε τα κουτάκια ☐ στις ασκήσεις πολλαπλής επιλογής.",
              "Ελέγξτε τις απαντήσεις σας στη σελίδα 10."] {
        text(attr("•", sans(13, .bold), orange), x: M + 22, width: 12, at: y)
        text(attr(s, serif(12.5)), x: M + 38, width: W - 2 * M - 60, after: 8)
    }
    footer(2)
}

// 3. Lesson 1 reading
page {
    header(lesson: "Μάθημα 1", title: "Στη λαϊκή αγορά", color: orange)
    text(rich("""
    Κάθε Σάββατο πρωί η Μαρία πηγαίνει στη **λαϊκή αγορά** της γειτονιάς της. Παίρνει μαζί της μια μεγάλη τσάντα και τη λίστα με τα **ψώνια**. Στους **πάγκους** βλέπει **φρέσκα** φρούτα και λαχανικά: ντομάτες, αγγούρια, πορτοκάλια και σταφύλια. Ο κύριος Νίκος, ο **μανάβης**, της χαμογελάει πάντα.
    """), after: 10)
    text(rich("""
    — Καλημέρα, κυρία Μαρία! Τι θα πάρετε σήμερα;
    — Καλημέρα! Θέλω ένα κιλό ντομάτες και δύο κιλά πορτοκάλια, παρακαλώ.
    — Τα πορτοκάλια είναι πολύ γλυκά φέτος. **Δοκιμάστε** ένα!
    """), x: M + 16, width: W - 2 * M - 16, after: 10)
    text(rich("""
    Η Μαρία δοκιμάζει και **συμφωνεί**. Πληρώνει, λέει «ευχαριστώ» και συνεχίζει τη βόλτα της. Στο τέλος αγοράζει και λίγο **μέλι** από ένα χωριό της Κρήτης. Όταν γυρίζει στο σπίτι, η τσάντα είναι γεμάτη και η Μαρία είναι πολύ χαρούμενη.
    """), after: 22)
    let box = NSRect(x: M, y: y, width: W - 2 * M, height: 196)
    fill(box, paleBlue, radius: 8)
    text(attr("Λεξιλόγιο", sans(13.5, .bold), blue), x: M + 18, at: y + 14)
    let vocab = [("η λαϊκή αγορά", "street market"), ("τα ψώνια", "shopping"), ("ο πάγκος", "stall"),
                 ("φρέσκος, -η, -ο", "fresh"), ("ο μανάβης", "greengrocer"), ("δοκιμάζω", "to taste, to try"),
                 ("συμφωνώ", "to agree"), ("το μέλι", "honey")]
    var vy = y + 42
    for (i, (g, e)) in vocab.enumerated() {
        let col = CGFloat(i / 4), row = CGFloat(i % 4)
        let x = M + 18 + col * 245
        text(attr(g, serif(12.5, bold: true)), x: x, width: 130, at: vy + row * 34)
        text(attr(e, serif(12, italic: true), soft), x: x + 125, width: 110, at: vy + row * 34)
    }
    vy += 4 * 34
    footer(3)
}

// 4. Exercises 1–3
page {
    header(lesson: "Μάθημα 1 · Ασκήσεις", title: "Ασκήσεις 1–3", color: orange)
    exercise(1, "Υπογραμμίστε τα ρήματα.", "Underline the verbs.", color: orange)
    numbered(["Η Μαρία πηγαίνει στην αγορά κάθε Σάββατο.",
              "Ο μανάβης χαμογελάει στους πελάτες.",
              "Εμείς αγοράζουμε φρούτα και λαχανικά.",
              "Τα παιδιά τρώνε σταφύλια στον κήπο.",
              "Πληρώνετε με κάρτα ή με μετρητά;"], gap: 9)
    y += 10
    exercise(2, "Συμπληρώστε με το σωστό άρθρο: ο, η, το, οι, τα.", "Fill in the article.", color: orange)
    for (i, s) in ["____ ντομάτες είναι φρέσκες.", "____ μανάβης είναι ευγενικός.", "____ μέλι είναι από την Κρήτη.",
                   "____ τσάντα της Μαρίας είναι μεγάλη.", "____ πορτοκάλια είναι γλυκά."].enumerated() {
        blankSentence(i + 1, s, blankWidth: 44)
    }
    y += 6
    exercise(3, "Σωστό (Σ) ή Λάθος (Λ);", "Tick the right box.", color: orange)
    text(attr("Σ", sans(11, .bold), soft), x: W - M - 58, width: 14, at: y - 4)
    text(attr("Λ", sans(11, .bold), soft), x: W - M - 24, width: 14, at: y - 4)
    y += 14
    for (i, s) in ["Η Μαρία πηγαίνει στην αγορά την Κυριακή.", "Ο κύριος Νίκος πουλάει φρούτα.",
                   "Η Μαρία αγοράζει τρία κιλά ντομάτες.", "Τα πορτοκάλια είναι γλυκά.", "Το μέλι είναι από την Κρήτη."].enumerated() {
        text(attr("\(i + 1).", sans(11.5, .medium), soft), x: M + 36, width: 20, at: y)
        text(attr(s, serif(12.5)), x: M + 56, width: 360, at: y)
        checkbox(W - M - 60, y); checkbox(W - M - 26, y)
        y += 26
    }
    footer(4)
}

// 5. Grammar
page {
    header(lesson: "Γραμματική", title: "Παρατατικός και Αόριστος", color: green)
    fill(NSRect(x: M, y: y, width: W - 2 * M, height: 104), NSColor(srgbRed: 0.92, green: 0.97, blue: 0.93, alpha: 1), radius: 8)
    text(attr("Πότε χρησιμοποιούμε…", sans(13, .bold), green), x: M + 18, at: y + 12)
    text(rich("**Παρατατικό**: κάτι γινόταν συχνά ή για πολύ ώρα (κάθε μέρα, πάντα, συνήθως, ενώ).", size: 12, lineSpacing: 3), x: M + 18, width: W - 2 * M - 36, at: y + 36)
    text(rich("**Αόριστο**: κάτι έγινε μία φορά και τελείωσε (χθες, πέρσι, ξαφνικά, μια μέρα).", size: 12, lineSpacing: 3), x: M + 18, width: W - 2 * M - 36, at: y + 70)
    y += 128
    func table(_ verb: String, _ p: [String], _ a: [String]) {
        text(attr(verb, serif(15, bold: true), green), after: 8)
        let cols: [CGFloat] = [M, M + 130, M + 285]
        let heads = ["Πρόσωπο", "Παρατατικός", "Αόριστος"]
        fill(NSRect(x: M, y: y, width: W - 2 * M, height: 22), NSColor(white: 0.93, alpha: 1))
        for (c, h) in zip(cols, heads) { text(attr(h, sans(11, .bold), soft), x: c + 8, width: 140, at: y + 5) }
        y += 26
        let persons = ["εγώ", "εσύ", "αυτός/ή/ό", "εμείς", "εσείς", "αυτοί/ές/ά"]
        for i in 0..<6 {
            text(attr(persons[i], sans(11.5), soft), x: cols[0] + 8, width: 120, at: y)
            text(attr(p[i], serif(13)), x: cols[1] + 8, width: 140, at: y)
            text(attr(a[i], serif(13)), x: cols[2] + 8, width: 140, at: y)
            y += 21
            line(M, y - 3, W - M, y - 3, NSColor(white: 0.88, alpha: 1), width: 0.5)
        }
        y += 18
    }
    table("γράφω", ["έγραφα", "έγραφες", "έγραφε", "γράφαμε", "γράφατε", "έγραφαν"],
                   ["έγραψα", "έγραψες", "έγραψε", "γράψαμε", "γράψατε", "έγραψαν"])
    table("διαβάζω", ["διάβαζα", "διάβαζες", "διάβαζε", "διαβάζαμε", "διαβάζατε", "διάβαζαν"],
                     ["διάβασα", "διάβασες", "διάβασε", "διαβάσαμε", "διαβάσατε", "διάβασαν"])
    text(attr("Προσοχή: στον Παρατατικό και τον Αόριστο ο τόνος πηγαίνει στην τρίτη συλλαβή από το τέλος (έγραφα, διάβασα).",
              serif(11.5, italic: true), soft, lineSpacing: 3))
    footer(5)
}

// 6. Exercises 4–5
page {
    header(lesson: "Γραμματική · Ασκήσεις", title: "Ασκήσεις 4–5", color: green)
    exercise(4, "Διαλέγω Παρατατικό ή Αόριστο.", "Tick α or β.", color: green)
    let items: [(String, String, String)] = [
        ("Κάθε καλοκαίρι ____ στην Κύπρο.", "πηγαίναμε", "πήγαμε"),
        ("Χθες το βράδυ ____ ένα ωραίο βιβλίο.", "διάβαζα", "διάβασα"),
        ("Όταν ήμουν παιδί, ____ πολύ γάλα.", "έπινα", "ήπια"),
        ("Πέρσι ____ σε ένα καινούργιο σπίτι.", "μετακομίζαμε", "μετακομίσαμε"),
        ("Ενώ ____, χτύπησε το τηλέφωνο.", "μαγείρευα", "μαγείρεψα"),
        ("Ξαφνικά ____ η βροχή.", "σταματούσε", "σταμάτησε"),
    ]
    for (i, (s, a, b)) in items.enumerated() {
        blankSentence(i + 1, s, blankWidth: 80)
        y -= 6
        checkbox(M + 56, y); text(attr("α) " + a, serif(12, italic: true), blue), x: M + 72, width: 150, at: y)
        checkbox(M + 216, y); text(attr("β) " + b, serif(12, italic: true), blue), x: M + 232, width: 150, at: y)
        y += 30
    }
    y += 4
    exercise(5, "Βάλτε τα ρήματα στον σωστό χρόνο.", "Put the verbs in the right tense.", color: green)
    blankSentence(1, "Χθες ____ ένα γράμμα στη γιαγιά μου.", blankWidth: 110, hintAfter: "(γράφω)")
    blankSentence(2, "Συνήθως ____ το πρωί, πριν από τη δουλειά.", blankWidth: 110, hintAfter: "(διαβάζω)")
    blankSentence(3, "Το 2020 ____ στη Θεσσαλονίκη.", blankWidth: 110, hintAfter: "(ταξιδεύω)")
    blankSentence(4, "Κάθε μέρα ____ μουσική στο λεωφορείο.", blankWidth: 110, hintAfter: "(ακούω)")
    footer(6)
}

// 7. Lesson 2: a letter
page {
    header(lesson: "Μάθημα 2", title: "Ένα γράμμα από τη Λεμεσό", color: purple)
    let card = NSRect(x: M, y: y, width: W - 2 * M, height: 262)
    fill(card, paleYellow, radius: 6)
    stroke(card, NSColor(srgbRed: 0.85, green: 0.78, blue: 0.55, alpha: 1), width: 0.8, radius: 6)
    y += 18
    text(attr("Λεμεσός, 14 Ιουλίου", serif(12, italic: true), soft, align: .right), x: M + 20, width: W - 2 * M - 40, after: 8)
    text(attr("Αγαπητή Ελένη,", serif(13.5, bold: true)), x: M + 20, after: 8)
    text(rich("""
    Σου γράφω από τη Λεμεσό. Φτάσαμε εδώ την Τρίτη και ο καιρός είναι υπέροχος. Κάθε πρωί **κολυμπούσαμε** στη θάλασσα και το απόγευμα **περπατούσαμε** στην παλιά πόλη. Χθες **επισκεφτήκαμε** το κάστρο και μετά **φάγαμε** χαλλούμι και σουβλάκια σε μια μικρή ταβέρνα. Ο σερβιτόρος μάς **έμαθε** μερικές λέξεις στην κυπριακή διάλεκτο!
    """, size: 13, lineSpacing: 6), x: M + 20, width: W - 2 * M - 40, after: 8)
    text(rich("Του χρόνου θέλω να έρθεις μαζί μας. Γράψε μου σύντομα.", size: 13), x: M + 20, width: W - 2 * M - 40, after: 14)
    text(attr("Με αγάπη,\nΆννα", serif(13, italic: true), ink, lineSpacing: 3), x: M + 20, width: W - 2 * M - 40)
    y = card.maxY + 22
    exercise(6, "Απαντήστε στις ερωτήσεις.", "Answer the questions.", color: purple)
    for (i, q) in ["Από πού γράφει η Άννα;", "Πότε έφτασαν;", "Τι έκαναν κάθε πρωί;", "Τι έφαγαν χθες;"].enumerated() {
        text(attr("\(i + 1).", sans(11.5, .medium), soft), x: M + 36, width: 20, at: y)
        text(attr(q, serif(12.5)), x: M + 56, width: 400)
        y -= 6
        answerLines(1, indent: 56, gap: 22)
    }
    footer(7)
}

// 8. "Scanned" vocabulary page: drawn into a slightly rotated, toned image, so it has no text layer.
do {
    let scale: CGFloat = 2
    let img = NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
        fill(NSRect(x: 0, y: 0, width: W, height: H), NSColor(srgbRed: 0.97, green: 0.96, blue: 0.92, alpha: 1))
        NSGraphicsContext.current?.cgContext.translateBy(x: W / 2, y: H / 2)
        NSGraphicsContext.current?.cgContext.rotate(by: 0.6 * .pi / 180)
        NSGraphicsContext.current?.cgContext.translateBy(x: -W / 2, y: -H / 2)
        y = 60
        text(attr("ΛΕΞΙΛΟΓΙΟ", sans(10, .medium), soft), after: 2)
        text(attr("Αντιστοιχίσεις", sans(22, .bold), ink), after: 18)
        exercise(7, "Αντιστοιχίστε τις λέξεις με τη μετάφραση.", "Match each word with its translation.", color: NSColor(white: 0.35, alpha: 1))
        let left = ["η θάλασσα", "το κάστρο", "το μέλι", "ο καιρός", "η ταβέρνα", "ο πάγκος"]
        let right = ["α. honey", "β. sea", "γ. castle", "δ. weather", "ε. stall", "στ. tavern"]
        for i in 0..<6 {
            text(attr("\(i + 1). " + left[i], serif(14)), x: M + 40, width: 180, at: y)
            line(M + 200, y + 10, M + 240, y + 10, NSColor(white: 0.6, alpha: 1), width: 0.6, dash: true)
            text(attr(right[i], serif(14, italic: true)), x: M + 290, width: 180, at: y)
            y += 32
        }
        y += 24
        exercise(8, "Κυκλώστε τη λέξη που δεν ταιριάζει.", "Circle the odd one out.", color: NSColor(white: 0.35, alpha: 1))
        for (i, s) in ["ντομάτα  –  αγγούρι  –  πορτοκάλι  –  τραπέζι",
                       "Δευτέρα  –  Τρίτη  –  Ιούλιος  –  Παρασκευή",
                       "κολυμπάω  –  θάλασσα  –  τρέχω  –  διαβάζω",
                       "Λεμεσός  –  Αθήνα  –  Κρήτη  –  Θεσσαλονίκη"].enumerated() {
            text(attr("\(i + 1).  " + s, serif(14)), x: M + 40, width: W - 2 * M - 40, at: y)
            y += 34
        }
        y += 20
        text(attr("Η σελίδα αυτή είναι «σκαναρισμένη»: δεν έχει κείμενο που επιλέγεται. Το μαρκαδόρο τον σέρνετε ως ορθογώνιο.",
                  serif(11, italic: true), soft, lineSpacing: 3), x: M + 40, width: W - 2 * M - 80)
        text(attr("8", sans(9, .medium), soft, align: .right), at: H - 34)
        return true
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
    // light scanner noise
    for _ in 0..<5000 {
        NSColor(white: CGFloat.random(in: 0.55...0.85), alpha: 0.25).setFill()
        NSRect(x: CGFloat.random(in: 0..<W), y: CGFloat.random(in: 0..<H), width: 0.6, height: 0.6).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72])!
    let cg = CGImage(jpegDataProviderSource: CGDataProvider(data: jpeg as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    ctx.beginPage(mediaBox: &media)
    ctx.draw(cg, in: media)
    ctx.endPage()
}

// 9. Review
page {
    header(lesson: "Επανάληψη", title: "Ασκήσεις 9–11", color: blue)
    exercise(9, "Βάλτε τις λέξεις στη σωστή σειρά.", "Put the words in the right order.", color: blue)
    for (i, s) in ["κάθε / πηγαίνω / στην / Σάββατο / αγορά", "ένα / χθες / έγραψα / γράμμα", "μέλι / Κρήτη / το / είναι / από / την"].enumerated() {
        text(attr("\(i + 1).", sans(11.5, .medium), soft), x: M + 36, width: 20, at: y)
        text(attr(s, serif(12.5, italic: true), blue), x: M + 56, width: 400)
        y -= 6
        answerLines(1, indent: 56, gap: 22)
    }
    exercise(10, "Συμπληρώστε τον διάλογο.", "In the taverna: complete the dialogue.", color: blue)
    for (who, s) in [("Α:", "Καλησπέρα! ____ ένα τραπέζι για δύο;"), ("Β:", "Βεβαίως. Τι θα ____ ;"),
                     ("Α:", "Μια χωριάτικη σαλάτα και δύο σουβλάκια, ____ ."), ("Β:", "Θα πιείτε κάτι;"), ("Α:", "Ένα ____ νερό, ευχαριστώ.")] {
        text(attr(who, sans(12, .bold), blue), x: M + 36, width: 24, at: y)
        var x = M + 62
        for (k, part) in s.components(separatedBy: "____").enumerated() {
            if k > 0 { line(x + 3, y + 15, x + 83, y + 15, soft, width: 0.8); x += 88 }
            let a = attr(part, serif(12.5)); a.draw(at: NSPoint(x: x, y: y)); x += a.size().width
        }
        y += 28
    }
    y += 8
    exercise(11, "Τι κάνατε το περασμένο Σαββατοκύριακο;", "Write 3–4 sentences (use the Αόριστος).", color: blue)
    answerLines(5, indent: 36, gap: 26)
    footer(9)
}

// 10. Answer key
page {
    header(lesson: "Παράρτημα", title: "Λύσεις", color: NSColor(white: 0.30, alpha: 1))
    let answers: [(String, String)] = [
        ("1", "πηγαίνει · χαμογελάει · αγοράζουμε · τρώνε · Πληρώνετε"),
        ("2", "1. Οι  2. Ο  3. Το  4. Η  5. Τα"),
        ("3", "1. Λ  2. Σ  3. Λ  4. Σ  5. Σ"),
        ("4", "1. α (πηγαίναμε)  2. β (διάβασα)  3. α (έπινα)  4. β (μετακομίσαμε)  5. α (μαγείρευα)  6. β (σταμάτησε)"),
        ("5", "1. έγραψα  2. διάβαζα  3. ταξίδεψα  4. άκουγα"),
        ("6", "1. Από τη Λεμεσό.  2. Την Τρίτη.  3. Κολυμπούσαν στη θάλασσα.  4. Χαλλούμι και σουβλάκια."),
        ("7", "1β  2γ  3α  4δ  5στ  6ε"),
        ("8", "1. τραπέζι  2. Ιούλιος  3. θάλασσα  4. Κρήτη (νησί, όχι πόλη)"),
        ("9", "1. Κάθε Σάββατο πηγαίνω στην αγορά.  2. Χθες έγραψα ένα γράμμα.  3. Το μέλι είναι από την Κρήτη."),
        ("10", "Έχετε · πάρετε · παρακαλώ · μπουκάλι"),
        ("11", "Ελεύθερη απάντηση, π.χ. «Το Σάββατο πήγα στη λαϊκή και αγόρασα φρούτα. Την Κυριακή κολύμπησα στη θάλασσα.»"),
    ]
    for (n, a) in answers {
        text(attr("Άσκηση \(n)", sans(11.5, .bold), ink), width: 90, at: y)
        text(attr(a, serif(12), ink, lineSpacing: 3), x: M + 95, width: W - 2 * M - 95, after: 12)
    }
    y += 10
    text(attr("Συμβουλή: βάλτε έναν σελιδοδείκτη «Λύσεις» σε αυτή τη σελίδα και γυρίστε πίσω με το Back.",
              serif(11.5, italic: true), soft, lineSpacing: 3))
    footer(10)
}

ctx.closePDF()
print("wrote \(out.path)")
