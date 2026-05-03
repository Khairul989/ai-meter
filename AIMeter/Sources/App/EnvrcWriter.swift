import Foundation

// MARK: - Errors

enum EnvrcWriterError: Error {
    case folderNotReadable(URL)
    case folderNotWritable(URL)
    /// Slug does not match ^[a-z0-9][a-z0-9-]{0,30}$
    case invalidSlug(String)
    case writeFailed(URL, underlying: Error)
}

// MARK: - WriteAction

enum WriteAction {
    case create        // file does not exist, will be created
    case update        // file exists, will be replaced (atomic rename)
    case deleteFile    // file exists but would become empty; caller removes it
    case noop          // contents identical, nothing to do
}

// MARK: - ProposedWrite

struct ProposedWrite {
    let envrcURL: URL
    let originalContents: String?  // nil if file didn't exist
    let newContents: String?       // nil only when action == .deleteFile
    let action: WriteAction
}

// MARK: - EnvrcDiffLine

struct EnvrcDiffLine {
    enum Kind { case unchanged, added, removed }
    let kind: Kind
    let oldNumber: Int?   // line number in original (nil for added lines)
    let newNumber: Int?   // line number in new (nil for removed lines)
    let text: String
}

// MARK: - EnvrcWriter

struct EnvrcWriter {

    // Block markers — reference these constants everywhere; never inline the strings.
    private static let openMarker  = "# >>> aimeter claude routing >>>"
    private static let closeMarker = "# <<< aimeter claude routing <<<"

    private static let slugRegex: NSRegularExpression = {
        // Force-try is safe: the pattern is a compile-time constant.
        try! NSRegularExpression(pattern: "^[a-z0-9][a-z0-9-]{0,30}$")
    }()

    // MARK: - Public API

    /// Returns the proposed new full contents for `<folderURL>/.envrc` after inserting/replacing
    /// the AIMeter marker block for the given `slug`. Reads the existing file if present.
    static func proposedContents(folderURL: URL, slug: String) throws -> ProposedWrite {
        // Validate slug before any I/O.
        try validateSlug(slug)

        let envrcURL = folderURL.appendingPathComponent(".envrc")
        let original = try readExistingFile(at: envrcURL)

        let block = makeBlock(slug: slug)

        let existing = original.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }

        let newContents: String
        if let contents = existing {
            newContents = try spliceBlock(block, into: contents)
        } else {
            // New file — just the block, no leading blank line.
            newContents = block
        }

        let action: WriteAction
        if let orig = original, !orig.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            action = newContents == orig ? .noop : .update
        } else {
            action = newContents == (original ?? "") ? .noop : .create
        }

        return ProposedWrite(
            envrcURL: envrcURL,
            originalContents: original,
            newContents: newContents,
            action: action
        )
    }

    /// Returns a proposal that removes the marker block from `<folderURL>/.envrc`.
    /// Returns `nil` if the file is missing or has no marker block.
    /// If the file would be empty after removal, action is `.deleteFile`.
    static func proposedRemoval(folderURL: URL) throws -> ProposedWrite? {
        let envrcURL = folderURL.appendingPathComponent(".envrc")

        guard let original = try readExistingFile(at: envrcURL),
              !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard original.contains(openMarker) else {
            return nil
        }

        let stripped = try removeBlock(from: original)

        if stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ProposedWrite(
                envrcURL: envrcURL,
                originalContents: original,
                newContents: nil,
                action: .deleteFile
            )
        }

        return ProposedWrite(
            envrcURL: envrcURL,
            originalContents: original,
            newContents: stripped,
            action: stripped == original ? .noop : .update
        )
    }

    /// Atomically commits a proposed write. Crash-safe: original is intact until rename succeeds.
    static func commit(_ proposal: ProposedWrite) throws {
        switch proposal.action {
        case .noop:
            return

        case .deleteFile:
            do {
                try FileManager.default.removeItem(at: proposal.envrcURL)
            } catch {
                throw EnvrcWriterError.writeFailed(proposal.envrcURL, underlying: error)
            }

        case .create, .update:
            guard let contents = proposal.newContents else {
                return
            }
            let data = Data(contents.utf8)
            let tmpURL = proposal.envrcURL.deletingLastPathComponent()
                .appendingPathComponent(".envrc.aimeter-tmp")

            do {
                // Write to temp file, fsync, then atomically rename.
                try data.write(to: tmpURL, options: [.withoutOverwriting])
            } catch let e as NSError where e.domain == NSCocoaErrorDomain && e.code == NSFileWriteFileExistsError {
                // Temp file already exists (leftover crash) — overwrite it.
                do {
                    try data.write(to: tmpURL, options: [])
                } catch {
                    throw EnvrcWriterError.writeFailed(tmpURL, underlying: error)
                }
            } catch {
                throw EnvrcWriterError.writeFailed(tmpURL, underlying: error)
            }

            // fsync via FileHandle before rename.
            do {
                let fh = try FileHandle(forWritingTo: tmpURL)
                fh.synchronizeFile()
                try fh.close()
            } catch {
                // Non-fatal: we still try the rename.
            }

            // Set permissions on the temp file before rename.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: tmpURL.path
            )

            // Atomic rename: moves temp → destination.
            do {
                if proposal.action == .update {
                    // replaceItemAt requires the destination to exist.
                    _ = try FileManager.default.replaceItemAt(
                        proposal.envrcURL,
                        withItemAt: tmpURL,
                        backupItemName: nil,
                        options: []
                    )
                } else {
                    // .create: destination does not yet exist; use moveItem (also atomic on APFS).
                    try FileManager.default.moveItem(at: tmpURL, to: proposal.envrcURL)
                }
            } catch {
                // Clean up temp on failure.
                try? FileManager.default.removeItem(at: tmpURL)
                throw EnvrcWriterError.writeFailed(proposal.envrcURL, underlying: error)
            }
        }
    }
}

