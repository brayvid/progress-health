//
//  ProgressApp.swift
//  Progress
//
//  Created by Blake Rayvid on 4/12/25.
//

import SwiftUI
import HealthKit

@main
struct ProgressApp: App {
    @StateObject private var healthManager = HealthManager()

    var body: some Scene {
        WindowGroup {
            TabView(selection: $healthManager.selectedTab) {
                ContentView()
                    .tag(0)
                    .tabItem {
                        Label("Dashboard", systemImage: "house")
                    }

                InsightsView()
                    .tag(1)
                    .tabItem {
                        Label("Insights", systemImage: "lightbulb")
                    }

                CorrelationView()
                    .tag(2)
                    .tabItem {
                        Label("Regression", systemImage: "chart.xyaxis.line")
                    }

                SettingsView()
                    .tag(3)
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .environmentObject(healthManager)
            .onAppear {
                healthManager.requestAuthorization()
            }
        }
    }
}
