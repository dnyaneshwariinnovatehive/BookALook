"""Builds docs/BookALook-Google-Play-Publishing-Guide.pdf.

Run:  python -I scratch/play_guide/make_play_guide.py  (from the repo root)
"""
import os
import sys

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    BaseDocTemplate, CondPageBreak, Frame, KeepTogether, NextPageTemplate, PageBreak,
    PageTemplate, Paragraph, Preformatted, Spacer, Table, TableStyle,
)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'docs', 'BookALook-Google-Play-Publishing-Guide.pdf')

F = 'C:/Windows/Fonts/'
pdfmetrics.registerFont(TTFont('UI', F + 'segoeui.ttf'))
pdfmetrics.registerFont(TTFont('UI-B', F + 'segoeuib.ttf'))
pdfmetrics.registerFont(TTFont('UI-I', F + 'segoeuii.ttf'))
pdfmetrics.registerFont(TTFont('UI-SB', F + 'seguisb.ttf'))
pdfmetrics.registerFont(TTFont('Mono', F + 'consola.ttf'))
pdfmetrics.registerFont(TTFont('Sym', F + 'seguisym.ttf'))
pdfmetrics.registerFontFamily('UI', normal='UI', bold='UI-B', italic='UI-I', boldItalic='UI-B')

# ------------------------------------------------------------------ palette
ACCENT = colors.HexColor('#6D28D9')
ACCENT_SOFT = colors.HexColor('#F3EEFF')
INK = colors.HexColor('#1F1A2E')
BODY = colors.HexColor('#3B3550')
MUTED = colors.HexColor('#6B6580')
LINE = colors.HexColor('#E3DEEF')
CODE_BG = colors.HexColor('#F5F4F8')
KINDS = {
    'important': (colors.HexColor('#FDECEC'), colors.HexColor('#D93838'), 'IMPORTANT'),
    'tip': (colors.HexColor('#EAF7EF'), colors.HexColor('#1E9E57'), 'TIP'),
    'project': (ACCENT_SOFT, ACCENT, 'IN YOUR PROJECT'),
    'note': (colors.HexColor('#EEF4FD'), colors.HexColor('#2F6FD6'), 'GOOD TO KNOW'),
}

# ------------------------------------------------------------------ styles
BASE = ParagraphStyle('base', fontName='UI', fontSize=10, leading=15, textColor=BODY, spaceAfter=6)
S = {
    'body': BASE,
    'small': ParagraphStyle('small', parent=BASE, fontSize=8.8, leading=12.5, textColor=MUTED),
    'h1': ParagraphStyle('h1', parent=BASE, fontName='UI-B', fontSize=20, leading=25, textColor=INK, spaceAfter=4),
    'lead': ParagraphStyle('lead', parent=BASE, fontSize=11, leading=16.5, textColor=MUTED, spaceAfter=12),
    'h2': ParagraphStyle('h2', parent=BASE, fontName='UI-B', fontSize=13.5, leading=18, textColor=INK,
                         spaceBefore=12, spaceAfter=6, keepWithNext=1),
    'h3': ParagraphStyle('h3', parent=BASE, fontName='UI-SB', fontSize=11, leading=15, textColor=ACCENT,
                         spaceBefore=8, spaceAfter=4, keepWithNext=1),
    'cell': ParagraphStyle('cell', parent=BASE, fontSize=9, leading=12.5, spaceAfter=0),
    'cellb': ParagraphStyle('cellb', parent=BASE, fontName='UI-SB', fontSize=9, leading=12.5, spaceAfter=0,
                            textColor=INK),
    'th': ParagraphStyle('th', parent=BASE, fontName='UI-B', fontSize=9, leading=12, spaceAfter=0,
                         textColor=colors.white),
    'step': ParagraphStyle('step', parent=BASE, leftIndent=22, firstLineIndent=0, spaceAfter=5),
    'bullet': ParagraphStyle('bullet', parent=BASE, leftIndent=14, spaceAfter=3),
    'code': ParagraphStyle('code', fontName='Mono', fontSize=8.6, leading=12, textColor=INK),
    'callout': ParagraphStyle('callout', parent=BASE, fontSize=9.4, leading=14, spaceAfter=3),
    'calloutTitle': ParagraphStyle('calloutTitle', parent=BASE, fontName='UI-B', fontSize=8, leading=10,
                                   spaceAfter=3),
    'check': ParagraphStyle('check', parent=BASE, leftIndent=18, spaceAfter=3, fontSize=9.6, leading=14),
}

W = A4[0] - 40 * mm  # content width


def P(text, style='body'):
    return Paragraph(text, S[style])


def code(text):
    return Preformatted(text.strip('\n'), S['code'])


def mono(text):
    return f'<font name="Mono" size="9">{text}</font>'


def H1(num, title, lead=None):
    badge = Table([[Paragraph(f'<font color="white"><b>{num}</b></font>',
                              ParagraphStyle('n', fontName='UI-B', fontSize=13, alignment=TA_CENTER, leading=16))]],
                  colWidths=[11 * mm], rowHeights=[11 * mm])
    badge.setStyle(TableStyle([('BACKGROUND', (0, 0), (-1, -1), ACCENT), ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                               ('ROUNDEDCORNERS', [6, 6, 6, 6])]))
    head = Table([[badge, P(title, 'h1')]], colWidths=[15 * mm, W - 15 * mm])
    head.setStyle(TableStyle([('VALIGN', (0, 0), (-1, -1), 'MIDDLE'), ('LEFTPADDING', (0, 0), (-1, -1), 0)]))
    out = [head, Spacer(1, 4)]
    if lead:
        out.append(P(lead, 'lead'))
    return out


def callout(kind, *paras, title=None):
    bg, edge, label = KINDS[kind]
    inner = [Paragraph(f'<font color="{edge.hexval()}">{title or label}</font>', S['calloutTitle'])]
    for p in paras:
        inner.append(p if not isinstance(p, str) else P(p, 'callout'))
    t = Table([[inner]], colWidths=[W])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), bg), ('LINEBEFORE', (0, 0), (0, -1), 3, edge),
        ('LEFTPADDING', (0, 0), (-1, -1), 12), ('RIGHTPADDING', (0, 0), (-1, -1), 12),
        ('TOPPADDING', (0, 0), (-1, -1), 8), ('BOTTOMPADDING', (0, 0), (-1, -1), 6),
    ]))
    return KeepTogether([Spacer(1, 4), t, Spacer(1, 8)])


def steps(items, start=1):
    out = []
    for i, it in enumerate(items, start):
        out.append(Paragraph(f'<font name="UI-B" color="{ACCENT.hexval()}">{i}.</font>&nbsp; {it}',
                             ParagraphStyle('st', parent=S['step'], firstLineIndent=-16, leftIndent=18)))
    return out


def bullets(items):
    return [Paragraph(f'<font color="{ACCENT.hexval()}">•</font>&nbsp; {it}',
                      ParagraphStyle('bl', parent=S['bullet'], firstLineIndent=-10, leftIndent=14)) for it in items]


def checks(items):
    return [Paragraph(f'<font name="Sym" size="11">\u2610</font>&nbsp; {it}',
                      ParagraphStyle('ck', parent=S['check'], firstLineIndent=-16, leftIndent=18)) for it in items]


