#!/usr/bin/env python3
"""Render a BRD Markdown file to a styled PDF that mirrors the reference
"Ledger BRD" look (blue title, Field/Value tables, priority pills, page footer).

Markdown source stays the source of truth; this only renders it. Uses headless
Chrome for HTML->PDF so no extra packages are needed.

Usage:
    python tools/brd_to_pdf.py docs/brd/AU-authentication-brd.md
    python tools/brd_to_pdf.py docs/brd/AU-authentication-brd.md -o out.pdf
"""
import argparse
import html
import os
import re
import subprocess
import sys
import tempfile

CHROME_CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
]


def find_chrome():
    for p in CHROME_CANDIDATES:
        if os.path.exists(p):
            return p
    raise SystemExit("No Chrome/Edge found for PDF rendering.")


def inline(text: str) -> str:
    """Inline markdown -> HTML. Preserves literal <br>; escapes the rest."""
    # Protect existing <br> tags the source uses inside table cells.
    text = text.replace("<br>", "BR")
    text = html.escape(text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    text = text.replace("BR", "<br>")
    return text


def split_cells(row: str):
    row = row.strip()
    if row.startswith("|"):
        row = row[1:]
    if row.endswith("|"):
        row = row[:-1]
    return [c.strip() for c in row.split("|")]


def render_table(rows):
    header = split_cells(rows[0])
    body = [split_cells(r) for r in rows[2:]]  # skip the |---| separator
    is_kv = [c.lower() for c in header] == ["field", "value"]
    cls = "kv" if is_kv else "grid"
    out = [f'<table class="{cls}">']
    out.append("<thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in header) + "</tr></thead>")
    out.append("<tbody>")
    for r in body:
        cells = []
        for i, c in enumerate(r):
            first = is_kv and i == 0
            # Priority pill: a KV row whose field is "Priority".
            if is_kv and i == 1 and r and r[0].strip().lower() == "priority":
                lvl = c.strip().lower()
                cells.append(f'<td><span class="pill {lvl}">{inline(c)}</span></td>')
            elif first:
                cells.append(f'<td class="k">{inline(c)}</td>')
            else:
                cells.append(f"<td>{inline(c)}</td>")
        out.append("<tr>" + "".join(cells) + "</tr>")
    out.append("</tbody></table>")
    return "\n".join(out)


def md_to_html_body(md: str):
    lines = md.splitlines()
    blocks = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        s = line.strip()
        if not s:
            i += 1
            continue
        if s == "---":
            i += 1
            continue
        if s.startswith("### "):
            blocks.append(f"<h3>{inline(s[4:])}</h3>")
            i += 1
            continue
        if s.startswith("## "):
            blocks.append(f"<h2>{inline(s[3:])}</h2>")
            i += 1
            continue
        if s.startswith("# "):
            blocks.append(f"<h1>{inline(s[2:])}</h1>")
            i += 1
            continue
        if s.startswith("|"):
            tbl = []
            while i < n and lines[i].strip().startswith("|"):
                tbl.append(lines[i])
                i += 1
            if len(tbl) >= 2:
                blocks.append(render_table(tbl))
            continue
        # Italic-only footer line, e.g. *Document in progress …*
        if s.startswith("*") and s.endswith("*") and not s.startswith("**"):
            blocks.append(f'<p class="note">{inline(s[1:-1])}</p>')
            i += 1
            continue
        # The metadata line under the H1 (starts with **Platform:**)
        if s.startswith("**Platform:**"):
            blocks.append(f'<p class="meta">{inline(s)}</p>')
            i += 1
            continue
        blocks.append(f"<p>{inline(s)}</p>")
        i += 1
    return "\n".join(blocks)


CSS = """
:root { --blue:#1b3fae; --blue-soft:#eaf0fb; --ink:#1f2733; --muted:#5b6472;
        --line:#d7deea; --hi:#e8462a; }
* { box-sizing:border-box; }
html { -webkit-print-color-adjust:exact; print-color-adjust:exact; }
body { font-family:'Segoe UI',Arial,sans-serif; color:var(--ink); font-size:11px;
       line-height:1.5; margin:0; }
h1 { color:var(--blue); font-size:30px; font-weight:800; letter-spacing:-.5px;
     margin:0 0 6px; }
h1 + p.meta { margin-top:0; }
p.meta { color:var(--muted); font-size:12px; border-bottom:2px solid var(--line);
         padding-bottom:14px; margin:0 0 20px; }
h2 { color:var(--blue); font-size:18px; font-weight:700; margin:26px 0 12px;
     padding-bottom:6px; border-bottom:2px solid var(--line); }
h3 { color:var(--blue); font-size:13.5px; font-weight:700; margin:22px 0 8px;
     break-after:avoid; }
p { margin:8px 0; }
p.note { color:var(--muted); font-style:italic; margin-top:18px; }
code { background:#f2f4f8; border:1px solid var(--line); border-radius:3px;
       padding:0 3px; font-family:'Consolas',monospace; font-size:10px; }
/* border-collapse:separate (not collapse) is REQUIRED so Chromium will
   fragment a long table across pages instead of shoving it whole to the next
   page (which left big blank gaps). Row-level break-inside keeps rows intact
   and thead repeats the header on each continuation page. */
table { width:100%; border-collapse:separate; border-spacing:0; margin:4px 0 8px; }
table.kv, table.grid { border:1px solid var(--line); }
thead { display:table-header-group; }
tr { break-inside:avoid; }
th { background:var(--blue); color:#fff; text-align:left; font-weight:600;
     font-size:11px; padding:7px 10px; }
td { border-top:1px solid var(--line); padding:8px 10px; vertical-align:top; }
td.k { width:120px; color:var(--blue); font-weight:600; background:#f7f9fd; }
table.kv tr td:first-child { white-space:nowrap; }
.pill { display:inline-block; padding:2px 12px; border-radius:11px;
        font-size:10px; font-weight:600; }
.pill.high { background:#e6effc; color:#1b3fae; }
.pill.medium { background:#fdf0e0; color:#b26a00; }
.pill.low { background:#eef0f3; color:#5b6472; }
@page { size:A4; margin:16mm 14mm 18mm; }
"""


def build_html(body: str, title: str) -> str:
    return f"""<!doctype html><html><head><meta charset="utf-8">
<title>{html.escape(title)}</title><style>{CSS}</style></head>
<body>{body}</body></html>"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("md")
    ap.add_argument("-o", "--out")
    args = ap.parse_args()

    md_path = os.path.abspath(args.md)
    with open(md_path, encoding="utf-8") as f:
        md = f.read()

    title = os.path.splitext(os.path.basename(md_path))[0]
    body = md_to_html_body(md)
    doc = build_html(body, title)

    out_pdf = os.path.abspath(args.out) if args.out else os.path.splitext(md_path)[0] + ".pdf"

    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as tf:
        tf.write(doc)
        html_path = tf.name

    chrome = find_chrome()
    try:
        subprocess.run(
            [chrome, "--headless", "--disable-gpu", "--no-sandbox",
             "--no-pdf-header-footer",
             f"--print-to-pdf={out_pdf}",
             "file:///" + html_path.replace("\\", "/")],
            check=True, capture_output=True, timeout=90,
        )
    finally:
        try:
            os.unlink(html_path)
        except OSError:
            pass
    print(f"Wrote {out_pdf}")


if __name__ == "__main__":
    main()
