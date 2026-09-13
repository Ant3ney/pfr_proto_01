"""Create the editable vector inserts and their Blender texture copies."""
from pathlib import Path
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "cover_art"
OUT.mkdir(exist_ok=True)
RED = "#e60012"
INK = "#202126"


def text(x, y, value, size=24, color=INK, extra=""):
    return f'<text x="{x}" y="{y}" font-family="Noto Sans, sans-serif" font-size="{size}" fill="{color}" {extra}>{value}</text>'


def line(x1, y1, x2, y2, color=INK, width=2):
    return f'<path d="M{x1} {y1} L{x2} {y2}" fill="none" stroke="{color}" stroke-width="{width}"/>'


def logo(x, y, scale=1, label=True):
    mark = '''<g fill="none" stroke="white" stroke-width="9">
      <path d="M70 8 H43 Q13 8 13 38 V87 Q13 116 43 116 H70 Z"/>
      <path d="M86 8 H109 Q139 8 139 38 V87 Q139 116 109 116 H86 Z" fill="white" stroke="none"/>
      <circle cx="43" cy="42" r="12" fill="white" stroke="none"/>
      <circle cx="110" cy="82" r="12" fill="#e60012" stroke="none"/>
    </g>'''
    if label:
        mark += text(76, 146, "NINTENDO", 16, "white", 'text-anchor="middle" letter-spacing="3" font-weight="700"')
        mark += text(76, 177, "SWITCH", 31, "white", 'text-anchor="middle" letter-spacing="2" font-weight="800"')
    return f'<g transform="translate({x} {y}) scale({scale})">{mark}</g>'


def rating(x, y, scale=1):
    return f'''<g transform="translate({x} {y}) scale({scale})">
      <rect width="128" height="164" fill="white" stroke="{INK}" stroke-width="5"/>
      <rect x="4" y="4" width="120" height="26" fill="{INK}"/>
      {text(64, 23, 'RATING PENDING', 12, 'white', 'text-anchor="middle" font-weight="700"')}
      {text(64, 113, 'RP', 76, INK, 'text-anchor="middle" font-weight="900" letter-spacing="-7"')}
      {line(4, 130, 124, 130)}
      {text(64, 151, 'PLACEHOLDER', 12, INK, 'text-anchor="middle" font-weight="700"')}
    </g>'''