def table(rows, widths, header=True, zebra=True):
    data = []
    for r, row in enumerate(rows):
        cells = []
        for c, cell in enumerate(row):
            if isinstance(cell, str):
                style = 'th' if (header and r == 0) else ('cellb' if c == 0 else 'cell')
                cells.append(Paragraph(cell, S[style]))
            else:
                cells.append(cell)
        data.append(cells)
    t = Table(data, colWidths=[w * W for w in widths], repeatRows=1 if header else 0)
    st = [
        ('VALIGN', (0, 0), (-1, -1), 'TOP'), ('GRID', (0, 0), (-1, -1), 0.5, LINE),
        ('LEFTPADDING', (0, 0), (-1, -1), 7), ('RIGHTPADDING', (0, 0), (-1, -1), 7),
        ('TOPPADDING', (0, 0), (-1, -1), 5), ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
    ]
    if header:
        st.append(('BACKGROUND', (0, 0), (-1, 0), ACCENT))
    if zebra:
        for r in range(1 if header else 0, len(rows)):
            if r % 2 == 0:
                st.append(('BACKGROUND', (0, r), (-1, r), colors.HexColor('#FAF8FE')))
    t.setStyle(TableStyle(st))
    return t


def codebox(text):
    t = Table([[code(text)]], colWidths=[W])
    t.setStyle(TableStyle([('BACKGROUND', (0, 0), (-1, -1), CODE_BG), ('BOX', (0, 0), (-1, -1), 0.5, LINE),
                           ('LEFTPADDING', (0, 0), (-1, -1), 10), ('TOPPADDING', (0, 0), (-1, -1), 7),
                           ('BOTTOMPADDING', (0, 0), (-1, -1), 7)]))
    return KeepTogether([t, Spacer(1, 8)])


def paste(title, text):
    """A ready-to-copy text block."""
    body = [Paragraph(f'<font color="{ACCENT.hexval()}">{title}</font>', S['calloutTitle'])]
    for line in text.strip().split('\n\n'):
        body.append(P(line.replace('\n', '<br/>'), 'callout'))
    t = Table([[body]], colWidths=[W])
    t.setStyle(TableStyle([('BOX', (0, 0), (-1, -1), 0.8, ACCENT), ('BACKGROUND', (0, 0), (-1, -1), colors.white),
                           ('LEFTPADDING', (0, 0), (-1, -1), 12), ('RIGHTPADDING', (0, 0), (-1, -1), 12),
                           ('TOPPADDING', (0, 0), (-1, -1), 8), ('BOTTOMPADDING', (0, 0), (-1, -1), 6)]))
    return [t, Spacer(1, 10)]


# ------------------------------------------------------------------ page chrome
def on_page(c, doc):
    c.saveState()
    c.setFont('UI', 8)
    c.setFillColor(MUTED)
    c.drawString(20 * mm, A4[1] - 12 * mm, 'BookALook  ·  Publishing on Google Play')
    c.drawRightString(A4[0] - 20 * mm, A4[1] - 12 * mm, 'Prepared 15 November 2026')
    c.setStrokeColor(LINE)
    c.line(20 * mm, A4[1] - 14 * mm, A4[0] - 20 * mm, A4[1] - 14 * mm)
    c.drawRightString(A4[0] - 20 * mm, 10 * mm, f'Page {doc.page}')
    c.restoreState()


def on_cover(c, doc):
    c.saveState()
    c.setFillColor(ACCENT)
    c.rect(0, A4[1] - 100 * mm, A4[0], 100 * mm, fill=1, stroke=0)
    c.setFillColor(colors.HexColor('#8B5CF6'))
    c.circle(A4[0] - 30 * mm, A4[1] - 25 * mm, 38 * mm, fill=1, stroke=0)
    c.setFillColor(ACCENT)
    c.circle(A4[0] - 30 * mm, A4[1] - 25 * mm, 24 * mm, fill=1, stroke=0)
    c.setFillColor(colors.white)
    c.setFont('UI-SB', 11)
    c.drawString(22 * mm, A4[1] - 32 * mm, 'BOOKALOOK  ·  STEP-BY-STEP GUIDE')
    c.setFont('UI-B', 32)
    c.drawString(22 * mm, A4[1] - 50 * mm, 'Publishing your apps')
    c.drawString(22 * mm, A4[1] - 64 * mm, 'on Google Play')
    c.setFont('UI', 12.5)
    c.drawString(22 * mm, A4[1] - 78 * mm, 'From a signed app file to "Live on the Play Store" —')
    c.drawString(22 * mm, A4[1] - 85 * mm, 'internal testing, closed testing and production, explained simply.')
    c.restoreState()


# ------------------------------------------------------------------ content
story = []
A = story.append
X = story.extend

# ---- cover body
A(NextPageTemplate('normal'))
A(Spacer(1, 86 * mm))
cover_rows = [
    ['App', 'Package name (permanent)', 'Play listing name'],
    ['Customer app', mono('com.bookalook.customer_app'), 'BookALook'],
    ['Partner (salon) app', mono('com.bookalook.partner_app'), 'BookALook Partner'],
]
A(table(cover_rows, [0.28, 0.42, 0.30]))
A(Spacer(1, 10))
A(P('<b>Who this is for:</b> you, publishing an app on Google Play for the first time. Every step says '
    '<i>where to click</i>, <i>what to type</i> and <i>why</i>. Wherever your project needs something specific, '
    'there is a purple <b>In your project</b> box.', 'body'))
A(P('<b>How to use it:</b> work through the chapters in order, once for the Customer app and once for the '
    'Partner app. The checklist in Appendix A lets you tick off each app separately.', 'body'))
A(Spacer(1, 8))
toc = [
    ['Chapter', 'What it covers'],
    ['1  The big picture', 'The journey, testing tracks, the 12-tester rule, timeline'],
    ['2  Before you start', 'Accounts, information and images to collect'],
    ['3  Fix the blockers', 'Signing key, reviewer login, website, notifications'],
    ['4  Build the app file', 'Create and test the .aab file Google needs'],
    ['5  Set up the app', 'Every "App content" question, answered for BookALook'],
    ['6  Store listing', 'Name, descriptions, screenshots, category'],
    ['7  Internal testing', 'Your first upload, tested by your own team'],
    ['8  Closed testing', '12+ testers for 14 days, then apply for production'],
    ['9  Production', 'Going live, staged rollout'],
    ['10  After launch', 'SuperAdmin links, updates, monitoring'],
    ['11  If Google rejects', 'Common reasons and fixes'],
    ['A / B / C', 'Checklist, ready-to-paste text, glossary'],
]
toc_t = table(toc, [0.32, 0.68])
toc_t.setStyle(TableStyle([('TOPPADDING', (0, 0), (-1, -1), 3), ('BOTTOMPADDING', (0, 0), (-1, -1), 3)]))
A(toc_t)
A(PageBreak())

# =================================================================== 1
X(H1('1', 'The big picture', 'Publishing is not one button. Google wants to see that your app is tested, '
     'safe and honest about the data it uses. Here is the whole journey.'))
journey = [
    ['Stage', 'What happens', 'Who sees the app'],
    ['Prepare', 'Signing key, release build, App content forms, store listing', 'Nobody yet'],
    ['Internal testing', 'Upload your first app file and test it on your own phones', 'Up to 100 people you list'],
    ['Closed testing', 'At least 12 testers use it for 14 days in a row (personal accounts)',
     'Only invited testers'],
    ['Apply for production', 'Answer Google\'s questions about your test', 'Google reviewers'],
    ['Production', 'Release to the public, step by step (staged rollout)', 'Everyone in India'],
]
A(table(journey, [0.22, 0.50, 0.28]))

