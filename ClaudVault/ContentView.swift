import SwiftUI
import SwiftData


@MainActor
struct ContentView:View {
    let dependencies:AppDependencies
    var body: some View {
        RootView(dependencies: dependencies).modelContainer(dependencies.modelContainer)
    }
}
