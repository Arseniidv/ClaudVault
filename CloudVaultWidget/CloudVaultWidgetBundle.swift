//
//  CloudVaultWidgetBundle.swift
//  CloudVaultWidget
//
//  Created by Arsenii Dvornichenko on 06.11.2026.
//

import WidgetKit
import SwiftUI

@main
struct CloudVaultWidgetBundle: WidgetBundle {
    var body: some Widget {
        CloudVaultWidget()
        #if os(iOS) && canImport(ActivityKit)
        CloudSyncLiveActivity()
        #endif
    }
}
