import SwiftUI
import AppKit

// MARK: - EnvrcDiffPreviewSheet

struct EnvrcDiffPreviewSheet: View {
    let proposal: ProposedWrite
    let slug: String
    /// Persist the route (or any other side-effect) only after `.envrc` is written successfully.
    /// Cancelling the sheet must NOT trigger this.
    var onWriteCommitted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var writeError: String?
    @State private var didWrite = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                actionBanner
                if proposal.action == .create || proposal.action == .update {
                    keychainWarning
                    nextStepHint
                }
                if proposal.action == .noop {
                    noopLabel
                } else {
                    diffViewer
                }
                if let error = writeError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .padding(16)
            Divider()
            if didWrite {
                postWriteHint
            } else {
                actionRow
            }
        }
        .frame(minWidth: 640)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Preview `.envrc` change")
                .font(.system(size: 15, weight: .semibold))
            // Truncate the path from the middle so folder names at each end remain visible.
            Text(proposal.envrcURL.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action Banner

    private var actionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: bannerIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(bannerColor)
            Text(bannerMessage)
                .font(.system(size: 12))
                .foregroundColor(bannerColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bannerColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var bannerColor: Color {
        switch proposal.action {
        case .create:     return .green
        case .update:     return .blue
        case .deleteFile: return .orange
        case .noop:       return .secondary
        }
    }

    private var bannerIcon: String {
        switch proposal.action {
        case .create:     return "plus.circle.fill"
        case .update:     return "arrow.triangle.2.circlepath.circle.fill"
        case .deleteFile: return "trash.circle.fill"
        case .noop:       return "checkmark.circle.fill"
        }
    }

    private var bannerMessage: LocalizedStringKey {
        switch proposal.action {
        case .create:
            return "AIMeter will **create** a new `.envrc` file in this folder."
        case .update:
            return "AIMeter will **update** the existing `.envrc` file. Your other lines are preserved."
        case .deleteFile:
            return "AIMeter will **remove** this `.envrc` file (it would otherwise be empty)."
        case .noop:
            return "No change needed — the file already matches."
        }
    }

    // MARK: - Keychain Warning

    private var keychainWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.yellow)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("**Heads up:** the first time `direnv` evaluates this `.envrc`, macOS will ask \"direnv wants to access your keychain.\" Click **Always Allow**. This happens once per binary.")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.yellow.opacity(0.30), lineWidth: 1)
        )
    }

    // MARK: - Next Step Hint

    private var nextStepHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .padding(.top, 1)
            Text("**Next step after writing:** run `direnv allow` once in this folder to activate the change. AIMeter will show the exact command — just copy and paste it into your terminal.")
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Noop Label

    private var noopLabel: some View {
        Text("Nothing to write.")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    // MARK: - Diff Viewer

    private var diffLines: [EnvrcDiffLine] {
        EnvrcWriter.diff(proposal)
    }

    private var hasAnyOldNumber: Bool { diffLines.contains { $0.oldNumber != nil } }
    private var hasAnyNewNumber: Bool { diffLines.contains { $0.newNumber != nil } }

    // Hug the content vertically (up to 320pt) so short diffs don't leave huge top/bottom gaps.
    // Row = 12pt monospaced text + 2pt vertical padding ≈ 16pt.
    private var estimatedDiffHeight: CGFloat {
        let perLine: CGFloat = 16
        let chrome: CGFloat = 8 + 16 // vertical padding + horizontal scrollbar gutter
        let estimated = CGFloat(max(diffLines.count, 1)) * perLine + chrome
        return min(estimated, 320)
    }

    private var diffViewer: some View {
        // Horizontal scroll inside a bounded vertical frame — long shell lines stay intact.
        // "Wrap lines to fit width" from spec is overridden: horizontal scroll preserves
        // diff line integrity (same choice as every terminal diff viewer).
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                    DiffLineRow(line: line, showOldGutter: hasAnyOldNumber, showNewGutter: hasAnyNewNumber)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.visible)
        .frame(maxWidth: .infinity)
        .frame(height: estimatedDiffHeight, alignment: .topLeading)
        .background(Color(NSColor.textBackgroundColor).opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Post-Write Hint

    private var postWriteHint: some View {
        let cmd = "direnv allow \(proposal.envrcURL.deletingLastPathComponent().path)"
        return VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.bottom, 4)
            Text("Run this in the folder for direnv to pick up the change:")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(cmd)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            HStack(spacing: 10) {
                Spacer()
                Button("Copy command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                }
                .font(.system(size: 12))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            Button("Write `.envrc`") {
                do {
                    try EnvrcWriter.commit(proposal)
                    writeError = nil
                    didWrite = true
                    onWriteCommitted()
                } catch {
                    writeError = "Couldn't write .envrc: \(error.localizedDescription). Check folder permissions and try again."
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundColor(proposal.action == .noop ? .secondary : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(proposal.action == .noop ? Color.secondary.opacity(0.15) : Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .disabled(proposal.action == .noop)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - DiffLineRow

private struct DiffLineRow: View {
    let line: EnvrcDiffLine
    let showOldGutter: Bool
    let showNewGutter: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Old line number gutter
            if showOldGutter { gutterNumber(line.oldNumber) }
            // New line number gutter
            if showNewGutter { gutterNumber(line.newNumber) }
            // Prefix character: +, -, or space
            Text(prefixChar)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(lineColor)
                .frame(width: 16, alignment: .leading)
                .padding(.leading, 4)
            // Line content — no wrap so horizontal scroll carries long lines
            Text(line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(lineColor)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 8)
        }
        .padding(.vertical, 1)
        .background(lineBackground)
    }

    private var prefixChar: String {
        switch line.kind {
        case .added:     return "+"
        case .removed:   return "-"
        case .unchanged: return " "
        }
    }

    private var lineColor: Color {
        switch line.kind {
        case .added:     return .green
        case .removed:   return .red
        case .unchanged: return .primary
        }
    }

    private var lineBackground: Color {
        switch line.kind {
        case .added:     return Color.green.opacity(0.12)
        case .removed:   return Color.red.opacity(0.12)
        case .unchanged: return Color.clear
        }
    }

    private func gutterNumber(_ n: Int?) -> some View {
        Group {
            if let n {
                Text("\(n)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
            } else {
                Color.clear
                    .frame(width: 36)
            }
        }
    }
}
