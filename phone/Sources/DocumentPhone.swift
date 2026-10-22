import SwiftUI
import WebKit

/// **Document view on the phone** (the Mac's Document tab, parity 3,
/// 2026-10-16): each scene as a page, set the way it prints — the engine's
/// own Document page, so the phone, the Mac's export and paper agree. Tap a
/// shot's title, words or note to type in it, as on the Mac (the words keep
/// their bold and italic); the page's type and each frame's place and size are
/// set from the menu, the Mac's type strip and frame layout.
struct DocumentPhoneView: View {
    @EnvironmentObject private var session: Session
    /// The scenes on the page, in order.
    let scenes: [String]

    @State private var page: URL?
    @State private var said: String?
    /// When the page itself last wrote something: the redraw that write
    /// causes is skipped, or the keyboard would drop mid-typing.
    @State private var wroteAt = Date.distantPast
    @State private var settingType = false
    @State private var layingOut = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
            if let page {
                DocumentWeb(url: page, rich: richWords, onEdit: written)
            } else if let said {
                ContentUnavailableView(said, systemImage: "doc.text")
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Menu {
                Button { settingType = true } label: { Label("Type", systemImage: "textformat.size") }
                Button { layingOut = true } label: { Label("Frames", systemImage: "rectangle.split.2x1") }
            } label: {
                Image(systemName: "textformat")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(.label))
                    .frame(width: 48, height: 48)
                    .glassCapsule()
            }
            .accessibilityLabel("Page")
            .accessibilityIdentifier("document.page.menu")
            .padding(.trailing, 16)
            .padding(.bottom, 96)
        }
        .task(id: stamp) {
            if Date().timeIntervalSince(wroteAt) < 1.5 { return }
            draw()
        }
        .sheet(isPresented: $settingType) {
            DocumentTypeSheet().environmentObject(session).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $layingOut) {
            DocumentFramesSheet(scenes: scenes).environmentObject(session).presentationDetents([.medium, .large])
        }
    }

    /// What the page depends on: redrawn when any of it changes.
    private var stamp: String {
        let rows = scenes.flatMap { session.rows(inScene: $0) }
        let words = rows.map { "\($0.shot)\($0.number)\($0.title)\($0.description)\($0.framePosition)\($0.frameWidth)\($0.frame?.hash ?? "")" }
        let type = (session.view?.project.docStyle ?? []).map { "\($0.class)\($0.size)\($0.face)\($0.case)\($0.colour ?? "")" }
        return (scenes + words + type).joined(separator: "|").hashValue.description
    }

    private var allRows: [Engine.Row] { scenes.flatMap { session.rows(inScene: $0) } }

    /// The words that carry bold or italic, as the page shows them.
    private func richWords() -> [String: String] {
        var out: [String: String] = [:]
        for r in allRows where !r.descriptionRich.isEmpty {
            if let runs = DocumentRich.runs(rich: r.descriptionRich, plain: r.description), DocumentRich.hasEmphasis(runs) {
                out[r.shot] = DocumentRich.html(runs)
            }
        }
        return out
    }

    /// One part of one shot, typed on the page. Written only when it changed:
    /// the words' emphasis is left alone unless the words or the emphasis did.
    private func written(_ shot: String, _ field: String, _ runs: [DocumentRich.Run]) {
        guard let row = allRows.first(where: { $0.shot == shot }) else { return }
        var text = DocumentRich.plain(runs)
        var runs = runs
        // The page's line-break placeholder: one trailing newline is not his.
        if text.hasSuffix("\n") { text.removeLast(); if var last = runs.last { last.text.removeLast(); runs[runs.count - 1] = last } }
        runs = DocumentRich.merged(runs)
        switch field {
        case "title":
            guard text != row.title else { return }
            wroteAt = Date(); session.set(row, "title", to: text)
        case "notes":
            guard text != row.notes else { return }
            wroteAt = Date(); session.set(row, "notes", to: text)
        default:
            let was = DocumentRich.runs(rich: row.descriptionRich, plain: row.description)
            let wasMarks = was.map(DocumentRich.marks) ?? Array(repeating: 0, count: row.description.utf16.count)
            let sameWords = text == row.description
            if sameWords && DocumentRich.marks(runs) == wasMarks { return }
            wroteAt = Date()
            if !sameWords { session.set(row, "description", to: text) }
            session.set(row, "description_rich", to: DocumentRich.encode(runs))
        }
    }

    private func draw() {
        guard let engine = session.engine else { said = "Not open"; return }
        guard !scenes.isEmpty else { said = "No scenes"; return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("document-page", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("page-\(UUID().uuidString.prefix(8)).html")
        var scope = Exporting.Scope()
        scope.scenes = scenes
        if let problem = Exporting.printPage(.document, to: path, scope: scope, engine: engine) {
            said = problem
            return
        }
        if let old = page { try? FileManager.default.removeItem(at: old) }
        page = path
    }
}

/// The page itself, scrolled and pinched like any document. A shot's title,
/// words and note are typed in on the page (the engine marks each shot with
/// `data-shot`); the page tells the app when one is left.
private struct DocumentWeb: UIViewRepresentable {
    let url: URL
    let rich: () -> [String: String]
    let onEdit: (String, String, [DocumentRich.Run]) -> Void

    static let script = """
    (function(){
      var st=document.createElement('style');
      st.textContent='[contenteditable]{outline:none;caret-color:#1f4e9c;-webkit-user-select:text;white-space:pre-wrap}'
        +'[contenteditable]:empty::before{content:attr(data-hint);color:#9a9aa2;font-weight:400;font-style:normal}'
        +'.shot-desc:empty{min-height:1.4em}';
      document.head.appendChild(st);
      var post=function(o){webkit.messageHandlers.edit.postMessage(o)};
      function runs(el){
        var out=[];
        (function walk(n,b,i){
          if(n.nodeType===3){out.push([n.nodeValue,b,i]);return}
          if(n.nodeType!==1)return;
          if(n.tagName==='BR'){out.push(['\\n',b,i]);return}
          var cs=getComputedStyle(n);
          var nb=b||n.tagName==='B'||n.tagName==='STRONG'||parseInt(cs.fontWeight)>=600;
          var ni=i||n.tagName==='I'||n.tagName==='EM'||cs.fontStyle==='italic';
          for(var c=n.firstChild;c;c=c.nextSibling)walk(c,nb,ni);
        })(el,false,false);
        return out;
      }
      function wire(el,shot,field,rich){
        el.setAttribute('contenteditable',rich?'true':'plaintext-only');
        el.dataset.hint={title:'Title',desc:'Words',notes:'Note'}[field];
        el.addEventListener('focus',function(){
          el.__was=JSON.stringify(runs(el));ensure(el.closest('article'));
          // iOS zooms in on a small field it is about to type in; hold the page still.
          var m=document.querySelector('meta[name=viewport]');if(m){m.__keep=m.content;m.content='width=device-width, initial-scale=1, maximum-scale=1'}
        });
        el.addEventListener('blur',function(){
          var m=document.querySelector('meta[name=viewport]');if(m&&m.__keep)m.content=m.__keep;
          var now=runs(el);
          if(JSON.stringify(now)!==el.__was)post({shot:shot,field:field,runs:now});
          if(el.__made&&!el.textContent){setTimeout(function(){if(!el.textContent&&document.activeElement!==el&&el.parentNode)el.remove()},300)}
        });
        el.addEventListener('beforeinput',function(e){
          if(e.inputType==='insertParagraph'){e.preventDefault();document.execCommand('insertLineBreak')}
          else if(e.inputType==='insertFromPaste'&&e.dataTransfer){e.preventDefault();document.execCommand('insertText',false,e.dataTransfer.getData('text/plain'))}
        });
      }
      function make(art,cls,field,before){
        var el=document.createElement('div');el.className=cls;el.__made=true;
        var shot=art.dataset.shot;wire(el,shot,field,field==='desc');
        var host=art.querySelector('.shot-body')||art;
        if(before&&before.parentNode)before.parentNode.insertBefore(el,before);else host.appendChild(el);
        return el;
      }
      function ensure(art){
        if(!art||art.__full)return;art.__full=true;
        var body=art.querySelector('.shot-body')||art;
        var desc=body.querySelector('.shot-desc');
        if(!body.querySelector('.shot-title')){
          var t=document.createElement('div');t.className='shot-title';t.__made=true;wire(t,art.dataset.shot,'title',false);
          var lead=body.querySelector('.shot-letter');
          if(desc)desc.parentNode.insertBefore(t,desc);else if(lead&&lead.nextSibling)lead.parentNode.insertBefore(t,lead.nextSibling);else body.appendChild(t);
        }
        if(!body.querySelector('.shot-notes'))make(art,'shot-notes','notes',null);
      }
      window.__setup=function(rich){
        document.querySelectorAll('article.shot[data-shot]').forEach(function(art){
          var shot=art.dataset.shot;
          var body=art.querySelector('.shot-body')||art;
          var title=body.querySelector('.shot-title');if(title)wire(title,shot,'title',false);
          var desc=body.querySelector('.shot-desc');
          if(!desc){
            desc=document.createElement('div');desc.className='shot-desc';desc.__made=true;
            var before=body.querySelector('.shot-quote')||body.querySelector('.shot-tech')||body.querySelector('.shot-notes');
            if(before)before.parentNode.insertBefore(desc,before);else body.appendChild(desc);
          }
          if(rich[shot])desc.innerHTML=rich[shot];
          wire(desc,shot,'desc',true);
          var notes=body.querySelector('.shot-notes');if(notes)wire(notes,shot,'notes',false);
        });
      };
    })();
    """

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var rich: () -> [String: String] = { [:] }
        var onEdit: (String, String, [DocumentRich.Run]) -> Void = { _, _, _ in }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let shot = body["shot"] as? String,
                  let field = body["field"] as? String, let parts = body["runs"] as? [[Any]] else { return }
            let runs = parts.compactMap { p -> DocumentRich.Run? in
                guard p.count == 3, let t = p[0] as? String else { return nil }
                return DocumentRich.Run(text: t, bold: (p[1] as? Bool) ?? false, italic: (p[2] as? Bool) ?? false)
            }
            onEdit(shot, field, runs)
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            let data = (try? JSONSerialization.data(withJSONObject: rich())) ?? Data("{}".utf8)
            web.evaluateJavaScript("window.__setup(\(String(data: data, encoding: .utf8) ?? "{}"))")
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        // A page on a phone: an inch of paper margin is too much, none is
        // too little — the words sit 16 points in, the way the list does.
        let setup = WKWebViewConfiguration()
        setup.userContentController.addUserScript(WKUserScript(
            source: "document.body.style.padding='16px 16px 140px';document.body.style.boxSizing='border-box';" + Self.script,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        setup.userContentController.add(context.coordinator, name: "edit")
        let web = WKWebView(frame: .zero, configuration: setup)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .secondarySystemBackground
        web.scrollView.backgroundColor = .secondarySystemBackground
        web.accessibilityIdentifier = "document.page"
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.rich = rich
        context.coordinator.onEdit = onEdit
        guard web.url != url else { return }
        let offset = web.scrollView.contentOffset
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        // Keep his place on the page through a redraw.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { web.scrollView.setContentOffset(offset, animated: false) }
    }
}

/// **The page's type** (the Mac's type strip): each kind of words, its size,
/// face, case and color; Reset; a default kept on this iPhone for other projects.
struct DocumentTypeSheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    @AppStorage("document.pageDefault") private var pageDefault = ""

    static let inks: [(name: String, hex: String)] = [
        ("Black", "17171a"), ("Graphite", "3a3a40"), ("Grey", "5c5c63"), ("Silver", "8c8c94"), ("Red", "b3261e"),
        ("Rust", "9a5216"), ("Green", "2c6b41"), ("Teal", "1e6a6a"), ("Blue", "1f4e9c"), ("Purple", "5a3a9c"),
    ]

    private var classes: [Engine.TextClass] { session.view?.project.docStyle ?? [] }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(classes, id: \.class) { t in
                    Section(t.label) {
                        Stepper(value: Binding(get: { t.size }, set: { write(t, size: $0) }), in: 6...30, step: 0.5) {
                            Text(t.size == t.size.rounded() ? "\(Int(t.size)) pt" : String(format: "%.1f pt", t.size))
                                .monospacedDigit()
                        }
                        Picker("Face", selection: Binding(get: { t.face }, set: { write(t, face: $0) })) {
                            Text("Serif").tag("serif"); Text("Sans").tag("sans"); Text("Mono").tag("mono")
                        }
                        if !["shot_title", "body", "notes"].contains(t.class) {
                            Picker("Case", selection: Binding(get: { t.case }, set: { write(t, casing: $0) })) {
                                Text("As Typed").tag("as"); Text("UPPER").tag("upper"); Text("lower").tag("lower")
                            }
                        }
                        Picker("Color", selection: Binding(get: { (t.colour ?? "").lowercased() }, set: { write(t, colour: $0) })) {
                            if !Self.inks.contains(where: { $0.hex == (t.colour ?? "").lowercased() }) {
                                Text("Custom").tag((t.colour ?? "").lowercased())
                            }
                            ForEach(Self.inks, id: \.hex) { Text($0.name).tag($0.hex) }
                        }
                    }
                }
                Section {
                    Button("Reset") { session.docStyle(["reset"]) }
                    Button("Save as Default") { pageDefault = session.view?.project.docStyleSaid ?? "" }
                    if !pageDefault.isEmpty {
                        Button("Use Default") { session.docStyle(["apply", pageDefault]) }
                        Button("Clear Default", role: .destructive) { pageDefault = "" }
                    }
                }
            }
            .navigationTitle("Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func write(_ t: Engine.TextClass, size: Double? = nil, face: String? = nil, casing: String? = nil, colour: String? = nil) {
        session.docStyle([t.class, String(format: "%.2f", size ?? t.size), face ?? t.face, casing ?? t.case, colour ?? (t.colour ?? "")])
    }
}

