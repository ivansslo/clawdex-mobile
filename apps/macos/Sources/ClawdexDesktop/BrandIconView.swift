import AppKit
import SwiftUI

enum BrandAsset: String {
    case clawdex = "mark"
    case codex = "engine-codex"
    case cursor = "engine-cursor"
    case opencode = "engine-opencode"

    var accessibilityLabel: String {
        switch self {
        case .clawdex:
            "Clawdex"
        case .codex:
            "Codex"
        case .cursor:
            "Cursor"
        case .opencode:
            "OpenCode"
        }
    }
}

struct BrandIconView: View {
    let asset: BrandAsset
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(5, round(size * 0.24)))
                .fill(tileColor)

            if let image = asset.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.08)
            } else {
                Text(asset.fallbackText)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.black)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: max(5, round(size * 0.24)))
                .stroke(strokeColor, lineWidth: 0.5)
        )
        .accessibilityLabel(asset.accessibilityLabel)
    }

    private var tileColor: Color {
        switch asset {
        case .clawdex, .cursor:
            Color.black.opacity(0.86)
        case .codex, .opencode:
            Color.white.opacity(0.96)
        }
    }

    private var strokeColor: Color {
        switch asset {
        case .clawdex, .cursor:
            Color.white.opacity(0.18)
        case .codex, .opencode:
            Color.black.opacity(0.12)
        }
    }
}

private extension BrandAsset {
    var image: NSImage? {
        for bundle in candidateBundles {
            if let url = bundle.url(forResource: rawValue, withExtension: "png") {
                return NSImage(contentsOf: url)
            }
        }
        return nil
    }

    var candidateBundles: [Bundle] {
        var bundles: [Bundle] = []
        if
            let resourceURL = Bundle.main.resourceURL?
                .appendingPathComponent("ClawdexDesktop_ClawdexDesktop.bundle"),
            let bundle = Bundle(url: resourceURL)
        {
            bundles.append(bundle)
        }
        bundles.append(Bundle.module)
        return bundles
    }

    var fallbackText: String {
        switch self {
        case .clawdex, .codex:
            "C"
        case .cursor:
            "Cu"
        case .opencode:
            "O"
        }
    }
}
