import SwiftUI

/// A scratchpad saved to Application Support as you type (half a second after you stop).
@Observable @MainActor
final class Notes {
    var text: String {
        didSet { scheduleSave() }
    }
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Ledge/notes.txt")

    init() {
        text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func save() {
        pendingSave?.cancel()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("Ledge: couldn't save notes: \(error)")
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }
}

struct NotesView: View {
    @Bindable var notes: Notes

    var body: some View {
        TextEditor(text: $notes.text)
            .font(.system(size: 13))
            .foregroundStyle(Palette.paper)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .frame(height: 112)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Radius.well, style: .continuous).fill(Palette.well))
            .overlay(alignment: .topLeading) {
                if notes.text.isEmpty {
                    Text("Jot something down")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ash)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
    }
}
