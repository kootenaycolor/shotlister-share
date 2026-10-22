import SwiftUI

/// Telling this phone about his relay. **Once, ever.**
///
/// The Mac gets all of this from *Set Up Sync* — a script that made the relay,
/// so it knows the address and it wrote the password into the Keychain itself.
/// A phone has neither. What it has instead:
///
/// - **The address comes with the film.** The Mac writes `remote.json` inside
///   the package on its first sync, and the package travels. So a film the Mac
///   has already pushed arrives here knowing where it lives, and the field
///   below is only for the first one, or for the day the relay moves.
/// - **The password is pasted.** Both devices are his and share a clipboard —
///   *Copy password for iPhone* on the Mac, ⌘C there, Paste here. It is two
///   presses and no typing, which is the whole point: it is 64 characters.
///
/// Nothing is stored until *Save*, and *Check* asks the relay before then, so a
/// wrong password is found while he is looking at the field rather than on a
/// location six weeks later.
struct SyncSetupView: View {
    /// The film whose `remote.json` should fill in the address, when there is
    /// one. **Optional on purpose:** a phone with no films at all still has to
    /// be able to set sync up — that is the only way *Open from relay* can
    /// work on a device that has never seen one of his films, which is the
    /// whole point of it existing.
    var film: URL?
    /// Said when a password is saved, so whoever presented this can act.
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var word = ""
    /// nil while nothing has been asked; then either the trouble or `nil` inside
    /// `.some` — hence two states rather than an optional string.
    @State private var checking = false
    @State private var checked: Checked?

    private enum Checked: Equatable {
        case good
        case bad(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Relay") {
                    TextField("sync.example.com", text: $address)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onChange(of: address) { _, _ in checked = nil }
                }

                Section {
                    // **A plain field, not `SecureField`.** He is pasting a
                    // random 64-character word he cannot check by eye, and a
                    // field of dots hides the one failure that matters — a
                    // paste that took the wrong thing. Nobody is shoulder-
                    // surfing a shot list.
                    TextField("Password", text: $word)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))
                        .onChange(of: word) { _, _ in checked = nil }

                    // **The system's own paste button, not one of ours.**
                    //
                    // A `Button` that reads `UIPasteboard.general` puts up
                    // *"Shotlister would like to paste from…"* every single
                    // time — measured in the simulator, and it is the one tap
                    // this screen exists to make easy. `UIPasteControl` is the
                    // button iOS trusts: it hands over the clipboard with no
                    // prompt at all, because the person pressed it.
                    SystemPasteButton { pasted in
                        word = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .frame(height: 36)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    Text("Password")
                } footer: {
                    Text("Copy password on the Mac")
                }

                Section {
                    Button {
                        Task { await check() }
                    } label: {
                        HStack {
                            Text("Check")
                            Spacer()
                            if checking { ProgressView() }
                        }
                    }
                    .disabled(checking || address.isEmpty || word.isEmpty)

                    switch checked {
                    case .good:
                        Label("It answers, and it lets this iPhone in.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                    case .bad(let why):
                        Label(why, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    case nil:
                        EmptyView()
                    }
                }

                if Relay.token != nil {
                    Section {
                        Button(role: .destructive) {
                            _ = Relay.remember(token: "")
                            word = ""
                            checked = nil
                        } label: {
                            Text("Forget password")
                        }
                    }
                }
            }
            .navigationTitle("Set Up Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(address.isEmpty || word.isEmpty)
                }
            }
            .onAppear(perform: fill)
        }
    }

    /// What is already known, so he is correcting rather than composing. The
    /// film's own address wins over anything typed here before — it is the one
    /// the Mac actually used.
    private func fill() {
        address = Relay.address(for: film) ?? Relay.typedAddress
        word = Relay.token ?? ""
    }

    private func check() async {
        checking = true
        defer { checking = false }
        if let why = await Relay.check(address: address, token: word) {
            checked = .bad(why)
        } else {
            checked = .good
        }
    }

    private func save() {
        Relay.typedAddress = address
        // **It stays open when the save failed.** Closing on a refusal is what
        // made this invisible the first time round.
        if let why = Relay.remember(token: word) {
            checked = .bad(why)
            return
        }
        onSaved()
        dismiss()
    }
}

/// The system paste button, as something SwiftUI can put in a `Form`.
///
/// **Not called `PasteButton`**, though it is one: SwiftUI already has a type of
/// that name, and a private one here would silently win over it in this file.
/// That is the `Engine.Plan` mistake — it cost a day on the Mac, reported as a
/// compiler bug in a file nobody had touched.
///
/// SwiftUI has a `PasteButton` of its own, and it will not do: it pastes
/// through `Transferable`, which on a plain string still trips the same
/// *"would like to paste"* prompt this exists to avoid. `UIPasteControl` is the
/// UIKit one — the system reads the clipboard itself and hands the app only
/// what it read, so there is nothing to ask permission for.
private struct SystemPasteButton: UIViewRepresentable {
    var onPaste: (String) -> Void

    func makeUIView(context: Context) -> UIPasteControl {
        let setup = UIPasteControl.Configuration()
        setup.displayMode = .labelOnly
        setup.cornerStyle = .capsule
        let control = UIPasteControl(configuration: setup)
        control.target = context.coordinator
        return control
    }

    func updateUIView(_ control: UIPasteControl, context: Context) {
        context.coordinator.onPaste = onPaste
    }

    func makeCoordinator() -> Target { Target(onPaste: onPaste) }

    /// `UIPasteControl` pastes into a `UIResponder`, not into a closure — it
    /// calls `paste(itemProviders:)` on whatever it is pointed at. So the
    /// target is a responder of our own that does nothing but read the string
    /// and hand it back.
    final class Target: UIResponder {
        var onPaste: (String) -> Void
        init(onPaste: @escaping (String) -> Void) {
            self.onPaste = onPaste
            super.init()
            // **Without this the button draws itself pale and does nothing.**
            //
            // `UIPasteControl` asks its target what it can accept and disables
            // itself when the answer is nothing — and a responder with no
            // `pasteConfiguration` accepts nothing. It is not an error, it is a
            // button that looks present and is not, which took a screenshot to
            // notice.
            pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
        }

        override func paste(itemProviders: [NSItemProvider]) {
            guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) })
            else { return }
            provider.loadObject(ofClass: NSString.self) { [weak self] value, _ in
                guard let text = value as? NSString else { return }
                DispatchQueue.main.async { self?.onPaste(text as String) }
            }
        }
    }
}
