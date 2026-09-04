import SwiftUI
import WidgetKit

// A QA widget must never launch the working TestFlight app's URL scheme.
private func pinbookWidgetDestination(_ route: String) -> URL? {
    guard let scheme = Bundle.main.object(forInfoDictionaryKey: "PinbookURLScheme") as? String,
          ["pinbook", "pinbook-qa"].contains(scheme) else { return nil }
    return URL(string: "\(scheme)://\(route)")
}

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
                destination: pinbookWidgetDestination("expense/new")
            )
        }
        .configurationDisplayName("Quick Expense")
        .description("Open a new expense without showing financial details on the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
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
                destination: pinbookWidgetDestination("summary")
            )
        }
        .configurationDisplayName("Balance Overview")
        .description("Open the private in-app summary. Amounts stay off the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct PinbookWidgetCard: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    let colors: [Color]
    let destination: URL?

    private var foreground: Color {
        renderingMode == .fullColor && showsBackground ? .white : .primary
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: symbol)
                        .font(.title2.weight(.semibold))
                        .widgetAccentable()
                }
                .accessibilityLabel(Text(title))
            case .accessoryInline:
                Label(title, systemImage: symbol)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    Label(eyebrow, systemImage: symbol)
                        .font(.caption.weight(.semibold))
                        .widgetAccentable()
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            default:
                homeScreenCard
            }
        }
        .widgetURL(destination)
        .containerBackground(for: .widget) {
            if family == .systemSmall || family == .systemMedium {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var homeScreenCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Label(eyebrow, systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(foreground.opacity(0.85))
                Spacer(minLength: 4)
                Text(title)
                    .font(family == .systemSmall ? .title3.bold() : .title2.bold())
                    .foregroundStyle(foreground)
                    .minimumScaleFactor(0.78)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(foreground.opacity(0.85))
                    .lineLimit(2)
            }

            if family == .systemMedium {
                Spacer(minLength: 4)
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(foreground)
                    .widgetAccentable()
                    .frame(width: 62, height: 62)
                    .background(foreground.opacity(0.16), in: Circle())
                    .overlay { Circle().stroke(foreground.opacity(0.22), lineWidth: 1) }
            }
        }
    }
}
