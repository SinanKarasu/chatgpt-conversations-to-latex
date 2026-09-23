import XCTest
@testable import ChatExportToLaTeX

final class LaTeXRenderingTests: XCTestCase {
	private func temporaryDirectory() throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		addTeardownBlock {
			try? FileManager.default.removeItem(at: url)
		}
		return url
	}

	func testLoadsEveryConversationShardFromManifest() throws {
		let directory = try temporaryDirectory()
		let manifest = #"{"logical_files":{"conversations.json":{"files":["conversations-000.json","conversations-001.json"],"sharded":true}}}"#
		let first = #"[{"id":"first","title":"First","mapping":{}}]"#
		let second = #"[{"id":"second","title":"Second","mapping":{}}]"#
		try manifest.write(
			to: directory.appendingPathComponent("export_manifest.json"),
			atomically: true,
			encoding: .utf8
		)
		try first.write(
			to: directory.appendingPathComponent("conversations-000.json"),
			atomically: true,
			encoding: .utf8
		)
		try second.write(
			to: directory.appendingPathComponent("conversations-001.json"),
			atomically: true,
			encoding: .utf8
		)

		let export = try loadChatExport(from: directory)

		XCTAssertEqual(export.conversations.map(\.id), ["first", "second"])
	}

	func testOpaqueImageAssetIsCopiedWithUsableExtension() throws {
		let sourceDirectory = try temporaryDirectory()
		let outputDirectory = try temporaryDirectory()
		let attachment = Attachment(
			id: "file-example",
			size: 4,
			name: "A diagram.png",
			mimeType: "image/png",
			width: 1,
			height: 1,
			source: nil
		)
		let message = ChatMessage(
			id: "message",
			author: Author(role: "user"),
			content: nil,
			createTime: 1,
			updateTime: nil,
			metadata: MessageMetadata(attachments: [attachment])
		)
		let conversation = ChatConversation(
			id: "conversation",
			title: "Test",
			createTime: 1,
			updateTime: nil,
			mapping: ["node": ChatNode(id: "node", message: message)]
		)
		let opaqueURL = sourceDirectory.appendingPathComponent("file-example.dat")
		try Data([0x89, 0x50, 0x4e, 0x47]).write(to: opaqueURL)
		let export = ChatExport(
			conversations: [conversation],
			sourceDirectory: sourceDirectory,
			assetFileNames: ["file-example.dat": "A diagram.png"]
		)

		let prepared = try prepareImages(for: export, in: outputDirectory)

		XCTAssertEqual(prepared.copiedCount, 1)
		XCTAssertEqual(
			prepared.relativePathsByAttachmentID["file-example"],
			"images/file-example.png"
		)
		XCTAssertTrue(
			FileManager.default.fileExists(
				atPath: outputDirectory.appendingPathComponent("images/file-example.png").path
			)
		)
	}

    func testRoleHeadersUseConfiguredUserName() {
        XCTAssertEqual(headerForRole("user", userName: "Ada"), "Dear Chat")
        XCTAssertEqual(headerForRole("assistant", userName: "Ada"), "Dear Ada")
        XCTAssertEqual(headerForRole("system", userName: "Ada"), "Dear Diary")
    }

    func testCommandLineUserNameOption() throws {
        let options = try parseCommandLine([
            "ChatExportToLaTeX",
            "conversations.json",
            "Output",
            "--user-name",
            "Ada Lovelace"
        ])

        XCTAssertEqual(options.userName, "Ada Lovelace")
        XCTAssertEqual(options.inputURL.lastPathComponent, "conversations.json")
        XCTAssertEqual(options.outputDirectoryURL.lastPathComponent, "Output")
    }

    func testCommandLineUsesPrivateNeutralDefault() throws {
        let options = try parseCommandLine([
            "ChatExportToLaTeX",
            "conversations.json",
            "Output"
        ])

        XCTAssertEqual(options.userName, "User")
    }

    func testPreservesParenthesizedAndBracketedMath() {
        let input = #"Energy \(E = mc^2\) & \[x_i = \frac{a}{b}\]"#

        XCTAssertEqual(
            escapeForLaTeXPreservingMath(input),
            #"Energy \(E = mc^2\) \& \[x_i = \frac{a}{b}\]"#
        )
    }

    func testPreservesBalancedDollarMath() {
        let input = #"Inline $x_i^2$ and display $$\sum_i x_i$$."#

        XCTAssertEqual(escapeForLaTeXPreservingMath(input), input)
    }

    func testCurrencyAndUnmatchedDollarsRemainText() {
        let input = "It costs $5–$10, or $7 today; unfinished $x"

        XCTAssertEqual(
            escapeForLaTeXPreservingMath(input),
            #"It costs \$5–\$10, or \$7 today; unfinished \$x"#
        )
    }

    func testCensoredProfanityBetweenDollarsRemainsText() {
        let input = #"His reply was "$%#@&^, really #$%^&"."#

        XCTAssertEqual(
            escapeForLaTeXPreservingMath(input),
            ##"His reply was "\$\%\#@\&\textasciicircum{}, really \#\$\%\textasciicircum{}\&"."##
        )
    }

    func testDollarPriceRatingCannotCaptureLaterMath() {
        let input = "TB5-ready, but $$$ still. Later, $$x = 2$$ is math."

        XCTAssertEqual(
            escapeForLaTeXPreservingMath(input),
            #"TB5-ready, but \$\$\$ still. Later, $$x = 2$$ is math."#
        )
    }

    func testShellVariablesAndCommandSubstitutionsRemainText() {
        let input = #"for v in $(tool | awk '{ print $2 }'); do\n get -r$v > out.$(echo $v)"#

        XCTAssertEqual(
            escapeForLaTeXPreservingMath(input),
            #"for v in \$(tool | awk '\{ print \$2 \}'); do\textbackslash{}n get -r\$v > out.\$(echo \$v)"#
        )
    }

	func testShellProcessIDsDoNotBecomeDisplayMath() {
		let input = #"""
		print -r -- "$(ts) START dir=$PWD pid=$$ model=$(readlink "$MODEL")" >> "$STATE"
		print -r -- "$(ts) DONE dir=$PWD pid=$$ model=$(readlink "$MODEL")" >> "$STATE"
		"""#

		let rendered = renderChatBodyToLaTeX(input)

		XCTAssertFalse(rendered.contains("pid=$$"))
		XCTAssertTrue(rendered.contains(#"pid=\$\$"#))
		XCTAssertTrue(rendered.contains(#"\$(ts)"#))
		XCTAssertTrue(rendered.contains(#"\$(readlink"#))
	}

	func testDisplayMathDelimiterOnOwnLineIsPreserved() {
		let input = "Before\n$$\nx^2 + y^2 = z^2\n$$\nAfter"

		XCTAssertEqual(escapeForLaTeXPreservingMath(input), input)
	}

	func testSedCharacterClassDollarsRemainLiteral() {
		let input = #"""
		cat preface.org | sed -e 's/^[$][^$]\(.*\)[$]$/\\[ \\1 \\]/'
		cat preface.org | sed -e 's/^[$]\([^$].*\)[$]$/\\[ \\1 \\]/'
		"""#

		let rendered = renderChatBodyToLaTeX(input)
		let withoutEscapedDollars = rendered.replacingOccurrences(of: #"\$"#, with: "")

		XCTAssertFalse(rendered.contains("[$]"))
		XCTAssertTrue(rendered.contains(#"[\$]"#))
		XCTAssertFalse(withoutEscapedDollars.contains("$"))
	}

	func testNestedMathDelimitersRenderOuterSpanLiterally() {
		let input = #"\left \[value \(\mathrm{b} \rightarrow 3\); more text\]"#

		let rendered = renderChatBodyToLaTeX(input)

		XCTAssertFalse(rendered.contains(#"\[value \("#))
		XCTAssertTrue(rendered.contains(#"\textbackslash{}[value \("#))
		XCTAssertTrue(rendered.contains(#"\textbackslash{}]"#))
	}

    func testPosixRegexParenthesesAreNotMathDelimiters() {
        let input = #"sed '/while[[:space:]]*\( *\+\+it *\)/d'"#

        let rendered = escapeForLaTeXPreservingMath(input)

        XCTAssertFalse(rendered.contains(#"\("#))
        XCTAssertFalse(rendered.contains(#"\+"#))
        XCTAssertTrue(rendered.contains(#"\textbackslash{}("#))
        XCTAssertTrue(rendered.contains(#"\textbackslash{}+"#))
    }

    func testIncompleteMathDelimiterCannotLeakMathMode() {
        XCTAssertEqual(
            escapeForLaTeXPreservingMath(#"Broken \(x_1"#),
            #"Broken \textbackslash{}(x\_1"#
        )
    }

    func testEscapedBackslashDoesNotOpenMathMode() {
        XCTAssertEqual(
            escapeForLaTeXPreservingMath(#"Literal \\(x_1\)"#),
            #"Literal \textbackslash{}\textbackslash{}(x\_1\textbackslash{})"#
        )
    }

    func testInlineCodeDoesNotBecomeMath() {
        let input = #"Code `\(notMath\)` and math \(x_1\)."#

        XCTAssertEqual(
            renderChatBodyToLaTeX(input),
            #"Code \texttt{\textbackslash{}(notMath\textbackslash{})} and math \(x_1\)."#
        )
    }

    func testInlineCodeContainingClosingBraceOrHash() {
        let input = #"The paragraph ends at `}`, then encounters `#`."#

        XCTAssertEqual(
            renderChatBodyToLaTeX(input),
            ##"The paragraph ends at \texttt{\}}, then encounters \texttt{\#}."##
        )
    }

    func testUnmatchedBacktickCannotCaptureLaterLines() {
        let input = #"""
        Error says `macro parameter character.

        The paragraph ends at `}`, then encounters `#`.
        """#

        XCTAssertEqual(
            renderChatBodyToLaTeX(input),
            ##"""
            Error says `macro parameter character.

            The paragraph ends at \texttt{\}}, then encounters \texttt{\#}.
            """##
        )
    }

    func testMainPreambleSelectsLuaLaTeXForFontSpec() {
        let preamble = generateMainPreamble()

        XCTAssertTrue(preamble.hasPrefix("% !TEX program = lualatex\n"))
        XCTAssertTrue(preamble.contains("\\usepackage{fancyvrb}"))
		XCTAssertTrue(preamble.contains("\\usepackage{cancel}"))
    }

    func testFencedCodeDoesNotBecomeMath() {
        let input = #"""
        Before \(x\)
        ```swift
        let value = "\(notMath)"
        ```
        After \[y^2\]
        """#

        let rendered = renderChatBodyToLaTeX(input)

        XCTAssertTrue(rendered.contains(#"Before \(x\)"#))
        XCTAssertTrue(rendered.contains("\\begin{Verbatim}"))
        XCTAssertTrue(rendered.contains(#"let value = "\(notMath)""#))
        XCTAssertTrue(rendered.contains("\\end{Verbatim}"))
        XCTAssertTrue(rendered.contains(#"After \[y^2\]"#))
    }

    func testFencedCodeMayDemonstrateLowercaseVerbatimEnvironment() {
        let input = #"""
        ```tex
        \begin{verbatim}
        literal text
        \end{verbatim}
        ```
        """#

        let rendered = renderChatBodyToLaTeX(input)

        XCTAssertTrue(rendered.hasPrefix("\\begin{Verbatim}\n"))
        XCTAssertTrue(rendered.contains("\\begin{verbatim}"))
        XCTAssertTrue(rendered.contains("\\end{verbatim}"))
        XCTAssertTrue(rendered.hasSuffix("\n\\end{Verbatim}"))
    }
}