A(P('What are "testing tracks"?', 'h2'))
A(P('A <b>track</b> is a separate lane for an app version. Each track has its own list of people who can '
    'install it. The same app can have version 1.0.2 in internal testing while 1.0.1 is on production. '
    'Think of them as rings around your app: your team, then invited friends, then everyone.'))
tracks = [
    ['Track', 'Who can install', 'Google review', 'Use it for'],
    ['Internal testing', 'Up to 100 Gmail addresses you add', 'Very light; usually ready in minutes',
     'Checking every build on real phones before anyone else sees it'],
    ['Closed testing', 'Only people you invite (email list or Google Group)', 'Yes, full review (hours to a few days)',
     'The required 14-day test with 12+ testers, and wider feedback'],
    ['Open testing', 'Anyone who finds the "test" listing', 'Yes', 'Public beta. You can skip this.'],
    ['Production', 'Everyone in the countries you choose', 'Yes, full review (hours to 7 days)', 'The real launch'],
]
A(table(tracks, [0.18, 0.27, 0.25, 0.30]))
A(callout('note', 'Testers install the app from the <b>real Play Store</b>, not from a file you send them. '
          'They first accept an invitation link (called <b>opting in</b>), then install it like any other app. '
          'Their Play Store shows the app as "(Internal beta)" or "(Beta)".'))

A(P('The 12 testers × 14 days rule', 'h2'))
A(P('Google wants new developers to test properly before launching. If your developer account is a '
    '<b>personal</b> account created after 13 November 2023, you <b>cannot publish to production</b> until:'))
X(bullets([
    'a <b>closed test</b> has run with <b>at least 12 testers who opted in</b>,',
    'those testers stayed opted in for <b>14 days in a row</b>, and',
    'you then fill in the <b>"Apply for production"</b> form and Google approves it.',
]))
A(P('<b>Organization</b> accounts (registered as a company, with a D-U-N-S number) do not have this rule; '
    'they can go from internal testing straight to production.'))
A(callout('important', '<b>Check your account type first.</b> Play Console → <b>Settings</b> (gear icon, '
          'bottom left) → <b>Developer account</b> → <b>About you / Account details</b>. It says '
          '<b>Personal</b> or <b>Organization</b>. If it is personal, plan for the 14-day test. '
          'The rule applies to <b>each app separately</b>: the Customer app and the Partner app each need their own '
          '12 testers for 14 days. The same people can test both apps.'))

A(P('How long will it take?', 'h2'))
timeline = [
    ['When', 'What you do', 'Waiting on'],
    ['Days 1–2', 'Chapters 2–6: fix signing, build, fill in App content and store listing', 'You'],
    ['Day 2', 'Chapter 7: internal test, check the app on your own phones', 'You'],
    ['Days 2–4', 'Chapter 8: start closed test; Google reviews it', 'Google (usually 1–3 days)'],
    ['Days 4–18', '14 days with 12+ opted-in testers using the app', 'The calendar'],
    ['Day 18', 'Apply for production', 'Google (usually up to 7 days)'],
    ['~Day 25', 'Chapter 9: production release and review', 'Google (hours to 7 days)'],
]
A(table(timeline, [0.16, 0.58, 0.26]))
A(P('Expect about <b>3–4 weeks</b> on a personal account and about <b>1 week</b> on an organization account. '
    'Both apps can go through the steps at the same time.', 'small'))
A(PageBreak())

# =================================================================== 2
X(H1('2', 'Before you start', 'Collect all of this first. Most delays come from a missing image or an '
     'unanswered form, not from the app itself.'))
A(P('Accounts and access', 'h2'))
X(checks([
    'Google Play Console developer account, identity <b>verified</b> (you already created both apps, so this is done).',
    'A real <b>Android phone</b> signed in with a Gmail you can add as a tester.',
    'The <b>Gmail addresses of at least 12 testers</b> (aim for 15–20; some will forget to opt in). '
    'Friends, family, staff, and a few salon owners for the Partner app.',
    'Access to the <b>production server</b> settings (the backend <font name="Mono">.env</font> file) for the reviewer login.',
]))
A(P('Information you will type in', 'h2'))
info = [
    ['Item', 'Value for BookALook'],
    ['Support email (shown publicly)', mono('bookalook01@gmail.com')],
    ['Website', mono('https://bookalook.in')],
    ['Privacy policy URL', mono('https://bookalook.in/privacy')],
    ['Account deletion URL', mono('https://bookalook.in/delete-account')],
    ['Terms', mono('https://bookalook.in/terms')],
    ['Phone number (optional, public)', 'Leave blank unless you want customers to call it'],
    ['Price', '<b>Free</b> (a free app can never be changed to paid later)'],
    ['Countries', '<b>India</b> (add more later anytime)'],
]
A(table(info, [0.38, 0.62]))
A(P('Images you must prepare (for each app)', 'h2'))
imgs = [
    ['Image', 'Exact requirement', 'Tip'],
    ['App icon', '512 × 512 px, PNG (32-bit, transparency allowed), max 1 MB',
     'Same artwork as the icon on the phone; no extra text or badges'],
    ['Feature graphic', '1024 × 500 px, JPG or PNG <b>without</b> transparency, max 15 MB',
     'Banner at the top of the listing: logo + one short line, e.g. "No waiting. Just booking."'],
    ['Phone screenshots', '2 to 8 images. JPG or PNG without transparency. Each side 320–3840 px; '
     'long side no more than 2× the short side',
     'Take them on a real phone (1080 × 1920 portrait is ideal). Show real screens: home, salon page, '
     'booking, QR check-in'],
    ['Tablet screenshots', 'Optional', 'Skip unless you design for tablets'],
]
A(table(imgs, [0.2, 0.42, 0.38]))
A(callout('tip', 'Screenshots must show the real app. You can add a short caption above each one '
          '(for example "Book in 3 taps"), but don\'t show features the app does not have and don\'t use words '
          'like "best" or "#1". Google rejects misleading listings.'))
A(PageBreak())

# =================================================================== 3
X(H1('3', 'Fix the blockers in your project', 'These were found by checking your actual code. Fix them '
     'before building, or the upload or review will fail.'))
blockers = [
    ['#', 'Problem', 'Effect if not fixed', 'Where'],
    ['3.1', 'Release builds are signed with the <b>debug key</b>', 'Play Console <b>refuses the upload</b>',
     'Both apps'],
    ['3.2', 'No reviewer login set up on the live server', 'Google can\'t log in → <b>rejected</b>',
     'Backend .env'],
    ['3.3', 'Policy pages must be live on bookalook.in', 'Links in the forms don\'t work → <b>rejected</b>',
     'Website'],
    ['3.4', 'Partner app has no Firebase setup', 'Salons get <b>no push notifications</b>', 'Partner app'],
]
A(table(blockers, [0.07, 0.38, 0.33, 0.22]))

A(P('3.1  Create an upload key and sign the release build', 'h2'))
A(P('Every app on Play is signed with a digital key, like a wax seal proving the update really came from you. '
    'There are two keys:'))
X(bullets([
    '<b>Upload key</b>: you create it and keep it. You sign every file you upload with it.',
    '<b>App signing key</b>: Google creates and keeps it safely (<b>Play App Signing</b>, turned on '
    'automatically on your first upload). Phones see this one.',
]))
A(P('Right now both apps\' <font name="Mono">android/app/build.gradle.kts</font> say '
    '<font name="Mono">signingConfig = signingConfigs.getByName("debug")</font>. Google rejects debug-signed '
    'files. Do this once per app:'))
