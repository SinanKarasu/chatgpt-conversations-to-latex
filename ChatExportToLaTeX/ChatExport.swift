//
//  ChatExport.swift
//  ChatExportToLaTeX
//
//  Created by Sinan Karasu on 11/12/25.
//

//#!/usr/bin/env swift
import Foundation

// MARK: - Models matching ChatGPT export JSON

struct ChatConversation: Decodable {
    let id: String
    let title: String?
    let createTime: Double?
    let mapping: [String: ChatNode]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createTime = "create_time"
        case mapping
    }
}

struct ChatNode: Decodable {
    let id: String
    let message: ChatMessage?
}

struct ChatMessage: Decodable {
    let id: String?
    let author: Author
    let content: ChatContent?
    let createTime: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case author
        case content
        case createTime = "create_time"
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

// MARK: - JSON loading

func loadConversation(from url: URL) throws -> ChatConversation {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .useDefaultKeys
    return try decoder.decode(ChatConversation.self, from: data)
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
            // Check for start of math
            if s == "$" {
                // $$...$$ ?
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
                    // normal backslash in text: escape it
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

// MARK: - Conversation → LaTeX

/// Map roles to "Dear X" headers
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

func conversationToLaTeX(_ convo: ChatConversation) -> String {
    var out: [String] = []

    // Preamble
    out.append("""
    % Auto-generated from ChatGPT export
    \\documentclass[12pt]{article}
    \\usepackage{fontspec}
    \\usepackage{amsmath,amssymb}
    \\usepackage[margin=1in]{geometry}

    % Use any font you like here
    \\setmainfont{Helvetica Neue}

    \\begin{document}
    """)

    if let title = convo.title {
        let safeTitle = escapeForLaTeXPreservingMath(title)
        out.append("\\section*{\(safeTitle)}")
        out.append("")
    }

    // Collect and sort messages by time
    var messages: [ChatMessage] = []
    for node in convo.mapping.values {
        if let msg = node.message,
           let parts = msg.content?.parts,
           !parts.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(msg)
        }
    }

    messages.sort { (a, b) -> Bool in
        (a.createTime ?? 0) < (b.createTime ?? 0)
    }

    for msg in messages {
        let role = msg.author.role
        let header = headerForRole(role)
        let headerLine = "{\\large 🧚‍♀️\\textbf{\(escapeForLaTeXPreservingMath(header))},}"

        out.append(headerLine)
        out.append("")

        if let parts = msg.content?.parts {
            let rawBody = parts.joined(separator: "\n\n")
            let escapedBody = escapeForLaTeXPreservingMath(rawBody)
            out.append(escapedBody)
            out.append("") // blank line between messages
        }
    }

    // Postamble
    out.append("\\end{document}")

    return out.joined(separator: "\n")
}

// MARK: - CLI

func printUsage() {
    let prog = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "ChatExportToLaTeX"
    fputs("Usage: \(prog) <conversation.json> [output.tex]\n", stderr)
}

func main() {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        printUsage()
        exit(1)
    }

    let inputPath = args[1]
    let inputURL = URL(fileURLWithPath: inputPath)

    let outputPath: String? = (args.count >= 3) ? args[2] : nil

    do {
        let convo = try loadConversation(from: inputURL)
        let tex = conversationToLaTeX(convo)

        if let outPath = outputPath {
            try tex.write(to: URL(fileURLWithPath: outPath),
                          atomically: true,
                          encoding: .utf8)
        } else {
            // stdout
            print(tex)
        }
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
    }
}

//main()
