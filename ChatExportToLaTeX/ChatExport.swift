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

//struct ChatMessage: Decodable {
//    let id: String?
//    let author: Author
//    let content: ChatContent?
//    let createTime: Double?
//    let updateTime: Double?
//
//    enum CodingKeys: String, CodingKey {
//        case id
//        case author
//        case content
//        case createTime = "create_time"
//        case updateTime = "update_time"
//    }
//}


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

struct Attachment: Decodable {
	let id: String?
	let size: Int?
	let name: String?
	let mimeType: String?
	let width: Int?
	let height: Int?
	let source: String?
	
	enum CodingKeys: String, CodingKey {
		case id
		case size
		case name
		case mimeType = "mime_type"
		case width
		case height
		case source
	}
}

struct MessageMetadata: Decodable {
	let attachments: [Attachment]?
}




struct ChatMessage: Decodable {
	let id: String?
	let author: Author
	let content: ChatContent?
	let createTime: Double?
	let updateTime: Double?
	let metadata: MessageMetadata?      // <-- NEW
	
	enum CodingKeys: String, CodingKey {
		case id
		case author
		case content
		case createTime = "create_time"
		case updateTime = "update_time"
		case metadata                   // <-- NEW
	}
}


// MARK: - Load an export or 1 conversation file

struct ChatExport {
	let conversations: [ChatConversation]
	let sourceDirectory: URL
	let assetFileNames: [String: String]
}

private struct ExportManifest: Decodable {
	struct LogicalFile: Decodable {
		let files: [String]
	}

	let logicalFiles: [String: LogicalFile]

	enum CodingKeys: String, CodingKey {
		case logicalFiles = "logical_files"
	}
}

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

func conversationFiles(in exportDirectory: URL) throws -> [URL] {
	let fileManager = FileManager.default
	let manifestURL = exportDirectory.appendingPathComponent("export_manifest.json")

	if fileManager.fileExists(atPath: manifestURL.path) {
		let data = try Data(contentsOf: manifestURL)
		let manifest = try JSONDecoder().decode(ExportManifest.self, from: data)
		if let logicalFile = manifest.logicalFiles["conversations.json"] {
			return logicalFile.files.map { exportDirectory.appendingPathComponent($0) }
		}
	}

	let legacyURL = exportDirectory.appendingPathComponent("conversations.json")
	if fileManager.fileExists(atPath: legacyURL.path) {
		return [legacyURL]
	}

	let shardURLs = try fileManager.contentsOfDirectory(
		at: exportDirectory,
		includingPropertiesForKeys: nil,
		options: [.skipsHiddenFiles]
	).filter {
		$0.lastPathComponent.hasPrefix("conversations-") && $0.pathExtension == "json"
	}.sorted {
		$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
	}

	guard !shardURLs.isEmpty else {
		throw CocoaError(.fileNoSuchFile, userInfo: [
			NSFilePathErrorKey: exportDirectory.path,
			NSLocalizedDescriptionKey: "No conversations.json or conversations-###.json files were found."
		])
	}
	return shardURLs
}

func loadChatExport(from inputURL: URL) throws -> ChatExport {
	var isDirectory: ObjCBool = false
	guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
		throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: inputURL.path])
	}

	let sourceDirectory = isDirectory.boolValue
		? inputURL
		: inputURL.deletingLastPathComponent()
	let files = isDirectory.boolValue
		? try conversationFiles(in: inputURL)
		: [inputURL]

	var conversations: [ChatConversation] = []
	for file in files {
		conversations.append(contentsOf: try loadConversations(from: file))
	}

	let namesURL = sourceDirectory.appendingPathComponent("conversation_asset_file_names.json")
	let assetFileNames: [String: String]
	if FileManager.default.fileExists(atPath: namesURL.path) {
		let data = try Data(contentsOf: namesURL)
		assetFileNames = try JSONDecoder().decode([String: String].self, from: data)
	} else {
		assetFileNames = [:]
	}

	return ChatExport(
		conversations: conversations,
		sourceDirectory: sourceDirectory,
		assetFileNames: assetFileNames
	)
}

// MARK: - LaTeX rendering