A(P('Step 1: make a safe folder for keys (outside the code folder)', 'h3'))
A(codebox(r'mkdir C:\Users\Admin\bookalook-keys'))
A(P('Step 2: create the key (Customer app shown; repeat with "partner" for the Partner app)', 'h3'))
A(P('Open <b>Command Prompt</b> and run the line below. If Windows says <i>keytool is not recognised</i>, '
    'use the full path: <font name="Mono">"C:\\Program Files\\Android\\Android Studio\\jbr\\bin\\keytool.exe"</font>.'))
A(codebox('keytool -genkey -v ^\n'
          '  -keystore C:\\Users\\Admin\\bookalook-keys\\customer-upload.jks ^\n'
          '  -keyalg RSA -keysize 2048 -validity 10000 -alias upload'))
A(P('The <font name="Mono">^</font> at the end of a line means "continued on the next line" in Command Prompt. '
    'You can also type it all on one line without the ^ marks.', 'small'))
A(P('It asks for a password (type it twice) and your name/company/city/country code (IN). '
    'Write the password down in a password manager.'))
A(P('Step 3: tell Flutter where the key is', 'h3'))
A(P('Create the file <font name="Mono">Customer App/android/key.properties</font> (and the same in the '
    'Partner App folder, pointing at partner-upload.jks):'))
A(codebox('storePassword=YOUR_PASSWORD\nkeyPassword=YOUR_PASSWORD\nkeyAlias=upload\n'
          'storeFile=C:/Users/Admin/bookalook-keys/customer-upload.jks'))
A(P('Step 4: use it in the release build', 'h3'))
A(P('In <font name="Mono">android/app/build.gradle.kts</font> of each app, add this at the very top:'))
A(codebox('import java.util.Properties\nimport java.io.FileInputStream\n\n'
          'val keystoreProperties = Properties()\n'
          'val keystorePropertiesFile = rootProject.file("key.properties")\n'
          'if (keystorePropertiesFile.exists()) {\n'
          '    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n}'))
A(P('Then inside the <font name="Mono">android { ... }</font> block, add a release signing config and use it:'))
A(codebox('signingConfigs {\n    create("release") {\n'
          '        keyAlias = keystoreProperties["keyAlias"] as String\n'
          '        keyPassword = keystoreProperties["keyPassword"] as String\n'
          '        storeFile = keystoreProperties["storeFile"]?.let { file(it) }\n'
          '        storePassword = keystoreProperties["storePassword"] as String\n    }\n}\n\n'
          'buildTypes {\n    release {\n'
          '        signingConfig = signingConfigs.getByName("release")   // was "debug"\n    }\n}'))
A(P('Step 5: keep secrets out of Git', 'h3'))
A(P('Add these two lines to each app\'s <font name="Mono">android/.gitignore</font>:'))
A(codebox('key.properties\n*.jks'))
A(callout('important', '<b>Back up the .jks files and passwords</b> (for example a USB drive plus a private '
          'cloud folder). If you lose the upload key you can\'t publish updates until Google resets it: '
          'Play Console → Test and release → <b>App integrity</b> → <b>Request upload key reset</b>. '
          'That takes a few days. Never share the key or password with anyone.'))
A(callout('tip', 'Claude can make the code changes in steps 3–5 for you. You only need to run step 2 '
          'yourself so the password stays with you.'))

A(P('3.2  Give Google\'s reviewers a way to log in', 'h2'))
A(P('Both apps log in with a WhatsApp OTP. A Google reviewer can\'t receive your WhatsApp messages, so your '
    'backend has a special login just for store review: listed phone numbers always accept one fixed code '
    'and no WhatsApp message is sent.'))
X(steps([
    'Pick a 10-digit number that no real customer or salon uses (a spare number you own is best).',
    'Pick a 6-digit code, for example a random one like 482917 (not 123456).',
    'On the <b>production server</b>, open the backend <font name="Mono">.env</font> file and set:',
]))
A(codebox('OTP_REVIEW_PHONES=9XXXXXXXXX\nOTP_REVIEW_CODE=482917'))
X(steps([
    'Reload the settings: run <font name="Mono">php artisan config:cache</font> in the backend folder on the server.',
    '<b>Test it yourself</b> on the Customer app: log in with that number and code.',
    '<b>Partner app:</b> the same number must own an <b>approved salon</b>. Register a salon with that number in the '
    'Partner app (for example "BookALook Review Salon"), add a few services and staff, then approve it in '
    'SuperAdmin → Salon Approval Queue. Log in once to check the dashboard opens.',
], start=4))
A(callout('project', 'The review login only works while <b>both</b> settings are filled in. Keep them set '
          'for as long as the apps are on Play, because Google re-checks some updates. The demo salon may show up '
          'in customer search, so give it a clearly-test name or hide it if SuperAdmin lets you.'))

A(P('3.3  Make sure the website pages are live', 'h2'))
A(P('Deploy the website, then open each link on your phone and check it loads:'))
X(checks([mono('https://bookalook.in/privacy'), mono('https://bookalook.in/terms'),
          mono('https://bookalook.in/delete-account'), mono('https://bookalook.in/partner-terms')]))

A(P('3.4  Push notifications for the Partner app', 'h2'))
A(P('The Customer app is connected to your Firebase project <font name="Mono">salon-notification-19fb5</font>. '
    'The Partner app only has placeholder Firebase settings, so salons won\'t get booking notifications. '
    'This doesn\'t block publishing, but salons will miss bookings. To fix: Firebase console → your project → '
    '<b>Add app</b> → Android → package <font name="Mono">com.bookalook.partner_app</font> → download '
    '<font name="Mono">google-services.json</font> and put it in <font name="Mono">Partner App/android/app/</font>. '
    'Then ask Claude to finish wiring it in.'))
A(PageBreak())

# =================================================================== 4
X(H1('4', 'Build the app file (.aab)', 'Google needs an Android App Bundle (.aab), not an .apk. '
     'You build it on your computer and upload it in Chapter 7.'))
A(P('4.1  Check the version number', 'h2'))
A(P('In each app\'s <font name="Mono">pubspec.yaml</font> you will find <font name="Mono">version: 1.0.0+1</font>.'))
A(table([
    ['Part', 'Name on Play', 'Rule'],
    ['1.0.0', 'Version name', 'What users see. Change it as you like: 1.0.1, 1.1.0, 2.0.0.'],
    ['+1', 'Version code', '<b>Must be higher on every upload</b>, even a test upload. Play never accepts the same '
     'number twice, even if you delete the release.'],
], [0.12, 0.2, 0.68]))
A(callout('tip', 'Every time you upload again, add 1 to the number after the "+": 1.0.0+1 → 1.0.0+2 → 1.0.1+3. '
          'If Play says "Version code 1 has already been used", this is why.'))
A(P('4.2  First test a release build on your phone', 'h2'))
A(P('A release build can behave differently from what you test in debug mode. Connect your phone with USB '
    '(USB debugging on), then from the app folder run:'))
A(codebox('cd "C:\\Users\\Admin\\Desktop\\All websites\\InnovateHive\\BookALook\\Customer App"\n'
          'flutter build apk --release\nflutter install --release'))
A(P('Open the app and check that login, search, booking, payment, the QR code and notifications work against '
    'the live server.'))
A(P('4.3  Build the .aab', 'h2'))
A(codebox('flutter build appbundle --release'))
A(P('The file is created at <font name="Mono">build\\app\\outputs\\bundle\\release\\app-release.aab</font>. '
    'Repeat in the <font name="Mono">Partner App</font> folder. If the build fails with a signing error, recheck '
    'the key.properties paths and passwords from 3.1.'))
