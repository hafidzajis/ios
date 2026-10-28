import Foundation

public enum CSVWriter {
    /// RFC 4180 quoting; rows joined with "\n" and the output ends with a trailing "\n".
    public static func write(_ rows: [[String]]) -> String {
        var output = ""
        for row in rows {
            output += row.map { escape($0) }.joined(separator: ",")
            output += "\n"
        }
        return output
    }

    static func escape(_ field: String) -> String {
        var needsQuotes = false
        for scalar in field.unicodeScalars {
            if scalar == "," || scalar == "\"" || scalar == "\n" || scalar == "\r" {
                needsQuotes = true
                break
            }
        }
        if !needsQuotes { return field }
        let doubled = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"" + doubled + "\""
    }
}

public enum CSVParser {
    /// Parses CSV text. Handles quoted fields, escaped quotes, CRLF/LF/CR line endings,
    /// a trailing newline and a leading UTF-8 BOM.
    public static func parse(_ text: String) -> [[String]] {
        var scalars = Array(text.unicodeScalars)
        if let first = scalars.first, first.value == 0xFEFF {
            scalars.removeFirst()
        }
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var recordHasContent = false
        var i = 0
        let count = scalars.count
        while i < count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < count && scalars[i + 1] == "\"" {
                        field.append(c)
                        i += 2
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
                recordHasContent = true
            } else if c == "," {
                row.append(String(field))
                field = String.UnicodeScalarView()
                recordHasContent = true
            } else if c == "\n" || c == "\r" {
                if c == "\r" && i + 1 < count && scalars[i + 1] == "\n" {
                    i += 1
                }
                row.append(String(field))
                field = String.UnicodeScalarView()
                rows.append(row)
                row = []
                recordHasContent = false
            } else {
                field.append(c)
                recordHasContent = true
            }
            i += 1
        }
        if recordHasContent || !row.isEmpty {
            row.append(String(field))
            rows.append(row)
        }
        return rows
    }
}