/// Escape content that must remain in LaTeX text mode.
private func escapePlainTextForLaTeX(_ text: String) -> String {
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
		
		// Preserve an explicitly escaped literal dollar without double-escaping it.
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

/// Escape prose while leaving complete LaTeX math spans intact.
///
/// Supported delimiters are `\(...\)`, `\[...\]`, `$...$`, and `$$...$$`.
/// An incomplete delimiter is escaped as ordinary prose instead of leaking an
/// unterminated math mode into the rest of the generated document.
func escapeForLaTeXPreservingMath(_ text: String) -> String {
	let characters = Array(text)
	var output = ""
	var textStart = 0
	var index = 0

	func matches(_ delimiter: [Character], at position: Int) -> Bool {
		guard position >= 0, position + delimiter.count <= characters.count else {
			return false
		}
		return Array(characters[position ..< position + delimiter.count]) == delimiter
	}

	func isEscaped(at position: Int) -> Bool {
		guard position > 0 else { return false }
		var backslashCount = 0
		var cursor = position - 1
		while cursor >= 0, characters[cursor] == "\\" {
			backslashCount += 1
			if cursor == 0 { break }
			cursor -= 1
		}
		return backslashCount.isMultiple(of: 2) == false
	}

	func closingDelimiter(
		_ delimiter: [Character],
		startingAt start: Int,
		allowNewlines: Bool
	) -> Int? {
		var cursor = start
		while cursor < characters.count {
			if !allowNewlines, characters[cursor].isNewline {
				return nil
			}
			if matches(delimiter, at: cursor), !isEscaped(at: cursor) {
				return cursor
			}
			cursor += 1
		}
		return nil
	}

	func dollarRunLength(at position: Int) -> Int {
		var cursor = position
		while cursor < characters.count, characters[cursor] == "$" {
			cursor += 1
		}
		return cursor - position
	}

	func canOpenDoubleDollar(at position: Int) -> Bool {
		let previous = position > 0 ? characters[position - 1] : nil
		let contentStart = position + 2
		guard contentStart < characters.count else { return false }

		// In shells, `$$` is the current process ID. In particular, never
		// interpret assignments such as `pid=$$` as display mathematics.
		if previous == "=" || previous?.isLetter == true || previous?.isNumber == true
			|| previous == "_" || previous == "$" {
			return false
		}

		let next = characters[contentStart]
		if !next.isWhitespace {
			return true
		}

		// Also support the common Markdown form with `$$` alone on a line.
		guard next.isNewline else { return false }
		var cursor = position - 1
		while cursor >= 0, !characters[cursor].isNewline {
			guard characters[cursor].isWhitespace else { return false }
			if cursor == 0 { break }
			cursor -= 1
		}
		return true
	}

	func dollarAppearsInCodeLikeLine(at position: Int) -> Bool {
		var lineStart = position
		while lineStart > 0, !characters[lineStart - 1].isNewline {
			lineStart -= 1
		}
		var lineEnd = position
		while lineEnd < characters.count, !characters[lineEnd].isNewline {
			lineEnd += 1
		}

		let line = String(characters[lineStart ..< lineEnd])
		return line.contains("$(")
			|| line.contains("${")
			|| line.contains("[$]")
			|| line.contains("[^$]")
	}

	func closingDoubleDollar(startingAt start: Int) -> Int? {
		var cursor = start
		while cursor < characters.count {
			if characters[cursor] == "$" {
				let runLength = dollarRunLength(at: cursor)
				if runLength == 2, !isEscaped(at: cursor) {
					return cursor
				}
				cursor += runLength
				continue
			}
			cursor += 1
		}
		return nil
	}

	func closingSingleDollar(startingAt start: Int) -> Int? {
		guard start < characters.count,
			  !characters[start].isWhitespace,
			  characters[start] != "$" else {
			return nil
		}

		var cursor = start
		while cursor < characters.count {
			if characters[cursor].isNewline {
				return nil
			}

			if characters[cursor] == "$", !isEscaped(at: cursor) {
				let previous = characters[cursor - 1]
				let next = cursor + 1 < characters.count ? characters[cursor + 1] : nil
				let followedByWord = next?.isLetter == true || next?.isNumber == true
				if !previous.isWhitespace, previous != "$", next != "$", !followedByWord {
					let content = String(characters[start ..< cursor])
					let containsUnsafeControl = (start ..< cursor).contains { position in
						let character = characters[position]
						return (character == "%" || character == "#" || character == "&")
							&& !isEscaped(at: position)
					}
					let resemblesShell = content.contains(" | ")
						|| content.contains(" > ")
						|| content.contains(";")
						|| content.contains("\\n")
					guard !containsUnsafeControl, !resemblesShell else {
						return nil
					}
					return cursor
				}
				// TeX would close at this dollar even when our prose/math
				// heuristics reject it. Never search past it for a later close.
				return nil
			}

			cursor += 1
		}
		return nil
	}

	func appendText(through end: Int) {
		guard textStart < end else { return }
		output += escapePlainTextForLaTeX(String(characters[textStart ..< end]))
	}

	func appendMath(from start: Int, through end: Int) {
		appendText(through: start)
		output += String(characters[start ..< end])
		index = end
		textStart = end
	}

	func resemblesRegularExpression(from start: Int, to end: Int) -> Bool {
		let content = String(characters[start ..< end])
		return content.contains("[[:")
			|| content.contains(":]]")
			|| content.contains("[^")
			|| content.contains(".*")
			|| content.contains("\\+")
			|| content.contains("\\*")
	}

	func containsNestedMathOpening(from start: Int, to end: Int) -> Bool {
		let content = String(characters[start ..< end])
		return content.contains("\\(") || content.contains("\\[")
	}

	while index < characters.count {
		if characters[index] == "$" {
			let runLength = dollarRunLength(at: index)
			if runLength > 2 {
				index += runLength
				continue
			}
			if dollarAppearsInCodeLikeLine(at: index) {
				index += runLength
				continue
			}
		}

		if matches(["\\", "("], at: index), !isEscaped(at: index),
		   let close = closingDelimiter(["\\", ")"], startingAt: index + 2, allowNewlines: false),
		   !resemblesRegularExpression(from: index + 2, to: close),
		   !containsNestedMathOpening(from: index + 2, to: close) {
			appendMath(from: index, through: close + 2)
			continue
		}

		if matches(["\\", "["], at: index), !isEscaped(at: index),
		   let close = closingDelimiter(["\\", "]"], startingAt: index + 2, allowNewlines: true),
		   !resemblesRegularExpression(from: index + 2, to: close),
		   !containsNestedMathOpening(from: index + 2, to: close) {
			appendMath(from: index, through: close + 2)
			continue
		}

		if matches(["$", "$"], at: index), !isEscaped(at: index),
		   canOpenDoubleDollar(at: index),
		   let close = closingDoubleDollar(startingAt: index + 2) {
			appendMath(from: index, through: close + 2)
			continue
		}

		if characters[index] == "$", !isEscaped(at: index),
		   (index == 0 || characters[index - 1] != "$"),
		   let close = closingSingleDollar(startingAt: index + 1) {
			appendMath(from: index, through: close + 1)
			continue
		}

		index += 1
	}

	appendText(through: characters.count)
	return output
}

/// Render inline Markdown code separately so code containing `$`, `\(`, or
/// Swift interpolation is never mistaken for mathematics.
private func renderInlineCodeAndMath(_ text: String) -> String {
	let characters = Array(text)
	var output = ""
	var textStart = 0
	var index = 0

	func backtickRunLength(at position: Int) -> Int {
		var cursor = position
		while cursor < characters.count, characters[cursor] == "`" {
			cursor += 1
		}
		return cursor - position
	}

	while index < characters.count {
		guard characters[index] == "`" else {
			index += 1
			continue
		}

		let delimiterLength = backtickRunLength(at: index)
		var close = index + delimiterLength
		while close < characters.count {
			if characters[close].isNewline {
				break
			}
			if characters[close] == "`",
			   backtickRunLength(at: close) == delimiterLength {
				break
			}
			close += 1
		}

		guard close < characters.count,
			  characters[close] == "`",
			  backtickRunLength(at: close) == delimiterLength else {
			index += delimiterLength
			continue
		}

		output += escapeForLaTeXPreservingMath(String(characters[textStart ..< index]))
		let codeStart = index + delimiterLength
		let code = String(characters[codeStart ..< close])
		output += "\\texttt{\(escapePlainTextForLaTeX(code))}"

		index = close + delimiterLength
		textStart = index
	}

	output += escapeForLaTeXPreservingMath(String(characters[textStart...]))
	return output
}

/// Render a ChatGPT message body, protecting fenced code before recognizing
/// inline code and math. Markdown styling is intentionally otherwise left as
/// plain text, matching the converter's existing behavior.
func renderChatBodyToLaTeX(_ text: String) -> String {
	let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
	var renderedSections: [String] = []
	var proseLines: [String] = []
	var codeLines: [String] = []
	var activeFence: String?

	func fenceMarker(in line: String) -> String? {
		let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
		if trimmed.hasPrefix("```") { return "```" }
		if trimmed.hasPrefix("~~~") { return "~~~" }
		return nil
	}

	func flushProse() {
		guard !proseLines.isEmpty else { return }
		renderedSections.append(renderInlineCodeAndMath(proseLines.joined(separator: "\n")))
		proseLines.removeAll(keepingCapacity: true)
	}

	func flushCode() {
		let code = codeLines.joined(separator: "\n")
		renderedSections.append("\\begin{Verbatim}\n\(code)\n\\end{Verbatim}")
		codeLines.removeAll(keepingCapacity: true)
	}

	for line in lines {
		if let fence = activeFence {
			if fenceMarker(in: line) == fence {
				flushCode()
				activeFence = nil
			} else {
				codeLines.append(line)
			}
		} else if let fence = fenceMarker(in: line) {
			flushProse()
			activeFence = fence
		} else {
			proseLines.append(line)
		}
	}

	if activeFence != nil {
		flushCode()
	}
	flushProse()

	return renderedSections.joined(separator: "\n")
}

//func figureForAttachment(_ attachment: Attachment) -> String? {
//	guard
//		let name = attachment.name,
//		let mime = attachment.mimeType,
//		mime.hasPrefix("image/")
//	else {
//		return nil
//	}
//	
//	let safeFile = latexSafePath(name)
//	let labelSlug = safeSlug(baseName(name))
//	
//	// You can tweak caption/width here once you see it on paper.
//	return """
//	\\begin{figure}[h!] % Optional: creates a floating figure environment
//		\\centering % Centers the image
//		\\includegraphics[width=0.9\\textwidth]{\(safeFile)} % Include the image
//		\\caption{\(escapeForLaTeXPreservingMath(baseName(name)))} % Add a caption
//		\\label{fig:\(labelSlug)} % Add a label for cross–referencing
//	\\end{figure}
//	"""
//}


let supportedMimes: Set<String> = ["image/png", "image/jpeg", "image/jpg"]

func figureForAttachment(
	_ attachment: Attachment,
	resolvedImagePaths: [String: String] = [:]
) -> String? {
	guard
		let mime = attachment.mimeType,
		supportedMimes.contains(mime),
		let pathString = attachment.id.flatMap({ resolvedImagePaths[$0] })
			?? exportedImageFilename(attachment)
	else {
		// Skip svg/webp/pbm/missing mime types
		return nil
	}
	// TODO:
//	let path = imageRoot.appendingPathComponent(pathString).path
//	guard FileManager.default.fileExists(atPath: path) else {
//		// Skip if the file isn't actually in images/
//		return nil
//	}
	
	let relPathForLaTeX = pathString        // e.g. "images/file-...png"
	let caption = attachment.name.map { escapeForLaTeXPreservingMath($0) } ?? "Image"
	let labelSlug = safeSlug(caption)
	
	return """
	\\begin{figure}[h!]
		\\centering
		\\includegraphics[width=0.9\\textwidth]{\(relPathForLaTeX)}
		\\caption{\(caption)}
		\\label{fig:\(labelSlug)}
	\\end{figure}
	"""
}

//func figureForAttachment(_ attachment: Attachment) -> String? {
//	guard attachment.mimeType?.hasPrefix("image/") == true else { return nil }
//	
//	guard let filePath = exportedImageFilename(attachment) else { return nil }
//	
//	let caption = attachment.name.map { escapeForLaTeXPreservingMath($0) } ?? "Image"
//	let labelSlug = safeSlug(caption)
//	
//	return """
//	\\begin{figure}[h!]
//		\\centering
//		\\includegraphics[width=0.9\\textwidth]{\(filePath)}
//		\\caption{\(caption)}
//		\\label{fig:\(labelSlug)}
//	\\end{figure}
//	"""
//}
//



// MARK: - Role → header

func headerForRole(_ role: String, userName: String) -> String {
    switch role {
    case "user":
        return "Dear Chat"
    case "assistant":
        return "Dear \(userName)"
    default:
        return "Dear Diary"
    }
}

// MARK: - Conversation → LaTeX


func generateMainPreamble() -> String {
		return "% !TEX program = lualatex\n" + """
		% Auto-generated from ChatGPT export
	\\documentclass{article}
	\\usepackage{graphicx} % Load the graphicx package

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
	\\usepackage{cancel}
	\\usepackage{fancyvrb}
	\\usepackage[margin=1in]{geometry}
	\\usepackage{darkmode}
	\\enabledarkmode    
	\\begin{document}
	\\graphicspath{{images/}}
	"""
}

func generateSectionPreamble() -> String {
	return """
	%!TEX root =../Main.tex
	"""
}


func conversationToLaTeX(
	_ convo: ChatConversation,
	userName: String,
	resolvedImagePaths: [String: String] = [:]
) -> String {
    var out: [String] = []

    out.append(generateSectionPreamble())

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
        let header = headerForRole(msg.author.role, userName: userName)
        let headerLine = "{\\large 🧚‍♀️\\textbf{\(escapeForLaTeXPreservingMath(header))},}"
        out.append(headerLine)
        out.append("")

        if let parts = msg.content?.parts {
            let rawBody = parts.map { $0.text }.joined(separator: "\n\n")
            out.append(renderChatBodyToLaTeX(rawBody))
            out.append("")
        }
		// After the body, inject any image attachments as LaTeX figures.
		if let attachments = msg.metadata?.attachments {
			for att in attachments {
				if let fig = figureForAttachment(
					att,
					resolvedImagePaths: resolvedImagePaths
				) {
					out.append(fig)
					out.append("")
				}
			}
		}
    }

    //out.append("\\end{document}")
    return out.joined(separator: "\n")
}