A(callout('project', 'Both apps already target <b>Android 16 (API level 36)</b>, which meets Google\'s current '
          'requirement. Google raises this every year around August, so plan a small update each year. Both apps '
          'call the live server <font name="Mono">https://api.bookalook.in/api</font> from their '
          '<font name="Mono">.env</font> file, which is correct for release.'))
A(PageBreak())

# =================================================================== 5
X(H1('5', 'Set up the app: "App content"', 'Open Play Console → choose the app → <b>Dashboard</b>. Under '
     '"Set up your app" there is a list of tasks. Most are in <b>Policy and programs → App content</b>. '
     'Every task must show a green tick before you can release. Below is each one, with BookALook\'s answer.'))

A(P('5.1  Privacy policy', 'h2'))
A(P('Enter <font name="Mono">https://bookalook.in/privacy</font> (same for both apps). Save.'))

A(P('5.2  App access', 'h2'))
A(P('Choose <b>"All or some functionality in my app is restricted"</b> → <b>Add instructions</b>. Fill in the '
    'name, the phone number as username, the OTP code as password, and paste the instructions from '
    '<b>Appendix B</b>. Tick "No other information is required".'))

A(P('5.3  Ads', 'h2'))
A(P('<b>No, my app does not contain ads.</b> Neither app has an advertising library.'))

A(P('5.4  Content rating', 'h2'))
A(P('Click <b>Start questionnaire</b>. Email: bookalook01@gmail.com. Category: <b>"All other app types"</b>. '
    'Answer as below, then <b>Save</b> → <b>Submit</b>. You get ratings for every region, typically '
    '<b>3+ / Everyone</b>.'))
A(table([
    ['Question (short form)', 'Answer'],
    ['Violence, fear, sexual content, bad language, drugs, gambling', 'No to all'],
    ['Do users interact or exchange content? (reviews are public text)',
     '<b>Yes</b> for the Customer app (salon reviews are visible to others). Partner app: <b>No</b>, '
     'unless salons can post public content.'],
    ['Does the app share the user\'s current location with other users?', 'No'],
    ['Does the app let users buy digital goods?', 'No (salon services are real-world services)'],
    ['Is the app a web browser or search engine?', 'No'],
], [0.6, 0.4]))

A(P('5.5  Target audience and content', 'h2'))
X(bullets([
    'Target age groups: tick <b>18 and over</b> only. Your Terms say users must be able to make legal transactions.',
    '"Could your store listing unintentionally appeal to children?" → <b>No</b>.',
]))

A(P('5.6  The short declarations', 'h2'))
A(table([
    ['Declaration', 'Answer for both apps'],
    ['News apps', 'No, it is not a news app'],
    ['Government apps', 'No'],
    ['Financial features', '"My app doesn\'t provide any financial features" (taking payment for a salon booking '
     'through Razorpay is not a financial feature such as loans, banking or crypto)'],
    ['Health apps', 'My app does not have any health features'],
    ['Advertising ID', '<b>No</b>, the app does not use advertising ID'],
], [0.3, 0.7]))

A(P('5.7  Data safety (the most important form)', 'h2'))
A(P('Google shows these answers publicly on your listing. They must match your Privacy Policy and what the app '
    'really does. Data that an SDK inside your app collects (Razorpay, Firebase) counts as collected by you.'))
A(P('Page 1: Data collection and security', 'h3'))
A(table([
    ['Question', 'Answer'],
    ['Does your app collect or share any of the required user data types?', 'Yes'],
    ['Is all user data encrypted in transit?', 'Yes (all traffic uses HTTPS)'],
    ['Account creation method', 'Phone number with OTP ("Username and other authentication" / "OTP")'],
    ['Can users request that their data is deleted?', 'Yes, with URL <font name="Mono">https://bookalook.in/delete-account</font>'],
], [0.55, 0.45]))
A(P('Page 2: Data types: Customer app', 'h3'))
A(table([
    ['Data type (Play\'s name)', 'Collected?', 'Required?', 'Why (purposes)'],
    ['Personal info → Name', 'Yes', 'Required', 'App functionality, Account management'],
    ['Personal info → Phone number', 'Yes', 'Required', 'App functionality, Account management'],
    ['Personal info → Email address', 'Yes', 'Optional', 'Account management, Developer communications'],
    ['Personal info → Address', 'Yes', 'Optional', 'App functionality'],
    ['Personal info → Other info (date of birth)', 'Yes', 'Optional', 'App functionality, Personalization'],
    ['Location → Approximate and Precise location', 'Yes', 'Optional', 'App functionality (nearby salons)'],
    ['Financial info → Payment info', 'Yes (Razorpay)', 'Optional', 'App functionality (online payment)'],
    ['Financial info → Purchase history', 'Yes', 'Required', 'App functionality (bookings and refunds)'],
    ['App activity → Other user-generated content', 'Yes', 'Optional', 'App functionality (reviews, complaints)'],
    ['Device or other IDs', 'Yes (push token)', 'Required', 'App functionality (notifications)'],
], [0.38, 0.15, 0.13, 0.34]))
A(P('Page 2: Data types: Partner app', 'h3'))
A(table([
    ['Data type (Play\'s name)', 'Collected?', 'Required?', 'Why (purposes)'],
    ['Personal info → Name, Phone number, Email address', 'Yes', 'Required', 'App functionality, Account management'],
    ['Personal info → Address (salon address)', 'Yes', 'Required', 'App functionality'],
    ['Location → Approximate and Precise location', 'Yes', 'Optional', 'App functionality (salon location pin)'],
    ['Photos and videos → Photos', 'Yes', 'Optional', 'App functionality (salon and service photos)'],
    ['Financial info → Other financial info (bank details for payouts)', 'Yes', 'Optional',
     'App functionality (paying the salon)'],
    ['Financial info → Purchase history', 'Yes', 'Required', 'App functionality (plans, dues, settlements)'],
    ['Device or other IDs', 'Yes (push token)', 'Required', 'App functionality (notifications)'],
], [0.38, 0.15, 0.13, 0.34]))
A(callout('note', '<b>"Shared" vs "collected":</b> for every data type Play asks whether it is <i>shared</i>. '
          'Answer <b>No</b> where the data only goes to your service providers (Razorpay, Firebase, the WhatsApp '
          'provider, your hosting) or to the salon the customer chose to book. Google doesn\'t count those as '
          'sharing. For each type also answer: <b>processed ephemerally?</b> No (it is stored), except location '
          'in the Customer app if it is only used for the search and not saved.'))
A(callout('project', 'The camera in the Partner app only scans QR codes and nothing is saved, so it is not '
          'listed. Neither app has crash-reporting or analytics libraries, so "App info and performance" is not '
          'collected. If you add Firebase Crashlytics or Analytics later, update this form.'))
A(P('5.8  Permissions', 'h2'))
A(P('Your apps use <b>location</b> (only while open), <b>camera</b> (Partner) and <b>notifications</b>. None of '
    'these need an extra Play declaration. You will only see a permissions form if Play detects a sensitive one '
    '(background location, SMS, all-files access); your apps have none of them.'))
A(P('5.9  Account deletion', 'h2'))
A(P('Covered in the Data safety form. Both apps also meet the in-app rule: the Customer app has '
    '<b>Profile → Delete Account</b>, and the Partner app has <b>More → Delete Account</b>, which explains the '
    'request process.'))
A(PageBreak())

# =================================================================== 6
X(H1('6', 'Store listing', 'Play Console → <b>Grow users → Store presence → Main store listing</b>. '
     'This is your shop window. Ready-made text is in Appendix B.'))
