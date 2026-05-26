"""Render a markdown file to a styled standalone HTML page.

Usage:
    python _render_md_to_html.py <input.md> <output.html>
"""
from __future__ import annotations

import sys
from pathlib import Path

import markdown


CSS = """
:root {
  --fg: #1f2328;
  --muted: #57606a;
  --bg: #ffffff;
  --accent: #0969da;
  --card-bg: #f6f8fa;
  --border: #d0d7de;
}
* { box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
  color: var(--fg);
  background: var(--bg);
  max-width: 900px;
  margin: 2rem auto;
  padding: 0 1.5rem 4rem;
  line-height: 1.55;
}
h1 {
  border-bottom: 2px solid var(--border);
  padding-bottom: 0.4rem;
  margin-top: 2rem;
}
h2 {
  margin-top: 2.5rem;
  padding: 0.4rem 0.7rem;
  background: var(--card-bg);
  border-left: 4px solid var(--accent);
  border-radius: 4px;
}
h3 { margin-top: 1.5rem; color: var(--accent); }
hr {
  border: 0;
  border-top: 1px solid var(--border);
  margin: 2.5rem 0;
}
code {
  background: var(--card-bg);
  padding: 0.1rem 0.35rem;
  border-radius: 3px;
  font-size: 0.92em;
}
pre code { display: block; padding: 0.8rem; overflow-x: auto; }
blockquote {
  border-left: 4px solid var(--accent);
  background: var(--card-bg);
  margin: 1rem 0;
  padding: 0.6rem 1rem;
  color: var(--muted);
}
ul, ol { padding-left: 1.5rem; }
li { margin: 0.25rem 0; }
strong { color: var(--fg); }
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
@media print {
  body { max-width: none; margin: 0; padding: 1cm; }
  h2 { page-break-inside: avoid; }
}
"""

TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<style>{css}</style>
</head>
<body>
{body}
</body>
</html>
"""


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    text = src.read_text(encoding="utf-8")
    html_body = markdown.markdown(
        text,
        extensions=["extra", "sane_lists", "toc"],
        output_format="html5",
    )
    title = "CrashTech VLSI 2026 - Challenges"
    dst.write_text(
        TEMPLATE.format(title=title, css=CSS, body=html_body),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
