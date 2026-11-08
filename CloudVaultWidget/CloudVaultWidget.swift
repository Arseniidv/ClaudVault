//
//  CloudVaultWidget.swift
//  CloudVaultWidget
//
//  Created by Arsenii Dvornichenko on 06.11.2026.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline

struct StorageTimelineEntry: TimelineEntry {
    let date: Date
    let storageData: MultiStorageWidgetData?
}

/// Виджет не выполняет сетевых запросов: он читает JSON-снимок,
/// который приложение пишет в App Group после каждой синхронизации.
/// Политика `.never` — обновление только по `WidgetCenter.reloadAllTimelines()`.
struct StorageTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> StorageTimelineEntry {
        StorageTimelineEntry(date: Date(), storageData: Self.mockData)
    }

    func getSnapshot(in context: Context, completion: @escaping (StorageTimelineEntry) -> Void) {
        completion(StorageTimelineEntry(date: Date(), storageData: loadSharedData() ?? Self.mockData))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StorageTimelineEntry>) -> Void) {
        let entry = StorageTimelineEntry(date: Date(), storageData: loadSharedData())
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func loadSharedData() -> MultiStorageWidgetData? {
        guard let defaults = UserDefaults(suiteName: WidgetStorage.appGroupID),
              let data = defaults.data(forKey: WidgetStorage.dataKey) else {
            return nil
        }
        return try? JSONDecoder().decode(MultiStorageWidgetData.self, from: data)
    }

    private static let mockData = MultiStorageWidgetData(
        lastUpdatedAt: Date(),
        accounts: [
            WidgetAccountInfo(provider: "googleDrive", email: "user@gmail.com", usedBytes: 12_000_000_000, totalBytes: 15_000_000_000),
            WidgetAccountInfo(provider: "dropbox", email: "work@example.com", usedBytes: 1_300_000_000, totalBytes: 2_000_000_000)
        ]
    )
}

// MARK: - Widget

struct CloudVaultWidget: Widget {
    let kind: String = "CloudVaultWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StorageTimelineProvider()) { entry in
            ClaudVaultWidgetEntryView(entry: entry)
                .containerBackground(Color(red: 0.055, green: 0.067, blue: 0.090), for: .widget)
        }
        .configurationDisplayName("ClaudVault Хранилища")
        .description("Занятое место в подключённых облачных хранилищах.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        #elseif os(macOS)
        // На macOS доступны те же system-семейства плюс ExtraLarge;
        // accessory-семейств (watchOS/iOS) здесь нет.
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        #endif
    }
}

// MARK: - Entry View

private enum WidgetPalette {
    static let background = Color(red: 0.055, green: 0.067, blue: 0.090)
    static let accent = Color(red: 0.25, green: 0.48, blue: 1.00)
    static let surface = Color(red: 0.090, green: 0.105, blue: 0.140)
    static let surfaceSecondary = Color(red: 0.120, green: 0.140, blue: 0.180)
}

struct ClaudVaultWidgetEntryView: View {
    var entry: StorageTimelineProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let data = entry.storageData, !data.accounts.isEmpty {
            switch family {
            case .systemSmall:
                SmallWidgetView(data: data)
            case .systemMedium:
                MediumWidgetView(data: data)
            case .systemLarge, .systemExtraLarge:
                LargeWidgetView(data: data)
            default:
                SmallWidgetView(data: data)
            }
        } else {
            emptyStateView
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "cloud.bolt.rain")
                .font(.system(size: 24))
                .foregroundStyle(.gray)
            Text("Нет данных")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "claudvault://storage"))
    }
}

// MARK: - Small

private struct SmallWidgetView: View {
    let data: MultiStorageWidgetData

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)

                // Сегментированное кольцо: каждый аккаунт занимает
                // свою дугу пропорционально доле от суммарной ёмкости.
                ForEach(Array(data.accounts.enumerated()), id: \.element.id) { index, account in
                    let start = data.accounts.prefix(index).reduce(0.0) {
                        $0 + min(max(Double($1.usedBytes) / Double(max(data.totalMaxBytes, 1)), 0), 1)
                    }
                    let end = min(start + min(max(Double(account.usedBytes) / Double(max(data.totalMaxBytes, 1)), 0), 1), 1)

                    if end > start {
                        Circle()
                            .trim(from: start, to: end)
                            .stroke(
                                ProviderPalette.color(for: account.provider),
                                style: StrokeStyle(lineWidth: 8, lineCap: .butt)
                            )
                            .rotationEffect(.degrees(-90))
                    }
                }

                VStack(spacing: 0) {
                    Text(String(format: "%.1f", data.totalUsedGB))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("ГБ занято")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 72, height: 72)

            Text("из \(String(format: "%.0f", data.totalMaxGB)) ГБ")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "claudvault://storage"))
    }
}

// MARK: - Medium

