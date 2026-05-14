#!/usr/bin/env python3
"""
Build a PowerPoint (.pptx) version of the workshop deck.

Why this exists: GHE Pages is disabled at Netflix and there's no internal
htmlpreview service for github.netflix.net. The HTML deck at
netflix-workshop.html is the source of truth and is what the speaker
presents from locally. This .pptx is for Google-Slides distribution -
upload to Google Drive, Drive auto-converts to Slides, share the URL.

Run: python3 presentation/build_pptx.py
Output: presentation/netflix-workshop.pptx

Requires: python-pptx (pip install --user python-pptx)
"""

from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN

# Catppuccin Mocha palette (matches the HTML deck)
BASE     = RGBColor(0x1e, 0x1e, 0x2e)
SURFACE0 = RGBColor(0x31, 0x32, 0x44)
SURFACE1 = RGBColor(0x45, 0x47, 0x5a)
TEXT     = RGBColor(0xcd, 0xd6, 0xf4)
SUBTEXT  = RGBColor(0xa6, 0xad, 0xc8)
OVERLAY  = RGBColor(0x6c, 0x70, 0x86)
BLUE     = RGBColor(0x89, 0xb4, 0xfa)
GREEN    = RGBColor(0xa6, 0xe3, 0xa1)
MAUVE    = RGBColor(0xcb, 0xa6, 0xf7)
PEACH    = RGBColor(0xfa, 0xb3, 0x87)
YELLOW   = RGBColor(0xf9, 0xe2, 0xaf)

# 16:9 slide size
SLIDE_W = Inches(13.333)
SLIDE_H = Inches(7.5)

prs = Presentation()
prs.slide_width = SLIDE_W
prs.slide_height = SLIDE_H

BLANK_LAYOUT = prs.slide_layouts[6]  # blank layout - we draw everything


def add_slide(bg=BASE):
    s = prs.slides.add_slide(BLANK_LAYOUT)
    bg_shape = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, SLIDE_W, SLIDE_H)
    bg_shape.fill.solid()
    bg_shape.fill.fore_color.rgb = bg
    bg_shape.line.fill.background()
    return s


def add_text(slide, left, top, width, height, text, *,
             size=18, bold=False, color=TEXT, mono=False, align=PP_ALIGN.LEFT):
    tx = slide.shapes.add_textbox(left, top, width, height)
    tf = tx.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.alignment = align
    r = p.add_run()
    r.text = text
    r.font.size = Pt(size)
    r.font.bold = bold
    r.font.color.rgb = color
    if mono:
        r.font.name = 'Menlo'
    else:
        r.font.name = 'Helvetica'
    return tx


def add_bullets(slide, left, top, width, height, items, *,
                size=18, color=SUBTEXT, bullet_char='-'):
    tx = slide.shapes.add_textbox(left, top, width, height)
    tf = tx.text_frame
    tf.word_wrap = True
    for i, item in enumerate(items):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.LEFT
        p.space_after = Pt(6)
        r = p.add_run()
        r.text = f"{bullet_char}  {item}"
        r.font.size = Pt(size)
        r.font.color.rgb = color
        r.font.name = 'Helvetica'
    return tx


def add_title(slide, text, *, size=36, color=TEXT, top=Inches(0.45)):
    return add_text(slide, Inches(0.6), top, Inches(12), Inches(1.1),
                    text, size=size, bold=True, color=color)


def add_section_tag(slide, section):
    if not section:
        return
    add_text(slide, Inches(0.6), Inches(0.15), Inches(6), Inches(0.3),
             section.upper(), size=10, color=OVERLAY)


def add_footer_url(slide):
    add_text(slide, Inches(0.6), Inches(7.1), Inches(8), Inches(0.3),
             "github.netflix.net/mminutillo/obsidian-worklog",
             size=10, color=OVERLAY)


def add_code_block(slide, left, top, width, height, lines, *, size=14):
    # Surface background
    bg = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top, width, height)
    bg.fill.solid()
    bg.fill.fore_color.rgb = SURFACE0
    bg.line.fill.background()
    bg.adjustments[0] = 0.05
    # Code text
    pad = Inches(0.2)
    tx = slide.shapes.add_textbox(left + pad, top + pad, width - 2*pad, height - 2*pad)
    tf = tx.text_frame
    tf.word_wrap = True
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.LEFT
        r = p.add_run()
        r.text = line
        r.font.size = Pt(size)
        r.font.color.rgb = GREEN if line.startswith('$') or line.startswith('/') else PEACH
        r.font.name = 'Menlo'


