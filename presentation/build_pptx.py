#!/usr/bin/env python3
"""
Build a PowerPoint (.pptx) version of the workshop deck for Google Slides upload.

The HTML deck (netflix-workshop.html) is the source of truth for live
presenting - it keeps the Catppuccin dark styling and click-through reveals.
This .pptx is the simpler async-share version: light theme, built-in fonts,
generous sizing. Google Slides will re-render fonts and may shift the theme
on import; the goal is for content to remain readable, not pixel-perfect.

Run: python3 presentation/build_pptx.py
Output: presentation/netflix-workshop.pptx

Requires: pip install --user python-pptx
"""

from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.text import PP_ALIGN, MSO_AUTO_SIZE

# Light palette - safer for Google Slides import than dark theme
WHITE     = RGBColor(0xff, 0xff, 0xff)
TEXT      = RGBColor(0x1a, 0x1a, 0x1a)
SUBTEXT   = RGBColor(0x4a, 0x4a, 0x4a)
MUTED     = RGBColor(0x6b, 0x72, 0x80)
CARD_BG   = RGBColor(0xf3, 0xf4, 0xf6)
CARD_BORDER = RGBColor(0xe1, 0xe4, 0xe8)
BLUE      = RGBColor(0x14, 0x68, 0xc7)
GREEN     = RGBColor(0x05, 0x7a, 0x55)
ACCENT    = RGBColor(0x0a, 0x40, 0x96)
CODE_BG   = RGBColor(0xf3, 0xf4, 0xf6)
CODE_TEXT = RGBColor(0x16, 0x42, 0x6e)
ORANGE    = RGBColor(0xc2, 0x49, 0x0c)

# Standard 16:9
SLIDE_W = Inches(13.333)
SLIDE_H = Inches(7.5)

# Universal fonts (available on Mac, Windows, and Google Slides)
FONT_BODY = 'Helvetica'
FONT_MONO = 'Courier New'

prs = Presentation()
prs.slide_width = SLIDE_W
prs.slide_height = SLIDE_H

BLANK_LAYOUT = prs.slide_layouts[6]


def add_slide():
    """White background, default theme — keeps Slides happy."""
    return prs.slides.add_slide(BLANK_LAYOUT)


def add_text(slide, left, top, width, height, text, *,
             size=18, bold=False, color=TEXT, mono=False,
             align=PP_ALIGN.LEFT, auto_fit=False):
    tx = slide.shapes.add_textbox(left, top, width, height)
    tf = tx.text_frame
    tf.word_wrap = True
    if auto_fit:
        tf.auto_size = MSO_AUTO_SIZE.TEXT_TO_FIT_SHAPE
    tf.margin_left = Inches(0.05)
    tf.margin_right = Inches(0.05)
    tf.margin_top = Inches(0.02)
    tf.margin_bottom = Inches(0.02)
    p = tf.paragraphs[0]
    p.alignment = align
    r = p.add_run()
    r.text = text
    r.font.size = Pt(size)
    r.font.bold = bold
    r.font.color.rgb = color
    r.font.name = FONT_MONO if mono else FONT_BODY
    return tx


def add_lines(slide, left, top, width, height, lines, *,
              size=14, color=TEXT, mono=False, bold_idx=None):
    """Multiple lines of text in one text box. bold_idx is an int or list to bold."""
    if isinstance(bold_idx, int):
        bold_idx = [bold_idx]
    bold_idx = bold_idx or []
    tx = slide.shapes.add_textbox(left, top, width, height)
    tf = tx.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0.05)
    tf.margin_right = Inches(0.05)
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.LEFT
        p.space_after = Pt(3)
        r = p.add_run()
        r.text = line
        r.font.size = Pt(size)
        r.font.color.rgb = color
        r.font.name = FONT_MONO if mono else FONT_BODY
        if i in bold_idx:
            r.font.bold = True
    return tx


def add_bullets(slide, left, top, width, height, items, *,
                size=16, color=TEXT, mark='•'):
    tx = slide.shapes.add_textbox(left, top, width, height)
    tf = tx.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0.05)
    tf.margin_right = Inches(0.05)
    for i, item in enumerate(items):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.LEFT
        p.space_after = Pt(8)
        r = p.add_run()
        prefix = mark if mark else ''
        r.text = f"{prefix}  {item}" if prefix else item
        r.font.size = Pt(size)
        r.font.color.rgb = color
        r.font.name = FONT_BODY
    return tx


def add_numbered(slide, left, top, width, height, items, *,
                 size=16, color=TEXT, start=1):
    tx = slide.shapes.add_textbox(left, top, width, height)
    tf = tx.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0.05)
    tf.margin_right = Inches(0.05)
    for i, item in enumerate(items):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.LEFT
        p.space_after = Pt(8)
        r = p.add_run()
        r.text = f"{start + i}.  {item}"
        r.font.size = Pt(size)
        r.font.color.rgb = color
        r.font.name = FONT_BODY
    return tx