// MARK: - Diff

extension EnvrcWriter {

    /// Produces a line-by-line diff for preview UI consumption.
    /// Uses a 3-region strategy (pre-block / block / post-block) since changes are always
    /// localised to the marker region.
    static func diff(_ proposal: ProposedWrite) -> [EnvrcDiffLine] {
        switch proposal.action {
        case .noop:
            let lines = proposal.originalContents.map { splitLines($0) } ?? []
            return lines.enumerated().map { i, line in
                EnvrcDiffLine(kind: .unchanged, oldNumber: i + 1, newNumber: i + 1, text: line)
            }

        case .create:
            let lines = splitLines(proposal.newContents ?? "")
            return lines.enumerated().map { i, line in
                EnvrcDiffLine(kind: .added, oldNumber: nil, newNumber: i + 1, text: line)
            }

        case .deleteFile:
            let lines = splitLines(proposal.originalContents ?? "")
            return lines.enumerated().map { i, line in
                EnvrcDiffLine(kind: .removed, oldNumber: i + 1, newNumber: nil, text: line)
            }

        case .update:
            return threeRegionDiff(
                old: proposal.originalContents ?? "",
                new: proposal.newContents ?? ""
            )
        }
    }

    // Split into lines preserving content; does not include empty trailing entry for final newline.
    private static func splitLines(_ text: String) -> [String] {
        var lines = text.components(separatedBy: "\n")
        // If text ends with newline, the last component is ""; drop it.
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    /// 3-region diff: pre-block lines are unchanged, block lines are removed/added, post lines unchanged.
    private static func threeRegionDiff(old: String, new: String) -> [EnvrcDiffLine] {
        let oldLines = splitLines(old)
        let newLines = splitLines(new)

        // Locate marker regions in both old and new.
        let oldRegion = markerRegion(in: oldLines)
        let newRegion = markerRegion(in: newLines)

        var result: [EnvrcDiffLine] = []
        var oldLineNum = 1
        var newLineNum = 1

        if let oldR = oldRegion, let newR = newRegion {
            // Pre-block: lines before the opening marker (same in both).
            let preCount = oldR.lowerBound
            for i in 0..<preCount {
                result.append(EnvrcDiffLine(kind: .unchanged, oldNumber: oldLineNum, newNumber: newLineNum, text: oldLines[i]))
                oldLineNum += 1
                newLineNum += 1
            }

            // Removed block lines (old marker block).
            for i in oldR {
                result.append(EnvrcDiffLine(kind: .removed, oldNumber: oldLineNum, newNumber: nil, text: oldLines[i]))
                oldLineNum += 1
            }

            // Added block lines (new marker block).
            for i in newR {
                result.append(EnvrcDiffLine(kind: .added, oldNumber: nil, newNumber: newLineNum, text: newLines[i]))
                newLineNum += 1
            }

            // Post-block: lines after closing marker.
            // Both old and new have identical post-block content (only the block changed),
            // so we can use oldPostLines as the canonical text for unchanged lines.
            let oldPostStart = oldR.upperBound
            let newPostStart = newR.upperBound
            let oldPostLines = Array(oldLines[oldPostStart...])
            let newPostLines = Array(newLines[newPostStart...])
            // Use the longer of the two to avoid dropping any lines in edge cases.
            let postCount = max(oldPostLines.count, newPostLines.count)
            for i in 0..<postCount {
                let text = i < oldPostLines.count ? oldPostLines[i] : newPostLines[i]
                let oldN = i < oldPostLines.count ? oldLineNum : nil
                let newN = i < newPostLines.count ? newLineNum : nil
                let kind: EnvrcDiffLine.Kind = (i < oldPostLines.count && i < newPostLines.count) ? .unchanged : (i < oldPostLines.count ? .removed : .added)
                result.append(EnvrcDiffLine(kind: kind, oldNumber: oldN, newNumber: newN, text: text))
                if i < oldPostLines.count { oldLineNum += 1 }
                if i < newPostLines.count { newLineNum += 1 }
            }
        } else {
            // Fallback: line-by-line LCS for unexpected structure.
            result = lcsLineDiff(oldLines: oldLines, newLines: newLines)
        }

        return result
    }

    /// Returns the closed range of line indices (inclusive) for the marker block in `lines`,
    /// or `nil` if no markers found.
    private static func markerRegion(in lines: [String]) -> ClosedRange<Int>? {
        guard let open = lines.firstIndex(where: { $0 == openMarker }),
              let close = lines[(open + 1)...].firstIndex(where: { $0 == closeMarker }) else {
            return nil
        }
        return open...close
    }

    /// Minimal LCS-based line diff used as fallback for unexpected file structures.
    private static func lcsLineDiff(oldLines: [String], newLines: [String]) -> [EnvrcDiffLine] {
        let m = oldLines.count
        let n = newLines.count

        // Build LCS table.
        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        for i in 1...max(1, m) {
            for j in 1...max(1, n) {
                if i > m || j > n { break }
                dp[i][j] = oldLines[i - 1] == newLines[j - 1]
                    ? dp[i - 1][j - 1] + 1
                    : max(dp[i - 1][j], dp[i][j - 1])
            }
        }

        // Trace back.
        var result: [EnvrcDiffLine] = []
        var i = m, j = n
        var oldNum = m, newNum = n

        var trace: [(EnvrcDiffLine.Kind, Int?, Int?, String)] = []

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1] {
                trace.append((.unchanged, oldNum, newNum, oldLines[i - 1]))
                i -= 1; j -= 1; oldNum -= 1; newNum -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                trace.append((.added, nil, newNum, newLines[j - 1]))
                j -= 1; newNum -= 1
            } else {
                trace.append((.removed, oldNum, nil, oldLines[i - 1]))
                i -= 1; oldNum -= 1
            }
        }

