// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import UIKit

/// A photo prepared for the model: longest side ≤ 2048 px, JPEG.
struct PickedImage: Identifiable {
    let id = UUID()
    let preview: UIImage
    let prompt: PromptImage

    init?(data: Data) {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 2048 ? 2048 / longest : 1
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return nil }
        preview = resized
        prompt = PromptImage(mediaType: "image/jpeg", data: jpeg, name: "photo.jpg")
    }
}
