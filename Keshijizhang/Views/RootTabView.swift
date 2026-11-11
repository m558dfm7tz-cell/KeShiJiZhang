import SwiftData
import SwiftUI
import UIKit

struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        let blue = UIColor(red: 0, green: 0.478, blue: 1, alpha: 1)
        let gray = UIColor.secondaryLabel
        appearance.stackedLayoutAppearance.normal.iconColor = gray
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: gray]
        appearance.stackedLayoutAppearance.selected.iconColor = blue
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: blue]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                TodayView()
            }
            .tabItem { Label("今天", systemImage: tab == 0 ? "checkmark.square.fill" : "checkmark.square") }
            .tag(0)

            NavigationStack {
                PaymentView()
            }
            .tabItem { Label("收款", systemImage: tab == 1 ? "yensign.circle.fill" : "yensign.circle") }
            .tag(1)

            NavigationStack {
                ManageView()
            }
            .tabItem { Label("管理", systemImage: tab == 2 ? "folder.fill" : "folder") }
            .tag(2)

            NavigationStack {
                MonthStatsView()
            }
            .tabItem { Label("月统计", systemImage: tab == 3 ? "chart.bar.fill" : "chart.bar") }
            .tag(3)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                context.saveNow()
            }
        }
    }
}