def add_title(slide, text, *, size=32):
    """Slide title in the top area."""
    return add_text(slide, Inches(0.6), Inches(0.4), Inches(12), Inches(0.9),
                    text, size=size, bold=True, color=TEXT)


def add_section_tag(slide, section):
    if not section:
        return
    add_text(slide, Inches(0.6), Inches(0.15), Inches(8), Inches(0.25),
             section.upper(), size=9, color=MUTED)


def add_footer(slide):
    add_text(slide, Inches(0.6), Inches(7.15), Inches(8), Inches(0.25),
             "github.netflix.net/mminutillo/obsidian-worklog",
             size=10, color=MUTED)


def add_card(slide, left, top, width, height, *,
             title=None, body=None, body_bullets=None, icon=None):
    """Card = light-gray background rectangle with optional border, text on top."""
    bg = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, width, height)
    bg.fill.solid()
    bg.fill.fore_color.rgb = CARD_BG
    bg.line.color.rgb = CARD_BORDER
    bg.line.width = Pt(0.75)
    pad = Inches(0.25)
    inner_top = top + pad
    inner_left = left + pad
    inner_w = width - 2 * pad
    if icon:
        add_text(slide, inner_left, inner_top, inner_w, Inches(0.55),
                 icon, size=24, color=TEXT)
        inner_top += Inches(0.6)
    if title:
        add_text(slide, inner_left, inner_top, inner_w, Inches(0.45),
                 title, size=16, bold=True, color=TEXT)
        inner_top += Inches(0.48)
    if body:
        add_text(slide, inner_left, inner_top, inner_w,
                 height - (inner_top - top) - pad,
                 body, size=12, color=SUBTEXT)
    if body_bullets:
        add_bullets(slide, inner_left, inner_top, inner_w,
                    height - (inner_top - top) - pad,
                    body_bullets, size=11, color=SUBTEXT)


def add_code_block(slide, left, top, width, height, lines, *, size=12):
    bg = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, left, top, width, height)
    bg.fill.solid()
    bg.fill.fore_color.rgb = CODE_BG
    bg.line.color.rgb = CARD_BORDER
    bg.line.width = Pt(0.5)
    pad = Inches(0.2)
    add_lines(slide, left + pad, top + pad, width - 2 * pad, height - 2 * pad,
              lines, size=size, color=CODE_TEXT, mono=True)


def add_table(slide, left, top, width, height, headers, rows, *, col_widths=None):
    n_cols = len(headers)
    n_rows = len(rows) + 1
    table_shape = slide.shapes.add_table(n_rows, n_cols, left, top, width, height)
    tbl = table_shape.table
    if col_widths:
        for j, w in enumerate(col_widths):
            tbl.columns[j].width = w
    for j, h in enumerate(headers):
        cell = tbl.cell(0, j)
        cell.text = h
        cell.fill.solid()
        cell.fill.fore_color.rgb = ACCENT
        for p in cell.text_frame.paragraphs:
            for r in p.runs:
                r.font.size = Pt(12)
                r.font.bold = True
                r.font.color.rgb = WHITE
                r.font.name = FONT_BODY
    for i, row in enumerate(rows, start=1):
        for j, val in enumerate(row):
            cell = tbl.cell(i, j)
            cell.text = val
            cell.fill.solid()
            cell.fill.fore_color.rgb = WHITE if i % 2 else CARD_BG
            for p in cell.text_frame.paragraphs:
                for r in p.runs:
                    r.font.size = Pt(11)
                    r.font.color.rgb = TEXT
                    r.font.name = FONT_BODY


# ============================================================
# Slide builders
# ============================================================

def slide_title():
    s = add_slide()
    add_text(s, Inches(0.6), Inches(2.7), Inches(12.1), Inches(1.4),
             "obsidian-worklog", size=64, bold=True, color=BLUE)
    add_text(s, Inches(0.6), Inches(4.0), Inches(12.1), Inches(0.6),
             "Netflix fork - walkthrough", size=22, color=SUBTEXT)
    add_text(s, Inches(0.6), Inches(5.2), Inches(12.1), Inches(0.4),
             "github.netflix.net/mminutillo/obsidian-worklog",
             size=14, color=MUTED)


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
    add_numbered(s, Inches(0.6), Inches(1.8), Inches(12), Inches(4.5),
                 items, size=20)
    add_text(s, Inches(0.6), Inches(6.4), Inches(12), Inches(0.4),
             "Have your laptop out. There's a clone-and-run-setup section partway through.",
             size=13, color=MUTED)
    add_footer(s)


