#!/usr/bin/env python3
"""GitHub Pages 다국어 정리: 언어 전환 링크 · hreflang 을 모든 페이지에 다시 넣는다.

사용법: python3 scripts/docs_i18n.py

페이지  docs/index.html · docs/privacy.html            한국어(기본)
        docs/<로케일>/index.html · privacy.html          그 언어로 쓴 페이지
각 페이지의 <!--HREFLANG-->…<!--/HREFLANG--> 와 <!--LANGNAV-->…<!--/LANGNAV--> 자리를 채운다.
"""
import pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent / "docs"
BASE = "https://m1zz.github.io/MoonlitOrder/"
LANGS = [("ko", "한국어"), ("en", "English"), ("en-GB", "English (UK)"), ("ja", "日本語"),
         ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("ru", "Русский"), ("es", "Español"),
         ("de", "Deutsch"), ("fr", "Français"), ("it", "Italiano"), ("pt-BR", "Português (Brasil)"),
         ("th", "ไทย"), ("vi", "Tiếng Việt"), ("cs", "Čeština"), ("da", "Dansk"), ("el", "Ελληνικά"),
         ("fi", "Suomi"), ("id", "Bahasa Indonesia"), ("nb", "Norsk bokmål"), ("nl", "Nederlands"),
         ("pl", "Polski"), ("sv", "Svenska"), ("tr", "Türkçe")]
CSS = (".langs{display:flex;flex-wrap:wrap;gap:4px 12px;justify-content:center;margin-top:16px;font-size:13px}"
       ".langs a{color:var(--muted);text-decoration:none}.langs a[aria-current]{color:var(--gold);font-weight:700}")


def folder(code):
    return "" if code == "ko" else f"{code}/"


def fill(path, code, page):
    html = path.read_text(encoding="utf-8")
    up = "" if code == "ko" else "../"
    href = "\n".join(f'<link rel="alternate" hreflang="{c}" href="{BASE}{folder(c)}{page}">' for c, _ in LANGS)
    href += f'\n<link rel="alternate" hreflang="x-default" href="{BASE}en/{page}">'
    href = f'<link rel="canonical" href="{BASE}{folder(code)}{page}">\n' + href
    nav = '<nav class="langs" aria-label="Language">' + "".join(
        f'<a href="{up}{folder(c)}{page}" hreflang="{c}" lang="{c}"' + (' aria-current="page"' if c == code else "") + f">{n}</a>"
        for c, n in LANGS) + "</nav>"
    html = re.sub(r"<!--HREFLANG-->.*?<!--/HREFLANG-->", lambda m: f"<!--HREFLANG-->\n{href}\n<!--/HREFLANG-->", html, flags=re.S)
    html = re.sub(r"<!--LANGNAV-->.*?<!--/LANGNAV-->", lambda m: f"<!--LANGNAV-->{nav}<!--/LANGNAV-->", html, flags=re.S)
    if ".langs{" not in html:
        html = html.replace("</style>", CSS + "\n</style>", 1)
    path.write_text(html, encoding="utf-8")


if __name__ == "__main__":
    for code, _ in LANGS:
        for page in ("index.html", "privacy.html"):
            p = ROOT / folder(code) / page
            if not p.exists():
                print("없음", p.relative_to(ROOT)); continue
            if "<!--HREFLANG-->" not in p.read_text(encoding="utf-8"):
                print("자리표 없음", p.relative_to(ROOT)); continue
            fill(p, code, page)
    print("done")
