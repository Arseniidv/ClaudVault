//
//  CloudSyncLiveActivity.swift
//  CloudVaultWidget
//
//  Live Activity для Dynamic Island и экрана блокировки:
//  отображает прогресс загрузки резервной копии в облако.
//

import WidgetKit
import SwiftUI
#if os(iOS) && canImport(ActivityKit)
import ActivityKit

private enum LiveActivityPalette {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.075)
    static let accent = Color(red: 0.25, green: 0.48, blue: 1.00)
    static let success = Color(red: 0.25, green: 0.78, blue: 0.52)
}

struct CloudSyncLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CloudSyncAttributes.self) { context in
            // MARK: Lock Screen / баннер
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(LiveActivityPalette.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.fileName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(context.attributes.providerName)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(value: context.state.progress)
                            .progressViewStyle(.linear)
                            .tint(LiveActivityPalette.accent)
                        HStack {
                            Text(context.state.statusMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            Text(context.state.currentSpeed)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(LiveActivityPalette.success)
                        }
                    }
                }
            } compactLeading: {
                // MARK: Compact leading — иконка облака
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(LiveActivityPalette.accent)
            } compactTrailing: {
                // MARK: Compact trailing — процент
                Text("\(Int(context.state.progress * 100))%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 44)
            } minimal: {
                // MARK: Minimal (несколько активностей)
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(LiveActivityPalette.accent)
            }
            .keylineTint(LiveActivityPalette.accent)
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<CloudSyncAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.up.doc.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(LiveActivityPalette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.fileName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(context.attributes.providerName)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Text("\(Int(context.state.progress * 100))%")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }

            ProgressView(value: context.state.progress)
                .progressViewStyle(.linear)
                .tint(LiveActivityPalette.accent)

            HStack {
                Text(context.state.statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(context.state.currentSpeed)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LiveActivityPalette.success)
            }
        }
        .padding(16)
        .activityBackgroundTint(LiveActivityPalette.background)
        .activitySystemActionForegroundColor(.white)
    }
}
#endif