def slide_origin():
    s = add_slide()
    add_section_tag(s, "Intro")
    add_title(s, "How it started, how it's going")
    add_text(s, Inches(0.6), Inches(1.6), Inches(5.8), Inches(0.4),
             "The experiment", size=18, bold=True, color=TEXT)
    add_bullets(s, Inches(0.6), Inches(2.1), Inches(5.8), Inches(4.5), [
        "I wanted a better TODO list. Mine kept drifting.",
        "Wrote a tiny Claude Code skill: paste raw stuff, get a clean weekly list.",
        "Started linking people I mentioned ([[Sarah]]) so I could find what I'd discussed with whom.",
        "Then programs got their own notes. Then summaries. Then the graph started being useful on its own.",
    ], size=14)
    add_text(s, Inches(6.9), Inches(1.6), Inches(5.8), Inches(0.4),
             "What it became", size=18, bold=True, color=TEXT)
    add_bullets(s, Inches(6.9), Inches(2.1), Inches(5.8), Inches(4.5), [
        "A personal context vault, not just a todo list",
        "The week is a thin slice; the vault is the long-arc memory",
        "Prep for 1:1s, promo cases, status updates - all from the same files I write into every week",
        "Netflix fork plugs in Pandora, Jira, Confluence, Coda, Slack threads via existing MCPs",
    ], size=14)
    add_footer(s)


def slide_what_it_is():
    s = add_slide()
    add_section_tag(s, "What it is")
    add_title(s, "What it is, concretely")
    add_text(s, Inches(0.6), Inches(1.5), Inches(12), Inches(0.4),
             "Three pieces that work together:", size=15, color=SUBTEXT)
    card_w = Inches(3.95)
    card_h = Inches(4.6)
    card_top = Inches(2.05)
    add_card(s, Inches(0.6), card_top, card_w, card_h,
             icon="A skill", title="Markdown instructions",
             body="A file at skills/worklog/SKILL.md. Claude reads it when you type /worklog. About 1500 lines of prose instructions.")
    add_card(s, Inches(4.7), card_top, card_w, card_h,
             icon="A vault", title="An Obsidian directory",
             body="Ten subdirectories: Worklogs, People, Programs, Teams, Meetings, Sources, Preferences, Archive, Summaries, Reports. Plain markdown.")
    add_card(s, Inches(8.8), card_top, card_w, card_h,
             icon="MCP hooks", title="Pinned tool IDs",
             body="The Netflix fork pins to specific tool IDs from core-tools and plugin_atlassian. Claude knows which MCP to call for Pandora, Jira, Confluence, or Slack.")
    add_text(s, Inches(0.6), Inches(6.85), Inches(12), Inches(0.3),
             "Public version: github.com/menottim/obsidian-worklog. This deck covers the Netflix fork on top.",
             size=11, color=MUTED)
    add_footer(s)


def slide_skill_itself():
    s = add_slide()
    add_section_tag(s, "What it is")
    add_title(s, 'What "a skill" actually is')
    code = [
        "--- skills/worklog/SKILL.md ---",
        "---",
        "name: worklog",
        "description: >",
        "  Manage Menotti's personal worklog stored in Obsidian. Use this",
        "  skill whenever the user says \"worklog\", \"weekly rollover\",",
        '  "what\'s on my plate", "add to my worklog", "summarize my week".',
        "---",
        "",
        "# How Claude Code uses this file:",
        "# 1. User types /worklog (or any keyword in description)",
        "# 2. Claude reads this entire SKILL.md",
        "# 3. Claude follows the prose instructions below",
        "",
        "## /worklog rollover",
        "Create the new week file from Templates/Weekly.md. Carry forward",
        "any items marked In Progress from the previous week.",
    ]
    add_code_block(s, Inches(0.6), Inches(1.6), Inches(12.1), Inches(3.9),
                   code, size=12)
    add_card(s, Inches(2.5), Inches(5.7), Inches(8.3), Inches(1.4),
             title="Skills vs MCPs vs plugins",
             body_bullets=[
                 "Skill: markdown instructions Claude follows when triggered",
                 "MCP server: external tool Claude can call (Atlassian, Slack, core-tools)",
                 "Plugin: distribution unit bundling skills + commands + MCP config",
             ])
    add_footer(s)


def slide_vault():
    s = add_slide()
    add_section_tag(s, "What it does")
    add_title(s, "The vault (the skill builds and maintains it for you)", size=26)
    add_text(s, Inches(0.6), Inches(1.55), Inches(12), Inches(0.4),
             "You don't set up directories. setup.sh creates the structure once; the skill places new files in the right folders.",
             size=13, color=SUBTEXT)
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
    add_code_block(s, Inches(0.6), Inches(2.2), Inches(7.4), Inches(4.7),
                   code, size=12)
    add_text(s, Inches(8.3), Inches(2.2), Inches(4.6), Inches(0.4),
             "Markdown, not a database", size=16, bold=True, color=TEXT)
    add_bullets(s, Inches(8.3), Inches(2.75), Inches(4.6), Inches(4), [
        "Plain markdown you can edit in Obsidian",
        "Backups: git push. Search: grep.",
        "The skill writes into your vault, never around it - your edits are preserved",
        "No migrations, no schema, no lock-in",
    ], size=13)
    add_footer(s)


