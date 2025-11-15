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


struct ChatPart: Decodable {
    let text: String

    private struct Obj: Decodable {
        struct TextObj: Decodable {
            let value: String?
        }
        let text: TextObj?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Old format: just a plain string
        if let s = try? container.decode(String.self) {
            self.text = s
            return
        }

        // New format: { "text": { "value": "..." } }
        let obj = try container.decode(Obj.self)
        self.text = obj.text?.value ?? ""
    }
}


struct Author: Decodable {
    let role: String   // "user", "assistant", "system", ...
}

struct ChatContent: Decodable {
    let contentType: String?
    let parts: [ChatPart]?

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
// MARK: - LaTeX escaping (no math detection, escape all $)

/**
 Escapes a string so it is safe to drop into LaTeX text mode.
 
 - All LaTeX special characters are escaped.
 - Every unescaped `$` becomes `\$` (so we don't accidentally enter math mode).
 - Existing `\$` sequences are left as-is to avoid double-escaping.
 
 This means any *real* math written with `$...$` or `$$...$$` will come out
 as `\$...\$` and will need to be hand-fixed later, which is acceptable for
 our usage: there are thousands of dollar signs and very little actual math.
 */
func escapeForLaTeXPreservingMath(_ text: String) -> String {
	var result = String.UnicodeScalarView()
	let scalars = Array(text.unicodeScalars)
	var i = 0
	
	func appendEscaped(_ s: UnicodeScalar) {
		switch s {
		case "$":
			// Generic rule: treat $ as literal currency/character
			result.append("\\")
			result.append("$")
		case "#", "%", "&", "_", "{", "}":
			// Simple one-char escapes like \#, \%, \&, \_, \{, \}
			result.append("\\")
			result.append(s)
		case "^":
			// Use text version to avoid entering math mode
			"\\textasciicircum{}".unicodeScalars.forEach { result.append($0) }
		case "~":
			"\\textasciitilde{}".unicodeScalars.forEach { result.append($0) }
		case "\\":
			"\\textbackslash{}".unicodeScalars.forEach { result.append($0) }
		default:
			result.append(s)
		}
	}
	
	while i < scalars.count {
		let s = scalars[i]
		
		// If we see backslash + dollar, assume it's *already* an escaped literal
		// and copy both characters through unchanged.
		if s == "\\".unicodeScalars.first!,
		   i + 1 < scalars.count,
		   scalars[i + 1] == "$".unicodeScalars.first! {
			result.append(s)
			result.append(scalars[i + 1])
			i += 2
			continue
		}
		
		appendEscaped(s)
		i += 1
	}
	
	return String(result)
}

// MARK: - Role → header

func headerForRole(_ role: String) -> String {
    switch role {
    case "user":
        return "Dear Chat"
    case "assistant":
        return "Dear Sinan"
    default:
        return "Dear Diary"
    }
}

// MARK: - Conversation → LaTeX

func conversationToLaTeX(_ convo: ChatConversation) -> String {
    var out: [String] = []

    out.append("""
    % Auto-generated from ChatGPT export
    \\documentclass{article}
    \\usepackage{fontspec}    
    \\directlua{luaotfload.add_fallback
     ("emojifallback",
      {
      "NotoColorEmoji:mode=harf;"
      }
    )}
    \\setmainfont{texgyretermes-regular}[
    Extension      = .otf ,
    BoldFont       = texgyretermes-bold,
    ItalicFont     = texgyretermes-italic,
    BoldItalicFont = texgyretermes-bolditalic,
    RawFeature={fallback=emojifallback}
    ]
    \\usepackage{amsmath,amssymb}
    \\usepackage[margin=1in]{geometry}
    \\usepackage{darkmode}
    \\enabledarkmode    
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

                let text = parts.map { $0.text }.joined(separator: "\n\n")
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
            let rawBody = parts.map { $0.text }.joined(separator: "\n\n")
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
	var mainFiles: [String] = []
    do {
        let convos = try loadConversations(from: inputURL)
		let mainURL = URL(fileURLWithPath: outDirPath).appendingPathComponent("main.tex")
        for (index, convo) in convos.enumerated() {
            let titleBase = convo.title ?? "conversation_\(index + 1)"
            let safe = sanitizeFileName(titleBase)
            let fileName = String(format: "%04d_%@.tex", index + 1, safe)
            let outURL = URL(fileURLWithPath: outDirPath).appendingPathComponent(fileName)
			//let mainURL = URL(fileURLWithPath: outDirPath).appendingPathComponent(fileName)
            let tex = conversationToLaTeX(convo)
            try tex.write(to: outURL, atomically: true, encoding: String.Encoding.utf8)
			mainFiles.append("\\include{\(fileName)}")
            print("Wrote \(outURL.path)")
        }
		let mainList = mainFiles.joined(separator: "\n")
		try mainList.write(to: mainURL, atomically: true, encoding: String.Encoding.utf8)
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
    }
}

//main()

