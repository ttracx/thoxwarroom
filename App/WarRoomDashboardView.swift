import SwiftUI
import WarRoomMesh

struct WarRoomDashboardView: View {
    @ObservedObject var model: WarRoomDashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                provenanceCard
                content
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding()
        }
        .background(ThoxTheme.background.ignoresSafeArea())
        .navigationTitle("War Room")
        .tint(ThoxTheme.accent)
        .task(id: model.profile.id) {
            model.load()
            await model.waitForCurrentLoad()
        }
        .onDisappear { model.cancel() }
    }

    private var provenanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.profile.displayName, systemImage: model.profile.endpoint.boundary.systemImage)
                .font(.title2.weight(.semibold))
            LabeledContent("Boundary", value: model.profile.endpoint.boundary.title)
            LabeledContent("Provider", value: model.profile.provider.displayName)
            LabeledContent("Endpoint", value: visibleOrigin)
            Label(
                "Read-only status from the explicitly configured workspace endpoint.",
                systemImage: "eye.fill"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .dashboardCard()
        .accessibilityIdentifier("dashboard-provenance")
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            stateCard(icon: "gauge.with.dots.needle.50percent", title: "Dashboard not loaded", detail: "No War Room status has been requested.") {
                Button("Load dashboard") { model.load() }.buttonStyle(.borderedProminent)
            }
        case .loading:
            stateCard(icon: "arrow.triangle.2.circlepath", title: "Loading War Room…", detail: "Reading devices, topology, and bounded event status.") {
                ProgressView()
                Button("Cancel", role: .cancel) { model.cancel() }
            }
        case .empty(let snapshot):
            VStack(alignment: .leading, spacing: 12) {
                Label("No status returned", systemImage: "tray")
                    .font(.title2.weight(.semibold))
                Text("The read-only requests succeeded, but the War Room currently contains no devices, topology nodes, or events.")
                    .foregroundStyle(.secondary)
                snapshotProvenance(snapshot)
                refreshButton
            }.dashboardCard().accessibilityIdentifier("dashboard-empty")
        case .ready(let snapshot):
            dashboard(snapshot, banner: nil)
                .accessibilityIdentifier("dashboard-ready")
        case .stale(let snapshot):
            dashboard(snapshot, banner: ("Snapshot may be stale", "The captured status exceeds the local freshness policy. Refresh before making operational decisions."))
                .accessibilityIdentifier("dashboard-stale")
        case .partialFailure(let snapshot):
            dashboard(snapshot, banner: ("Partial status", "Some read-only sections failed. Available data remains visible with its provenance."))
                .accessibilityIdentifier("dashboard-partial")
        case .offline(let message):
            stateCard(icon: "wifi.slash", title: "Provider offline", detail: message) { refreshButton }
                .accessibilityIdentifier("dashboard-offline")
        case .error(let message):
            stateCard(icon: "exclamationmark.triangle.fill", title: "Dashboard unavailable", detail: message) { refreshButton }
                .accessibilityIdentifier("dashboard-error")
        }
    }

    private func dashboard(
        _ snapshot: WarRoomDashboardSnapshot,
        banner: (String, String)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let banner {
                Label(banner.0, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(banner.1).foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                metric("Devices", snapshot.devices.count)
                metric("Links", snapshot.topology?.edges.count ?? 0)
                metric("Events", snapshot.events.count)
            }
            if !snapshot.devices.isEmpty {
                section("Devices") {
                    ForEach(snapshot.devices, id: \.id) { device in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.displayName).font(.headline).privacySensitive()
                            Text("\(device.platform) · \(device.role)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !snapshot.events.isEmpty {
                section("Recent event types") {
                    ForEach(snapshot.events, id: \.id) { event in
                        HStack {
                            Text(event.eventType).privacySensitive()
                            Spacer()
                            Text(event.severity).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            ForEach(snapshot.failures, id: \.section) { failure in
                Label("\(failure.section.title): \(failure.message)", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
            snapshotProvenance(snapshot)
            refreshButton
        }
        .dashboardCard()
    }

    private func snapshotProvenance(_ snapshot: WarRoomDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider()
            Label("Read-only admin-console snapshot", systemImage: "checkmark.shield")
            if let latest = snapshot.provenance.map(\.fetchedAt).max() {
                Text("Captured \(latest.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Contract source is present but not yet live-verified.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading) {
            Text(value, format: .number).font(.title.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            content()
        }
    }

    private var refreshButton: some View {
        Button("Refresh") { model.load() }.buttonStyle(.borderedProminent)
    }

    private var visibleOrigin: String {
        guard let scheme = model.profile.endpoint.url.scheme,
              let host = model.profile.endpoint.url.host else {
            return "Validated endpoint"
        }
        if let port = model.profile.endpoint.url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private func stateCard<Actions: View>(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 38)).foregroundStyle(ThoxTheme.accent)
            Text(title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions()
        }
        .frame(maxWidth: .infinity)
        .dashboardCard()
    }
}

private extension View {
    func dashboardCard() -> some View {
        padding(22)
            .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(ThoxTheme.separator) }
    }
}
