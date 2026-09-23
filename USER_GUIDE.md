# ChatGPT Conversations → LaTeX

This guide covers the conversion of a ChatGPT data export into a LaTeX book.

## 1. Export from ChatGPT

Request a data export and download the resulting ZIP file. Extract it. Current
large exports may contain `conversations-000.json`, `conversations-001.json`,
and so on, plus `export_manifest.json`; older exports contain one
`conversations.json`.

Keep the original ZIP unchanged so it remains a reference copy.

## 2. Run the converter

Using a standalone build:

```bash
ChatExportToLaTeX \
  /path/to/extracted-export \
  /path/to/ExportedLaTeX \
  --user-name "Your Name"
```

Or run directly through Swift Package Manager:

```bash
swift run ChatExportToLaTeX \
  /path/to/extracted-export \
  /path/to/ExportedLaTeX \
  --user-name "Your Name"
```

Pass the extracted export directory to process every shard. A direct path to a
single JSON file is still accepted when only that file should be converted.

The output directory will contain `main.tex` and one numbered `.tex` file per
conversation. If `--user-name` is omitted, assistant messages use the neutral
salutation “Dear User.” The name is supplied locally and is not inferred from
email addresses or other account identifiers in the export.

## 3. Images

For current exports, supported PNG and JPEG `.dat` assets are copied and given
usable extensions automatically. The result looks like:

```text
ExportedLaTeX/
├── main.tex
├── 0001_Conversation-title.tex
└── images/
```

Supported attachments are referenced from the generated conversation files.
For a legacy single-file export, an existing manually prepared `images`
directory remains compatible.

## 4. Math and code handling

The converter preserves complete ChatGPT math regions written as `\(...\)`,
`\[...\]`, `$...$`, or `$$...$$`. Unmatched delimiters and ordinary currency
such as `$5` are emitted as text, preventing one malformed message from
leaking math mode into the rest of the document.

Inline backtick code and fenced code blocks are protected before math is
recognized, so Swift interpolation such as `\(value)` remains code.

## 5. Build the PDF

From the generated output directory:

```bash
lualatex main.tex
lualatex main.tex
```

The generated `main.tex` also selects LuaLaTeX automatically when opened in
TeXShop. If the file was already open while it was regenerated, close and
reopen it before typesetting so TeXShop rereads the engine directive.

The second pass resolves cross-file references and the table of contents when
those are present.

## 6. Build a DOCX

From the generated output directory, Pandoc can convert the generated master
file directly:

```bash
pandoc main.tex -o main.docx
```

The resulting `main.docx` can be opened in Apple Pages, Microsoft Word, or
Collabora Office. To also extract referenced media into a separate directory:

```bash
pandoc main.tex -o main.docx --extract-media=media
```

## 7. Run the tests

```bash
swift test
```
