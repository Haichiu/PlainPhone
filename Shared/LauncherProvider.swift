import SwiftUI
import WidgetKit

/// Decides which layout and page a widget instance displays. Storage is
/// injectable so the selection logic can be tested deterministically.
struct LauncherProvider: AppIntentTimelineProvider {
    let defaults: UserDefaults?

    init(defaults: UserDefaults? = nil) { self.defaults = defaults }
    typealias Entry = LauncherEntry

    func resolveEntry(for configuration: SelectLayoutIntent?) -> LauncherEntry {
        let store = LauncherStore(defaults: defaults)
        let layouts = store.data.layouts.isEmpty ? DefaultLayouts.all : store.data.layouts

        var layout: LauncherLayout?
        if let configuration,
           let idString = configuration.layout?.id,
           let uuid = UUID(uuidString: idString) {
            layout = layouts.first { $0.id == uuid }
        }
        // Widget configuration is the only layout selector. With no
        // configuration, or one pointing at a deleted layout, fall back to the
        // first layout rather than to a remembered global selection.
        let resolved = layout ?? layouts.first ?? DefaultLayouts.everyday
        let page = WidgetCapacity.clampPage(configuration?.page ?? 1)
        // Header marker index = the layout's position in the owner's list
        // (dot → square → triangle → diamond). Falls back to 0 for the
        // seed fallback layout, which is always the first group.
        let markerIndex = layouts.firstIndex { $0.id == resolved.id } ?? 0
        return LauncherEntry(date: .now, layoutName: resolved.name,
                             items: resolved.items, page: page,
                             settings: store.data.settings,
                             markerIndex: markerIndex)
    }

    func placeholder(in context: Context) -> LauncherEntry {
        entry(from: DefaultLayouts.everyday)
    }

    func snapshot(for configuration: SelectLayoutIntent, in context: Context) async -> LauncherEntry {
        resolveEntry(for: context.isPreview ? nil : configuration)
    }

    func timeline(for configuration: SelectLayoutIntent, in context: Context) async -> Timeline<LauncherEntry> {
        // Static content; the app calls WidgetCenter.reloadAllTimelines() after edits.
        Timeline(entries: [resolveEntry(for: configuration)], policy: .never)
    }

    private func entry(from layout: LauncherLayout) -> LauncherEntry {
        LauncherEntry(date: .now, layoutName: layout.name, items: layout.items,
                      page: 1, settings: LauncherStore(defaults: defaults).data.settings)
    }
}
