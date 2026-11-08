#if os(iOS) && !SHARE_EXTENSION
import SwiftUI

/// Streaming answer for a natural-language library question.
struct AskCard: View {
    @Bindable var assistant: Assistant
    let ask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch assistant.phase {
            case .idle:
                EmptyView()
            case .unavailable:
                Text("On-device Apple Intelligence isn't available here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case let .failed(message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !assistant.modelFailed { Button("Try Again", action: ask) }
            default:
                if let plan = assistant.plan {
                    FlowChips(plan.summaryChips)
                }
                if assistant.phase == .planning {
                    ProgressView("Understanding…")
                } else {
                    Text(countLabel)
                        .font(.headline)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: assistant.count)
                }
                if !assistant.answer.isEmpty {
                    Text(assistant.answer)
                        .font(.body)
                } else if assistant.phase == .answering {
                    ProgressView()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var countLabel: String {
        let n = assistant.count
        return n == 1 ? String(localized: "1 match") : String(localized: "\(n) matches")
    }
}

private struct FlowChips: View {
    let chips: [String]
    init(_ chips: [String]) { self.chips = chips }

    var body: some View {
        FlexibleChipRow(chips: chips)
    }
}

/// Simple wrapping chip row without a layout dependency.
private struct FlexibleChipRow: View {
    let chips: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { chip in
                        Text(chip)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
    }

    /// Rough wrap at ~36 characters per row.
    private var rows: [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        var width = 0
        for chip in chips {
            let w = chip.count + 2
            if width + w > 36, !current.isEmpty {
                result.append(current)
                current = [chip]
                width = w
            } else {
                current.append(chip)
                width += w
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
#endif