// MARK: - Utils


func extForMime(_ mime: String?) -> String {
	guard let mime = mime else { return "png" }
	if mime == "image/jpeg" { return "jpg" }
	if mime == "image/jpg"  { return "jpg" }
	if mime == "image/png"  { return "png" }
	if mime == "image/gif"  { return "gif" }
	// default:
	return "png"
}


//func exportedImageFilename(_ attachment: Attachment) -> String? {
//	guard let id = attachment.id else { return nil }
//	let ext = extForMime(attachment.mimeType)
//	return "images/\(id)-sanitized.\(ext)"
//}

func exportedImageFilename(_ attachment: Attachment) -> String? {
	guard let id = attachment.id else { return nil }
	
	// file_0000... -> sanitized naming
	if id.hasPrefix("file_") {
		let ext = extForMime(attachment.mimeType)
		return "images/\(id)-sanitized.\(ext)"
	}
	
	// file-XYZ... -> unsanitized, original name appended
	if id.hasPrefix("file-") {
		if let name = attachment.name {
			// name already includes the extension, e.g. "Screenshot ....png"
			return "images/\(id)-\(name)"
		} else {
			let ext = extForMime(attachment.mimeType)
			return "images/\(id).\(ext)" // fallback
		}
	}
	
	// Unknown pattern
	return nil
}