A(table([
    ['Field', 'Limit', 'Customer app', 'Partner app'],
    ['App name', '30 characters', 'BookALook: Salon Booking', 'BookALook Partner'],
    ['Short description', '80 characters', 'See Appendix B', 'See Appendix B'],
    ['Full description', '4000 characters', 'See Appendix B', 'See Appendix B'],
    ['App icon', '512 × 512', 'Customer icon', 'Partner icon'],
    ['Feature graphic', '1024 × 500', 'Required', 'Required'],
    ['Phone screenshots', '2–8', 'Home, salon page, booking, QR, bookings', 'Dashboard, appointments, QR scan, services'],
], [0.2, 0.17, 0.32, 0.31]))
A(P('Store settings', 'h2'))
A(P('Play Console → <b>Store presence → Store settings</b>:'))
X(bullets([
    '<b>App or game:</b> App.',
    '<b>Category:</b> Customer app → <b>Beauty</b>. Partner app → <b>Business</b>.',
    '<b>Tags:</b> optional. Pick up to 5 that fit (for example Salon, Beauty services, Appointments).',
    '<b>Contact details:</b> email bookalook01@gmail.com, website https://bookalook.in. These are public.',
]))
A(callout('important', 'Avoid these in names and descriptions (common rejection reasons): "best", "#1", "free" '
          'in the name, emojis in the name, lists of keywords, other brands\' names, prices or promotions that may '
          'change, and features that aren\'t in the app yet.'))
A(PageBreak())

# =================================================================== 7
X(H1('7', 'Internal testing: your first upload', 'This is where your .aab first goes onto Google Play. '
     'Only people on your list can see it. It is the safe place to catch problems.'))
A(P('7.1  Create the testers list', 'h2'))
X(steps([
    'Play Console → choose the app → <b>Test and release → Testing → Internal testing</b>.',
    'Open the <b>Testers</b> tab → <b>Create email list</b>. Name it "BookALook team".',
    'Add the Gmail addresses (yours and your team\'s, up to 100) → <b>Save changes</b>.',
    'Tick the list so it is attached to this track. Also set a <b>Feedback URL or email</b> (bookalook01@gmail.com).',
]))
A(P('7.2  Upload the build', 'h2'))
X(steps([
    'Open the <b>Releases</b> tab → <b>Create new release</b>.',
    'The first time only: Play asks about <b>app signing</b>. Choose <b>"Use Google-generated key"</b> '
    '(the default). This is Play App Signing.',
    'Under <b>App bundles</b>, upload <font name="Mono">app-release.aab</font> from Chapter 4. Wait until it '
    'finishes processing.',
    '<b>Release name</b> fills in automatically (for example "1 (1.0.0)"). You can keep it.',
    '<b>Release notes</b>: short text testers see, for example "First test version".',
    'Click <b>Next</b>. Read any errors (red, must fix) and warnings (yellow, can usually continue).',
    'Click <b>Save and publish</b> (or <b>Start rollout to Internal testing</b>).',
]))
A(P('7.3  Testers install the app', 'h2'))
X(steps([
    'Back on the <b>Testers</b> tab, find <b>"How testers join your test"</b> → <b>Copy link</b>.',
    'Send that link to your testers (WhatsApp is fine).',
    'Each tester opens it <b>on their phone, signed in with the Gmail you added</b>, taps <b>Accept invite / '
    'Become a tester</b>, then <b>Download it on Google Play</b>.',
    'It can take a few minutes up to a couple of hours after the first upload before the app appears.',
]))
A(callout('tip', 'If a tester sees "App not available": check they used the same Gmail as on the list. If their '
          'phone has several Google accounts, they should switch the Play Store to that account. Then wait 15 '
          'minutes and try again.'))
A(P('7.4  What to test (both apps)', 'h2'))
X(checks([
    'Install, open, log in with OTP; log out and back in.',
    'Customer: find salons near you, open a salon, book (Pay at Store and one small online payment), get the WhatsApp '
    'confirmation, see the booking, cancel and reschedule, see the QR in the last 15 minutes before the slot.',
    'Partner: log in, see the booking arrive (and the notification once Firebase is set up), scan the customer\'s QR, '
    'complete the appointment, edit services and staff.',
    'Links in Profile/More: Terms, Privacy, Refund policy, Delete account all open.',
    'Login with the <b>reviewer number</b> works on the Play-installed app.',
    '<b>In-app update test:</b> upload a second build (1.0.0+2), set it as latest in SuperAdmin → App Versions, '
    'open the app and check the update flow.',
]))
A(callout('note', 'After each upload Play runs an automatic <b>pre-launch report</b> on real test devices '
          '(Test and release → <b>Pre-launch report</b>). It lists crashes, layout problems and security warnings. '
          'Fix anything marked as an error.'))
A(PageBreak())

# =================================================================== 8
X(H1('8', 'Closed testing: the 14-day test', 'Needed for personal developer accounts. This is a real test '
     'with real users, and Google checks that it really happened.'))
A(P('8.1  Set up the closed track', 'h2'))
X(steps([
    'Play Console → <b>Test and release → Testing → Closed testing</b>. A track called <b>"Closed testing - Alpha"</b> '
    'already exists; click <b>Manage track</b>.',
    '<b>Countries/regions</b> tab → add <b>India</b>.',
    '<b>Testers</b> tab → choose <b>Email list</b> → create "BookALook closed testers" → add <b>at least 15</b> Gmail '
    'addresses (12 is the minimum that must stay opted in; extras protect you if someone drops out). '
    'Add a feedback email → <b>Save</b>.',
    '<b>Releases</b> tab → <b>Create new release</b> → <b>Add from library</b> to reuse the build already tested '
    'internally, or upload a newer one.',
    'Add release notes → <b>Next</b> → <b>Save</b>.',
    'Go to <b>Publishing overview</b> (left menu) → <b>Send changes for review</b>. The first review usually takes '
    '1–3 days and can take up to 7.',
]))
A(P('8.2  Get testers in and keep them in', 'h2'))
X(steps([
    'After approval, copy the opt-in link from the <b>Testers</b> tab and send it to everyone.',
    'Each tester must <b>accept the invite</b> and <b>install</b> the app. The 14 days count from the moment the '
    '12th tester opts in.',
    'Ask them to <b>stay opted in and keep the app installed</b> for the full 14 days, and to open it every few days. '
    'Real use counts; Google can see engagement.',
    'Watch progress: <b>Dashboard</b> shows "X of 12 testers opted in" and how many days remain.',
]))
A(callout('important', 'If testers leave and the count drops below 12, the 14 days start again. Use people who '
          'will really cooperate. Don\'t use paid "tester exchange" services that install and never open the app; '
          'Google looks for real engagement and may refuse production access.'))
A(callout('tip', 'Collect feedback (a WhatsApp group works well) and publish at least one improved build to the '
          'closed track during the 14 days. Google asks what you changed based on feedback, and a real update makes '
          'that answer easy and honest.'))
A(KeepTogether([
    P('8.3  Apply for production access', 'h2'),
    P('When the 14 days are done, the Dashboard shows <b>"Apply for production"</b>. The form has three parts; '
      'sample answers to adapt are in Appendix B.'),
    table([
        ['Part', 'What Google asks'],
        ['About your closed test', 'How you recruited testers, how easy it was, how they used the app, '
         'what feedback you got'],
        ['About your app', 'Who it is for, what value it gives, how many installs you expect in year one'],
        ['Production readiness', 'What you changed after testing, and how you decided it is ready'],
    ], [0.3, 0.7]),
    Spacer(1, 8),
    P('Answer specifically and honestly; short or copy-paste answers are a common reason for refusal. Google '
      'usually replies within 7 days by email. If refused, the email says why: run the test longer or with more '
      'active testers, then apply again.'),
]))
A(PageBreak())

