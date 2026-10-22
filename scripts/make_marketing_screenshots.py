#!/usr/bin/env python3
"""App Store 마케팅 스크린샷: 원본 캡처 + 헤드라인 → 헤드리스 Chrome (appstore-assets 스킬 방식).

사용법: python3 scripts/make_marketing_screenshots.py [ko en ...]   (없으면 전부)

원본    docs/screenshots/raw/<언어>/0N-….png         아이폰 6.9" 캡처(1320×2868, 게임방법(봇과 연습) 모드)
제출본  docs/screenshots/marketing/<스토어 로케일>/0N-….png        1242×2688

바탕·글자색은 제품 페이지 헤더(make_creative_assets.py)와 같다: 밤하늘 그라데이션 + 달빛 노랑.
"""
import subprocess, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "screenshots" / "raw"
OUT = ROOT / "docs" / "screenshots" / "marketing"
WORK = pathlib.Path("/tmp") / "moonlit-marketing"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
STORE = {"ko": "ko", "en": "en-US", "en-GB": "en-GB"}

# (원본 파일, 헤드라인, 서브카피) — 언어마다 따로 쓴다.
SHOTS = {
    "ko": [
        ("01-home.png",   "모이면 바로<br>파티게임 시작", "인터넷 없이 가까운 아이폰끼리 연결돼요"),
        ("02-role.png",   "내 역할은<br>나만 알아요", "숨어든 그림자를 찾는 정체 추리, 달빛 결사"),
        ("03-vote.png",   "찬성일까,<br>반대일까", "모두의 표가 공개되는 순간 판이 뒤집혀요"),
        ("04-draw.png",   "그리고<br>맞히고", "한 명이 그리면 나머지가 맞히는 달빛 화실"),
        ("05-result.png", "빨리 맞힐수록<br>높은 점수", "최대 15명까지 함께 즐겨요"),
    ],
    "en": [
        ("01-home.png",   "Gather round,<br>start a party game", "Nearby iPhones connect with no internet"),
        ("02-role.png",   "Only you<br>know your role", "Find the hidden Shadows in Moonlit Order"),
        ("03-vote.png",   "Approve<br>or reject?", "The moment everyone's votes are revealed, the game flips"),
        ("04-draw.png",   "Draw it,<br>guess it", "One draws, the rest guess, in Moonlit Studio"),
        ("05-result.png", "Guess faster,<br>score higher", "Play with up to 15 friends"),
    ],
    "en-GB": [
        ("01-home.png", "Gather round,<br>start a party game", "Nearby iPhones connect with no internet"),
        ("02-role.png", "Only you<br>know your role", "Find the hidden Shadows in Moonlit Order"),
        ("03-vote.png", "Approve<br>or reject?", "The moment everyone's votes are revealed, the game flips"),
        ("04-draw.png", "Draw it,<br>guess it", "One draws, the rest guess, in Moonlit Studio"),
        ("05-result.png", "Guess faster,<br>score higher", "Play with up to 15 friends"),
    ],
}

DEVICES = {
    # 이름: (캔버스, 기기 폭, 기기 top, 모서리, 테두리, 파일 접두사, 원본 하위 폴더)
    "iphone": ((1242, 2688), 900, 820, 112, 24, "", ""),
}

CSS = """
* { margin:0; padding:0; box-sizing:border-box; }
html,body { width:%(W)dpx; height:%(H)dpx; overflow:hidden; }
body { background:linear-gradient(180deg,#0F1226 0%%,#21173D 100%%); position:relative;
  font-family:-apple-system, "SF Pro Display", "Apple SD Gothic Neo", sans-serif; }
.glow { position:absolute; left:50%%; top:%(GT)dpx; width:%(GW)dpx; height:%(GW)dpx; margin-left:-%(GH)dpx;
  border-radius:50%%; filter:blur(200px); background:rgba(242,199,89,.16); }
.t { position:absolute; left:80px; right:80px; top:%(TT)dpx; text-align:center; }
.headline { font-size:%(HS)dpx; font-weight:800; color:#F5F3FB; letter-spacing:-0.03em; line-height:1.14; }
.sub { margin-top:40px; font-size:%(SS)dpx; font-weight:500; color:#A19DBA; letter-spacing:-0.01em; line-height:1.3; }
:lang(ko) .headline, :lang(ko) .sub { word-break:keep-all; }
.dev { position:absolute; left:50%%; top:%(DT)dpx; width:%(DW)dpx; margin-left:-%(DH)dpx; background:#0c0b10;
  border:4px solid #3a3850; padding:%(PAD)dpx; border-radius:%(R)dpx; box-shadow:0 60px 160px rgba(0,0,0,.6); }
.dev img { width:100%%; display:block; border-radius:%(IR)dpx; }
"""

HTML = """<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>{css}</style></head>
<body><div class="glow"></div><div class="t"><div class="headline">{h}</div><div class="sub">{s}</div></div>
<div class="dev"><img src="{img}"></div></body></html>"""


def render(lang, device):
    (W, H), dw, dt, r, pad, prefix, sub = DEVICES[device]
    src = RAW / sub / lang if sub else RAW / lang
    out = OUT / STORE[lang]
    out.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(exist_ok=True)
    css = CSS % {"W": W, "H": H, "GT": dt + 200, "GW": 1400, "GH": 700, "TT": 230 if device == "iphone" else 210,
                 "HS": 104 if device == "iphone" else 120, "SS": 48 if device == "iphone" else 56,
                 "DT": dt, "DW": dw, "DH": dw // 2, "PAD": pad, "R": r, "IR": r - pad}
    for fname, h, s in SHOTS[lang]:
        img = src / fname
        html = WORK / f"{lang}-{device}-{fname}.html"
        html.write_text(HTML.format(lang=lang, css=css, h=h, s=s, img=img.as_uri()), encoding="utf-8")
        target = out / f"{prefix}{fname}"
        # 다른 세션의 Chrome 과 겹치면 가끔 실패하거나 끝나지 않는다 — 새 프로필로 다시 시도한다.
        for attempt in range(4):
            target.unlink(missing_ok=True)
            try:
                subprocess.run([CHROME, "--headless=new", f"--screenshot={target}", f"--window-size={W},{H}",
                                "--force-device-scale-factor=1", "--hide-scrollbars", "--disable-gpu",
                                "--no-first-run", f"--user-data-dir={WORK / f'chrome-{attempt}'}", html.as_uri()],
                               capture_output=True, timeout=40)
            except subprocess.TimeoutExpired:
                pass
            if target.exists() and target.stat().st_size > 0:
                break
        else:
            sys.exit(f"렌더 실패: {target}")
        print("rendered", target.relative_to(ROOT))


if __name__ == "__main__":
    for lang in sys.argv[1:] or list(SHOTS):
        for device in DEVICES:
            render(lang, device)