def add_card(slide, left, top, width, height, *,
             title=None, body=None, body_bullets=None, accent=None, icon=None):
    bg = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top, width, height)
    bg.fill.solid()
    bg.fill.fore_color.rgb = SURFACE0
    bg.line.fill.background()
    bg.adjustments[0] = 0.05
    if accent:
        bar = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, Inches(0.06), height)
        bar.fill.solid()
        bar.fill.fore_color.rgb = accent
        bar.line.fill.background()
    pad = Inches(0.25)
    inner_left = left + pad
    inner_top = top + pad
    inner_w = width - 2*pad
    if icon:
        add_text(slide, inner_left, inner_top, inner_w, Inches(0.5),
                 icon, size=28, color=TEXT)
        inner_top += Inches(0.55)
    if title:
        add_text(slide, inner_left, inner_top, inner_w, Inches(0.5),
                 title, size=18, bold=True, color=TEXT)
        inner_top += Inches(0.5)
    if body:
        add_text(slide, inner_left, inner_top, inner_w, height - (inner_top - top) - pad,
                 body, size=13, color=SUBTEXT)
    if body_bullets:
        add_bullets(slide, inner_left, inner_top, inner_w,
                    height - (inner_top - top) - pad,
                    body_bullets, size=12, color=SUBTEXT)


def add_table(slide, left, top, width, height, headers, rows):
    n_cols = len(headers)
    n_rows = len(rows) + 1
    table_shape = slide.shapes.add_table(n_rows, n_cols, left, top, width, height)
    tbl = table_shape.table
    for j, h in enumerate(headers):
        cell = tbl.cell(0, j)
        cell.text = h
        cell.fill.solid()
        cell.fill.fore_color.rgb = SURFACE0
        for p in cell.text_frame.paragraphs:
            for r in p.runs:
                r.font.size = Pt(13)
                r.font.bold = True
                r.font.color.rgb = BLUE
                r.font.name = 'Helvetica'
    for i, row in enumerate(rows, start=1):
        for j, val in enumerate(row):
            cell = tbl.cell(i, j)
            cell.text = val
            cell.fill.solid()
            cell.fill.fore_color.rgb = BASE
            for p in cell.text_frame.paragraphs:
                for r in p.runs:
                    r.font.size = Pt(12)
                    r.font.color.rgb = SUBTEXT
                    r.font.name = 'Helvetica'


# ============================================================
# Slide builders
# ============================================================

def slide_title():
    s = add_slide()
    add_text(s, Inches(0.6), Inches(2.6), Inches(12.1), Inches(1.5),
             "obsidian-worklog", size=72, bold=True, color=BLUE)
    add_text(s, Inches(0.6), Inches(3.9), Inches(12.1), Inches(0.6),
             "Netflix fork - walkthrough", size=24, color=SUBTEXT)
    add_text(s, Inches(0.6), Inches(5.0), Inches(12.1), Inches(0.4),
             "github.netflix.net/mminutillo/obsidian-worklog",
             size=14, color=OVERLAY)


def slide_plan():
    s = add_slide()
    add_section_tag(s, "Intro")
    add_title(s, "Plan for the hour")
    items = [
        "What this is, briefly (5 min)",
        "Set it up together (15 min, pause at checkpoints)",
        "Walk through how I use it Monday-to-Friday (10 min)",
        "Less obvious uses - 1:1 prep, doc ingest, Pandora lookup (10 min)",
        "Whatever you want to ask (rest)",
    ]
    add_bullets(s, Inches(0.6), Inches(2.0), Inches(11.5), Inches(4),
                items, size=22)
    add_text(s, Inches(0.6), Inches(6.0), Inches(11.5), Inches(0.4),
             "Have your laptop out. There's a clone-and-run-setup section partway through.",
             size=14, color=OVERLAY)
    add_footer_url(s)


def slide_origin():
    s = add_slide()
    add_section_tag(s, "Intro")
    add_title(s, "How it started, how it's going")
    add_text(s, Inches(0.6), Inches(1.7), Inches(5.8), Inches(0.4),
             "The experiment", size=18, bold=True, color=TEXT)
    add_bullets(s, Inches(0.6), Inches(2.2), Inches(5.8), Inches(4.5), [
        "I wanted a better TODO list. Mine kept drifting.",
        "Wrote a tiny Claude Code skill: paste raw stuff, get a clean weekly list.",
        "Started linking people I mentioned ([[Sarah]]) so I could find what I'd discussed with whom.",
        "Then programs got their own notes. Then summaries. Then the graph started being useful on its own.",
    ], size=16)
    add_text(s, Inches(6.9), Inches(1.7), Inches(5.8), Inches(0.4),
             "What it became", size=18, bold=True, color=TEXT)
    add_bullets(s, Inches(6.9), Inches(2.2), Inches(5.8), Inches(4.5), [
        "A personal context vault, not just a todo list",
        "The week is a thin slice; the vault is the long-arc memory",
        "Prep for 1:1s, promo cases, status updates - all come out of the same files I write into every week",
        "The Netflix fork plugs in Pandora, Jira, Confluence, Coda, Slack threads via existing MCPs",
    ], size=16)
    add_footer_url(s)


