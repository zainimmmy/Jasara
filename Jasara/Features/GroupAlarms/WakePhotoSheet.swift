import SwiftUI
import UIKit
import SensitiveContentAnalysis

extension PendingGroupCheckIn: Identifiable {
    var id: String { "\(groupID.uuidString)|\(occurrenceOn)" }
}

/// Offered after a group alarm is solved: a quick photo that only the group can
/// see, for 24 hours. Always optional.
struct WakePhotoSheet: View {
    @Environment(\.dismiss) private var dismiss
    var checkIn: PendingGroupCheckIn

    @State private var image: UIImage?
    @State private var showingCamera = false
    @State private var uploading = false
    @State private var error: String?
    @State private var done = false

    private var groupName: String {
        GroupAlarmSync.shared.groups.first { $0.id == checkIn.groupID }?.label ?? "your group"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if done {
                    Spacer()
                    Text("📸").font(.system(size: 50))
                    Text("Posted to \(groupName)").font(Face.title(22))
                    Text("Only people in the group can see it, and it disappears after 24 hours.")
                        .font(Face.caption).foregroundStyle(Ink.muted).multilineTextAlignment(.center)
                    Spacer()
                    PrimaryButton(title: "Done", palette: .mint) { dismiss() }
                } else if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
                        .frame(maxHeight: 420)
                    if let error {
                        Text(error).font(Face.caption).foregroundStyle(Palette.blush.ink)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                    PrimaryButton(title: uploading ? "Posting…" : "Post to \(groupName)", palette: .mint,
                                  isEnabled: !uploading) { post(image) }
                    Button("Retake") { showingCamera = true }.disabled(uploading)
                } else {
                    Spacer()
                    Text("☀️").font(.system(size: 50))
                    Text("You're up.").font(Face.display(30))
                    Text("Show \(groupName) with a wake photo? Only the group sees it, for 24 hours.")
                        .font(Face.row).foregroundStyle(Ink.muted).multilineTextAlignment(.center)
                    Spacer()
                    PrimaryButton(title: "Take a photo", palette: .lilac,
                                  isEnabled: CameraPicker.isAvailable) { showingCamera = true }
                    if !CameraPicker.isAvailable {
                        Text("This device has no camera.").font(Face.caption).foregroundStyle(Ink.muted)
                    }
                    Button("Not today") { dismiss() }.frame(minHeight: Metric.minTarget)
                }
            }
            .padding(Metric.gutter)
            .background(Ink.background)
            .navigationTitle("Wake photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !done { Button("Skip") { dismiss() } }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { picked in
                    showingCamera = false
                    if let picked { image = picked; error = nil }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func post(_ image: UIImage) {
        Task {
            uploading = true
            defer { uploading = false }
            guard let jpeg = WakePhotoProcessing.jpeg(from: image) else {
                error = "Couldn't prepare that photo."
                return
            }
            if await WakePhotoProcessing.looksSensitive(image) {
                error = "This photo can't be posted. Try another one."
                return
            }
            // The server only accepts a photo once the check-in it belongs to exists.
            await GroupAlarmSync.shared.flushCheckIns()
            do {
                try await Backend.shared.uploadWakePhoto(jpeg, group: checkIn.groupID,
                                                         occurrenceOn: checkIn.occurrenceOn)
                done = true
            } catch {
                self.error = Backend.describe(error)
            }
        }
    }
}

enum WakePhotoProcessing {
    /// Small enough for a quick upload and the 2 MB bucket limit, big enough to look fine.
    static func jpeg(from image: UIImage, maxSide: CGFloat = 1280) -> Data? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.75, 0.6, 0.45] {
            if let data = resized.jpegData(compressionQuality: quality), data.count < 1_900_000 {
                return data
            }
        }
        return nil
    }

    /// Apple's on-device check. It only runs when the person has Sensitive Content
    /// Warning or Communication Safety turned on, so it's a first line, not the
    /// only one: reporting and review cover the rest.
    static func looksSensitive(_ image: UIImage) async -> Bool {
        let analyzer = SCSensitivityAnalyzer()
        guard analyzer.analysisPolicy != .disabled, let cgImage = image.cgImage else { return false }
        return (try? await analyzer.analyzeImage(cgImage))?.isSensitive ?? false
    }
}

/// The system camera. Front camera by default: it's a selfie of being awake.
struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        if UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
