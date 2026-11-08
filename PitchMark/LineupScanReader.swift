//
//  LineupScanReader.swift
//  PitchMark
//
//  Scan Opponent Lineup: reads text off a screenshot or a photo of a
//  screen with Apple's on-device text recognition (Vision) and hands it to
//  LineupScanParser. Nothing leaves the phone and nothing is saved - the
//  image is dropped once read.
//

import SwiftUI
import UIKit
import Vision
import VisionKit
import CoreImage

enum LineupScanReader {
    /// Every piece of text on one image, top-left origin.
    static func read(_ image: UIImage) async -> [LineupScanText] {
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = straightened(image) ?? normalizedCGImage(image) else { return [] }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Names aren't dictionary words; correction "fixes" them.
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                debugLog("⚠️ lineup scan: text recognition failed:", error.localizedDescription)
                return []
            }
            return (request.results ?? []).compactMap { observation -> LineupScanText? in
                guard let best = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                return LineupScanText(
                    best.string,
                    x: Double(box.minX),
                    y: Double(1 - box.midY),
                    height: Double(box.height),
                    confidence: Double(best.confidence)
                )
            }
        }.value
    }

    /// Reads several images and merges them in pick order.
    static func rows(from images: [UIImage]) async -> [LineupScanRow] {
        var perImage: [[LineupScanRow]] = []
        for image in images {
            perImage.append(LineupScanParser.parse(await read(image)))
        }
        return LineupScanParser.merge(perImage)
    }

    // MARK: Image prep

    /// The image upright, as a CGImage.
    private static func normalizedCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }.cgImage
    }

    /// A photo of another screen, squared up. A screenshot comes back nil
    /// (used as is): its panels are already square to the image, and
    /// cropping to one would lose rows outside it.
    private static func straightened(_ image: UIImage) -> CGImage? {
        guard let cgImage = normalizedCGImage(image) else { return nil }
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumSize = 0.4
        request.minimumConfidence = 0.8
        request.quadratureTolerance = 30
        request.minimumAspectRatio = 0.3
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil,
              let rect = request.results?.first else { return nil }

        // Square to the image already = a screenshot's panel, not a screen
        // photographed at an angle.
        let tilt = max(
            abs(rect.topLeft.x - rect.bottomLeft.x), abs(rect.topRight.x - rect.bottomRight.x),
            abs(rect.topLeft.y - rect.topRight.y), abs(rect.bottomLeft.y - rect.bottomRight.y)
        )
        guard tilt > 0.02 else { return nil }

        let ciImage = CIImage(cgImage: cgImage)
        let size = ciImage.extent.size
        func point(_ p: CGPoint) -> CIVector { CIVector(x: p.x * size.width, y: p.y * size.height) }
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(point(rect.topLeft), forKey: "inputTopLeft")
        filter.setValue(point(rect.topRight), forKey: "inputTopRight")
        filter.setValue(point(rect.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(point(rect.bottomRight), forKey: "inputBottomRight")
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

/// VisionKit's document camera: it finds the screen's edges and squares
/// the shot up itself. Only offered where the device supports it.
struct LineupScanCamera: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: LineupScanCamera
        init(_ parent: LineupScanCamera) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            debugLog("⚠️ lineup scan camera failed:", error.localizedDescription)
            parent.onCancel()
        }
    }
}