def slide_what_it_is():
    s = add_slide()
    add_section_tag(s, "What it is")
    add_title(s, "What it is, concretely")
    add_text(s, Inches(0.6), Inches(1.7), Inches(12), Inches(0.4),
             "Three pieces that work together:", size=16, color=SUBTEXT)
    card_w = Inches(3.9)
    card_h = Inches(4.2)
    card_top = Inches(2.3)
    add_card(s, Inches(0.6), card_top, card_w, card_h,
             icon="📜", title="A skill",
             body="A markdown file at skills/worklog/SKILL.md. Claude reads it when you type /worklog. ~1500 lines of prose instructions.")
    add_card(s, Inches(4.7), card_top, card_w, card_h,
             icon="🗂", title="A vault",
             body="An Obsidian vault with 10 directories: Worklogs/, People/, Programs/, Teams/, Meetings/, Sources/, Preferences/, Archive/, Summaries/, Reports/. Plain markdown.")
    add_card(s, Inches(8.8), card_top, card_w, card_h,
             icon="🔌", title="MCP hooks",
             body="The Netflix fork pins to specific tool IDs from core-tools and plugin_atlassian so Claude knows which MCP to call for Pandora, Jira, Confluence, or Slack.")
    add_text(s, Inches(0.6), Inches(6.8), Inches(12), Inches(0.4),
             "Public version: github.com/menottim/obsidian-worklog. This deck covers the Netflix fork on top.",
             size=13, color=OVERLAY)
    add_footer_url(s)


def slide_skill_itself():
    s = add_slide()
    add_section_tag(s, "What it is")
    add_title(s, "What \"a skill\" actually is")
    code = [
        "--- skills/worklog/SKILL.md ---",
        "---",
        "name: worklog",
        "description: >",
        "  Manage Menotti's personal worklog stored in Obsidian. Use this",
        "  skill whenever the user says \"worklog\", \"weekly rollover\",",
        "  \"what's on my plate\", \"add to my worklog\", \"summarize my week\".",
        "---",
        "",
        "# How Claude Code uses this file:",
        "# 1. User types /worklog (or any keyword in description)",
        "# 2. Claude reads this entire SKILL.md",
        "# 3. Claude follows the prose instructions below",
        "",
        "## Commands",
        "",
        "### /worklog rollover",
        "Create the new week file from Templates/Weekly.md. Carry forward",
        "any items marked In Progress from the previous week. Move Done...",
    ]
    add_code_block(s, Inches(0.6), Inches(1.6), Inches(12), Inches(4.1), code, size=13)
    add_card(s, Inches(3.5), Inches(5.95), Inches(6.3), Inches(1.3),
             title="Skills vs MCPs vs plugins",
             body_bullets=[
                 "Skill: markdown instructions Claude follows when triggered",
                 "MCP server: external tool Claude can call (Atlassian, Slack, core-tools)",
                 "Plugin: distribution unit bundling skills + commands + MCP config",
             ])
    add_footer_url(s)


def slide_vault():
    s = add_slide()
    add_section_tag(s, "What it does")
    add_title(s, "The vault (the skill builds and maintains this for you)", size=30)
    add_text(s, Inches(0.6), Inches(1.6), Inches(12), Inches(0.4),
             "You don't set up directories. setup.sh creates the structure once; the skill places new files in the right folders as you go.",
             size=14, color=SUBTEXT)
    code = [
        "# Created at setup time, maintained by the skill",
        "Your Vault/",
        "  Worklogs/       # YYYY-Www.md, one per week + Backlog",
        "  People/         # One note per person, wiki-linked",
        "  Programs/       # One note per program/initiative",
        "  Teams/          # Org structure (Pandora-aware)",
        "  Meetings/       # Ingested Slack threads + docs",
        "  Sources/        # Registered Slack channels",
        "  Preferences/    # Voice, style, workflow rules",
        "  Archive/        # Completed weeks (compact)",
        "  Summaries/      # Weekly/monthly/quarterly",
        "  Reports/        # D3 visualizations (HTML)",
    ]
    add_code_block(s, Inches(0.6), Inches(2.3), Inches(7.2), Inches(4.5), code, size=13)
    add_text(s, Inches(8.1), Inches(2.3), Inches(4.6), Inches(0.4),
             "Markdown, not a database", size=18, bold=True, color=TEXT)
    add_bullets(s, Inches(8.1), Inches(2.8), Inches(4.6), Inches(4), [
        "Plain markdown you can edit in Obsidian",
        "Backups: git push. Search: grep.",
        "The skill writes into your vault, never around it - your edits are preserved",
        "No migrations, no schema, no lock-in",
    ], size=14)
    add_footer_url(s)


def slide_graph():
    s = add_slide()
    add_section_tag(s, "What it does")
    add_title(s, "Wiki-links connect the files")
    add_text(s, Inches(0.6), Inches(2.3), Inches(12.1), Inches(3),
             "Every [[Jane Smith]] mentioned in a worklog creates a backlink to her People note. Obsidian's graph view shows the connections. Useful for finding every week she came up.",
             size=20, color=SUBTEXT)
    add_text(s, Inches(0.6), Inches(4.0), Inches(12.1), Inches(2),
             "(See the live HTML deck for the graph screenshot)",
             size=14, color=OVERLAY)
    add_footer_url(s)


