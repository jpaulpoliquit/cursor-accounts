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
            MenuBarStatusLabel(presentation: model.presentation, usage: model.menuBarUsage)
                .onAppear {
                    model.startBootstrap()
                    AppModel.sharedForVerify = model
                }
        }

        Window("Accounts", id: DashboardWindowIdentity.sceneID) {
            DashboardView(model: model)
                .frame(minWidth: 720, minHeight: 560)
                .modifier(DashboardColorSchemeModifier())
                .onAppear {
                    model.startBootstrap()
                    AppModel.sharedForVerify = model
                }
        }
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