# =================================================================== 9
X(H1('9', 'Production: going live', 'Once production access is granted (or straight away on an '
     'organization account), you can release to everyone.'))
A(P('9.1  Create the production release', 'h2'))
X(steps([
    'Play Console → <b>Test and release → Production</b> → <b>Countries/regions</b> tab → add <b>India</b>.',
    '<b>Releases</b> tab → <b>Create new release</b> → <b>Add from library</b> → pick the build that passed testing.',
    'Release notes ("What\'s new"), for example "Welcome to BookALook! Find salons near you and book in seconds."',
    'Click <b>Next</b>. Under rollout percentage, choose a <b>staged rollout</b> of <b>20%</b>. You can go to '
    '100% later.',
    '<b>Save</b> → <b>Publishing overview</b> → <b>Send changes for review</b>.',
]))
A(callout('tip', '<b>Managed publishing</b> (Publishing overview → turn on) holds an approved release until '
          'you click <b>Publish</b>. Useful if you want to launch both apps on the same day.'))
A(P('9.2  Review and rollout', 'h2'))
X(bullets([
    'Production reviews take from a few hours up to 7 days. You get an email when it is done.',
    'When it says <b>Available on Google Play</b>, open the Play Store on your phone and search for the app. '
    'Search can take a day or two to show a new app, but the direct link works straight away.',
    'Watch <b>Android vitals</b> (crashes, freezes) and reviews for 1–2 days, then increase the rollout: '
    'Production → Releases → <b>Update rollout</b> → 50% → 100%.',
    'If something serious appears, <b>Halt rollout</b> stops new installs while you fix it.',
]))
A(P('9.3  Your public links', 'h2'))
A(codebox('https://play.google.com/store/apps/details?id=com.bookalook.customer_app\n'
          'https://play.google.com/store/apps/details?id=com.bookalook.partner_app'))
A(PageBreak())

# =================================================================== 10
X(H1('10', 'After launch', 'Once both apps are live at 100%.'))
A(P('10.1  Connect the links in SuperAdmin', 'h2'))
X(steps([
    '<b>SuperAdmin → App Versions</b> → Customer App → <b>New release</b>: Version 1.0.0, build 1, status '
    '<b>Live</b> → Record release.',
    'In <b>Update rule</b>: latest = v1.0.0, choose <b>Remind them</b>, click <b>Use Customer App link</b> → '
    '<b>Save rule</b>.',
    'Switch to <b>Partner App</b> and repeat with <b>Use Partner App link</b>.',
    '<b>SuperAdmin → Policy Settings</b> → "Salon QR codes &amp; the app" → <b>Play Store link</b> = the Customer '
    'link → Save changes.',
    'Check the website download buttons open the right listings.',
]))
A(P('10.2  Every future update', 'h2'))
X(steps([
    'Raise the version in <font name="Mono">pubspec.yaml</font> (for example 1.0.0+1 → 1.0.1+2).',
    '<font name="Mono">flutter build appbundle --release</font>.',
    'Upload to <b>Internal testing</b> and check it on your phone.',
    'Promote to <b>Production</b> as a staged rollout (20% → 50% → 100%). Updates don\'t need the 14-day test again.',
    'At 100%: SuperAdmin → App Versions → <b>New release</b> → it becomes the latest → users get the update '
    'reminder in the app.',
    'Block older versions only for serious problems, and only after the rollout is at 100%.',
]))
A(P('10.3  Keep the account healthy', 'h2'))
X(bullets([
    'Reply to Play Console emails about policy within their deadline.',
    'Reply to user reviews: it helps your rating and shows the app is maintained.',
    'Each year around August, Google raises the required Android target level. Update Flutter, rebuild and '
    'publish an update before the deadline.',
    'If you change what data the apps collect (for example adding analytics), update <b>Data safety</b> and the '
    'Privacy Policy <b>before</b> releasing that version.',
    'Log in to Play Console now and then; long-inactive developer accounts can be closed.',
]))
A(PageBreak())

# =================================================================== 11
X(H1('11', 'If Google rejects your app', 'Rejections are normal and fixable. You get an email and a '
     'message in Play Console → <b>Policy status</b> explaining the reason. Fix it, upload a new build if '
     'needed, and send for review again.'))
A(table([
    ['Message you may see', 'What it means', 'Fix'],
    ['Login credentials / App access', 'The reviewer couldn\'t log in', 'Check OTP_REVIEW_PHONES/CODE on the '
     'server; for Partner, the demo salon must be approved; update App access instructions'],
    ['Invalid Privacy Policy', 'Link broken, or the policy doesn\'t mention the app or its data',
     'Open bookalook.in/privacy on a phone; it must load without login'],
    ['Data safety mismatch', 'The form doesn\'t match what the app or its SDKs collect',
     'Compare with Chapter 5.7; declare what Razorpay and Firebase collect'],
    ['Broken functionality', 'Crash, blank screen, or a feature that doesn\'t work',
     'Check the pre-launch report and test the release build on a phone; make sure the server is up'],
    ['Metadata policy', 'Name or description has keywords, "best", emojis, misleading claims',
     'Rewrite plainly (use Appendix B)'],
    ['Account deletion', 'No clear way to delete an account',
     'Point to Profile → Delete Account and bookalook.in/delete-account'],
    ['Production access not granted', 'Closed test too weak',
     'More active testers, a real update during testing, more detailed answers; apply again'],
    ['"Version code already used"', 'Same build number as an earlier upload', 'Raise the +number in pubspec.yaml'],
    ['"Signed in debug mode"', 'Upload key not set up', 'Chapter 3.1'],
], [0.25, 0.33, 0.42]))
A(callout('tip', 'If you think a rejection is a mistake, use the <b>Appeal</b> link in the email and explain '
          'calmly with steps to reproduce. Most first-app problems are fixed faster by simply correcting and '
          'resubmitting.'))
A(PageBreak())

# =================================================================== Appendix A
X(H1('A', 'Master checklist', 'Tick each item for each app: first box = Customer app, second box = Partner app.'))
CHECKS = [
    ('Before', ['Account type checked (personal / organization)', '12–20 tester Gmail addresses collected',
                'Icon 512×512, feature graphic 1024×500, 2–8 screenshots ready',
                'Website pages live (privacy, terms, delete-account)']),
    ('Project', ['Upload key created and backed up', 'key.properties + gradle signing set, secrets git-ignored',
                 'Reviewer phone + code set on the server and tested', 'Partner demo salon approved (Partner app)',
                 'Partner Firebase set up (recommended)', 'Release build tested on a phone',
                 '.aab built (version code higher than any upload before)']),
    ('App content', ['Privacy policy', 'App access (reviewer instructions)', 'Ads: No', 'Content rating submitted',
                     'Target audience: 18+', 'News / Government / Financial / Health declarations',
                     'Advertising ID: No', 'Data safety submitted']),
    ('Listing', ['Name, short and full description', 'Icon, feature graphic, screenshots',
                 'Category, contact details']),
    ('Testing', ['Internal test published and installed by the team', 'Pre-launch report checked',
                 'Closed test approved, 12+ testers opted in', '14 days completed, an update published during testing',
                 'Production access applied and granted']),
    ('Launch', ['Production release at 20% → 50% → 100%', 'SuperAdmin App Versions: release recorded + link',
                'Policy Settings Play link', 'Website buttons checked']),
]
for group, items in CHECKS:
    A(P(group, 'h3'))
    rows = [[Paragraph('<font name="Sym" size="11">\u2610   \u2610</font>', S['cell']), P(i, 'cell')] for i in items]
    t = Table(rows, colWidths=[0.1 * W, 0.9 * W])
    t.setStyle(TableStyle([('LINEBELOW', (0, 0), (-1, -1), 0.4, LINE), ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                           ('TOPPADDING', (0, 0), (-1, -1), 1.5), ('BOTTOMPADDING', (0, 0), (-1, -1), 1.5)]))
    A(t)
