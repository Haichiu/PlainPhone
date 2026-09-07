import AppIntents
import Foundation

/// AppEntity representing one saved layout, offered as the widget's
/// configuration parameter with dynamic options from shared storage.
struct LauncherLayoutEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "版面")
    static let defaultQuery = LayoutQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

extension LauncherLayoutEntity {
    static var available: [LauncherLayoutEntity] { available(suiteName: nil) }

    /// Injectable seam so tests (and callers with an explicit suite) read from
    /// the SAME storage they configured, instead of a self-resolved store.
    static func available(suiteName: String?) -> [LauncherLayoutEntity] {
        let defaults = suiteName.flatMap { UserDefaults(suiteName: $0) }
        return LauncherStore(defaults: defaults).data.layouts
            .map { LauncherLayoutEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

/// Widget layout-picker query. Stores a suite-name string (trivially
/// Sendable) rather than a UserDefaults reference.
struct LayoutQuery: EntityQuery {
    var suiteName: String?

    init(suiteName: String?) { self.suiteName = suiteName }
    init() { self.suiteName = nil }

    func entities(for identifiers: [String]) async throws -> [LauncherLayoutEntity] {
        LauncherLayoutEntity.available(suiteName: suiteName).filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [LauncherLayoutEntity] {
        LauncherLayoutEntity.available(suiteName: suiteName)
    }

    func defaultResult() async -> LauncherLayoutEntity? {
        LauncherLayoutEntity.available(suiteName: suiteName).first
    }
}

/// Widget configuration intent: choose which layout the widget displays.
struct SelectLayoutIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "選擇版面"
    static let description = IntentDescription(
        "選擇這個小工具要顯示的版面與頁次。放不下的項目會落到下一頁；把不同頁次的小工具疊在一起，就能上下滑動切換。")

    @Parameter(title: "版面")
    var layout: LauncherLayoutEntity?

    /// 1-based page. Out-of-range values are clamped by `WidgetCapacity`.
    @Parameter(title: "頁次", default: 1)
    var page: Int?
}