def slide_commands():
    s = add_slide()
    add_section_tag(s, "What it does")
    add_title(s, "Commands and features", size=32)
    rows = [
        ("/worklog", "Show active items by priority", "Any time"),
        ("/worklog rollover", "New week, archive previous, carry forward", "Monday"),
        ("/worklog review", "Walk through each item for status updates", "Monday morning"),
        ("/worklog add P1 <title>", "Quick-add an item, checks for duplicates", "Mid-week"),
        ("/worklog pull", "Ingest unprocessed threads from Slack sources", "Mid-week"),
        ("/worklog summary [week|month|quarter]", "Impact summary for reporting up", "End of period"),
        ("/worklog audit", "Vault health check + stale-note flagging", "Friday / monthly"),
        ("/worklog viz [period]", "D3 charts as standalone HTML", "End of month/quarter"),
        ("/worklog sync", "Git commit + push of the vault", "After any update"),
    ]
    add_table(s, Inches(0.6), Inches(1.7), Inches(12), Inches(4.8),
              ["Command", "What it does", "When"], rows)
    add_footer_url(s)


def slide_netflix_layer():
    s = add_slide()
    add_section_tag(s, "What it does")
    add_title(s, "What the Netflix fork adds")
    add_text(s, Inches(0.6), Inches(1.55), Inches(12), Inches(0.4),
             "Three commands on top of what the public fork has.",
             size=14, color=SUBTEXT)
    card_w = Inches(3.9)
    card_h = Inches(3.6)
    card_top = Inches(2.2)
    add_card(s, Inches(0.6), card_top, card_w, card_h,
             icon="🌐", title="/worklog ingest",
             body="Takes a URL (Coda, Confluence, Google Doc, Slack thread permalink). Fetches the body via the matched MCP, extracts action items, wiki-links people.")
    add_card(s, Inches(4.7), card_top, card_w, card_h,
             icon="👤", title="/worklog whois",
             body="Resolves a name against Pandora via core-tools MCP. Writes title, manager, team into a People/ note. Creates a stub for the manager.")
    add_card(s, Inches(8.8), card_top, card_w, card_h,
             icon="🎫", title="/worklog jira",
             body="Pulls a Jira ticket via the Atlassian MCP. Adds the title, status, and assignee to the current week under the right subgroup.")
    add_text(s, Inches(0.6), Inches(6.1), Inches(12.1), Inches(1),
             "Each command names the exact MCP tool ID it wants - e.g. mcp__plugin_atlassian_atlassian__getJiraIssue. Claude still reads and follows the instruction (that's inference); the choice space is one tool, not 'find something Jira-like'. When a call fails, you know which named tool failed.",
             size=12, color=OVERLAY)
    add_footer_url(s)


def slide_auto_routing():
    s = add_slide()
    add_section_tag(s, "What it does")
    add_title(s, "You don't have to type the subcommand")
    add_text(s, Inches(0.6), Inches(1.55), Inches(12.1), Inches(0.4),
             "Type /worklog <arg> and the skill classifies the argument and routes.",
             size=14, color=SUBTEXT)
    add_text(s, Inches(0.6), Inches(2.1), Inches(5.8), Inches(0.4),
             "What you type", size=16, bold=True, color=TEXT)
    inputs = [
        "/worklog https://docs.google.com/document/d/abc...",
        "/worklog WISSE-1234",
        "/worklog https://netflix.atlassian.net/browse/SIDE-99",
        "/worklog jane.smith@netflix.com",
        "/worklog status",
        "/worklog spent 2 hrs reviewing the rollout plan",
    ]
    add_code_block(s, Inches(0.6), Inches(2.6), Inches(5.8), Inches(3.6), inputs, size=11)
    add_text(s, Inches(6.9), Inches(2.1), Inches(5.8), Inches(0.4),
             "What runs", size=16, bold=True, color=TEXT)
    outputs = [
        "-> /worklog ingest (Google Doc URL)",
        "-> /worklog jira (matches [A-Z]+-\\d+)",
        "-> /worklog jira (extracted from URL)",
        "-> /worklog whois (netflix.com email)",
        "-> /worklog status (known subcommand)",
        "-> raw worklog input (default)",
    ]
    add_code_block(s, Inches(6.9), Inches(2.6), Inches(5.8), Inches(3.6), outputs, size=11)
    add_text(s, Inches(0.6), Inches(6.4), Inches(12.1), Inches(0.8),
             "Bare names like \"Sarah Chen\" don't auto-route to whois - too easy to confuse with worklog item text. Email format (firstname.lastname@netflix.com) is the unambiguous signal.",
             size=12, color=OVERLAY)
    add_footer_url(s)