struct PreparedImages {
	let relativePathsByAttachmentID: [String: String]
	let copiedCount: Int
	let missingCount: Int
}

/// Materialize the opaque `.dat` assets used by current ChatGPT exports as
/// ordinary PNG/JPEG files that `graphicx` can load.
func prepareImages(
	for export: ChatExport,
	in outputDirectory: URL
) throws -> PreparedImages {
	let fileManager = FileManager.default
	var imageAttachmentsByID: [String: Attachment] = [:]

	for conversation in export.conversations {
		guard let mapping = conversation.mapping else { continue }
		for node in mapping.values {
			for attachment in node.message?.metadata?.attachments ?? [] {
				guard let id = attachment.id,
					  let mime = attachment.mimeType,
					  supportedMimes.contains(mime) else {
					continue
				}
				imageAttachmentsByID[id] = attachment
			}
		}
	}

	guard !export.assetFileNames.isEmpty, !imageAttachmentsByID.isEmpty else {
		return PreparedImages(
			relativePathsByAttachmentID: [:],
			copiedCount: 0,
			missingCount: 0
		)
	}

	let imagesDirectory = outputDirectory.appendingPathComponent("images", isDirectory: true)
	try fileManager.createDirectory(
		at: imagesDirectory,
		withIntermediateDirectories: true
	)

	var relativePaths: [String: String] = [:]
	var copiedCount = 0
	var missingCount = 0

	for (id, attachment) in imageAttachmentsByID.sorted(by: { $0.key < $1.key }) {
		let opaqueFileName = "\(id).dat"
		guard export.assetFileNames[opaqueFileName] != nil else {
			missingCount += 1
			continue
		}

		let sourceURL = export.sourceDirectory.appendingPathComponent(opaqueFileName)
		guard fileManager.fileExists(atPath: sourceURL.path) else {
			missingCount += 1
			continue
		}

		let destinationName = "\(id).\(extForMime(attachment.mimeType))"
		let destinationURL = imagesDirectory.appendingPathComponent(destinationName)
		if !fileManager.fileExists(atPath: destinationURL.path) {
			try fileManager.copyItem(at: sourceURL, to: destinationURL)
			copiedCount += 1
		}
		relativePaths[id] = "images/\(destinationName)"
	}

	return PreparedImages(
		relativePathsByAttachmentID: relativePaths,
		copiedCount: copiedCount,
		missingCount: missingCount
	)
}


