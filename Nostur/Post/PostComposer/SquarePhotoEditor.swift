import SwiftUI
import UIKit
import ImageIO
import NavigationBackport

/// Coordinates are relative to the oriented source image, independent of editor size.
struct SquarePhotoCrop: Hashable {
    var zoom: CGFloat = 1
    var center = CGPoint(x: 0.5, y: 0.5)

    func rect(in size: CGSize) -> CGRect {
        let side = min(size.width, size.height) / min(max(zoom, 1), 8)
        return CGRect(
            x: min(max(center.x * size.width - side / 2, 0), size.width - side),
            y: min(max(center.y * size.height - side / 2, 0), size.height - side),
            width: side, height: side
        )
    }

    mutating func constrain(to size: CGSize) {
        zoom = min(max(zoom, 1), 8)
        let rect = rect(in: size)
        center = CGPoint(x: rect.midX / size.width, y: rect.midY / size.height)
    }
}

struct SquarePhotoEditor: View {
    let attachment: PostedImageMeta
    let onSave: (PostedImageMeta) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preview: UIImage?
    @State private var crop: SquarePhotoCrop
    @State private var saving = false
    @State private var failed = false

    init(attachment: PostedImageMeta, onSave: @escaping (PostedImageMeta) -> Void) {
        self.attachment = attachment
        self.onSave = onSave
        _crop = State(initialValue: attachment.squareCrop ?? SquarePhotoCrop())
    }

    var body: some View {
        NBNavigationStack {
            VStack(spacing: 20) {
                Text("Pinch to zoom. Drag to position.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let preview {
                    SquarePhotoCropCanvas(image: preview, crop: $crop)
                    PhotoCropControls(crop: $crop, imageSize: preview.size)
                }
                else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding()
            .navigationTitle("Square crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if saving { ProgressView() }
                        else { Image(systemName: "checkmark") }
                    }
                    .accessibilityLabel("Apply crop")
                    .disabled(preview == nil || saving)
                }
            }
            .disabled(saving)
            .alert("Couldn’t edit photo", isPresented: $failed) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please try again. Your original photo has been kept.")
            }
            .task {
                preview = await prepareComposerPhotoPreview(data: attachment.cropSourceData ?? attachment.data)
                if preview == nil { failed = true }
            }
        }
        .interactiveDismissDisabled()
    }

    private func save() {
        saving = true
        let selection = crop
        let sourceAttachment = attachment
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                renderSquarePhoto(attachment: sourceAttachment, crop: selection)
            }.value
            saving = false
            if let result {
                onSave(result)
                dismiss()
            }
            else { failed = true }
        }
    }
}

private struct SquarePhotoCropCanvas: View {
    let image: UIImage
    @Binding var crop: SquarePhotoCrop

    var body: some View {
        GeometryReader { geometry in
            let side = max(1, min(geometry.size.width, geometry.size.height))
            let rect = crop.rect(in: image.size)
            let scale = side / rect.width
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
                    .offset(x: (image.size.width / 2 - rect.midX) * scale,
                            y: (image.size.height / 2 - rect.midY) * scale)
                PhotoCropGrid()
                    .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .clipped()
            .overlay { Rectangle().strokeBorder(.white, lineWidth: 2).allowsHitTesting(false) }
            .contentShape(Rectangle())
            .overlay {
                PhotoCropGestures(crop: $crop, imageSize: image.size, side: side)
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .accessibilityLabel("Photo crop preview")
            .accessibilityHint("Use the zoom slider and position controls below to adjust the crop")
        }
    }

}

/// UIKit's recognizers support simultaneous pinch and pan on every supported OS.
private struct PhotoCropGestures: UIViewRepresentable {
    @Binding var crop: SquarePhotoCrop
    let imageSize: CGSize
    let side: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        pan.delegate = context.coordinator
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PhotoCropGestures
        init(parent: PhotoCropGestures) { self.parent = parent }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Only the crop surface's pinch and pan may run together. Allowing
            // the sheet's pan here also moves the sheet while repositioning a photo.
            gestureRecognizer.view === otherGestureRecognizer.view
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // A drag starting on the photo belongs to the crop surface. Make
            // ancestor pan gestures wait so the sheet cannot start following it.
            gestureRecognizer is UIPanGestureRecognizer
                && otherGestureRecognizer is UIPanGestureRecognizer
                && gestureRecognizer.view !== otherGestureRecognizer.view
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            var crop = parent.crop
            let scale = crop.rect(in: parent.imageSize).width / parent.side
            crop.center.x -= translation.x * scale / parent.imageSize.width
            crop.center.y -= translation.y * scale / parent.imageSize.height
            crop.constrain(to: parent.imageSize)
            parent.crop = crop
        }

        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            var crop = parent.crop
            // Keep the source pixel under the fingers stationary while zooming.
            let before = crop.rect(in: parent.imageSize)
            let point = gesture.location(in: gesture.view)
            crop.zoom *= gesture.scale
            gesture.scale = 1
            let after = crop.rect(in: parent.imageSize)
            crop.center.x += (point.x / parent.side - 0.5) * (before.width - after.width) / parent.imageSize.width
            crop.center.y += (point.y / parent.side - 0.5) * (before.height - after.height) / parent.imageSize.height
            crop.constrain(to: parent.imageSize)
            parent.crop = crop
        }
    }
}