/// **Frames on the page** (the Mac's frame layout): every shot's frame above,
/// below or beside its words, and how much of the line it takes; or all at
/// once, alternating or mixed up.
struct DocumentFramesSheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    let scenes: [String]

    static let sizes: [(String, Double)] = [
        ("Full Width", 1.0), ("Two Thirds", 0.66), ("Half", 0.5), ("A Third", 0.34), ("A Quarter", 0.25), ("Thumbnail", 0.15),
    ]
    static let places: [(String, String)] = [("Above", "above"), ("Below", "below"), ("Left", "left"), ("Right", "right")]
    static let mixture: [(String, Double)] = [("left", 0.34), ("below", 1.0), ("right", 0.34), ("above", 0.5)]

    private var rows: [Engine.Row] { scenes.flatMap { session.rows(inScene: $0) } }

    static func clamp(_ w: Double, on place: String) -> Double {
        min(["left", "right"].contains(place) ? 0.55 : 1.0, max(0.1, w))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Menu("All Frames") {
                        ForEach(Self.places, id: \.1) { name, place in
                            Button(name) { all { _, r in (place, Self.clamp(r.frameWidth > 0 ? r.frameWidth : 0.5, on: place)) } }
                        }
                        Divider()
                        ForEach(Self.sizes, id: \.1) { name, w in
                            Button(name) { all { _, r in
                                let p = r.framePosition.isEmpty ? "right" : r.framePosition
                                return (p, Self.clamp(w, on: p))
                            } }
                        }
                        Divider()
                        Button("Alternate Sides") { all { at, r in
                            let side = at.isMultiple(of: 2) ? "left" : "right"
                            return (side, Self.clamp(r.frameWidth > 0 ? r.frameWidth : 0.34, on: side))
                        } }
                        Button("Mix It Up") { all { at, _ in Self.mixture[at % Self.mixture.count] } }
                    }
                }
                Section {
                    ForEach(rows) { r in
                        HStack {
                            Text(r.number).monospacedDigit().frame(width: 44, alignment: .leading)
                            Text(r.title.isEmpty ? r.description : r.title).lineLimit(1)
                            Spacer()
                            Menu {
                                Picker("Place", selection: Binding(get: { r.framePosition }, set: { p in
                                    session.layout(r, position: p, width: Self.clamp(r.frameWidth > 0 ? r.frameWidth : 0.5, on: p))
                                })) { ForEach(Self.places, id: \.1) { Text($0.0).tag($0.1) } }
                                Picker("Size", selection: Binding(get: { Self.nearest(r.frameWidth) }, set: { w in
                                    let p = r.framePosition.isEmpty ? "right" : r.framePosition
                                    session.layout(r, position: p, width: Self.clamp(w, on: p))
                                })) { ForEach(Self.sizes, id: \.1) { Text($0.0).tag($0.1) } }
                            } label: {
                                Text(Self.word(r)).font(.system(size: Kit.Size.body)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Frames")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    static func nearest(_ w: Double) -> Double {
        sizes.map(\.1).min { abs($0 - w) < abs($1 - w) } ?? 0.5
    }

    static func word(_ r: Engine.Row) -> String {
        let place = places.first { $0.1 == r.framePosition }?.0 ?? "Right"
        let size = sizes.first { $0.1 == nearest(r.frameWidth) }?.0 ?? ""
        return "\(place) · \(size)"
    }

    private func all(_ decide: (Int, Engine.Row) -> (String, Double)) {
        for (at, r) in rows.enumerated() {
            let (p, w) = decide(at, r)
            session.layout(r, position: p, width: w)
        }
    }
}