def slide_graph():
    s = add_slide()
    add_section_tag(s, "What it does")
    add_title(s, "Wiki-links connect the files")
    add_text(s, Inches(1.2), Inches(2.8), Inches(11), Inches(2.5),
             "Every [[Jane Smith]] mentioned in a worklog creates a backlink to her People note. Obsidian's graph view shows the connections - useful for finding every week she came up.",
             size=19, color=SUBTEXT, align=PP_ALIGN.CENTER)
    add_text(s, Inches(0.6), Inches(5.5), Inches(12.1), Inches(0.4),
             "(See the live HTML deck for the graph screenshot)",
             size=12, color=MUTED, align=PP_ALIGN.CENTER)
    add_footer(s)


def slide_commands():
    s = add_slide()
    add_section_tag(s, "What it does")
    add_title(s, "Commands and features", size=28)
    rows = [
        ("/worklog", "Show active items by priority", "Any time"),
        ("/worklog rollover", "New week, archive previous, carry forward", "Monday"),
        ("/worklog review", "Walk through each item for status updates", "Monday morning"),
        ("/worklog add P1 <title>", "Quick-add an item, check for duplicates", "Mid-week"),
        ("/worklog pull", "Ingest unprocessed threads from Slack sources", "Mid-week"),
        ("/worklog summary [period]", "Impact summary for reporting up", "End of period"),
        ("/worklog audit", "Vault health check + stale-note flagging", "Friday / monthly"),
        ("/worklog viz [period]", "D3 charts as standalone HTML", "Monthly / quarterly"),
        ("/worklog sync", "Git commit + push of the vault", "After any update"),
    ]
    add_table(s, Inches(0.6), Inches(1.6), Inches(12.1), Inches(5.3),
              ["Command", "What it does", "When"], rows,
              col_widths=[Inches(3.5), Inches(6.2), Inches(2.4)])
    add_footer(s)


def slide_netflix_layer():
    s = add_slide()
    add_section_tag(s, "What it does")
    add_title(s, "What the Netflix fork adds")
    add_text(s, Inches(0.6), Inches(1.4), Inches(12), Inches(0.4),
             "Three commands on top of what the public fork has.",
             size=13, color=SUBTEXT)
    card_w = Inches(3.95)
    card_h = Inches(3.7)
    card_top = Inches(2.0)
    add_card(s, Inches(0.6), card_top, card_w, card_h,
             title="/worklog ingest <url>",
             body="Takes a URL (Coda, Confluence, Google Doc, Slack thread permalink). Fetches the body via the matched MCP, extracts action items, wiki-links people.")
    add_card(s, Inches(4.7), card_top, card_w, card_h,
             title="/worklog whois <name>",
             body="Resolves a name against Pandora via the core-tools MCP. Writes title, manager, team into a People/ note. Creates a stub for the manager.")
    add_card(s, Inches(8.8), card_top, card_w, card_h,
             title="/worklog jira <key>",
             body="Pulls a Jira ticket via the Atlassian MCP. Adds the title, status, and assignee to the current week under the right subgroup.")
    add_text(s, Inches(0.6), Inches(6.0), Inches(12.1), Inches(1),
             "Each command names the exact MCP tool ID it wants (e.g. mcp__plugin_atlassian_atlassian__getJiraIssue). Claude still reads and follows the instruction (that's inference); the choice space is one tool, not 'find something Jira-like'. When a call fails, you know which named tool failed.",
             size=11, color=MUTED)
    add_footer(s)


def slide_auto_routing():
    s = add_slide()
    add_section_tag(s, "What it does")
    add_title(s, "You don't have to type the subcommand")
    add_text(s, Inches(0.6), Inches(1.4), Inches(12.1), Inches(0.4),
             "Type /worklog <arg> and the skill classifies the argument and routes.",
             size=13, color=SUBTEXT)
    add_text(s, Inches(0.6), Inches(1.95), Inches(5.8), Inches(0.4),
             "What you type", size=15, bold=True, color=TEXT)
    inputs = [
        "/worklog https://docs.google.com/document/d/abc",
        "/worklog WISSE-1234",
        "/worklog https://netflix.atlassian.net/browse/SIDE-99",
        "/worklog jane.smith@netflix.com",
        "/worklog status",
        "/worklog spent 2 hrs reviewing the rollout",
    ]
    add_code_block(s, Inches(0.6), Inches(2.45), Inches(5.95), Inches(3.6),
                   inputs, size=11)
    add_text(s, Inches(6.85), Inches(1.95), Inches(5.85), Inches(0.4),
             "What runs", size=15, bold=True, color=TEXT)
    outputs = [
        "-> /worklog ingest (Google Doc URL)",
        "-> /worklog jira (matches [A-Z]+-d+)",
        "-> /worklog jira (extracted from URL)",
        "-> /worklog whois (netflix.com email)",
        "-> /worklog status (known subcommand)",
        "-> raw worklog input (default)",
    ]
    add_code_block(s, Inches(6.85), Inches(2.45), Inches(5.85), Inches(3.6),
                   outputs, size=11)
    add_text(s, Inches(0.6), Inches(6.25), Inches(12.1), Inches(0.7),
             'Bare names like "Sarah Chen" don\'t auto-route to whois - too easy to confuse with worklog item text. Email format (firstname.lastname@netflix.com) is the unambiguous signal.',
             size=11, color=MUTED)
    add_footer(s)


