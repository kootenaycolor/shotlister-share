import SwiftUI
import WidgetKit

/// **Lock Screen**, in the phone's Settings (his ask, 2026-10-09): the four
/// shortcuts a *Shotlister Shortcut* widget can be. Each is Shotlister itself
/// or a film at a page. Saved as soon as it changes, and every widget on the
/// lock screen is told to redraw.
struct LockScreenSection: View {
    @EnvironmentObject private var projects: Projects
    @State private var shortcuts = LockShortcuts.all()
    /// What the information widgets follow; nil is Soonest Shoot.
    @State private var shootDay = InfoChoices.shootDayFilm
    @State private var nextShots = InfoChoices.nextShotsFilm

    var body: some View {
        Section("Lock Screen") {
            ForEach(shortcuts) { shortcut in
                NavigationLink {
                    LockShortcutEditor(slot: shortcut.slot)
                } label: {
                    LabeledContent("Shortcut \(shortcut.slot)",
                                   value: shortcut.film.map { "\($0) · \(shortcut.subtitle)" } ?? "Open Studio")
                }
                .accessibilityIdentifier("lock.shortcut.\(shortcut.slot)")
            }
        }
        .onAppear { shortcuts = LockShortcuts.all() }
        Section("Information Widgets") {
            filmPicker("Shoot Day", $shootDay, id: "info.shootday")
            filmPicker("Next Shots", $nextShots, id: "info.nextshots")
        }
        .onChange(of: shootDay) { _, film in InfoChoices.shootDayFilm = film; WidgetCenter.shared.reloadAllTimelines() }
        .onChange(of: nextShots) { _, film in InfoChoices.nextShotsFilm = film; WidgetCenter.shared.reloadAllTimelines() }
    }

    private func filmPicker(_ title: String, _ choice: Binding<String?>, id: String) -> some View {
        Picker(title, selection: choice) {
            Text("Soonest Shoot").tag(String?.none)
            ForEach(projects.all.map(\.name), id: \.self) { Text($0).tag(String?.some($0)) }
        }
        .accessibilityIdentifier(id)
    }
}

struct LockShortcutEditor: View {
    @EnvironmentObject private var projects: Projects
    @State private var shortcut: LockShortcut

    /// The places a shortcut can open, the film's own first.
    static let places: [Place] = [.shotList, .script, .schedule, .locations, .references, .diagrams,
                                  .film, .shoots, .library]

    init(slot: Int) {
        _shortcut = State(initialValue: LockShortcuts.one(slot))
    }

    /// Every film on this iPhone, and the one already chosen even if it has
    /// since gone, so the picker never shows a blank.
    private var films: [String] {
        var names = projects.all.map(\.name)
        if let chosen = shortcut.film, !names.contains(chosen) { names.append(chosen) }
        return names
    }

    var body: some View {
        Form {
            Section {
                Picker("Project", selection: $shortcut.film) {
                    Text("Open Studio").tag(String?.none)
                    ForEach(films, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .accessibilityIdentifier("lock.film")
                if shortcut.film != nil {
                    Picker("Page", selection: $shortcut.place) {
                        ForEach(Self.places) { place in
                            Label(place.title, systemImage: place.symbol).tag(String?.some(place.key))
                        }
                    }
                    .accessibilityIdentifier("lock.page")
                }
                Picker("Look", selection: $shortcut.look) {
                    ForEach(WidgetLook.allCases) { Text($0.name).tag(String?.some($0.rawValue)) }
                }
                .accessibilityIdentifier("lock.look")
            }
            .listRowBackground(Style.card)
        }
        .scrollContentBackground(.hidden)
        .background(Style.page)
        .navigationTitle("Shortcut \(shortcut.slot)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: shortcut.film) { _, film in
            // A film chosen with no page yet starts at the Shot List.
            if film != nil && shortcut.place == nil { shortcut.place = Place.shotList.key }
            if film == nil { shortcut.place = nil }
            save()
        }
        .onChange(of: shortcut.place) { _, _ in save() }
        .onChange(of: shortcut.look) { _, _ in save() }
        .onAppear { if shortcut.look == nil { shortcut.look = WidgetLook.badge.rawValue } }
    }

    private func save() {
        let place = shortcut.place.flatMap { Place(key: $0) }
        shortcut.placeTitle = place?.title
        shortcut.symbol = place?.symbol
        let mark = projects.all.first { $0.name == shortcut.film }?.mark
        shortcut.markPath = mark?.path
        shortcut.markColour = mark?.colour
        LockShortcuts.save(shortcut)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18, *) { ControlCenter.shared.reloadAllControls() }
    }
}