def slide_stride():
    s = add_slide()
    add_section_tag(s, "What it does")
    add_title(s, "Where this sits next to STRIDE")
    add_text(s, Inches(0.6), Inches(1.55), Inches(12.1), Inches(0.4),
             "STRIDE (github.netflix.net/corp/stride) is a personal assistant. The two are complementary.",
             size=14, color=SUBTEXT)
    rows = [
        ("One-liner",
         "Personal assistant for the day-to-day - email triage, calendar, channel summaries, scheduled debriefs",
         "Weekly worklog as a long-arc context vault - people, programs, decisions, summaries"),
        ("Runs as",
         "Daemon + Slack bot on Dev Workspace; also via Claude Code",
         "A Claude Code skill, on-demand when you type /worklog"),
        ("Time horizon",
         "\"What needs my attention right now?\"",
         "\"What have I been doing over the last quarter?\""),
        ("Storage",
         "Reads your existing email, calendar, Slack, etc.",
         "Writes a single Obsidian vault on disk"),
        ("Scheduled?",
         "Yes - daily / weekly debriefs on cron",
         "No - runs when you invoke it"),
    ]
    add_table(s, Inches(0.6), Inches(2.1), Inches(12.1), Inches(3.6),
              ["", "STRIDE", "obsidian-worklog"], rows)
    add_text(s, Inches(0.6), Inches(5.95), Inches(12.1), Inches(1.2),
             "Common workflow: STRIDE summarizes your inbox and channels in the morning. You skim, decide what's worth keeping, and feed those bits into /worklog. The vault accumulates context-worth-keeping; STRIDE handles always-arriving stuff.",
             size=12, color=OVERLAY)
    add_footer_url(s)


def slide_prereqs():
    s = add_slide()
    add_section_tag(s, "Lab: Setup")
    add_title(s, "Setup: prerequisites")
    add_text(s, Inches(0.6), Inches(1.6), Inches(12), Inches(0.4),
             "Run through these before we move on. If anything's missing, flag it.",
             size=14, color=SUBTEXT)
    add_bullets(s, Inches(0.6), Inches(2.2), Inches(12), Inches(4), [
        "Claude Code installed (CLI, desktop, or IDE extension)",
        "Obsidian installed (any recent version)",
        "A directory for your vault (existing or new - setup will create the structure)",
        "newt on PATH: command -v newt",
        "gh authed for github.netflix.net: GH_HOST=github.netflix.net gh auth status",
        "Your @netflix.com git email handy",
    ], size=18, bullet_char='[ ]')
    add_text(s, Inches(0.6), Inches(6.3), Inches(12), Inches(0.6),
             "Checkpoint: everything green? Speak up if not.",
             size=16, color=GREEN, bold=True)
    add_footer_url(s)


def slide_clone():
    s = add_slide()
    add_section_tag(s, "Lab: Setup")
    add_title(s, "Step 1 - clone")
    code = [
        "$ cd ~/workspace  # or wherever you keep your repos",
        "$ git clone https://github.netflix.net/mminutillo/obsidian-worklog",
        "$ cd obsidian-worklog",
    ]
    add_code_block(s, Inches(0.6), Inches(1.9), Inches(12), Inches(1.6), code, size=18)
    add_text(s, Inches(0.6), Inches(3.7), Inches(12), Inches(2),
             "The public version at github.com/menottim/obsidian-worklog works too, but skips the Netflix-specific commands (/worklog ingest, /worklog whois, /worklog jira) and the MCP profile auto-join. Use the Netflix fork unless you have a reason not to.",
             size=14, color=SUBTEXT)
    add_text(s, Inches(0.6), Inches(6.0), Inches(12), Inches(0.6),
             "Checkpoint: ls shows setup.sh, skills/, docs/, README.md.",
             size=16, color=GREEN, bold=True)
    add_footer_url(s)


def slide_setup():
    s = add_slide()
    add_section_tag(s, "Lab: Setup")
    add_title(s, "Step 2 - run setup")
    code = [
        "$ ./setup.sh",
        "",
        "=== obsidian-worklog setup (strict mode) ===",
        "Obsidian vault path [~/Documents/Obsidian Vault]: ...",
        "Your display name [yourname]: ...",
        "Git user.email []: you@netflix.com",
        "",
        "=== Netflix identity detected ===",
        "  OK newt installed at /usr/local/bin/newt",
        "  OK genai-core-tools profile already joined",
        "  OK gh authenticated for github.netflix.net",
        "  OK GHE login: yourname",
        "",
        "Backup repo URL [https://github.netflix.net/yourname/obsidian-vault.git]:",
        "Apply these settings? [Y/n]: y",
    ]
    add_code_block(s, Inches(0.6), Inches(1.7), Inches(12.1), Inches(5), code, size=12)
    add_text(s, Inches(0.6), Inches(6.9), Inches(12), Inches(0.3),
             "Strict mode: any failed step aborts. \"Setup complete!\" only prints after every check passes.",
             size=12, color=OVERLAY)
    add_footer_url(s)


def slide_verify():
    s = add_slide()
    add_section_tag(s, "Lab: Setup")
    add_title(s, "What setup.sh checks")
    add_text(s, Inches(0.6), Inches(1.5), Inches(12), Inches(0.4),
             "All bash-callable. The script doesn't ask Claude anything during setup.",
             size=14, color=SUBTEXT)
    rows = [
        ("newt on PATH", "command -v newt"),
        ("genai-core-tools profile", "newt resolve | grep -q ... (auto-joins if missing)"),
        ("gh authed for GHE", "GH_HOST=github.netflix.net gh auth status"),
        ("Authoritative GHE login", "gh api user --jq .login (no whoami guessing)"),
        ("GHE backup repo exists", "gh repo view + offer to gh repo create"),
        ("Install path safety", "Must start with $HOME/.claude/"),
        ("All placeholders replaced", "Literal grep -F against known list"),
        ("All values landed in SKILL.md", "Post-substitution presence check"),
        ("Plugin manifest installed", "File exists at install path"),
    ]
    add_table(s, Inches(0.6), Inches(2.0), Inches(12), Inches(4.8),
              ["Check", "Mechanism"], rows)
    add_footer_url(s)


