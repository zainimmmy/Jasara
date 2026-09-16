import SwiftUI
import UIKit

struct TileChallengeView: View {
    var tier: Tier
    var rounds: Int
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var round = 0
    @State private var lit: Set<Int> = []
    @State private var tapped: Set<Int> = []
    @State private var showing = true
    @State private var wrongTile: Int?

    private var spec: ChallengeCatalog.TileSpec { ChallengeCatalog.tileSpec(tier) }
    private var tileCount: Int { spec.gridSize * spec.gridSize }

    var body: some View {
        VStack(spacing: 20) {
            ChallengeHeader(title: showing ? "Memorise" : "Tap them back", round: round, total: rounds)

            GeometryReader { geo in
                // The grid fills the full width. At 10×10 a cell is about 34pt,
                // under Apple's 44pt guidance, so each cell carries tap tolerance
                // via its spacing rather than shrinking the hit area.
                let spacing: CGFloat = spec.gridSize > 7 ? 3 : 6
                let side = (geo.size.width - spacing * CGFloat(spec.gridSize - 1)) / CGFloat(spec.gridSize)
                VStack(spacing: spacing) {
                    ForEach(0..<spec.gridSize, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<spec.gridSize, id: \.self) { column in
                                let index = row * spec.gridSize + column
                                tile(index, side: side)
                            }
                        }
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 360)

            Text(showing
                 ? "\(spec.litTiles) tiles, \(String(format: "%.2f", spec.showSeconds)) seconds"
                 : "\(lit.count - tapped.count) left")
                .font(Face.caption).monospacedDigit()
                .foregroundStyle(Ink.primary.opacity(0.7))
        }
        .padding(.horizontal, Metric.gutter)
        .onAppear { startRound() }
    }

    private func tile(_ index: Int, side: CGFloat) -> some View {
        let isLit = showing && lit.contains(index)
        let isFound = tapped.contains(index)
        let isWrong = wrongTile == index
        return RoundedRectangle(cornerRadius: side > 30 ? 10 : 6, style: .continuous)
            .fill(isWrong ? Palette.blush.fill
                  : isFound ? Palette.mint.fill
                  : isLit ? Palette.lilac.fill
                  : Ink.surface.opacity(0.85))
            .frame(width: side, height: side)
            .overlay(
                RoundedRectangle(cornerRadius: side > 30 ? 10 : 6, style: .continuous)
                    .strokeBorder(isFound ? Palette.mint.ink : Ink.primary.opacity(0.18), lineWidth: 1)
            )
            // Tap tolerance: the touch area extends into the gap around the cell.
            .contentShape(Rectangle().inset(by: -4))
            .onTapGesture { tap(index) }
            .accessibilityLabel(accessibilityLabel(index))
            .accessibilityAddTraits(.isButton)
    }

    private func accessibilityLabel(_ index: Int) -> String {
        let row = index / spec.gridSize + 1
        let column = index % spec.gridSize + 1
        let state = showing && lit.contains(index) ? "lit" : tapped.contains(index) ? "found" : "empty"
        return "Row \(row), column \(column), \(state)"
    }

    private func startRound() {
        tapped = []
        wrongTile = nil
        lit = Set((0..<tileCount).shuffled().prefix(spec.litTiles))
        showing = true
        let delay = reduceMotion ? spec.showSeconds + 1 : spec.showSeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.2)) { showing = false }
        }
    }

    private func tap(_ index: Int) {
        guard !showing else { return }
        guard lit.contains(index) else {
            // Wrong tile: same tiles, shown again. The round doesn't count as lost.
            withAnimation { wrongTile = index }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { startRound() }
            return
        }
        guard !tapped.contains(index) else { return }
        tapped.insert(index)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard tapped.count == lit.count else { return }
        round += 1
        if round >= rounds {
            onComplete()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { startRound() }
        }
    }
}
