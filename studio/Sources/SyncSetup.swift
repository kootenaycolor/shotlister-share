import SwiftUI

/// Telling *this* Mac about his relay. **Once, ever.**
///
/// The one anatomy, at the narrow width: two fields, the hint sentence under
/// the password (the one thing he has to do himself, once — the clause in
/// CLAUDE.md that lets a sentence live), and Check far left in the footer.
struct SyncSetupSheet: View {
    @ObservedObject var state: ShellState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    @State private var address = ""
    @State private var word = ""
    @State private var checking = false
    @State private var checked: Checked?

    private enum Checked: Equatable {
        case good
        case bad(String)
    }

    private var incomplete: Bool {
        Relay.tidy(address).isEmpty || word.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Sheet(title: "Set Up Sync", width: .narrow) {
            Field("Address") {
                FieldText(placeholder: "sync.example.com", text: $address)
                    .onChange(of: address) { _, _ in checked = nil }
            }

            Field("Password") {
                VStack(alignment: .leading, spacing: 6) {
                    FieldText(placeholder: "", text: $word)
                        .onChange(of: word) { _, _ in checked = nil }
                    Text("Copy password on the first Mac")
                        .sans(Brand.Size.small)
                        .foregroundStyle(Brand.ink3(dark))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            switch checked {
            case .good:
                Text("Connected")
                    .sans(Brand.Size.small)
                    .foregroundStyle(.green)
            case .bad(let why):
                Text(why)
                    .sans(Brand.Size.small)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            case nil:
                EmptyView()
            }
        } leading: {
            Button("Check") { Task { await ask() } }
                .disabled(checking || incomplete)
            if checking { ProgressView().controlSize(.small) }
            if Relay.ready {
                Button("Forget Password") {
                    _ = Relay.remember(token: "")
                    word = ""
                    checked = nil
                }
            }
        } trailing: {
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Save", action: save)
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(incomplete)
        }
        .onAppear(perform: fill)
    }

    private func fill() {
        address = Relay.address ?? ""
        word = Relay.token ?? ""
    }

    private func ask() async {
        checking = true
        defer { checking = false }
        if let why = await Relay.check(address: address, token: word) {
            checked = .bad(why)
        } else {
            checked = .good
        }
    }

    private func save() {
        if let why = Relay.remember(address: address) {
            checked = .bad(why)
            return
        }
        if let why = Relay.remember(token: word) {
            checked = .bad(why)
            return
        }
        // The toolbar is told by `Relay.learnedTheWord`, which `remember` posts
        // and `watchForTheRelayWord` is already listening for — so the button
        // appears behind this sheet as it closes, rather than at the next start.
        dismiss()
    }
}
