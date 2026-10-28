import Foundation
import WidgetKit

/// Pushes the non-sensitive summary of the vault (names and dates) to the
/// places outside the app that show it: widgets, the Control Center control,
/// Siri, Quick Actions and (if enabled) Spotlight.
@MainActor
enum SystemSync {
    static func refresh(documents: [VaultDocument]) {
        let snapshot = VaultSnapshot(items: documents.map { $0.snapshotItem() }, generatedAt: .now)
        try? snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        QuickActions.update(documents: documents)
        if SpotlightIndexer.isEnabled {
            SpotlightIndexer.index(documents)
        }
    }
}