def slide_restart():
    s = add_slide()
    add_section_tag(s, "Lab: Setup")
    add_title(s, "Step 3 - restart and verify")
    add_bullets(s, Inches(0.6), Inches(1.8), Inches(12), Inches(4.5), [
        "Quit Claude Code fully (Cmd+Q on Mac). MCP servers load at session start, not mid-session.",
        "Reopen Claude Code.",
        "Type /mcp. Look for core-tools, plugin_atlassian, plugin_slack in the list.",
        "Type /worklog status. First run will say \"no current week\" - that's expected.",
        "Type /worklog rollover. That creates your first weekly file.",
    ], size=18, bullet_char='1.')
    add_text(s, Inches(0.6), Inches(6.3), Inches(12), Inches(0.6),
             "Checkpoint: /worklog status now shows a week with no items.",
             size=16, color=GREEN, bold=True)
    add_footer_url(s)


def slide_monday():
    s = add_slide()
    add_section_tag(s, "Typical use")
    add_title(s, "How I use it Monday morning")
    add_text(s, Inches(0.6), Inches(1.7), Inches(7), Inches(0.4),
             "Takes about 10 minutes sitting down with coffee:",
             size=15, color=SUBTEXT)
    add_bullets(s, Inches(0.6), Inches(2.2), Inches(7), Inches(4), [
        "/worklog rollover - starts the new week, carries forward unfinished",
        "/worklog pull - reads new Slack threads from registered channel sources",
        "/worklog review - walks item by item: done / in progress / blocked / pinged X",
        "/worklog sync - commits and pushes the vault",
    ], size=15, bullet_char='1.')
    add_card(s, Inches(8.0), Inches(2.0), Inches(4.7), Inches(4.5),
             title="What \"review\" looks like",
             body_bullets=[
                 "\"done\" - moves to done, archived on rollover",
                 "\"still on it\" - stays active, optional dated note",
                 "\"pinged Sarah\" - annotation, wiki-links her",
                 "\"blocked on X\" - flagged; audit surfaces stuck items",
             ])
    add_footer_url(s)


def slide_paste():
    s = add_slide()
    add_section_tag(s, "Typical use")
    add_title(s, "Mid-week: paste raw context, ask to log it")
    add_text(s, Inches(0.6), Inches(1.6), Inches(12), Inches(0.4),
             "Most of the time, I'm not typing commands. I'm pasting notes and asking Claude to add them.",
             size=15, color=SUBTEXT)
    code = [
        "here are notes from my 1:1 with Sarah:",
        "- she's concerned about the migration timeline slipping",
        "- wants to bring in a contractor for the gap",
        "- Marcus is doing well picking up Dev's work",
        "",
        "add to worklog",
    ]
    add_code_block(s, Inches(0.6), Inches(2.2), Inches(12), Inches(2.6), code, size=16)
    add_text(s, Inches(0.6), Inches(5.0), Inches(12), Inches(2),
             "Claude extracts action items, wiki-links Sarah and Marcus (creates People stubs if they don't exist), adds dated annotations to the migration item, reports what changed. Slack threads and transcripts work the same way.",
             size=14, color=SUBTEXT)
    add_footer_url(s)


def slide_summaries():
    s = add_slide()
    add_section_tag(s, "Typical use")
    add_title(s, "End of week / month / quarter")
    add_text(s, Inches(0.6), Inches(1.7), Inches(5.8), Inches(0.4),
             "/worklog summary [period]", size=17, bold=True, color=TEXT)
    add_bullets(s, Inches(0.6), Inches(2.2), Inches(5.8), Inches(3), [
        "week - this week as a paragraph",
        "month - adds priority-drift notes",
        "quarter - adds trend bullets and time allocation",
        "2026-Q1 - or any specific period",
    ], size=14)
    add_text(s, Inches(0.6), Inches(4.7), Inches(5.8), Inches(1),
             "Writes to Summaries/, also puts a plain-text copy on clipboard.",
             size=12, color=OVERLAY)
    add_text(s, Inches(6.9), Inches(1.7), Inches(5.8), Inches(0.4),
             "/worklog viz quarter", size=17, bold=True, color=TEXT)
    add_text(s, Inches(6.9), Inches(2.2), Inches(5.8), Inches(0.4),
             "Generates a standalone HTML with four D3 charts:",
             size=14, color=SUBTEXT)
    add_bullets(s, Inches(6.9), Inches(2.7), Inches(5.8), Inches(2.5), [
        "Time-allocation pie by subgroup",
        "Program activity heatmap",
        "P0 trend line over weeks",
        "Completion rate bars",
    ], size=14)
    add_text(s, Inches(6.9), Inches(5.2), Inches(5.8), Inches(1),
             "Open in any browser. I've used these for quarter-end share-outs.",
             size=12, color=OVERLAY)
    add_footer_url(s)