private struct PhotoCropGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for fraction in [CGFloat(1 / 3.0), CGFloat(2 / 3.0)] {
                path.move(to: CGPoint(x: size.width * fraction, y: 0))
                path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                path.move(to: CGPoint(x: 0, y: size.height * fraction))
                path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
            }
            context.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

private struct PhotoCropControls: View {
    @Binding var crop: SquarePhotoCrop
    let imageSize: CGSize

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "minus.magnifyingglass").accessibilityHidden(true)
                Slider(value: $crop.zoom, in: 1...8)
                    .accessibilityLabel("Zoom")
                    .onValueChange(crop.zoom) { _, _ in crop.constrain(to: imageSize) }
                Image(systemName: "plus.magnifyingglass").accessibilityHidden(true)
            }
            HStack(spacing: 8) {
                Button { move(x: -0.05, y: 0) } label: { Image(systemName: "arrow.left") }
                    .accessibilityLabel("Move crop left")
                Button { move(x: 0, y: -0.05) } label: { Image(systemName: "arrow.up") }
                    .accessibilityLabel("Move crop up")
                Button("Reset") { crop = SquarePhotoCrop() }
                Button { move(x: 0, y: 0.05) } label: { Image(systemName: "arrow.down") }
                    .accessibilityLabel("Move crop down")
                Button { move(x: 0.05, y: 0) } label: { Image(systemName: "arrow.right") }
                    .accessibilityLabel("Move crop right")
            }
            .buttonStyle(.bordered)
        }
    }

    private func move(x: CGFloat, y: CGFloat) {
        let rect = crop.rect(in: imageSize)
        crop.center.x += x * rect.width / imageSize.width
        crop.center.y += y * rect.height / imageSize.height
        crop.constrain(to: imageSize)
    }
}

/// Runs off the main thread. ImageIO applies EXIF orientation before cropping.
func renderSquarePhoto(attachment: PostedImageMeta, crop: SquarePhotoCrop) -> PostedImageMeta? {
    let sourceData = attachment.cropSourceData ?? attachment.data
    guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
          let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        kCGImageSourceShouldCacheImmediately: true
    ]
    guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let rect = crop.rect(in: CGSize(width: oriented.width, height: oriented.height))
    let side = max(1, floor(rect.width))
    let pixelRect = CGRect(x: floor(rect.minX), y: floor(rect.minY), width: side, height: side)
    guard let cropped = oriented.cropping(to: pixelRect) else { return nil }
    let image = UIImage(cgImage: cropped)
    let isPNG = attachment.type == .png
    guard let data = isPNG ? image.pngData() : image.jpegData(compressionQuality: 0.95) else { return nil }
    var result = PostedImageMeta(index: attachment.index, data: data, type: isPNG ? .png : .jpeg, uniqueId: UUID().uuidString)
    result.altText = attachment.altText
    result.cropSourceData = sourceData
    result.squareCrop = crop
    return result
}
