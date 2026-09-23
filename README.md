# chatgpt-conversations-to-latex

Convert exported ChatGPT conversations (JSON) into a LaTeX “book” with one
section per conversation – plus optional image inclusion – and then on to
DOCX for editing in Collabora Office or Apple Pages.

This tool takes an extracted ChatGPT export directory (or a single conversation
JSON file), walks all messages, escapes them for LaTeX, and writes:

- `main.tex` – the master LaTeX file
- `####_<slug>.tex` – one file per conversation, included from `main.tex`
- Optional `\begin{figure}...\end{figure}` blocks for image attachments
  (referencing files in `images/`)

The intent is: generate LaTeX once, then reuse it for PDF, DOCX, and
further editing.

---

## Features

- Handles legacy `conversations.json` exports and manifest-driven,
  `conversations-###.json` sharded exports
- Maps roles to friendly headers:
  - `user` → **Dear Chat**
  - `assistant` → **Dear User**, or the name supplied with `--user-name`
  - everything else → **Dear Diary**
- Preserves complete `\(...\)`, `\[...\]`, `$...$`, and `$$...$$` math spans
- Keeps currency, unmatched dollar signs, inline code, and fenced code out of math mode
- Emits a `main.tex` with `\include{####_<slug>}` for each conversation
- Materializes opaque `.dat` assets from current exports as PNG/JPEG files in
  the generated `images/` directory and emits corresponding LaTeX figures

See `ChatExport.swift` for the details of the models and LaTeX generation.

---

## Recommended ChatGPT instruction

Dollar-sign math delimiters are ambiguous in exported conversations because
the same characters are also used for currency, shell variables, and literal
text. To make future exports easier to convert, add this wording to ChatGPT's
custom instructions:

```text
For all LaTeX math in your responses, use \( ... \) for inline math and
\[ ... \] for display math. Do not use $...$ or $$...$$ math delimiters.
```

This affects future responses only; it does not rewrite existing conversation
history. The converter still recognizes all four delimiter forms and protects
common non-mathematical uses of dollar signs.

---

## Requirements

- macOS with Swift 5.9+ (or whatever ships with your Xcode)
- A TeX distribution (TeX Live / MacTeX) if you want to compile PDF
- [pandoc](https://pandoc.org/) if you want DOCX output
- Optional but recommended:
  - `latexpand` (usually included with TeX Live) to flatten `\include` files

The LaTeX preamble uses:

- `fontspec`
- `graphicx`
- `amsmath`, `amssymb`
- `cancel`
- `fancyvrb`
- `geometry`
- `darkmode` package
- `texgyretermes` fonts and `NotoColorEmoji` as an emoji fallback

Make sure those are available in your TeX installation.

---

## Building

### Option A: Xcode Command Line Tool (recommended for now)

Build the existing project in Xcode, or from Terminal with:

```bash
xcodebuild -project ChatExportToLaTeX.xcodeproj \
  -scheme ChatExportToLaTeX \
  -configuration Release
```

### Option B: Swift Package Manager

Build and run the automated renderer tests with:

```bash
swift build
swift test
```

Run the converter with:

```bash
swift run ChatExportToLaTeX \
  /path/to/extracted-export \
  OutputDirectory \
  --user-name "Your Name"
```
