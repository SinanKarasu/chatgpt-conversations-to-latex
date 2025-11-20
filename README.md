# chatgpt-conversations-to-latex

Convert exported ChatGPT conversations (JSON) into a LaTeX “book” with one
section per conversation – plus optional image inclusion – and then on to
DOCX for editing in Collabora Office or Apple Pages.

This tool takes the `conversations.json` export from ChatGPT, walks all
messages, escapes them for LaTeX, and writes:

- `main.tex` – the master LaTeX file
- `####_<slug>.tex` – one file per conversation, included from `main.tex`
- Optional `\begin{figure}...\end{figure}` blocks for image attachments
  (referencing files in `images/`)

The intent is: generate LaTeX once, then reuse it for PDF, DOCX, and
further editing.

---

## Features

- Handles both old and new ChatGPT export formats
- Maps roles to friendly headers:
  - `user` → **Dear Chat**
  - `assistant` → **Dear Sinan**
  - everything else → **Dear Diary**
- Escapes LaTeX specials, including `$`, so pandoc doesn’t choke on stray math
- Emits a `main.tex` with `\include{####_<slug>}` for each conversation
- Emits LaTeX figures for supported image attachments (`image/png`, `image/jpeg`)
  and assumes they live under `images/` with sanitized filenames

See `ChatExport.swift` for the details of the models and LaTeX generation.

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
- `geometry`
- `darkmode` package
- `texgyretermes` fonts and `NotoColorEmoji` as an emoji fallback

Make sure those are available in your TeX installation.

---

## Building

### Option A: Xcode Command Line Tool (recommended for now)

1. In Xcode, create a **Command Line Tool** project (Swift).
2. Add `ChatExport.swift` and `main.swift` to the target.
3. Build & run from Xcode, or build and run from Terminal with:

   ```bash
   xcodebuild -scheme ChatExportToLaTeX -configuration Release