def slide_1on1():
    s = add_slide()
    add_section_tag(s, "Less obvious uses")
    add_title(s, "Pre-1:1 prep")
    add_text(s, Inches(0.6), Inches(1.6), Inches(12), Inches(0.4),
             "Before a 1:1, I'll usually do something like:",
             size=15, color=SUBTEXT)
    code = [
        "prep me for the 1:1 with [[Jane Smith]] tomorrow",
        "",
        "- pull the last 6 weeks where Jane appeared",
        "- flag anything that was in_progress 3+ weeks ago and is still open",
        "- surface anything from our last 1:1 that hasn't been addressed",
        "- highlight people in Jane's note I should ask about",
    ]
    add_code_block(s, Inches(0.6), Inches(2.2), Inches(12), Inches(2.6), code, size=14)
    add_text(s, Inches(0.6), Inches(5.0), Inches(12), Inches(2),
             "Claude writes back a focused brief: items where she's mentioned, stuck items, open commitments, names in her note. The point is the brief comes from your own writing - the LLM is organizing context you already wrote, not hallucinating it.",
             size=14, color=SUBTEXT)
    add_footer_url(s)


def slide_promo():
    s = add_slide()
    add_section_tag(s, "Less obvious uses")
    add_title(s, "Promo case prep")
    code = [
        "build the impact case for promo conversation 2026 H1",
        "",
        "- pull items where I drove a decision, not just attended or tracked",
        "- cross-org partnerships (programs touching CIS, CATS, AppSec)",
        "- times I unblocked someone else's work",
        "- counter-list: things that slipped or got descoped and what I learned",
    ]
    add_code_block(s, Inches(0.6), Inches(1.8), Inches(12), Inches(2.6), code, size=14)
    add_text(s, Inches(0.6), Inches(4.6), Inches(12), Inches(2.4),
             "Same idea as the 1:1 prep, longer horizon. You wrote the weeks for a different reason - now they're a corpus you can ask questions about. The output is a draft to edit, not a finished case. The structure shows up; the specifics still come from you.",
             size=14, color=SUBTEXT)
    add_footer_url(s)


def slide_ingest_demo():
    s = add_slide()
    add_section_tag(s, "Less obvious uses")
    add_title(s, "Ingest a Confluence/Coda doc")
    code = [
        "/worklog ingest https://confluence.netflix.com/display/SECURITY/2026-05-12+Migration+Sync",
        "# or just:",
        "/worklog https://confluence.netflix.com/display/SECURITY/2026-05-12+Migration+Sync",
    ]
    add_code_block(s, Inches(0.6), Inches(1.7), Inches(12.1), Inches(1.5), code, size=11)
    add_text(s, Inches(0.6), Inches(3.4), Inches(12), Inches(0.4),
             "What runs (either form):", size=14, color=SUBTEXT, bold=True)
    add_bullets(s, Inches(0.6), Inches(3.9), Inches(12), Inches(2.5), [
        "URL matches confluence.netflix.com -> skill calls mcp__core-tools__netflix_search_data",
        "Claude announces the tool ID it's about to call",
        "Fetches the page body, detects date + attendees + action items section",
        "Creates Meetings/2026-05-12-migration-sync.md",
        "Extracts action items, wiki-links attendees (resolves emails via Pandora)",
        "Adds items to the current week under the right subgroup",
    ], size=13)
    add_text(s, Inches(0.6), Inches(6.7), Inches(12.1), Inches(0.5),
             "🔒 Fetched body is treated as data, not instructions - injection attempts get flagged as suspicious content, not followed.",
             size=11, color=OVERLAY)
    add_footer_url(s)


def slide_whois_demo():
    s = add_slide()
    add_section_tag(s, "Less obvious uses")
    add_title(s, "Pandora-resolved People notes")
    code = [
        "/worklog whois Sarah Chen",
        "",
        "Using mcp__core-tools__netflix_search_api to resolve Sarah Chen against Pandora",
        "",
        "Pulled Sarah Chen (Senior Software Engineer, Platform Infrastructure).",
        "Manager: Alex Park (stub created).",
        "People note: ~/vault/People/Sarah Chen.md",
    ]
    add_code_block(s, Inches(0.6), Inches(1.7), Inches(12), Inches(2.4), code, size=12)
    add_text(s, Inches(0.6), Inches(4.4), Inches(5.8), Inches(0.4),
             "The People note becomes:", size=14, bold=True, color=TEXT)
    fm = [
        "---",
        "email: sarah.chen@netflix.com",
        "title: Senior Software Engineer",
        "team: Platform Infrastructure",
        "manager: \"[[Alex Park]]\"",
        "pandora_id: schen",
        "status: active",
        "---",
        "- [2026-05-13] Created from Pandora",
        "- [2026-05-13] First appeared in W19",
    ]
    add_code_block(s, Inches(0.6), Inches(4.9), Inches(5.8), Inches(2.2), fm, size=11)
    add_text(s, Inches(6.9), Inches(4.4), Inches(5.8), Inches(2.8),
             "Anything that later mentions \"Sarah Chen\" - ingested meeting notes, Slack threads, Jira tickets - wiki-links to the same canonical note. After a few months, opening her note shows every week she came up.",
             size=13, color=SUBTEXT)
    add_footer_url(s)