def slide_stride():
    s = add_slide()
    add_section_tag(s, "What it does")
    add_title(s, "Where this sits next to STRIDE")
    add_text(s, Inches(0.6), Inches(1.4), Inches(12.1), Inches(0.4),
             "STRIDE (github.netflix.net/corp/stride) is a personal assistant. The two are complementary.",
             size=13, color=SUBTEXT)
    rows = [
        ("One-liner",
         "Personal assistant for the day-to-day: email triage, calendar, channel summaries, scheduled debriefs",
         "Weekly worklog as a long-arc context vault: people, programs, decisions, summaries"),
        ("Runs as",
         "Daemon + Slack bot on Dev Workspace; also via Claude Code",
         "A Claude Code skill, on-demand when you type /worklog"),
        ("Time horizon",
         '"What needs my attention right now?"',
         '"What have I been doing over the last quarter?"'),
        ("Storage",
         "Reads your existing email, calendar, Slack, etc.",
         "Writes a single Obsidian vault on disk"),
        ("Scheduled?",
         "Yes - daily / weekly debriefs on cron",
         "No - runs when you invoke it"),
    ]
    add_table(s, Inches(0.6), Inches(1.95), Inches(12.1), Inches(3.6),
              ["", "STRIDE", "obsidian-worklog"], rows,
              col_widths=[Inches(1.8), Inches(5.15), Inches(5.15)])
    add_text(s, Inches(0.6), Inches(5.85), Inches(12.1), Inches(1.2),
             "Common workflow: STRIDE summarizes your inbox and channels in the morning. You skim, decide what's worth keeping, and feed those bits into /worklog. The vault accumulates context-worth-keeping; STRIDE handles always-arriving stuff.",
             size=11, color=MUTED)
    add_footer(s)


def slide_prereqs():
    s = add_slide()
    add_section_tag(s, "Lab: Setup")
    add_title(s, "Setup: prerequisites")
    add_text(s, Inches(0.6), Inches(1.4), Inches(12), Inches(0.4),
             "Run through these before we move on. If anything's missing, flag it.",
             size=13, color=SUBTEXT)
    add_bullets(s, Inches(0.6), Inches(2.0), Inches(12), Inches(4.2), [
        "Claude Code installed (CLI, desktop, or IDE extension)",
        "Obsidian installed (any recent version)",
        "A directory for your vault (existing or new - setup will create the structure)",
        "newt on PATH:  command -v newt",
        "gh authed for github.netflix.net:  GH_HOST=github.netflix.net gh auth status",
        "Your @netflix.com git email handy",
    ], size=16, mark="[ ]")
    add_text(s, Inches(0.6), Inches(6.4), Inches(12), Inches(0.5),
             "Checkpoint: everything green? Speak up if not.",
             size=14, color=GREEN, bold=True)
    add_footer(s)


def slide_clone():
    s = add_slide()
    add_section_tag(s, "Lab: Setup")
    add_title(s, "Step 1 - clone")
    code = [
        "$ cd ~/workspace      # or wherever you keep your repos",
        "$ git clone https://github.netflix.net/mminutillo/obsidian-worklog",
        "$ cd obsidian-worklog",
    ]
    add_code_block(s, Inches(0.6), Inches(1.7), Inches(12.1), Inches(1.7),
                   code, size=15)
    add_text(s, Inches(0.6), Inches(3.7), Inches(12.1), Inches(2),
             "The public version at github.com/menottim/obsidian-worklog works too, but skips the Netflix commands (/worklog ingest, /worklog whois, /worklog jira) and the MCP profile auto-join. Use the Netflix fork unless you have a reason not to.",
             size=14, color=SUBTEXT)
    add_text(s, Inches(0.6), Inches(6.2), Inches(12), Inches(0.5),
             "Checkpoint: ls shows setup.sh, skills/, docs/, README.md",
             size=14, color=GREEN, bold=True)
    add_footer(s)


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
        "Backup repo URL [https://github.netflix.net/yourname/obsidian-vault.git]: ...",
        "Apply these settings? [Y/n]: y",
    ]
    add_code_block(s, Inches(0.6), Inches(1.6), Inches(12.1), Inches(5),
                   code, size=11)
    add_text(s, Inches(0.6), Inches(6.8), Inches(12), Inches(0.3),
             'Strict mode: any failed step aborts. "Setup complete!" only prints after every check passes.',
             size=11, color=MUTED)
    add_footer(s)


