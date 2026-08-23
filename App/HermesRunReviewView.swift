import SwiftUI
import WarRoomHermes

struct HermesRunReviewView: View {
    @ObservedObject var model: HermesRunReviewModel
    @FocusState private var isRunIDFocused: Bool

    var body: some View {
        ZStack {
            ThoxTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    runSelector
                    phaseContent
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding()
            }
        }
        .tint(ThoxTheme.accent)
        .onDisappear { model.cancelLoading() }
        .accessibilityIdentifier("hermes-run-review")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Hermes run review", systemImage: "eye.fill")
                .font(.title2.weight(.semibold))
            Text("Read-only • Live event review")
                .font(.callout.weight(.medium))
                .foregroundStyle(ThoxTheme.accent)
            Text("Review status and event provenance. Approval and stop actions are unavailable in this surface.")
                .foregroundStyle(.secondary)
        }
    }

    private var runSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Opaque run identifier").font(.headline)
            HStack {
                runIDField
                Button("Load run") {
                    isRunIDFocused = false
                    model.startLoading()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isReviewActive)
                .accessibilityHint("Loads read-only status and follows live Hermes events")
                .accessibilityIdentifier("load-hermes-run")
            }
            if !model.recentRuns.isEmpty {
                Picker("Recent run", selection: recentRunSelection) {
                    Text("Select a recent run").tag(Optional<HermesRunID>.none)
                    ForEach(Array(model.recentRuns.enumerated()), id: \.offset) { index, runID in
                        Text("Recent run \(index + 1)").tag(Optional(runID))
                    }
                }
                .accessibilityHint("Run identifiers are intentionally hidden from picker labels")
                .accessibilityIdentifier("recent-hermes-run")
            }
            Text("The identifier is used only for this request and is omitted from status, provenance, and errors.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(ThoxTheme.separator) }
    }

    @ViewBuilder
    private var runIDField: some View {
        #if os(iOS)
        TextField("Paste run identifier", text: $model.runIDInput)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isRunIDFocused)
            .textFieldStyle(.roundedBorder)
            .privacySensitive()
            .accessibilityIdentifier("hermes-run-id")
        #else
        TextField("Paste run identifier", text: $model.runIDInput)
            .focused($isRunIDFocused)
            .textFieldStyle(.roundedBorder)
            .privacySensitive()
            .accessibilityIdentifier("hermes-run-id")
        #endif
    }

    private var recentRunSelection: Binding<HermesRunID?> {
        Binding(
            get: { model.selectedRecentRun },
            set: { model.selectRecentRun($0) }
        )
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .empty:
            reviewState(
                icon: "tray",
                title: "No run selected",
                detail: "Enter or select a run identifier to load status and follow live events."
            ) { EmptyView() }
                .accessibilityIdentifier("hermes-review-empty")
        case .loading:
            reviewState(
                icon: "arrow.triangle.2.circlepath",
                title: "Loading run…",
                detail: "Loading status and opening a live event stream from the selected Hermes workspace."
            ) {
                HStack {
                    ProgressView()
                    Button("Cancel") { model.cancelLoading() }
                        .accessibilityIdentifier("cancel-hermes-load")
                }
            }
            .accessibilityIdentifier("hermes-review-loading")
        case .failed(let message, let partialSnapshot):
            VStack(alignment: .leading, spacing: 14) {
                reviewState(icon: "exclamationmark.triangle", title: "Live review ended with an error", detail: message) {
                    Button("Retry") { model.retry() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("retry-hermes-load")
                }
                if let partialSnapshot {
                    snapshotContent(partialSnapshot, streamState: "Partial events retained")
                }
            }
            .accessibilityIdentifier("hermes-review-error")
        case .cancelled:
            reviewState(
                icon: "xmark.circle",
                title: "Load cancelled",
                detail: "The live connection was closed and no review data was retained."
            ) {
                Button("Retry") { model.retry() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("retry-cancelled-hermes-load")
            }
            .accessibilityIdentifier("hermes-review-cancelled")
        case .live(let snapshot):
            snapshotContent(snapshot, streamState: "Live")
        case .completed(let snapshot):
            snapshotContent(snapshot, streamState: "Review complete")
        }
    }

    private var isReviewActive: Bool {
        switch model.phase {
        case .loading, .live: true
        default: false
        }
    }

    private func snapshotContent(
        _ snapshot: HermesRunReviewSnapshot,
        streamState: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Run status", systemImage: "circle.fill")
                    .font(.headline)
                Spacer()
                Text(statusLabel(snapshot.status))
                    .font(.callout.weight(.semibold))
                    .accessibilityLabel("Run status: \(statusLabel(snapshot.status))")
            }
            Text("Source: Hermes API status endpoint")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
            HStack {
                Text("Live events").font(.headline)
                Spacer()
                Text(streamState)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(streamState == "Live" ? ThoxTheme.accent : Color.secondary)
            }
            if streamState == "Live" {
                Button("Cancel live review") { model.cancelLoading() }
                    .accessibilityIdentifier("cancel-hermes-live-review")
            }
            if snapshot.discardedEventCount > 0 {
                Text("Showing the newest \(snapshot.events.count) events. \(snapshot.discardedEventCount) older events were discarded on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("hermes-events-retention-notice")
            }
            if snapshot.events.isEmpty {
                Label(streamState == "Live" ? "Waiting for the next event…" : "No events were received.", systemImage: "tray")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("hermes-events-empty")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(snapshot.events.enumerated()), id: \.offset) { _, event in
                        HermesEventReviewRow(event: event)
                    }
                }
            }
        }
        .padding(18)
        .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(ThoxTheme.separator) }
        .accessibilityIdentifier("hermes-review-loaded")
    }

    private func statusLabel(_ status: HermesRunStatus) -> String {
        switch status {
        case .started: "Started"
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        default: "Unknown status • value redacted"
        }
    }

    private func reviewState<Actions: View>(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.title).foregroundStyle(ThoxTheme.accent)
                .accessibilityHidden(true)
            Text(title).font(.title3.weight(.semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(ThoxTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(ThoxTheme.separator) }
    }
}

