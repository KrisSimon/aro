// FileFormat.swift - ARO-0040: Format-Aware File I/O
// Automatic format detection based on file extensions

import Foundation

/// Supported file formats for automatic serialization/deserialization
public enum FileFormat: String, Sendable, CaseIterable {
    case json
    case yaml
    case xml
    case toml
    case csv
    case tsv
    case markdown
    case html
    case text
    case sql
    case binary

    /// Detect file format from path extension
    /// - Parameter path: File path to analyze
    /// - Returns: Detected format (defaults to .binary for unknown extensions)
    public static func detect(from path: String) -> FileFormat {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "json":
            return .json
        case "yaml", "yml":
            return .yaml
        case "xml":
            return .xml
        case "toml":
            return .toml
        case "csv":
            return .csv
        case "tsv":
            return .tsv
        case "md", "markdown":
            return .markdown
        case "html", "htm":
            return .html
        case "txt":
            return .text
        case "sql":
            return .sql
        case "obj", "bin", "dat":
            return .binary
        default:
            return .binary  // Unknown extensions default to binary
        }
    }

    /// Whether this format supports deserialization (parsing back to structured data)
    public var supportsDeserialization: Bool {
        switch self {
        case .json, .yaml, .xml, .toml, .csv, .tsv, .text:
            return true
        case .markdown, .html, .sql, .binary:
            return false  // These are write-only formats or pass-through
        }
    }

    /// Human-readable format name
    public var displayName: String {
        switch self {
        case .json: return "JSON"
        case .yaml: return "YAML"
        case .xml: return "XML"
        case .toml: return "TOML"
        case .csv: return "CSV"
        case .tsv: return "TSV"
        case .markdown: return "Markdown"
        case .html: return "HTML"
        case .text: return "Plain Text"
        case .sql: return "SQL"
        case .binary: return "Binary"
        }
    }
}