/// Strip extension from a filename.
func baseName(_ name: String) -> String {
	return (name as NSString).deletingPathExtension
}

/// Sanitize an image filename for LaTeX.
/// We keep dots and slashes, but escape LaTeX specials.
func latexSafePath(_ raw: String) -> String {
	// Escape standard LaTeX specials but leave . and / alone.
	// Reuse your existing text escaper, it doesn't touch . or /.
	return escapeForLaTeXPreservingMath(raw)
}

/// Convert a conversation title into a filesystem- and LaTeX-safe slug.
func safeSlug(_ raw: String) -> String {
	// Trim whitespace
	var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
	
	// Remove trailing periods (.)
	while s.hasSuffix(".") {
		s.removeLast()
	}
	
	// Replace anything that is NOT a letter, number, or dash with "-"
	let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
	s = s.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
	
	// Collapse multiple --- into a single -
	while s.contains("--") {
		s = s.replacingOccurrences(of: "--", with: "-")
	}
	
	// Trim leading/trailing dashes
	s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
	
	// Fallback
	if s.isEmpty { s = "Untitled" }
	
	return s
}

func sanitizeFileName(_ s: String) -> String {
    let badChars = CharacterSet(charactersIn: "/:\\?%*|\"<>")
    let cleaned = s.unicodeScalars.map { badChars.contains($0) ? "_" : Character($0) }
    let asString = String(cleaned)
    if asString.isEmpty { return "conversation" }
    return asString.replacingOccurrences(of: " ", with: "_")
}

