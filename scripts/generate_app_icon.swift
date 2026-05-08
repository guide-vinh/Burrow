// One-shot tool: render the BrandLogo (coral squircle + white tornado) into
// AppIcon.appiconset at all sizes macOS expects. Run with:
//
//   swift scripts/generate_app_icon.swift
//
// Requires macOS 13+ (ImageRenderer). The Burrow app itself targets macOS 12.

import AppKit
import SwiftUI

let assetDir = "Burrow/Resources/Assets.xcassets/AppIcon.appiconset"

struct IconArtwork: View {
    let size: CGFloat

    // Apple's macOS icon template: visible content occupies ~80% of the
    // canvas (824/1024) so the icon sits visually consistent with other
    // dock apps. Edge-to-edge artwork makes Burrow look oversized.
    private let visibleScale: CGFloat = 0.80

    var body: some View {
        let visible = size * visibleScale
        ZStack {
            Color.clear
            RoundedRectangle(cornerRadius: visible * 0.225, style: .continuous)
                .fill(Color(red: 0xFF / 255.0, green: 0x7A / 255.0, blue: 0x59 / 255.0))
                .frame(width: visible, height: visible)
            Image(systemName: "tornado")
                .font(.system(size: visible * 0.55, weight: .regular))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

@MainActor
func renderPNG(size: CGFloat) -> Data? {
    let renderer = ImageRenderer(content: IconArtwork(size: size))
    renderer.scale = 1
    guard let cg = renderer.cgImage else { return nil }
    let rep = NSBitmapImageRep(cgImage: cg)
    return rep.representation(using: .png, properties: [:])
}

let outputs: [(filename: String, size: Int)] = [
    ("icon_16.png",   16),
    ("icon_32.png",   32),
    ("icon_64.png",   64),
    ("icon_128.png",  128),
    ("icon_256.png",  256),
    ("icon_512.png",  512),
    ("icon_1024.png", 1024),
]

let manifest: [(idiom: String, scale: String, size: String, filename: String)] = [
    ("mac", "1x", "16x16",   "icon_16.png"),
    ("mac", "2x", "16x16",   "icon_32.png"),
    ("mac", "1x", "32x32",   "icon_32.png"),
    ("mac", "2x", "32x32",   "icon_64.png"),
    ("mac", "1x", "128x128", "icon_128.png"),
    ("mac", "2x", "128x128", "icon_256.png"),
    ("mac", "1x", "256x256", "icon_256.png"),
    ("mac", "2x", "256x256", "icon_512.png"),
    ("mac", "1x", "512x512", "icon_512.png"),
    ("mac", "2x", "512x512", "icon_1024.png"),
]

@MainActor
func run() {
    let fm = FileManager.default
    let dirURL = URL(fileURLWithPath: assetDir)
    guard fm.fileExists(atPath: dirURL.path) else {
        FileHandle.standardError.write(Data("error: \(assetDir) not found — run from the repo root\n".utf8))
        exit(1)
    }

    for (filename, size) in outputs {
        guard let data = renderPNG(size: CGFloat(size)) else {
            FileHandle.standardError.write(Data("error: failed to render \(filename)\n".utf8))
            exit(1)
        }
        let url = dirURL.appendingPathComponent(filename)
        try! data.write(to: url)
        print("wrote \(filename) (\(size)×\(size))")
    }

    let images = manifest.map { entry in
        """
            {
              "idiom" : "\(entry.idiom)",
              "scale" : "\(entry.scale)",
              "size" : "\(entry.size)",
              "filename" : "\(entry.filename)"
            }
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }.joined(separator: ",\n    ")

    let json = """
    {
      "images" : [
        \(images)
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
    let contentsURL = dirURL.appendingPathComponent("Contents.json")
    try! json.write(to: contentsURL, atomically: true, encoding: .utf8)
    print("wrote Contents.json")
}

MainActor.assumeIsolated { run() }
