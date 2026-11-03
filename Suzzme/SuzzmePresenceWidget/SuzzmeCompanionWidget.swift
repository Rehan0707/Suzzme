import SwiftUI
import UIKit
import WidgetKit

struct SuzzmeCompanionProvider: TimelineProvider {
    func placeholder(in context: Context) -> SuzzmeCompanionEntry { .init(date: .now, snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (SuzzmeCompanionEntry) -> Void) {
        let now = Date.now
        let sample = SuzzmeCompanionSnapshot(phase: nil, updatedAt: now,
            summaryGeneratedAt: now, summaryExpiresAt: now.addingTimeInterval(7200))
        completion(.init(date: now, snapshot: context.isPreview ? sample : SuzzmeCompanionSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SuzzmeCompanionEntry>) -> Void) {
        let now = Date.now
        let snapshot = SuzzmeCompanionSnapshotStore.load()
        let dates = [now] + (snapshot?.transitionDates(after: now) ?? [])
        let entries = dates.map { SuzzmeCompanionEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct SuzzmeCompanionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SuzzmeCompanionSnapshot.widgetKind, provider: SuzzmeCompanionProvider()) { entry in
            SuzzmeCompanionSmallView(entry: entry)
                .containerBackground(Color(uiColor: .secondarySystemBackground), for: .widget)
        }
        .configurationDisplayName("Suzzme Companion")
        .description("A quiet snapshot of your session and received Daily Summary.")
        .supportedFamilies([.systemSmall])
    }
}

#if !SUZZME_PRESENCE_RENDER
#Preview("Companion · Small", as: .systemSmall) {
    SuzzmeCompanionWidget()
} timeline: {
    SuzzmeCompanionEntry(date: .now, snapshot: nil)
    SuzzmeCompanionEntry(date: .now, snapshot: .init(phase: .speaking, updatedAt: .now))
    SuzzmeCompanionEntry(date: .now, snapshot: .init(phase: nil, updatedAt: .now, summaryGeneratedAt: .now, summaryExpiresAt: .now.addingTimeInterval(7200)))
}

#endif
