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
            ForEach(model.presentation.connectedAccounts) { seat in
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