        for (kind, old, new, text) in trace.reversed() {
            result.append(EnvrcDiffLine(kind: kind, oldNumber: old, newNumber: new, text: text))
        }
        return result
    }
}

// MARK: - Private Helpers

private extension EnvrcWriter {

    /// Validates slug against ^[a-z0-9][a-z0-9-]{0,30}$.
    static func validateSlug(_ slug: String) throws {
        let range = NSRange(slug.startIndex..., in: slug)
        guard slugRegex.firstMatch(in: slug, range: range) != nil else {
            throw EnvrcWriterError.invalidSlug(slug)
        }
    }

    /// Reads existing file contents; returns `nil` if file does not exist.
    /// Throws `EnvrcWriterError.folderNotReadable` for genuine permission errors.
    static func readExistingFile(at url: URL) throws -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch let e as CocoaError where e.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw EnvrcWriterError.folderNotReadable(url.deletingLastPathComponent())
        }
    }

    /// Generates the full marker block string (including the markers themselves) ending with `\n`.
    static func makeBlock(slug: String) -> String {
        """
        \(openMarker)
        if token=$(security find-generic-password -s claude-\(slug) -w 2>&1); then
          export CLAUDE_CODE_OAUTH_TOKEN="$token"
        else
          echo "AIMeter: keychain entry 'claude-\(slug)' missing or denied" >&2
        fi
        \(closeMarker)
        """
        + "\n"
    }

    /// Splices the new block into `contents`, replacing any existing marker blocks.
    /// Detects corrupted states (missing close marker, duplicate blocks) and handles per spec.
    static func spliceBlock(_ block: String, into contents: String) throws -> String {
        var lines = contents.components(separatedBy: "\n")
        // Strip trailing empty component from the final newline so line indices are clean.
        if lines.last == "" { lines.removeLast() }

        // Find all open-marker indices.
        let openIndices = lines.indices.filter { lines[$0] == openMarker }

        if openIndices.isEmpty {
            // No existing block — append with one blank line separator.
            var result = lines
            // Ensure exactly one blank line between existing content and the block.
            if let last = result.last, !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append("")  // blank line
            }
            // Append block lines (block already ends with \n, so split and drop trailing empty).
            var blockLines = block.components(separatedBy: "\n")
            if blockLines.last == "" { blockLines.removeLast() }
            result.append(contentsOf: blockLines)
            return result.joined(separator: "\n") + "\n"
        }

        // Check for missing close marker after the first open marker.
        let firstOpen = openIndices[0]
        guard let firstClose = lines[(firstOpen + 1)...].firstIndex(where: { $0 == closeMarker }) else {
            let msg = "EnvrcWriter: opening marker found at line \(firstOpen + 1) but no closing marker — refusing to write to avoid further corruption"
            throw EnvrcWriterError.writeFailed(
                URL(fileURLWithPath: ".envrc"),
                underlying: NSError(domain: "EnvrcWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
            )
        }

        // Warn and strip duplicate marker blocks if more than one exists.
        if openIndices.count > 1 {
            let warning = "EnvrcWriter: \(openIndices.count) AIMeter marker blocks found — keeping first, removing duplicates\n"
            FileHandle.standardError.write(Data(warning.utf8))
        }

        // Build result: pre-block + new block + post-block, stripping duplicates as we go.
        let preLines = Array(lines[..<firstOpen])
        var postLines = Array(lines[(firstClose + 1)...])

        // Remove any additional marker blocks from postLines.
        postLines = stripAllMarkerBlocks(from: postLines)

        // Parse block into lines (drop trailing empty from trailing \n).
        var blockLines = block.components(separatedBy: "\n")
        if blockLines.last == "" { blockLines.removeLast() }

        var result: [String] = []
        result.append(contentsOf: preLines)
        result.append(contentsOf: blockLines)
        result.append(contentsOf: postLines)

        return result.joined(separator: "\n") + "\n"
    }

    /// Removes the marker block from `contents`. Throws if opening marker has no closing pair.
    static func removeBlock(from contents: String) throws -> String {
        var lines = contents.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }

        guard let openIdx = lines.firstIndex(where: { $0 == openMarker }) else {
            return contents  // No block present.
        }

        guard let closeIdx = lines[(openIdx + 1)...].firstIndex(where: { $0 == closeMarker }) else {
            let msg = "EnvrcWriter: opening marker found but no closing marker — refusing to modify"
            throw EnvrcWriterError.writeFailed(
                URL(fileURLWithPath: ".envrc"),
                underlying: NSError(domain: "EnvrcWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
            )
        }

        var result = lines
        result.removeSubrange(openIdx...closeIdx)

        // Remove the blank separator line immediately before the block if present.
        if openIdx > 0 && result.indices.contains(openIdx - 1) && result[openIdx - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.remove(at: openIdx - 1)
        }

        return result.joined(separator: "\n") + "\n"
    }

    /// Strips all AIMeter marker blocks from a line array (used when de-duplicating).
    private static func stripAllMarkerBlocks(from lines: [String]) -> [String] {
        var result: [String] = []
        var i = 0
        while i < lines.count {
            if lines[i] == openMarker {
                // Find and skip to close marker.
                if let closeOffset = lines[(i + 1)...].firstIndex(where: { $0 == closeMarker }) {
                    i = closeOffset + 1
                } else {
                    // No close marker — keep the line to avoid silent data loss.
                    result.append(lines[i])
                    i += 1
                }
            } else {
                result.append(lines[i])
                i += 1
            }
        }
        return result
    }
}
