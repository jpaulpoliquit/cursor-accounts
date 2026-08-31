import CursorBarDomain
import SwiftUI

@main
struct CursorBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRoot(model: model)
                .onAppear {
                    model.startBootstrap()
                    AppModel.sharedForVerify = model
                }
        } label: {
            Text(model.presentation.menuBarLabel)
                .onAppear {
                    model.startBootstrap()
                    AppModel.sharedForVerify = model
                }
        }

        Window("Dashboard", id: DashboardWindowIdentity.sceneID) {
            DashboardView(model: model)
                .frame(minWidth: 720, minHeight: 560)
                .modifier(DashboardColorSchemeModifier())
                .onAppear {
                    model.startBootstrap()
                    AppModel.sharedForVerify = model
                }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 860, height: 800)
        .windowResizability(.contentMinSize)
    }
}

private struct DashboardColorSchemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if CommandLine.arguments.contains("--dashboard-dark") {
            content.preferredColorScheme(.dark)
        } else {
            content
        }
    }
}
