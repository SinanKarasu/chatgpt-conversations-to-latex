//#!/usr/bin/env swift
import Foundation

// MARK: - Models matching ChatGPT export JSON

struct ChatConversation: Decodable {
    let id: String?                      // was non-optional
    let title: String?
    let createTime: Double?
    let updateTime: Double?
    let mapping: [String: ChatNode]?     // make this optional too

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createTime = "create_time"
        case updateTime = "update_time"
        case mapping
    }
}

struct ChatNode: Decodable {
    let id: String?
    let message: ChatMessage?
    // we ignore parent/children/metadata, they’ll just be discarded
}

struct ChatMessage: Decodable {
    let id: String?
    let author: Author
    let content: ChatContent?
    let createTime: Double?
    let updateTime: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case author
        case content
        case createTime = "create_time"
        case updateTime = "update_time"
    }
}


struct Author: Decodable {
    let role: String   // "user", "assistant", "system", ...
}

struct ChatContent: Decodable {
    let contentType: String?
    let parts: [String]?

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case parts
    }
}

// MARK: - Load 1 or many conversations

func loadConversations(from url: URL) throws -> [ChatConversation] {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .useDefaultKeys

    // Try array first (conversations.json)
    do {
        let many = try decoder.decode([ChatConversation].self, from: data)
        return many
    } catch {
        fputs("Array decode failed, trying single conversation. Error was:\n\(error)\n", stderr)
    }

    // Fallback: single conversation file
    let one = try decoder.decode(ChatConversation.self, from: data)
    return [one]
}

// MARK: - LaTeX escaping with math preservation

/// Escape LaTeX specials outside of math regions.
/// Math regions are: $...$, $$...$$, \(...\), \[...\]
func escapeForLaTeXPreservingMath(_ input: String) -> String {
    enum Mode {
        case text
        case inlineDollar
        case displayDollar
        case inlineParen
        case displayBracket
    }

    var result = ""
    let scalars = Array(input.unicodeScalars)
    var i = 0
    var mode: Mode = .text

    func escapeScalar(_ s: UnicodeScalar) -> String {
        switch s {
        case "#": return "\\#"
        case "$": return "\\$"
        case "%": return "\\%"
        case "&": return "\\&"
        case "_": return "\\_"
        case "{": return "\\{"
        case "}": return "\\}"
        case "^": return "\\^{}"
        case "~": return "\\~{}"
        default:  return String(s)
        }
    }

    while i < scalars.count {
        let s = scalars[i]

        switch mode {
        case .text:
            if s == "$" {
                if i + 1 < scalars.count, scalars[i + 1] == "$" {
                    mode = .displayDollar
                    result.append("$$")
                    i += 2
                } else {
                    mode = .inlineDollar
                    result.append("$")
                    i += 1
                }
            } else if s == "\\" && i + 1 < scalars.count {
                let next = scalars[i + 1]
                if next == "(" {
                    mode = .inlineParen
                    result.append("\\(")
                    i += 2
                } else if next == "[" {
                    mode = .displayBracket
                    result.append("\\[")
                    i += 2
                } else {
                    result.append("\\textbackslash{}")
                    i += 1
                }
            } else {
                result.append(escapeScalar(s))
                i += 1
            }

        case .inlineDollar:
            if s == "$" {
                mode = .text
                result.append("$")
                i += 1
            } else {
                result.append(String(s))
                i += 1
            }

        case .displayDollar:
            if s == "$", i + 1 < scalars.count, scalars[i + 1] == "$" {
                mode = .text
                result.append("$$")
                i += 2
            } else {
                result.append(String(s))
                i += 1
            }

        case .inlineParen:
            if s == "\\" && i + 1 < scalars.count, scalars[i + 1] == ")" {
                mode = .text
                result.append("\\)")
                i += 2
            } else {
                result.append(String(s))
                i += 1
            }

        case .displayBracket:
            if s == "\\" && i + 1 < scalars.count, scalars[i + 1] == "]" {
                mode = .text
                result.append("\\]")
                i += 2
            } else {
                result.append(String(s))
                i += 1
            }
        }
    }

    return result
}

// MARK: - Role → header

func headerForRole(_ role: String) -> String {
    switch role {
    case "user":
        return "Dear Sinan"
    case "assistant":
        return "Dear Chat"
    default:
        return "Dear Diary"
    }
}

// MARK: - Conversation → LaTeX

func conversationToLaTeX(_ convo: ChatConversation) -> String {
    var out: [String] = []

    out.append("""
    % Auto-generated from ChatGPT export
    \\documentclass[12pt]{article}
    \\usepackage{fontspec}
    \\usepackage{amsmath,amssymb}
    \\usepackage[margin=1in]{geometry}
    \\setmainfont{Helvetica Neue}
    \\begin{document}
    """)

    if let title = convo.title {
        let safeTitle = escapeForLaTeXPreservingMath(title)
        out.append("\\section*{\(safeTitle)}")
        out.append("")
    }

    var messages: [ChatMessage] = []

    if let mapping = convo.mapping {
        for node in mapping.values {
            if let msg = node.message,
               let parts = msg.content?.parts {

                let text = parts.joined(separator: "\n\n")
                if !text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                    messages.append(msg)
                }
            }
        }
    }

    messages.sort { (a, b) -> Bool in
        (a.createTime ?? 0) < (b.createTime ?? 0)
    }

    for msg in messages {
        let header = headerForRole(msg.author.role)
        let headerLine = "{\\large 🧚‍♀️\\textbf{\(escapeForLaTeXPreservingMath(header))},}"
        out.append(headerLine)
        out.append("")

        if let parts = msg.content?.parts {
            let rawBody = parts.joined(separator: "\n\n")
            let escapedBody = escapeForLaTeXPreservingMath(rawBody)
            out.append(escapedBody)
            out.append("")
        }
    }

    out.append("\\end{document}")
    return out.joined(separator: "\n")
}

// MARK: - Utils

func sanitizeFileName(_ s: String) -> String {
    let badChars = CharacterSet(charactersIn: "/:\\?%*|\"<>")
    let cleaned = s.unicodeScalars.map { badChars.contains($0) ? "_" : Character($0) }
    let asString = String(cleaned)
    if asString.isEmpty { return "conversation" }
    return asString.replacingOccurrences(of: " ", with: "_")
}

func printUsage() {
    let prog = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "ChatExportToLaTeX"
    fputs("Usage: \(prog) <conversations.json> <output-directory>\n", stderr)
}

// MARK: - CLI main

func main() {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        printUsage()
        exit(1)
    }

    let inputURL = URL(fileURLWithPath: args[1])
    let outDirPath = args[2]
    let fm = FileManager.default
    try? fm.createDirectory(atPath: outDirPath, withIntermediateDirectories: true)

    do {
        let convos = try loadConversations(from: inputURL)
        for (index, convo) in convos.enumerated() {
            let titleBase = convo.title ?? "conversation_\(index + 1)"
            let safe = sanitizeFileName(titleBase)
            let fileName = String(format: "%04d_%@.tex", index + 1, safe)
            let outURL = URL(fileURLWithPath: outDirPath).appendingPathComponent(fileName)

            let tex = conversationToLaTeX(convo)
            try tex.write(to: outURL, atomically: true, encoding: .utf8)
            print("Wrote \(outURL.path)")
        }
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
    }
}

//main()
