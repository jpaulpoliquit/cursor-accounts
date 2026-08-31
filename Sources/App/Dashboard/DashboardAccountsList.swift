import CursorBarDomain
import SwiftUI

struct DashboardAccountsList: View {
    @Bindable var model: AppModel
    var surface: DashboardSeatSurface

    var body: some View {
        let spacing: CGFloat = {
            switch surface {
            case .card:
                return 16
            case .row:
                return 0
            }
        }()
        VStack(alignment: .leading, spacing: spacing) {
            let listing = DashboardAccountFilter.Listing.make(
                seats: model.presentation.connectedAccounts,
                query: model.accountFilter
            )
            if let empty = listing.emptyReason {
                Text(empty.message)
                    .font(CursorProfile.Font.table)
                    .foregroundStyle(.secondary)
                    .padding(surface == .card ? 0 : 20)
            } else {
                ForEach(listing.visible) { seat in
                    SeatCardView(
                        seat: seat,
                        hardLimitPhase: model.presentation.setHardLimitPhase,
                        model: model,
                        surface: surface
                    )
                }
            }
        }
    }
}
