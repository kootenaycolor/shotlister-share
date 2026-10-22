import AppKit
import CoreText
// Advance widths of the system font (what WebKit's -apple-system resolves to)
// at 10pt, in thousandths of an em, for U+0020..U+024F.
let weights: [(String, NSFont.Weight)] = [("REGULAR", .regular), ("SEMIBOLD", .semibold), ("BOLD", .bold)]
var out = ""
for (name, w) in weights {
    let font = NSFont.systemFont(ofSize: 10, weight: w) as CTFont
    var vals: [Int] = []
    for cp in 0x20...0x24F {
        var ch = UniChar(cp); var g: CGGlyph = 0
        if CTFontGetGlyphsForCharacters(font, &ch, &g, 1) && g != 0 {
            var adv = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &adv, 1)
            vals.append(Int((adv.width / 10 * 1000).rounded()))
        } else { vals.append(0) }
    }
    out += "pub const \(name): [u16; \(vals.count)] = [\n"
    for chunk in stride(from: 0, to: vals.count, by: 16) {
        out += "    " + vals[chunk..<min(chunk+16, vals.count)].map(String.init).joined(separator: ", ") + ",\n"
    }
    out += "];\n"
    print(name, CTFontCopyFullName(font))
}
// a few punctuation outside the range
for (name, w) in weights {
    let font = NSFont.systemFont(ofSize: 10, weight: w) as CTFont
    var s = "pub const \(name)_EXTRA: [(char, u16); 12] = ["
    for c in ["\u{2010}","\u{2013}","\u{2014}","\u{2018}","\u{2019}","\u{201C}","\u{201D}","\u{2026}","\u{2022}","\u{2032}","\u{2033}","\u{00D7}"] {
        var ch = c.utf16.first!; var g: CGGlyph = 0
        CTFontGetGlyphsForCharacters(font, &ch, &g, 1)
        var adv = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &adv, 1)
        s += "('\\u{\(String(c.unicodeScalars.first!.value, radix: 16))}', \(Int((adv.width/10*1000).rounded()))), "
    }
    out += s + "];\n"
}
try! out.write(toFile: "metrics_table.rs", atomically: true, encoding: .utf8)
