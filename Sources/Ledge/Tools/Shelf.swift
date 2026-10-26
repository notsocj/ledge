import AppKit
import SwiftUI

/// Files parked on the notch. Holds references to the originals, not copies, and remembers them
/// across launches (files that have since been moved or deleted drop off).
@Observable @MainActor
final class Shelf {
    private(set) var files: [URL]

    init() {
        files = (UserDefaults.standard.stringArray(forKey: "shelf") ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        files = urls.filter { $0.isFileURL && !files.contains($0) } + files
        save()
    }

    func remove(_ url: URL) {
        files.removeAll { $0 == url }
        save()
    }

    func clear() {
        files = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(files.map(\.path), forKey: "shelf")
    }
}

struct ShelfView: View {
    let shelf: Shelf
    /// A file is being dragged somewhere on screen, so the shelf shows where it can land.
    var dragging = false
    @State private var targeted = false

    var body: some View {
        Group {
            if shelf.files.isEmpty {
                // An outlined drop zone, so the empty shelf shows where files go before anything is dragged.
                EmptyTab(symbol: "inbox-linear", title: dragging ? "Drop to keep it here" : "Drop files here",
                         hint: dragging ? "Let go and it waits on the shelf. Drag it back out whenever you need it."
                                        : "Drag files onto the notch to keep them handy, then drag them out wherever you need them.")
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: Radius.well, style: .continuous)
                        .fill(Palette.well.opacity(dragging ? 1 : 0))
                        .strokeBorder(dragging ? Palette.graphite : Palette.rail, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    .animation(Motion.ease(0.2), value: dragging)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(shelf.files.count == 1 ? "1 file" : "\(shelf.files.count) files")
                            .foregroundStyle(Palette.graphite)
                        Spacer()
                        Button("Clear") { withAnimation(Motion.easeOut(0.2)) { shelf.clear() } }
                            .buttonStyle(SecondaryStyle())
                            .padding(.trailing, -10)
                    }
                    .font(Typeface.caption)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            if dragging { DropTile().transition(.opacity.combined(with: .scale(scale: 0.95))) }
                            ForEach(shelf.files, id: \.self) { url in
                                FileTile(url: url) { withAnimation(Motion.easeOut(0.2)) { shelf.remove(url) } }
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: Radius.well, style: .continuous)
                .fill(Palette.well)
                .strokeBorder(Palette.graphite, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .opacity(targeted ? 1 : 0)
        }
        .animation(Motion.ease(0.15), value: targeted)
        .dropDestination(for: URL.self) { urls, _ in
            withAnimation(Motion.easeOut(0.2)) { shelf.add(urls) }
            return true
        } isTargeted: { targeted = $0 }
    }
}

/// The space a new file will take, shown at the front of the shelf while one is being dragged.
private struct DropTile: View {
    var body: some View {
        VStack(spacing: 6) {
            Icon(name: "add-circle-linear", size: 20)
                .foregroundStyle(Palette.graphite)
                .frame(width: 48, height: 48)
            Text("Drop to add")
                .font(Typeface.caption)
                .foregroundStyle(Palette.graphite)
        }
        .frame(width: 80)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Palette.well)
            .strokeBorder(Palette.graphite, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }
}

private struct FileTile: View {
    let url: URL
    let remove: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 48, height: 48)
            Text(url.lastPathComponent)
                .font(Typeface.caption)
                .foregroundStyle(Palette.graphite)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 76)
        }
        .frame(width: 80)
        .contentShape(Rectangle())
        .draggable(url)
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Remove from shelf", action: remove)
        }
        .help(url.path)
    }
}
