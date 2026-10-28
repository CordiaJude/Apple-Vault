import SwiftUI
import WidgetKit

@main
struct VaultWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ExpirationsWidget()
        NextExpiringWidget()
        DocumentControl()
    }
}
