import AppKit
import SwiftUI

/// Pick any color on screen with macOS's own magnifier. Each pick is copied as hex and kept (last 12).
@Observable @MainActor
final class ColorPicker {
    static let limit = 12

    private(set) var colors: [String]
    @ObservationIgnored var onPicked: ((String) -> Void)?

    init() {
        colors = UserDefaults.standard.stringArray(forKey: "pickedColors") ?? []
    }

    func pick() {
        NSColorSampler().show { [weak self] color in
            MainActor.assumeIsolated {
                guard let self, let color else { return } // nil: cancelled with Escape
                let hex = Self.hex(color)
                self.remember(hex)
                Self.copy(hex)
                self.onPicked?(hex)
            }
        }
    }

    func remember(_ hex: String) {
        colors.removeAll { $0 == hex }
        colors.insert(hex, at: 0)
        if colors.count > Self.limit { colors.removeLast(colors.count - Self.limit) }
        UserDefaults.standard.set(colors, forKey: "pickedColors")
    }

    func clear() {
        colors = []
        UserDefaults.standard.set(colors, forKey: "pickedColors")
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func hex(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int(($0 * 255).rounded()).clamped(0, 255) }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }

    static func color(hex: String) -> NSColor? {
        guard hex.count == 7, hex.hasPrefix("#"), let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// The same color written the ways designers and developers paste it.
    static func formats(_ hex: String) -> [(label: String, text: String)] {
        guard let color = color(hex: hex) else { return [] }
        let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
        func byte(_ value: CGFloat) -> Int { Int((value * 255).rounded()) }
        func unit(_ value: CGFloat) -> String { String(format: "%.3f", value) }
        return [
            ("Hex", hex),
            ("CSS", "rgb(\(byte(r)), \(byte(g)), \(byte(b)))"),
            ("SwiftUI", "Color(red: \(unit(r)), green: \(unit(g)), blue: \(unit(b)))"),
        ]
    }
}

private extension Int {
    func clamped(_ low: Int, _ high: Int) -> Int { Swift.min(high, Swift.max(low, self)) }
}

struct ColorsView: View {
    let picker: ColorPicker
    let pick: () -> Void
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: pick) {
                    HStack(spacing: 6) {
                        Icon(name: "pipette-linear", size: 13)
                        Text("Pick a color")
                    }
                }
                .buttonStyle(PrimaryStyle())
                Text(picker.colors.isEmpty ? "or press ⌃⌥P anywhere" : "Click a swatch to copy it again")
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.ash)
                Spacer(minLength: 0)
                if !picker.colors.isEmpty {
                    Button("Clear") { withAnimation(Motion.easeOut(0.2)) { picker.clear() } }
                        .buttonStyle(SecondaryStyle())
                }
            }
            if picker.colors.isEmpty {
                // Empty slots where swatches will land, so the space explains itself.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: Radius.control + 1, style: .continuous)
                                .strokeBorder(Palette.rail, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .frame(height: 30)
                        }
                    }
                    Text("Colors you pick land here, newest first.")
                        .font(Typeface.caption)
                        .foregroundStyle(Palette.ash)
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                    ForEach(picker.colors, id: \.self) { hex in
                        Swatch(hex: hex, copied: copied == hex) {
                            ColorPicker.copy(hex)
                            showCopied(hex)
                        } copyAs: { text in
                            ColorPicker.copy(text)
                            showCopied(hex)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
            }
        }
        .animation(Motion.easeOut(0.2), value: picker.colors)
    }

    private func showCopied(_ hex: String) {
        copied = hex
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copied == hex { copied = nil }
        }
    }
}

private struct Swatch: View {
    let hex: String
    let copied: Bool
    let copy: () -> Void
    let copyAs: (String) -> Void

    var body: some View {
        Button(action: copy) {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: Radius.control + 1, style: .continuous)
                    .fill(Color(nsColor: ColorPicker.color(hex: hex) ?? .gray))
                    .frame(height: 30)
                    .overlay(RoundedRectangle(cornerRadius: Radius.control + 1, style: .continuous).strokeBorder(Palette.rail, lineWidth: 1))
                Text(copied ? "Copied" : hex)
                    .font(Typeface.caption.monospacedDigit())
                    .foregroundStyle(copied ? Palette.paper : Palette.graphite)
                    .contentTransition(.opacity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .animation(Motion.easeOut(0.2), value: copied)
        .contextMenu {
            ForEach(ColorPicker.formats(hex), id: \.label) { format in
                Button("Copy as \(format.label)") { copyAs(format.text) }
            }
        }
        .accessibilityLabel("Color \(hex)")
        .accessibilityHint("Copies it")
    }
}