def slide_verify():
    s = add_slide()
    add_section_tag(s, "Lab: Setup")
    add_title(s, "What setup.sh checks")
    add_text(s, Inches(0.6), Inches(1.4), Inches(12), Inches(0.4),
             "All bash-callable. The script doesn't ask Claude anything during setup.",
             size=13, color=SUBTEXT)
    rows = [
        ("newt on PATH", "command -v newt"),
        ("genai-core-tools profile", "newt resolve | grep -q ... (auto-joins if missing)"),
        ("gh authed for GHE", "GH_HOST=github.netflix.net gh auth status"),
        ("Authoritative GHE login", "gh api user --jq .login (no whoami guessing)"),
        ("GHE backup repo exists", "gh repo view, with offer to gh repo create"),
        ("Install path safety", "Must start with $HOME/.claude/"),
        ("All placeholders replaced", "Literal grep -F against known list"),
        ("All values landed in SKILL.md", "Post-substitution presence check"),
        ("Plugin manifest installed", "File exists at install path"),
    ]
    add_table(s, Inches(0.6), Inches(1.95), Inches(12.1), Inches(5),
              ["Check", "Mechanism"], rows,
              col_widths=[Inches(4.5), Inches(7.6)])
    add_footer(s)


def slide_restart():
    s = add_slide()
    add_section_tag(s, "Lab: Setup")
    add_title(s, "Step 3 - restart and verify")
    items = [
        "Quit Claude Code fully (Cmd+Q on Mac). MCP servers load at session start, not mid-session.",
        "Reopen Claude Code.",
        "Type /mcp. Look for core-tools, plugin_atlassian, plugin_slack in the list.",
        'Type /worklog status. First run says "no current week" - that is expected.',
        "Type /worklog rollover. That creates your first weekly file.",
    ]
    add_numbered(s, Inches(0.6), Inches(1.7), Inches(12), Inches(4.5),
                 items, size=16)
    add_text(s, Inches(0.6), Inches(6.4), Inches(12), Inches(0.5),
             "Checkpoint: /worklog status now shows a week with no items.",
             size=14, color=GREEN, bold=True)
    add_footer(s)


def slide_monday():
    s = add_slide()
    add_section_tag(s, "Typical use")
    add_title(s, "How I use it Monday morning")
    add_text(s, Inches(0.6), Inches(1.5), Inches(7.5), Inches(0.4),
             "Takes about 10 minutes sitting down with coffee:",
             size=14, color=SUBTEXT)
    items = [
        "/worklog rollover - starts the new week, carries forward unfinished",
        "/worklog pull - reads new Slack threads from registered sources",
        "/worklog review - walks item by item: done / in progress / blocked",
        "/worklog sync - commits and pushes the vault",
    ]
    add_numbered(s, Inches(0.6), Inches(2.0), Inches(7.5), Inches(4),
                 items, size=14)
    add_card(s, Inches(8.4), Inches(1.9), Inches(4.4), Inches(4.5),
             title='What "review" looks like',
             body_bullets=[
                 '"done" - moves to done, archived on rollover',
                 '"still on it" - stays active, optional dated note',
                 '"pinged Sarah" - adds annotation, wiki-links her',
                 '"blocked on X" - flagged; audit surfaces stuck items',
             ])
    add_footer(s)


def slide_paste():
    s = add_slide()
    add_section_tag(s, "Typical use")
    add_title(s, "Mid-week: paste raw context, ask to log it")
    add_text(s, Inches(0.6), Inches(1.5), Inches(12), Inches(0.4),
             "Most of the time, I'm not typing commands. I'm pasting notes and asking Claude to add them.",
             size=14, color=SUBTEXT)
    code = [
        "here are notes from my 1:1 with Sarah:",
        "- she's concerned about the migration timeline slipping",
        "- wants to bring in a contractor for the gap",
        "- Marcus is doing well picking up Dev's work",
        "",
        "add to worklog",
    ]
    add_code_block(s, Inches(0.6), Inches(2.1), Inches(12.1), Inches(2.7),
                   code, size=14)
    add_text(s, Inches(0.6), Inches(5.1), Inches(12.1), Inches(2),
             "Claude extracts action items, wiki-links Sarah and Marcus (creates People stubs if they don't exist), adds dated annotations to the migration item, reports what changed. Slack threads and transcripts work the same way.",
             size=13, color=SUBTEXT)
    add_footer(s)


