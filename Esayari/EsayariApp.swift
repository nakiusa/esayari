import SwiftUI
import SwiftData
import UserNotifications
import GoogleMobileAds

@main
struct EsayariApp: App {
    init() { MobileAds.shared.start() }

    var body: some Scene {
        WindowGroup {
            FishList()
                .task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        }
        .modelContainer(container)
    }

    /// `-demo` で起動すると、ストア用のスクリーンショットを撮るための見本を入れたメモリ上の帳面で開く。
    let container: ModelContainer = {
        let demo = ProcessInfo.processInfo.arguments.contains("-demo")
        let c = try! ModelContainer(for: Fish.self, configurations: ModelConfiguration(isStoredInMemoryOnly: demo))
        if demo {
            for (name, hours, ago) in [("金魚の水槽", 12, [13.0, 25, 37]), ("メダカ", 24, [3.0, 27, 51]),
                                       ("ベタ", 24, [20.0, 44]), ("グッピー", 8, [1.0, 9, 17, 25])] {
                let fish = Fish(name: name, intervalHours: hours)
                fish.createdAt = .now.addingTimeInterval(-86400 * 3)
                fish.feedings = ago.map { .now.addingTimeInterval(-$0 * 3600) }
                c.mainContext.insert(fish)
            }
        }
        return c
    }()
}

@Model
final class Fish {
    var name: String
    var intervalHours: Int
    var feedings: [Date] = []
    var createdAt = Date()
    var uid = UUID()

    init(name: String, intervalHours: Int) {
        self.name = name
        self.intervalHours = intervalHours
    }

    var lastFed: Date? { feedings.max() }
    var nextDue: Date { (lastFed ?? createdAt).addingTimeInterval(Double(intervalHours) * 3600) }

    func feed(at date: Date = .now) {
        feedings.append(date)
        Reminder.schedule(self)
    }
}

/// 魚ごとに、次のえさの時刻に一つだけ通知を置く。あげるたびに置き直す。
enum Reminder {
    static func id(_ fish: Fish) -> String { fish.uid.uuidString }

    static func schedule(_ fish: Fish) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id(fish)])
        let seconds = fish.nextDue.timeIntervalSinceNow
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "えさの時間です"
        content.body = "\(fish.name)にえさをあげましょう"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        center.add(UNNotificationRequest(identifier: id(fish), content: content, trigger: trigger))
    }

    static func cancel(_ fish: Fish) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id(fish)])
    }
}

struct FishList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Fish.createdAt) private var fishes: [Fish]
    @State private var adding = false

    var body: some View {
        NavigationStack {
            // 一分ごとに「あと何分」を描き直す。
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                List {
                    ForEach(fishes.sorted { $0.nextDue < $1.nextDue }) { fish in
                        NavigationLink { FishDetail(fish: fish) } label: { FishRow(fish: fish, now: timeline.date) }
                    }
                    .onDelete { offsets in
                        let sorted = fishes.sorted { $0.nextDue < $1.nextDue }
                        for i in offsets {
                            Reminder.cancel(sorted[i])
                            context.delete(sorted[i])
                        }
                    }
                }
                .overlay {
                    if fishes.isEmpty {
                        ContentUnavailableView("魚がいません", systemImage: "fish",
                                               description: Text("右上の＋から、えさをあげる魚や水槽を登録します。"))
                    }
                }
            }
            // ストアのスクリーンショットに第三者の広告は写せないので、見本のときは出さない。
            .safeAreaInset(edge: .bottom) {
                if !ProcessInfo.processInfo.arguments.contains("-demo") { AdBanner() }
            }
            .navigationTitle("えさやり帳")
            .toolbar {
                Button("追加", systemImage: "plus") { adding = true }
            }
            .sheet(isPresented: $adding) { AddFish() }
        }
    }
}

struct FishRow: View {
    let fish: Fish
    let now: Date

    var body: some View {
        let overdue = fish.nextDue <= now
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(fish.name).font(.headline)
                Text(fish.lastFed.map { "前回 \(relative($0))" } ?? "まだあげていません")
                    .font(.caption).foregroundStyle(.secondary)
                Text(overdue ? "えさの時間です" : "次は\(relative(fish.nextDue))（\(fish.nextDue.formatted(date: .omitted, time: .shortened))）")
                    .font(.subheadline)
                    .foregroundStyle(overdue ? .red : .secondary)
            }
            Spacer()
            Button("あげた") { fish.feed() }
                .buttonStyle(.borderedProminent)
                .tint(overdue ? .orange : .accentColor)
        }
    }

    func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}

struct FishDetail: View {
    @Bindable var fish: Fish

    var body: some View {
        Form {
            Section {
                TextField("名前", text: $fish.name)
                Stepper("\(fish.intervalHours)時間ごと", value: $fish.intervalHours, in: 1...168)
            } footer: {
                Text("次のえさは \(fish.nextDue.formatted(date: .abbreviated, time: .shortened)) です。その時刻に通知します。")
            }
            Section("記録") {
                Button("いまあげた") { fish.feed() }
                ForEach(fish.feedings.sorted(by: >), id: \.self) { date in
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                }
                .onDelete { offsets in
                    let sorted = fish.feedings.sorted(by: >)
                    let removed = Set(offsets.map { sorted[$0] })
                    fish.feedings.removeAll { removed.contains($0) }
                    Reminder.schedule(fish)
                }
            }
        }
        .navigationTitle(fish.name)
        .onChange(of: fish.intervalHours) { Reminder.schedule(fish) }
        .onChange(of: fish.name) { Reminder.schedule(fish) }
    }
}

struct AddFish: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hours = 24

    var body: some View {
        NavigationStack {
            Form {
                TextField("名前（例：メダカの水槽）", text: $name)
                Stepper("\(hours)時間ごと", value: $hours, in: 1...168)
            }
            .navigationTitle("魚を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        let fish = Fish(name: name.trimmingCharacters(in: .whitespaces), intervalHours: hours)
                        context.insert(fish)
                        Reminder.schedule(fish)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
