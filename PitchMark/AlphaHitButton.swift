//
//  AlphaHitButton.swift
//  PitchMark
//
//  Created by Mark Springer on 11/11/25.
//


import SwiftUI
import UIKit

struct AlphaHitButton: UIViewRepresentable {
    let imageName: String
    let onTap: () -> Void
    var alphaThreshold: CGFloat = 0.1

    func makeUIView(context: Context) -> UIImageView {
        let iv = UIImageView(image: UIImage(named: imageName))
        iv.isUserInteractionEnabled = true
        iv.contentMode = .scaleAspectFit
        iv.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        return iv
    }
    func updateUIView(_ uiView: UIImageView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(alphaThreshold: alphaThreshold, onTap: onTap) }

    final class Coordinator: NSObject {
        let alphaThreshold: CGFloat; let onTap: () -> Void
        init(alphaThreshold: CGFloat, onTap: @escaping () -> Void) { self.alphaThreshold = alphaThreshold; self.onTap = onTap }

        @objc func tap(_ gr: UITapGestureRecognizer) {
            guard let v = gr.view as? UIImageView,
                  let img = v.image, let cg = img.cgImage else { return }
            let p = gr.location(in: v)
            let imgSize = CGSize(width: cg.width, height: cg.height)
            let viewSize = v.bounds.size
            let scale = min(viewSize.width / imgSize.width, viewSize.height / imgSize.height)
            let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
            let x0 = (viewSize.width - drawSize.width) / 2
            let y0 = (viewSize.height - drawSize.height) / 2
            guard p.x >= x0, p.y >= y0, p.x <= x0+drawSize.width, p.y <= y0+drawSize.height else { return }
            let ix = Int((p.x - x0) / scale), iy = Int((p.y - y0) / scale)
            if sampleAlpha(cg: cg, x: ix, y: iy) >= alphaThreshold { onTap() }
        }

        private func sampleAlpha(cg: CGImage, x: Int, y: Int) -> CGFloat {
            guard x >= 0, y >= 0, x < cg.width, y < cg.height else { return 0 }
            var pixel: [UInt8] = [0,0,0,0]
            let cs = CGColorSpaceCreateDeviceRGB()
            let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: -CGFloat(x), y: -CGFloat(y), width: CGFloat(cg.width), height: CGFloat(cg.height)))
            return CGFloat(pixel[3]) / 255.0
        }
    }
}

struct ZoneSpec: Identifiable {
    let id: String
    let image: String
    // normalized center and width relative to container
    let cx: CGFloat
    let cy: CGFloat
    let w:  CGFloat
}

struct FieldZonesView: View {
    @State private var selected = Set<String>()

    // TODO: put your 22 zones here with rough positions; tweak live
    let zones: [ZoneSpec] = [
        .init(id:"Shallow_CF", image:"Shallow_CF", cx:0.50, cy:0.35, w:0.28),
        .init(id:"Deep_CF",    image:"Deep_CF",    cx:0.50, cy:0.22, w:0.38),
        .init(id:"SS",         image:"SS",         cx:0.42, cy:0.55, w:0.18),
        .init(id:"2B",         image:"2B",         cx:0.58, cy:0.55, w:0.18),
        // ... add the rest (Deep_LF, Deep_RF, Shallow_LF/RF, 3B,1B,Front_*, Pitcher, HR_*, Foul pieces)
    ]

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height

            ZStack {
                // Buttons UNDER the field image
                ForEach(zones) { z in
                    AlphaHitButton(imageName: z.image) {
                        if selected.contains(z.id) { selected.remove(z.id) } else { selected.insert(z.id) }
                        print("Tapped \(z.id)")
                    }
                    .frame(width: z.w * W, height: z.w * W) // square frames work well for aspectFit; adjust if needed
                    .position(x: z.cx * W, y: z.cy * H)
                    .overlay( // simple highlight on selection
                        selected.contains(z.id) ? Color.white.opacity(0.25) : Color.clear
                    )
                }

                // Field image ON TOP, see-through, but ignores touches
                Image("full_field")
                    .resizable()
                    .scaledToFit()
                    .opacity(0.65)
                    .allowsHitTesting(false)
                    .frame(width: W, height: H)
            }
        }
    }
}