def slide_summaries():
    s = add_slide()
    add_section_tag(s, "Typical use")
    add_title(s, "End of week / month / quarter")
    add_text(s, Inches(0.6), Inches(1.6), Inches(5.8), Inches(0.4),
             "/worklog summary [period]", size=15, bold=True, color=TEXT)
    add_bullets(s, Inches(0.6), Inches(2.1), Inches(5.8), Inches(2.5), [
        "week - this week as a paragraph",
        "month - adds priority-drift notes",
        "quarter - adds trend bullets and time allocation",
        "2026-Q1 - or any specific period reference",
    ], size=13)
    add_text(s, Inches(0.6), Inches(4.6), Inches(5.8), Inches(0.8),
             "Writes to Summaries/, also puts a plain-text copy on the clipboard.",
             size=11, color=MUTED)

    add_text(s, Inches(6.9), Inches(1.6), Inches(5.8), Inches(0.4),
             "/worklog viz quarter", size=15, bold=True, color=TEXT)
    add_text(s, Inches(6.9), Inches(2.1), Inches(5.8), Inches(0.4),
             "Generates a standalone HTML with four D3 charts:",
             size=13, color=SUBTEXT)
    add_bullets(s, Inches(6.9), Inches(2.6), Inches(5.8), Inches(2.2), [
        "Time-allocation pie by subgroup",
        "Program activity heatmap",
        "P0 trend line over weeks",
        "Completion rate bars",
    ], size=13)
    add_text(s, Inches(6.9), Inches(5.1), Inches(5.8), Inches(0.8),
             "Open in a browser. I've used these for quarter-end share-outs.",
             size=11, color=MUTED)
    add_footer(s)


def slide_1on1():
    s = add_slide()
    add_section_tag(s, "Less obvious uses")
    add_title(s, "Pre-1:1 prep")
    add_text(s, Inches(0.6), Inches(1.5), Inches(12), Inches(0.4),
             "Before a 1:1, I'll usually do something like:",
             size=14, color=SUBTEXT)
    code = [
        "prep me for the 1:1 with [[Jane Smith]] tomorrow",
        "",
        "- pull the last 6 weeks where Jane appeared",
        "- flag anything that was in_progress 3+ weeks ago and is still open",
        "- surface anything from our last 1:1 that hasn't been addressed",
        "- highlight people in Jane's note I should ask about",
    ]
    add_code_block(s, Inches(0.6), Inches(2.1), Inches(12.1), Inches(2.5),
                   code, size=13)
    add_text(s, Inches(0.6), Inches(4.9), Inches(12.1), Inches(2),
             "Claude writes back a focused brief: items where she's mentioned, stuck items, open commitments, names in her note. The brief comes from your own writing - the LLM is organizing context you already wrote, not hallucinating it.",
             size=13, color=SUBTEXT)
    add_footer(s)


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
    add_code_block(s, Inches(0.6), Inches(1.7), Inches(12.1), Inches(2.5),
                   code, size=13)
    add_text(s, Inches(0.6), Inches(4.5), Inches(12.1), Inches(2.5),
             "Same idea as the 1:1 prep, longer horizon. You wrote the weeks for a different reason - now they're a corpus you can ask questions about. The output is a draft to edit, not a finished case. The structure shows up; the specifics still come from you.",
             size=13, color=SUBTEXT)
    add_footer(s)


def slide_ingest_demo():
    s = add_slide()
    add_section_tag(s, "Less obvious uses")
    add_title(s, "Ingest a Confluence/Coda doc")
    code = [
        "/worklog ingest https://confluence.netflix.com/display/SECURITY/Migration+Sync",
        "# or just",
        "/worklog https://confluence.netflix.com/display/SECURITY/Migration+Sync",
    ]
    add_code_block(s, Inches(0.6), Inches(1.6), Inches(12.1), Inches(1.5),
                   code, size=11)
    add_text(s, Inches(0.6), Inches(3.3), Inches(12), Inches(0.4),
             "What runs (either form):", size=13, color=SUBTEXT, bold=True)
    add_bullets(s, Inches(0.6), Inches(3.85), Inches(12), Inches(2.6), [
        "URL matches confluence.netflix.com -> skill calls mcp__core-tools__netflix_search_data",
        "Claude announces the tool ID it's about to call",
        "Fetches the page body, detects date + attendees + action items section",
        "Creates Meetings/2026-05-12-migration-sync.md",
        "Extracts action items, wiki-links attendees (resolves emails via Pandora)",
        "Adds items to the current week under the right subgroup",
    ], size=12)
    add_text(s, Inches(0.6), Inches(6.6), Inches(12.1), Inches(0.5),
             "Fetched body is treated as data, not instructions - injection attempts get flagged as suspicious content, not followed.",
             size=10, color=MUTED)
    add_footer(s)


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
    add_code_block(s, Inches(0.6), Inches(1.6), Inches(12.1), Inches(2.4),
                   code, size=12)
    add_text(s, Inches(0.6), Inches(4.2), Inches(5.8), Inches(0.4),
             "The People note becomes:", size=14, bold=True, color=TEXT)
    fm = [
        "---",
        "email: sarah.chen@netflix.com",
        "title: Senior Software Engineer",
        "team: Platform Infrastructure",
        'manager: "[[Alex Park]]"',
        "pandora_id: schen",
        "status: active",
        "---",
        "- [2026-05-13] Created from Pandora",
        "- [2026-05-13] First appeared in W19",
    ]
    add_code_block(s, Inches(0.6), Inches(4.7), Inches(6), Inches(2.3),
                   fm, size=10)
    add_text(s, Inches(6.95), Inches(4.2), Inches(5.8), Inches(2.8),
             'Anything that later mentions "Sarah Chen" - ingested meeting notes, Slack threads, Jira tickets - wiki-links to the same canonical note. After a few months, opening her note shows every week she came up.',
             size=13, color=SUBTEXT)
    add_footer(s)