struct CommandLineOptions {
	let inputURL: URL
	let outputDirectoryURL: URL
	let userName: String
}

enum CommandLineError: LocalizedError {
	case missingArguments
	case missingOptionValue(String)
	case unexpectedArgument(String)
	case emptyUserName

	var errorDescription: String? {
		switch self {
		case .missingArguments:
			return "An export directory or input JSON file and an output directory are required."
		case .missingOptionValue(let option):
			return "Missing value for \(option)."
		case .unexpectedArgument(let argument):
			return "Unexpected argument: \(argument)"
		case .emptyUserName:
			return "--user-name cannot be empty."
		}
	}
}

func parseCommandLine(_ arguments: [String]) throws -> CommandLineOptions {
	var positionalArguments: [String] = []
	var userName = "User"
	var index = 1

	while index < arguments.count {
		let argument = arguments[index]

		if argument == "--user-name" {
			guard index + 1 < arguments.count else {
				throw CommandLineError.missingOptionValue(argument)
			}
			userName = arguments[index + 1]
			index += 2
			continue
		}

		if argument.hasPrefix("--user-name=") {
			userName = String(argument.dropFirst("--user-name=".count))
			index += 1
			continue
		}

		if argument.hasPrefix("-") {
			throw CommandLineError.unexpectedArgument(argument)
		}

		positionalArguments.append(argument)
		index += 1
	}

	guard positionalArguments.count == 2 else {
		if positionalArguments.count > 2 {
			throw CommandLineError.unexpectedArgument(positionalArguments[2])
		}
		throw CommandLineError.missingArguments
	}

	userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
	guard !userName.isEmpty else {
		throw CommandLineError.emptyUserName
	}

	return CommandLineOptions(
		inputURL: URL(fileURLWithPath: positionalArguments[0]),
		outputDirectoryURL: URL(fileURLWithPath: positionalArguments[1]),
		userName: userName
	)
}