private struct HermesEventReviewRow: View {
    let event: HermesRunEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }
            Text(provenance)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ThoxTheme.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch event {
        case .messageDelta: "Message update"
        case .toolStarted: "Tool started"
        case .toolCompleted: "Tool completed"
        case .reasoningAvailable: "Reasoning available"
        case .approvalRequest: "Approval requested • review only"
        case .approvalResponded: "Approval response observed"
        case .runCompleted: "Run completed"
        case .runFailed: "Run failed"
        case .runCancelled: "Run cancelled"
        case .unknown(let unknown):
            unknown.auditName == "<redacted>" ? "Redacted unknown event" : "Unknown event: \(unknown.auditName)"
        }
    }

    private var icon: String {
        switch event {
        case .messageDelta: "text.bubble"
        case .toolStarted, .toolCompleted: "wrench.and.screwdriver"
        case .reasoningAvailable: "brain"
        case .approvalRequest, .approvalResponded: "hand.raised"
        case .runCompleted: "checkmark.circle"
        case .runFailed: "exclamationmark.octagon"
        case .runCancelled: "xmark.circle"
        case .unknown: "questionmark.diamond"
        }
    }

    private var detail: String? {
        switch event {
        case .messageDelta(let event): event.delta
        case .toolStarted(let event), .toolCompleted(let event):
            event.toolName.map { "Tool metadata: \($0)" } ?? "Tool name not provided."
        case .reasoningAvailable:
            "Reasoning content is not retained by this event contract."
        case .approvalRequest(let event):
            "\(event.choices.count) canonical choices advertised. No action is available here."
        case .approvalResponded(let event):
            event.choice.map { "Observed choice: \($0.rawValue)" } ?? "Choice not provided."
        case .unknown(let event):
            event.payloadWasDiscarded ? "Unknown payload discarded." : "Unknown payload unavailable."
        case .runCompleted, .runFailed, .runCancelled:
            nil
        }
    }

    private var provenance: String {
        let timestamp: String? = switch event {
        case .messageDelta(let event): event.metadata.timestamp
        case .toolStarted(let event), .toolCompleted(let event): event.metadata.timestamp
        case .reasoningAvailable(let metadata), .runCompleted(let metadata),
             .runFailed(let metadata), .runCancelled(let metadata): metadata.timestamp
        case .approvalRequest(let event): event.metadata.timestamp
        case .approvalResponded(let event): event.metadata.timestamp
        case .unknown: nil
        }
        if let timestamp {
            return "Hermes API • Live SSE • \(timestamp)"
        }
        return "Hermes API • Live SSE"
    }
}