def slide_other_uses():
    s = add_slide()
    add_section_tag(s, "Less obvious uses")
    add_title(s, "Other things people have done with it")
    card_w = Inches(3.95)
    card_h = Inches(2.4)
    pairs = [
        ("Incident debrief",
         "Ingest the incident-channel Slack thread, get a Meeting note with timeline and follow-ups linked to the current week."),
        ("Onboarding a new report",
         "Paste notes from each pre-onboarding meeting. Their People/ note has context from before week 1."),
        ("OKR allocation check",
         "Tag items with OKR labels. End of quarter: ask Claude what fraction of P0/P1 effort went to each."),
        ("Week-over-week diff",
         "Before a status update, ask: compare this week to last - what's new, what shifted, what's stuck."),
        ("Cross-team mapping",
         "Run /worklog whois on people you depend on. Builds a who-owns-what map across orgs."),
        ("Talk / conference prep",
         "Ingest the talk outline + related Coda research, get an action-itemized prep flow in the current week."),
    ]
    positions = [
        (Inches(0.5), Inches(1.6)),
        (Inches(4.7), Inches(1.6)),
        (Inches(8.9), Inches(1.6)),
        (Inches(0.5), Inches(4.2)),
        (Inches(4.7), Inches(4.2)),
        (Inches(8.9), Inches(4.2)),
    ]
    for (title, body), (left, top) in zip(pairs, positions):
        add_card(s, left, top, card_w, card_h, title=title, body=body)
    add_footer(s)


def slide_wrap():
    s = add_slide()
    add_section_tag(s, "Wrap")
    add_title(s, "Where we are")
    add_text(s, Inches(0.6), Inches(1.6), Inches(5.8), Inches(0.4),
             "Current state", size=16, bold=True, color=TEXT)
    add_bullets(s, Inches(0.6), Inches(2.1), Inches(5.8), Inches(3.5), [
        "Working install, verified by tests/e2e-setup.sh",
        "Three Netflix commands wired to MCPs you already have",
        "A vault directory",
        "A backup repo at github.netflix.net/yourname/obsidian-vault",
    ], size=14)
    add_text(s, Inches(6.9), Inches(1.6), Inches(5.8), Inches(0.4),
             "If you want to try it this week", size=16, bold=True, color=TEXT)
    add_bullets(s, Inches(6.9), Inches(2.1), Inches(5.8), Inches(3.5), [
        "Run /worklog rollover Monday",
        "Paste one meeting's notes into a conversation, ask Claude to add it",
        "Try /worklog whois on one person you work with",
        "Run /worklog summary week Friday and see what it produces",
    ], size=14)
    add_text(s, Inches(0.6), Inches(6.2), Inches(12.1), Inches(0.8),
             "Repo: github.netflix.net/mminutillo/obsidian-worklog  |  Docs: docs/SETUP-NETFLIX.md, docs/NETFLIX-COMMANDS.md  |  Test: tests/e2e-setup.sh",
             size=10, color=MUTED)


def slide_qa():
    s = add_slide()
    add_section_tag(s, "Wrap")
    add_text(s, Inches(0.6), Inches(2.6), Inches(12.1), Inches(2),
             "Questions?", size=72, bold=True, color=TEXT, align=PP_ALIGN.CENTER)
    add_text(s, Inches(0.6), Inches(4.5), Inches(12.1), Inches(0.6),
             "Or catch me afterwards if you hit something during setup.",
             size=18, color=SUBTEXT, align=PP_ALIGN.CENTER)
    add_text(s, Inches(0.6), Inches(6.4), Inches(12.1), Inches(0.4),
             "github.netflix.net/mminutillo/obsidian-worklog",
             size=12, color=MUTED, align=PP_ALIGN.CENTER)


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
