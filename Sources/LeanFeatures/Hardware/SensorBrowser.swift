// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import LeanDesignSystem
import LeanDomain

struct SensorValueRow: View {
    let reading: SensorReading

    var body: some View {
        HStack {
            Text(reading.displayName)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f °C", reading.temp)).monospacedDigit()
                if reading.category == "CPU" || reading.category == "GPU" {
                    let level = MonLevel.temp(reading.temp)
                    Text(level.temperatureLabel).font(.caption2).foregroundStyle(level.color)
                }
            }
        }.font(.callout)
    }
}

struct SensorBrowser: View {
    let readings: [SensorReading]
    let back: () -> Void
    @State private var query = ""
    @State private var page = 0
    private let pageSize = 6

    var body: some View {
        let matches = readings.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
        let lastPage = max(0, (matches.count - 1) / pageSize)
        let currentPage = min(page, lastPage)
        let start = currentPage * pageSize
        VStack(alignment: .leading, spacing: 10) {
            Button(action: back) { Label(tr("Monitor"), systemImage: "chevron.left") }.buttonStyle(.link)
            Text(tr("Temperature sensors")).font(.headline)
            TextField(tr("Find a sensor"), text: $query)
                .onChange(of: query) { _, _ in page = 0 }
            if matches.isEmpty {
                Text(tr("No matching sensors")).foregroundStyle(Pal.ink2)
            } else {
                ForEach(matches.dropFirst(start).prefix(pageSize)) { reading in
                    JDivider()
                    SensorValueRow(reading: reading)
                }
                HStack {
                    Text("\(start + 1)–\(min(start + pageSize, matches.count)) / \(matches.count)").monospacedDigit()
                    Spacer()
                    Button(tr("Previous")) { page = currentPage - 1 }.disabled(currentPage == 0)
                    Button(tr("Next")) { page = currentPage + 1 }.disabled(currentPage == lastPage)
                }.controlSize(.small)
            }
        }.jCard()
    }
}
