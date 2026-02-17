import Testing
import Foundation

/// Scans all `.swift` view files in Screenboom/ for raw font, color, and shadow usage
/// that should go through the SB design system tokens instead.
struct DesignSystemComplianceTests {

    // Files exempt from scanning (token definitions, data models, rendering engines, core model)
    private static let exemptFiles: Set<String> = [
        "SBTokens.swift",
        "SBModifiers.swift",
        "SBComponents.swift",
        "SBFormatters.swift",
        "DesignSystem.swift",       // legacy, should be deleted — keep exempt just in case
        "BackgroundModels.swift",
        "FrameRenderer.swift",
        "CursorOverlayEngine.swift",  // CIFilter/CGContext drawing uses CIColor/CGColor
        "Project.swift",              // data model persistence, CodableColor constructors
        "EditorSettingsController.swift", // preset data uses Color/CodableColor constructors
    ]

    // Patterns that indicate raw usage bypassing the design system
    private static let forbiddenPatterns: [(regex: String, description: String)] = [
        (#"\.font\(\.system\("#,          "Raw .font(.system(...)) — use SB.Typo.* or SB.Icons.*"),
        (#"\.font\(\.caption"#,           "Raw .font(.caption) — use SB.Typo.caption"),
        (#"\.font\(\.caption2"#,          "Raw .font(.caption2) — use SB.Typo.caption or SB.Typo.mono"),
        (#"\.font\(\.body"#,              "Raw .font(.body) — use SB.Typo.body"),
        (#"\.font\(\.title"#,             "Raw .font(.title) — use SB.Typo.pageTitle or SB.Typo.heroTitle"),
        (#"\.font\(\.headline"#,          "Raw .font(.headline) — use SB.Typo.sectionTitle"),
        (#"[^a-zA-Z]Color\(red:"#,         "Raw Color(red:...) — use SB.Colors.*"),
        (#"[^a-zA-Z]Color\(white:"#,     "Raw Color(white:...) — use SB.Colors.*"),
        (#"\.foregroundStyle\(\.secondary\)"#,  "Raw .foregroundStyle(.secondary) — use SB.Colors.textSecondary"),
        (#"\.foregroundStyle\(\.primary\)"#,    "Raw .foregroundStyle(.primary) — use SB.Colors.textPrimary"),
        (#"\.foregroundStyle\(\.tertiary\)"#,   "Raw .foregroundStyle(.tertiary) — use SB.Colors.textTertiary"),
        (#"Color\.red[^:]"#,              "Raw Color.red — use SB.Colors.accent or SB.Colors.destructive"),
        (#"Color\.gray[^:]"#,             "Raw Color.gray — use SB.Colors.surface or SB.Colors.textTertiary"),
        (#"Color\.accentColor"#,          "Raw Color.accentColor — use SB.Colors.accent"),
        (#"[^a-zA-Z]NSColor\(red:"#,      "Raw NSColor(red:...) — use SB.Colors.accentNS"),
        (#"\.foregroundStyle\(\.white\)"#,  "Raw .foregroundStyle(.white) — use SB.Colors.textPrimary"),
        (#"Color\.white\.opacity"#,         "Raw Color.white.opacity — use SB.Glass.*"),
        (#"Color\.black\.opacity"#,         "Raw Color.black.opacity — use SB.Colors.surfaceOverlay or SB.Shadows"),
        (#"\.black\.opacity"#,              "Raw .black.opacity — use SB.Colors.surfaceOverlay or SB.Shadows"),
    ]

    @Test func featureViewsUseDesignTokens() throws {
        let screenboomDir = findScreenboomSourceDir()
        let swiftFiles = try collectSwiftFiles(in: screenboomDir)

        var violations: [String] = []

        for fileURL in swiftFiles {
            let fileName = fileURL.lastPathComponent
            guard !Self.exemptFiles.contains(fileName) else { continue }

            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)

            for (lineNumber, line) in lines.enumerated() {
                // Skip lines with the escape hatch comment
                if line.contains("// sb-exempt") { continue }

                for pattern in Self.forbiddenPatterns {
                    if let regex = try? Regex(pattern.regex),
                       line.contains(regex) {
                        violations.append("\(fileName):\(lineNumber + 1): \(pattern.description)")
                    }
                }
            }
        }

        #expect(
            violations.isEmpty,
            """
            Design system violations found (\(violations.count)):
            \(violations.joined(separator: "\n"))
            """
        )
    }

    // MARK: - Helpers

    /// Walk up from test bundle to find the Screenboom/ source directory.
    private func findScreenboomSourceDir() -> URL {
        // In Xcode tests, we can use a known path relative to the project
        // The project root is predictable from the test bundle location
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // ScreenboomTests/
            .deletingLastPathComponent()    // project root
        return projectRoot.appendingPathComponent("Screenboom")
    }

    private func collectSwiftFiles(in directory: URL) throws -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return results
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "swift" {
                results.append(fileURL)
            }
        }

        return results
    }
}
