import SwiftData
import SwiftUI

@main
struct KeshijizhangApp: App {
    private let container: ModelContainer?

    init() {
        container = try? KeshijizhangApp.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootTabView()
                    .modelContainer(container)
                    .environment(\.locale, CN.locale)
                    .preferredColorScheme(.light)
                    .tint(Theme.blue)
            } else {
                VStack(spacing: 12) {
                    Text("本地数据无法打开")
                        .font(.headline)
                    Text("请删除本 App 后重新安装。安装前如果已经记过账，数据会随 App 一起被系统清掉。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
    }

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Organization.self,
            SmallGroup.self,
            Student.self,
            WeeklySlot.self,
            PriceRecord.self,
            Lesson.self,
        ])
        let configuration = ModelConfiguration(
            "Keshijizhang",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
