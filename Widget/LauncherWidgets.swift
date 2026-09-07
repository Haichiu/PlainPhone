import SwiftUI
import WidgetKit
import AppIntents

struct PlainPhoneWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PlainPhoneLauncher", intent: SelectLayoutIntent.self, provider: LauncherProvider()) { entry in
            LauncherWidgetView(entry: entry)
        }
        .configurationDisplayName("極簡啟動器")
        .description("黑底白字的文字啟動器，每一列都能直接點開。放不下的項目會落到下一頁。")
        // systemSmall is deliberately NOT supported: it provides a single
        // widget-level tap target, so a list of independently tappable rows
        // cannot be delivered honestly at that size.
        .supportedFamilies([.systemMedium, .systemLarge])
        // The system content margin STAYS. Disabling it let the marker
        // reach the corner but moved every name up and outward, and the
        // owner's ordering is explicit (2026-09-07): the text may not move,
        // the marker is the negotiable one. Row positions are therefore
        // exactly what they were before that experiment.
    }
}