def slide_other_uses():
    s = add_slide()
    add_section_tag(s, "Less obvious uses")
    add_title(s, "Other things people have done with it")
    card_w = Inches(3.95)
    card_h = Inches(2.3)
    pairs = [
        ("🚨", "Incident debrief",
         "Ingest the incident-channel Slack thread, get a Meeting note with timeline and follow-ups linked to the current week."),
        ("🆕", "Onboarding a new report",
         "Paste notes from each pre-onboarding meeting. Their People/ note has context from before week 1."),
        ("🎯", "OKR allocation check",
         "Tag items with OKR labels. End of quarter: ask Claude what fraction of P0/P1 effort went to each."),
        ("📊", "Week-over-week diff",
         "Before a status update, ask: compare this week to last - what's new, what shifted, what's stuck."),
        ("🗺", "Cross-team mapping",
         "Run /worklog whois on people you depend on. Builds a who-owns-what map across orgs."),
        ("🎤", "Talk / conference prep",
         "Ingest the talk outline + related Coda research, get an action-itemized prep flow in the current week."),
    ]
    positions = [
        (Inches(0.5),  Inches(1.7)),
        (Inches(4.7),  Inches(1.7)),
        (Inches(8.9),  Inches(1.7)),
        (Inches(0.5),  Inches(4.3)),
        (Inches(4.7),  Inches(4.3)),
        (Inches(8.9),  Inches(4.3)),
    ]
    for (icon, title, body), (left, top) in zip(pairs, positions):
        add_card(s, left, top, card_w, card_h, icon=icon, title=title, body=body)
    add_footer_url(s)


def slide_wrap():
    s = add_slide()
    add_section_tag(s, "Wrap")
    add_title(s, "Where we are")
    add_text(s, Inches(0.6), Inches(1.8), Inches(5.8), Inches(0.4),
             "Current state", size=18, bold=True, color=TEXT)
    add_bullets(s, Inches(0.6), Inches(2.3), Inches(5.8), Inches(3.5), [
        "Working install, verified by tests/e2e-setup.sh",
        "Three Netflix commands wired to MCPs you already have",
        "A vault directory",
        "A backup repo at github.netflix.net/yourname/obsidian-vault",
    ], size=15)
    add_text(s, Inches(6.9), Inches(1.8), Inches(5.8), Inches(0.4),
             "If you want to try it this week", size=18, bold=True, color=TEXT)
    add_bullets(s, Inches(6.9), Inches(2.3), Inches(5.8), Inches(3.5), [
        "Run /worklog rollover Monday",
        "Paste one meeting's notes into a conversation, ask Claude to add it",
        "Try /worklog whois on one person you work with",
        "Run /worklog summary week Friday and see what it produces",
    ], size=15)
    add_text(s, Inches(0.6), Inches(6.4), Inches(12), Inches(0.8),
             "Repo: github.netflix.net/mminutillo/obsidian-worklog  ·  Docs: docs/SETUP-NETFLIX.md, docs/NETFLIX-COMMANDS.md  ·  Test: tests/e2e-setup.sh",
             size=11, color=OVERLAY)


def slide_qa():
    s = add_slide()
    add_section_tag(s, "Wrap")
    add_text(s, Inches(0.6), Inches(2.6), Inches(12.1), Inches(2),
             "Questions?", size=84, bold=True, color=TEXT, align=PP_ALIGN.CENTER)
    add_text(s, Inches(0.6), Inches(4.5), Inches(12.1), Inches(0.6),
             "Or catch me afterwards if you hit something during setup.",
             size=18, color=SUBTEXT, align=PP_ALIGN.CENTER)
    add_text(s, Inches(0.6), Inches(6.4), Inches(12.1), Inches(0.4),
             "github.netflix.net/mminutillo/obsidian-worklog",
             size=12, color=OVERLAY, align=PP_ALIGN.CENTER)


# ============================================================
# Build
# ============================================================
build_order = [
    slide_title,
    slide_plan,
    slide_origin,
    slide_what_it_is,
    slide_skill_itself,
    slide_vault,
    slide_graph,
    slide_commands,
    slide_netflix_layer,
    slide_auto_routing,
    slide_stride,
    slide_prereqs,
    slide_clone,
    slide_setup,
    slide_verify,
    slide_restart,
    slide_monday,
    slide_paste,
    slide_summaries,
    slide_1on1,
    slide_promo,
    slide_ingest_demo,
    slide_whois_demo,
    slide_other_uses,
    slide_wrap,
    slide_qa,
]

for fn in build_order:
    fn()

import os
out_path = os.path.join(os.path.dirname(__file__), "netflix-workshop.pptx")
prs.save(out_path)
print(f"Wrote {out_path} ({len(build_order)} slides)")
