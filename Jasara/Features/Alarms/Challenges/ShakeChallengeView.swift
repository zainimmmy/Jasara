import SwiftUI
import UIKit
import CoreMotion

struct ShakeChallengeView: View {
    var tier: Tier
    var rounds: Int
    var onComplete: () -> Void

    @State private var motion = ShakeDetector()

    var body: some View {
        VStack(spacing: 24) {
            ChallengeHeader(title: "Shake it off", round: motion.count, total: rounds)

            ZStack {
                Circle()
                    .stroke(Ink.primary.opacity(0.12), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: Double(motion.count) / Double(max(rounds, 1)))
                    .stroke(Palette.mint.ink, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: motion.count)
                VStack(spacing: 2) {
                    Text("\(max(rounds - motion.count, 0))")
                        .font(Face.display(46)).monospacedDigit()
                    Text("to go").font(Face.caption).foregroundStyle(Ink.primary.opacity(0.7))
                }
            }
            .frame(width: 210, height: 210)

            // Live meter so the setup screen and the real thing feel the same.
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Ink.primary.opacity(0.12))
                        Capsule().fill(Palette.butter.ink)
                            .frame(width: geo.size.width * min(motion.magnitude / (threshold * 1.5), 1))
                        Rectangle().fill(Palette.blush.ink)
                            .frame(width: 2)
                            .offset(x: geo.size.width * min(threshold / (threshold * 1.5), 1) - 1)
                    }
                }
                .frame(height: 10)
                Text(String(format: "%.1f g  •  needs %.1f g", motion.magnitude, threshold))
                    .font(Face.caption).monospacedDigit()
                    .foregroundStyle(Ink.primary.opacity(0.7))
            }
            .frame(maxWidth: 280)

            Text("Hold it tight. Wrist strap energy, not frisbee energy.")
                .font(Face.caption)
                .foregroundStyle(Ink.primary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Metric.gutter)
        .onAppear { motion.start(threshold: threshold) }
        .onDisappear { motion.stop() }
        .onChange(of: motion.count) { _, count in
            if count >= rounds { onComplete() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shake the phone \(max(rounds - motion.count, 0)) more times")
    }

    private var threshold: Double { ChallengeCatalog.shakeThreshold(tier) }
}

/// Counts distinct shakes: a peak over the tier's threshold, with a cooldown so
/// one violent wobble isn't worth five.
@Observable
final class ShakeDetector {
    private(set) var count = 0
    private(set) var magnitude: Double = 0

    private let manager = CMMotionManager()
    private var threshold: Double = 2.1
    private var lastCounted: Date = .distantPast
    private var armed = true

    func start(threshold: Double) {
        self.threshold = threshold
        count = 0
        guard manager.isAccelerometerAvailable else { return }
        manager.accelerometerUpdateInterval = 1.0 / 50
        manager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let force = sqrt(pow(data.acceleration.x, 2)
                             + pow(data.acceleration.y, 2)
                             + pow(data.acceleration.z, 2))
            self.magnitude = force
            if force >= self.threshold, self.armed,
               Date().timeIntervalSince(self.lastCounted) >= ChallengeCatalog.shakeCooldown {
                self.count += 1
                self.lastCounted = .now
                self.armed = false
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
            // Re-arm once the phone settles, so the count follows real shakes.
            if force < self.threshold * 0.6 { self.armed = true }
        }
    }

    func stop() { manager.stopAccelerometerUpdates() }
}