private struct MediumWidgetView: View {
    let data: MultiStorageWidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ClaudVault")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("Обновлено \(Self.timeFormatter.string(from: data.lastUpdatedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(data.accounts) { account in
                            let fraction = data.totalMaxBytes > 0
                                ? Double(account.usedBytes) / Double(data.totalMaxBytes) : 0
                            let width = geo.size.width * CGFloat(min(max(fraction, 0), 1))

                            if width > 0 {
                                Rectangle()
                                    .fill(ProviderPalette.color(for: account.provider))
                                    .frame(width: width)
                            }
                        }

                        let freeFraction = data.totalMaxBytes > 0
                            ? max(Double(data.totalMaxBytes - data.totalUsedBytes), 0) / Double(data.totalMaxBytes) : 1

                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: geo.size.width * CGFloat(min(max(freeFraction, 0), 1)))
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())

                HStack {
                    Text("\(String(format: "%.1f", data.totalUsedGB)) ГБ занято")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("Свободно: \(String(format: "%.1f", data.totalAvailableGB)) ГБ")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            HStack(spacing: 6) {
                ForEach(data.accounts.prefix(3)) { account in
                    ProviderBadge(provider: account.provider)
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "claudvault://storage"))
    }

    fileprivate static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// MARK: - Large

private struct LargeWidgetView: View {
    let data: MultiStorageWidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Подключенные хранилища")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("Обновлено \(MediumWidgetView.timeFormatter.string(from: data.lastUpdatedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            VStack(spacing: 10) {
                ForEach(data.accounts.prefix(4)) { account in
                    AccountRow(account: account)
                }
            }

            // Быстрые действия: виджет не может сам открыть пикер
            // файлов или камеру — кнопки ведут в приложение по deep
            // link, а оно сразу показывает нужный интерфейс.
            HStack(spacing: 10) {
                WidgetActionButton(
                    title: "Файл",
                    systemImage: "doc.badge.plus",
                    url: URL(string: "claudvault://backup/new?mode=file")!
                )
                WidgetActionButton(
                    title: "Скан",
                    systemImage: "doc.viewfinder",
                    url: URL(string: "claudvault://backup/new?mode=scan")!
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Кнопка быстрого действия в large-виджете. `Link` — единственный
/// способ передать тап виджета в приложение (widgetURL даёт только
/// один URL на весь виджет).
private struct WidgetActionButton: View {
    let title: String
    let systemImage: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(WidgetPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        WidgetPalette.accent.opacity(0.35),
                        lineWidth: 1
                    )
            }
        }
    }
}

private struct AccountRow: View {
    let account: WidgetAccountInfo

    var body: some View {
        Link(destination: Self.deepLink(for: account)) {
            HStack(spacing: 12) {
                let providerColor = ProviderPalette.color(for: account.provider)

                Image(systemName: Self.iconName(for: account.provider))
                    .font(.system(size: 16))
                    .foregroundStyle(providerColor)
                    .frame(width: 32, height: 32)
                    .background(providerColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(Self.providerTitle(for: account.provider)) Storage")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(String(format: "%.1f", account.usedGB)) / \(String(format: "%.0f", account.totalGB)) ГБ")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                    ProgressView(value: min(max(account.usageFraction, 0), 1))
                        .progressViewStyle(.linear)
                        .tint(providerColor)
                        .frame(width: 64)
                    Text("\(Int(account.usageFraction * 100))%")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(10)
            .background(WidgetPalette.surface.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// `claudvault://storage/{provider}?email={email}` — обрабатывается в RootView.
    static func deepLink(for account: WidgetAccountInfo) -> URL {
        var components = URLComponents()
        components.scheme = "claudvault"
        components.host = "storage"
        components.path = "/\(account.provider)"
        components.queryItems = [URLQueryItem(name: "email", value: account.email)]
        return components.url ?? URL(string: "claudvault://storage")!
    }

    static func iconName(for provider: String) -> String {
        switch provider {
        case "googleDrive": return "arrow.triangle.2.circlepath"
        case "dropbox": return "shippingbox"
        case "oneDrive": return "cloud"
        default: return "externaldrive"
        }
    }

    static func providerTitle(for provider: String) -> String {
        switch provider {
        case "googleDrive": return "Google Drive"
        case "dropbox": return "Dropbox"
        case "oneDrive": return "OneDrive"
        default: return provider.capitalized
        }
    }
}

private struct ProviderBadge: View {
    let provider: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ProviderPalette.color(for: provider))
                .frame(width: 6, height: 6)
            Image(systemName: AccountRow.iconName(for: provider))
                .font(.system(size: 9))
            Text(AccountRow.providerTitle(for: provider))
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(WidgetPalette.surface)
        .clipShape(Capsule())
    }
}

#Preview(as: .systemMedium) {
    CloudVaultWidget()
} timeline: {
    StorageTimelineEntry(date: .now, storageData: nil)
}
