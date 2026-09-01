import SwiftUI
import WidgetKit

private struct PinbookWidgetEntry: TimelineEntry {
    let date: Date
}

private struct PinbookWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PinbookWidgetEntry {
        PinbookWidgetEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PinbookWidgetEntry) -> Void) {
        completion(PinbookWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinbookWidgetEntry>) -> Void) {
        completion(Timeline(entries: [PinbookWidgetEntry(date: .now)], policy: .never))
    }
}

@main
struct PinbookWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickExpenseWidget()
        BalanceOverviewWidget()
    }
}

private struct QuickExpenseWidget: Widget {
    let kind = "PinbookQuickExpenseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinbookWidgetProvider()) { _ in
            PinbookWidgetCard(
                eyebrow: "Pinbook",
                title: "Add expense",
                detail: "Open a clean expense form",
                symbol: "plus",
                colors: [Color(red: 0.08, green: 0.43, blue: 0.33), Color(red: 0.12, green: 0.20, blue: 0.17)],
                destination: URL(string: "pinbook://expense/new")!
            )
        }
        .configurationDisplayName("Quick Expense")
        .description("Open a new expense without showing financial details on the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct BalanceOverviewWidget: Widget {
    let kind = "PinbookBalanceOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinbookWidgetProvider()) { _ in
            PinbookWidgetCard(
                eyebrow: "Pinbook",
                title: "Balance overview",
                detail: "Review balances safely by currency",
                symbol: "chart.bar.xaxis",
                colors: [Color(red: 0.16, green: 0.30, blue: 0.67), Color(red: 0.08, green: 0.12, blue: 0.24)],
                destination: URL(string: "pinbook://summary")!
            )
        }
        .configurationDisplayName("Balance Overview")
        .description("Open the private in-app summary. Amounts stay off the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct PinbookWidgetCard: View {
    @Environment(\.widgetFamily) private var family
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    let colors: [Color]
    let destination: URL

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Label(eyebrow, systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 4)
                Text(title)
                    .font(family == .systemSmall ? .title3.bold() : .title2.bold())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.78)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(2)
            }

            if family == .systemMedium {
                Spacer(minLength: 4)
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(.white.opacity(0.16), in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.22), lineWidth: 1) }
            }
        }
        .widgetURL(destination)
        .containerBackground(for: .widget) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .accessibilityElement(children: .combine)
    }
}