def svg(name, width, height, body):
    source = OUT / f"{name}.svg"
    source.write_text(f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<title>Editable {name.replace('_', ' ')} insert</title>
<rect width="100%" height="100%" fill="#fbfbf8"/>
{body}
</svg>''')
    subprocess.run(["rsvg-convert", "-w", str(width * 2), "-h", str(height * 2), str(source), "-o", str(OUT / f"{name}.png")], check=True)


# Intentionally loose vector lettering echoes the hand-drawn reference.
front = f'<rect width="235" height="225" fill="{RED}"/>' + logo(48, 22, .92)
front += '''<g fill="none" stroke="#242529" stroke-width="12" stroke-linecap="round" stroke-linejoin="round">
  <path d="M734 265 Q751 228 756 220 M792 278 Q812 247 819 238 M681 294 Q678 372 743 389 Q802 404 839 345" stroke-width="8"/>
  <g transform="translate(106 362) rotate(-3)">
    <path d="M0 0 L71 134 L136 17 M71 134 L48 228"/>
    <path d="M212 120 C136 93 126 208 193 219 C257 240 281 130 212 120 Z"/>
    <path d="M300 122 L292 189 Q294 244 345 213 L375 136 M375 136 L365 223"/>
    <path d="M421 149 L416 229 M420 171 Q440 116 485 156"/>
  </g>
  <g transform="translate(99 724) rotate(-2)">
    <path d="M184 25 C103 -32 -11 24 3 149 C16 268 143 287 202 223 L202 160 L119 158"/>
    <path d="M340 116 C254 79 229 248 298 257 Q352 264 363 180 M357 120 L355 264"/>
    <path d="M413 129 L404 276 M410 184 Q444 94 485 148 L497 269 M490 179 Q544 112 575 163 L590 274"/>
    <path d="M636 210 Q768 203 724 148 C689 107 623 147 630 215 Q636 288 738 266"/>
  </g>
  <g transform="translate(149 1080) rotate(-2)" stroke="#e60012" stroke-width="16">
    <path d="M0 0 L-5 248 M106 -1 L104 244 M-1 113 L105 110"/>
    <path d="M232 5 L167 2 L159 246 L233 248 M164 113 L221 112"/>
    <path d="M291 247 L295 1 Q402 -8 399 72 Q397 130 293 127 M312 126 L409 251"/>
    <path d="M522 7 L456 3 L452 249 L530 251 M456 117 L514 115"/>
    <path d="M612 9 L608 191 M608 238 L608 248"/>
  </g>
  <g stroke="#ed6871" stroke-width="6">
    <path d="M102 1099 L76 1082 M88 1153 L51 1144 M78 1215 L42 1213 M83 1274 L53 1284 M99 1331 L77 1351 M166 1371 L155 1400 M254 1377 L251 1409 M345 1383 L350 1416 M438 1380 L451 1411 M534 1381 L553 1410 M630 1387 L649 1415 M718 1385 L741 1411 M799 1359 L823 1377"/>
  </g>
</g>'''
front += rating(42, 1450, .90)
front += text(977, 1589, "YOUR STUDIO", 20, "#77797c", 'text-anchor="end" letter-spacing="3"')
svg("front_cover", 1030, 1650, front)

spine = f'<rect width="100" height="1650" fill="{RED}"/>' + logo(18, 38, .42, False)
spine += '<g transform="translate(34 528) rotate(90)">' + text(0, 0, "YOUR AWESOME GAME!", 36, "white", 'font-weight="500" letter-spacing="1.1"') + '</g>'
spine += '<g transform="translate(42 1495) rotate(90)">' + text(0, 0, "HAC-P-00000", 14, "white", 'letter-spacing="1"') + '</g>'
svg("spine_cover", 100, 1650, spine)

back = '<g font-family="DejaVu Sans Mono, monospace" fill="#27292c" font-size="88">'
for y, words in [(118, "Your back"), (224, "cover art"), (330, "goes here.")]:
    back += f'<text x="47" y="{y}">{words}</text>'
back += '</g>'
back += text(52, 410, "Make room for your next great adventure.", 26, "#717578")

# Retail-style information band; every content field is a template placeholder.
for x, w in [(40, 195), (239, 185), (428, 185), (617, 373)]:
    back += f'<rect x="{x}" y="1072" width="{w}" height="55" fill="#292b2d"/>'
    back += f'<rect x="{x}" y="1127" width="{w}" height="39" fill="white" stroke="#949698" stroke-width="2"/>'
back += text(137, 1108, "PLAY MODE", 22, "white", 'text-anchor="middle" font-weight="700"')
back += text(137, 1153, "PLAYERS", 19, INK, 'text-anchor="middle"')
# Screen / tabletop / handheld line icons.
back += '<g fill="none" stroke="white" stroke-width="4"><rect x="298" y="1083" width="64" height="30" rx="2"/><path d="M330 1113 V1119 M310 1119 H350"/><rect x="491" y="1085" width="58" height="29" rx="2"/><path d="M539 1115 L550 1120"/><rect x="714" y="1085" width="66" height="29" rx="3"/><path d="M727 1085 V1114 M767 1085 V1114"/></g>'
back += text(331, 1153, "1–4", 23, INK, 'text-anchor="middle"')
back += text(520, 1153, "1–2", 23, INK, 'text-anchor="middle"')
back += text(747, 1153, "1", 23, INK, 'text-anchor="middle"')
back += text(878, 1108, "HANDHELD", 19, "white", 'text-anchor="middle"')
back += f'<rect x="40" y="1186" width="950" height="81" fill="#fff5f4" stroke="#cb8a8b" stroke-width="2"/>'
back += f'<path d="M69 1201 L91 1246 H47 Z" fill="{RED}"/>'
back += text(69, 1237, "!", 31, "white", 'text-anchor="middle" font-weight="800"')
back += text(110, 1214, "IMPORTANT INFORMATION", 19, RED, 'font-weight="700"')
back += text(110, 1244, "Replace this area with the game’s notices and compatibility details.", 20, "#8d686b")
back += f'<rect x="40" y="1285" width="950" height="140" fill="none" stroke="#aeb0b1" stroke-width="2"/>'
for y, words in [(1316, "Add your game description, publisher details and required notices here."),
                 (1344, "This is an editable cover-art mockup. Artwork, product information,"),
                 (1372, "player counts and rating shown are placeholders for your design."),
                 (1400, "Front, back and spine artwork can be replaced independently.")]:
    back += text(56, y, words, 21, "#5a5e61")
back += rating(43, 1445, .98)
back += text(189, 1481, "RATING", 20, INK, 'font-weight="700"')
back += text(189, 1511, "PENDING", 20, INK, 'font-weight="700"')
back += text(189, 1545, "Your content", 20, "#77797c")
back += text(189, 1573, "descriptors here", 20, "#77797c")
back += f'<rect x="503" y="1447" width="184" height="158" fill="none" stroke="#aeb0b1" stroke-width="2"/>'
back += text(595, 1480, "YOUR STUDIO", 20, INK, 'text-anchor="middle" font-weight="700"')
back += text(595, 1514, "LOGO", 22, "#878a8c", 'text-anchor="middle"')
back += text(595, 1580, "HAC-P-00000", 16, "#77797c", 'text-anchor="middle"')
back += f'<rect x="706" y="1447" width="284" height="158" fill="white" stroke="#aeb0b1" stroke-width="2"/>'
rng = random.Random(7)
x = 727
while x < 971:
    w = rng.choice((2, 2, 3, 4, 6))
    back += f'<rect x="{x}" y="1464" width="{w}" height="104" fill="#25272a"/>'
    x += w + rng.choice((2, 3, 4))
back += text(848, 1591, "0  00000  00000  0", 18, INK, 'text-anchor="middle" letter-spacing="2"')
svg("back_cover", 1030, 1650, back)
print(f"Created editable SVG inserts and PNG textures in {OUT}")