A(PageBreak())

# =================================================================== Appendix B
X(H1('B', 'Ready-to-paste text', 'Replace the parts in [square brackets]. Check the character counts in '
     'Play Console. It shows a counter under each field.'))
CUST_SHORT = 'Book salon appointments near you. Pick a time, skip the wait, check in by QR.'
PART_SHORT = "Manage your salon's bookings, staff and services, and get found by customers."
assert len(CUST_SHORT) <= 80 and len(PART_SHORT) <= 80, (len(CUST_SHORT), len(PART_SHORT))
X(paste(f'CUSTOMER APP: SHORT DESCRIPTION ({len(CUST_SHORT)}/80)', CUST_SHORT))
X(paste('CUSTOMER APP: FULL DESCRIPTION', """
BookALook helps you book salon and grooming appointments without the wait. Find salons near you, see their services and prices, choose a time that suits you, and walk in when it is your turn.

What you can do:
• Discover salons, barbershops and grooming studios near you
• See services, prices, photos and opening hours before you book
• Choose your date and time slot and get instant confirmation
• Pay online securely, or pay at the salon
• Get booking confirmations and reminders on WhatsApp
• Check in at the salon with your booking's QR code
• Cancel or reschedule up to 90 minutes before your appointment
• Rate and review salons after your visit

BookALook connects you with independent salon partners. Each salon provides its own services at the prices shown in the app.

Questions or help: bookalook01@gmail.com
"""))
X(paste(f'PARTNER APP: SHORT DESCRIPTION ({len(PART_SHORT)}/80)', PART_SHORT))
X(paste('PARTNER APP: FULL DESCRIPTION', """
BookALook Partner is the app for salons, barbershops and grooming studios listed on BookALook. Run your daily appointments from your phone and reach new customers nearby.

With BookALook Partner you can:
• See new and upcoming bookings in one place
• Accept bookings and keep your schedule free of double bookings
• Check customers in by scanning their booking QR code
• Manage your services, prices, staff and opening hours
• Add photos that show customers your salon
• Track your plan, payments and settlements

To use the app, register your salon. The BookALook team reviews and approves new salons before they appear to customers.

Questions or help: bookalook01@gmail.com
"""))
X(paste('APP ACCESS: CUSTOMER APP (Play Console → App content → App access)', """
The app signs in with a one-time code (OTP) normally sent on WhatsApp. For review, please use this test number. It always accepts the code below, and no message is sent.

Phone number: [10-digit review number]
OTP code: [6-digit review code]

Steps: open the app, enter the phone number, tap Send OTP, enter the code. You can then browse salons, open a salon, book an appointment (please choose "Pay at Store" to avoid a real payment), view it under Bookings, and delete the account from Profile → Delete Account.
"""))
X(paste('APP ACCESS: PARTNER APP', """
The app is for registered salon owners and signs in with a one-time code (OTP) normally sent on WhatsApp. For review, please use this test number. It belongs to an approved demo salon, "[demo salon name]".

Phone number: [10-digit review number]
OTP code: [6-digit review code]

After signing in you can see the dashboard and appointments, manage services and staff, and scan customer QR codes from the check-in screen. Account deletion steps are under More → Delete Account.
"""))
X(paste('APPLY FOR PRODUCTION: SAMPLE ANSWERS (make them true to your test)', """
How did you recruit testers? We invited [number] people: our team, friends and family who regularly visit salons, and [number] salon owners in [city] who plan to use BookALook. We shared the opt-in link on WhatsApp and set up a WhatsApp group for feedback.

How did testers use the app? Testers searched for salons, made real bookings with Pay at Store and online payment, cancelled and rescheduled bookings, and checked in at partner salons with the QR code. Salon testers received bookings, scanned QR codes and updated their services and staff.

What feedback did you receive and what did you change? [Example: testers found the time-slot list hard to scroll and asked for clearer refund status. We redesigned the slot picker, added refund status to booking details, and fixed a crash on Android 10. These were released to testers as version 1.0.1.]

Who is the app for and what value does it give? Adults in India who want to book salon visits without waiting in a queue. It shows real services and prices and confirms a time slot in advance.

Expected installs in the first year: [your honest estimate, e.g. 1,000–10,000].

Why is it ready for production? All main flows (login, search, booking, payments, cancellation, QR check-in) were used by testers over 14 days with no open crashes in Android vitals or the pre-launch report.
"""))
A(PageBreak())

# =================================================================== Appendix C
X(H1('C', 'Words you will see', 'A plain-language glossary.'))
A(table([
    ['Term', 'Meaning'],
    ['AAB (Android App Bundle)', 'The .aab file you upload. Google turns it into the right install file for each phone.'],
    ['APK', 'The install file a phone uses. You only build one yourself to test on your own phone.'],
    ['Package name', 'Permanent ID of the app (com.bookalook.customer_app). Can never change after the first upload.'],
    ['Version code', 'The number after "+" in pubspec.yaml. Must go up on every upload.'],
    ['Version name', 'The visible version like 1.0.1.'],
    ['Upload key', 'Your private key that signs the files you upload. Keep it safe and backed up.'],
    ['Play App Signing', 'Google keeps the final signing key, so a lost upload key can be reset.'],
    ['Track', 'A lane for releases: internal, closed, open, production.'],
    ['Opt in', 'A tester accepting the invite link so the Play Store lets them install a test version.'],
    ['Release', 'One version sent to one track, with release notes.'],
    ['Staged rollout', 'Giving an update to a percentage of users first (20% → 100%).'],
    ['Halt rollout', 'Stopping a staged rollout if something goes wrong.'],
    ['Pre-launch report', 'Google\'s automatic test of your build on real devices.'],
    ['Android vitals', 'Crash and freeze statistics from real users in Play Console.'],
    ['IARC', 'The international age-rating system behind the Content rating questionnaire.'],
    ['Data safety', 'The public summary of what data your app collects and why.'],
    ['Managed publishing', 'Holds approved changes until you click Publish.'],
], [0.3, 0.7]))
A(Spacer(1, 14))
A(callout('note', 'Google changes Play Console menus and limits from time to time. If a button has moved, '
          'search for its name in the Play Console search bar at the top, or check Google\'s help page '
          '"Play Console Help". The steps and order in this guide stay the same.'))


# ------------------------------------------------------------------ build
def build():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    doc = BaseDocTemplate(OUT, pagesize=A4, leftMargin=20 * mm, rightMargin=20 * mm, topMargin=20 * mm,
                          bottomMargin=18 * mm, title='Publishing BookALook on Google Play',
                          author='Bookalook Private Limited', subject='Step-by-step Google Play publishing guide')
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id='f')
    doc.addPageTemplates([PageTemplate('cover', [frame], onPage=on_cover),
                          PageTemplate('normal', [frame], onPage=on_page)])
    doc.build(story)
    print('wrote', OUT)


if __name__ == '__main__':
    build()
    sys.exit(0)
