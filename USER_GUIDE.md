## Suggested `USER_GUIDE.md`

This is a more hand-holding walkthrough.

```markdown
# ChatGPT Conversations → LaTeX → DOCX → Collabora / Pages

This guide walks you through the entire workflow:

1. Exporting your conversations from ChatGPT
2. Running the Swift converter
3. Getting a `main.tex` book file
4. Converting that to DOCX with pandoc
5. Opening the result in Collabora Office and Apple Pages

---

## 1. Export from ChatGPT

1. In ChatGPT, request a data export (or download a single-conversation JSON).
2. You’ll get a `.zip` file that contains `conversations.json` (and possibly media).
3. Extract the zip somewhere convenient, e.g. `~/Downloads/chatgpt-export/`.

Make sure you know the full path to `conversations.json`.

---

## 2. Run the converter

From Terminal:

```bash
cd /path/to/chatgpt-conversations-to-latex

# If you built a standalone binary:
./chatgpt-conversations-to-latex \
  ~/Downloads/chatgpt-export/conversations.json \
  ./ExportedLaTeX

It is recommended that you put all the media into a folder in the target folder named images/

so images hould be in
./ExportedLaTeX/images
in the above example.
