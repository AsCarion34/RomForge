import SwiftUI

/// upstream ToolTabViewModel의 표준 진행 표시(XAML progressArea):
/// ProgressLabel · ProgressPercent · ProgressSpeed · ProgressTime · ProgressPct 막대(140pt) 한 줄.
struct ToolProgressBar: View {
    let vm: RemoteObject?
    var barWidth: CGFloat = 140

    var body: some View {
        HStack(spacing: 10) {
            Text(vm?.string("ProgressLabel") ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(vm?.string("ProgressPercent") ?? "")
                .fontWeight(.semibold)
                .foregroundStyle(.green)
            Text(vm?.string("ProgressSpeed") ?? "")
                .foregroundStyle(.secondary)
            Text(vm?.string("ProgressTime") ?? "")
                .foregroundStyle(.green)
            ProgressView(value: min(max((vm?["ProgressPct"]?.double ?? 0) / 100, 0), 1))
                .frame(width: barWidth)
        }
        .font(.caption.monospacedDigit())
        .frame(minHeight: 22)
    }
}