func printUsage(to stream: UnsafeMutablePointer<FILE> = stderr) {
    let prog = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "ChatExportToLaTeX"
	fputs(
		"Usage: \(prog) <export-directory-or-conversations.json> <output-directory> [--user-name <name>]\n",
		stream
	)
}


// MARK: - CLI main

func main() {
    let args = CommandLine.arguments
	if args.contains("--help") || args.contains("-h") {
		printUsage(to: stdout)
		return
	}

	let options: CommandLineOptions
	do {
		options = try parseCommandLine(args)
	} catch {
		fputs("Error: \(error.localizedDescription)\n", stderr)
		printUsage()
		exit(1)
	}

	let inputURL = options.inputURL
	let outDirPath = options.outputDirectoryURL.path
    let fm = FileManager.default
    try? fm.createDirectory(atPath: outDirPath, withIntermediateDirectories: true)
	var mainFiles: [String] = []
	mainFiles.append(generateMainPreamble())
    do {
		let export = try loadChatExport(from: inputURL)
		let convos = export.conversations
		let mainURL = URL(fileURLWithPath: outDirPath).appendingPathComponent("main.tex")
		let preparedImages = try prepareImages(
			for: export,
			in: options.outputDirectoryURL
		)
		if preparedImages.copiedCount > 0 {
			print("Copied \(preparedImages.copiedCount) image assets into \(outDirPath)/images")
		}
		if preparedImages.missingCount > 0 {
			fputs(
				"Warning: \(preparedImages.missingCount) supported image assets were not present in the export.\n",
				stderr
			)
		}
        for (index, convo) in convos.enumerated() {
            let titleBase = convo.title ?? "conversation_\(index + 1)"
            //let safe = sanitizeFileName(titleBase)
			let safe = safeSlug(titleBase)
            let fileName = String(format: "%04d_%@.tex", index + 1, safe)
            let outURL = URL(fileURLWithPath: outDirPath).appendingPathComponent(fileName)
			//let mainURL = URL(fileURLWithPath: outDirPath).appendingPathComponent(fileName)
			let tex = conversationToLaTeX(
				convo,
				userName: options.userName,
				resolvedImagePaths: preparedImages.relativePathsByAttachmentID
			).removingControlCharacters()
            try tex.write(to: outURL, atomically: true, encoding: String.Encoding.utf8)
			mainFiles.append("\\include{\(fileName.replacingOccurrences(of: ".tex", with: ""))}")
            print("Wrote \(outURL.path)")
        }
		mainFiles.append("\\end{document}")
		let mainList = mainFiles.joined(separator: "\n")
		try mainList.write(to: mainURL, atomically: true, encoding: String.Encoding.utf8)
    } catch {
        fputs("Error: \(error)\n", stderr)
        exit(1)
    }
}


extension String {
	/// Remove unprintable control characters (e.g. U+0014) but
	/// keep tab, LF, and CR.
	func removingControlCharacters() -> String {
		let allowedControls: Set<UInt32> = [0x09, 0x0A, 0x0D] // tab, LF, CR
		
		var cleanedScalars = String.UnicodeScalarView()
		cleanedScalars.reserveCapacity(self.unicodeScalars.count)
		
		for scalar in self.unicodeScalars {
			let v = scalar.value
			// ASCII control range 0x00–0x1F + DEL(0x7F)
			if (v <= 0x1F || v == 0x7F), !allowedControls.contains(v) {
				// skip this scalar (this nukes your U+0014)
				continue
			}
			cleanedScalars.append(scalar)
		}
		
		return String(cleanedScalars)
	}
}


//main()
