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
STORE = {"ko": "ko", "en": "en-US", "en-GB": "en-GB", "ja": "ja", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant", "ru": "ru", "es": "es-ES", "de": "de-DE", "fr": "fr-FR", "it": "it", "pt-BR": "pt-BR", "th": "th", "vi": "vi", "cs": "cs", "da": "da", "el": "el", "fi": "fi", "id": "id", "nb": "no", "nl": "nl-NL", "pl": "pl"}

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
    "ja": [
        ("01-home.png", "集まったらすぐ<br>パーティゲーム", "インターネットなしで近くのiPhone同士がつながります"),
        ("02-role.png", "自分の役職は<br>自分だけが知っている", "潜んだ影を探す正体推理「月光結社」"),
        ("03-vote.png", "賛成か、<br>反対か", "みんなの票が公開された瞬間、形勢が逆転します"),
        ("04-draw.png", "描いて、<br>当てて", "1人が描いて、残りが当てる「月光アトリエ」"),
        ("05-result.png", "早く当てるほど<br>高得点", "最大15人まで一緒に楽しめます"),
    ],
    "zh-Hans": [
        ("01-home.png", "聚在一起<br>马上玩派对游戏", "不用网络,附近的iPhone就能相互连接"),
        ("02-role.png", "你的身份<br>只有你知道", "在“月光结社”中找出潜伏的暗影"),
        ("03-vote.png", "赞成<br>还是反对?", "大家的票公开的瞬间,局势翻转"),
        ("04-draw.png", "画一画,<br>猜一猜", "在“月光画室”,一人画,其他人猜"),
        ("05-result.png", "猜得越快<br>得分越高", "最多15人一起玩"),
    ],
    "zh-Hant": [
        ("01-home.png", "聚在一起<br>馬上玩派對遊戲", "不用網路,附近的iPhone就能相互連線"),
        ("02-role.png", "你的身分<br>只有你知道", "在“月光結社”中找出潛伏的暗影"),
        ("03-vote.png", "贊成<br>還是反對?", "大家的票公開的瞬間,局勢翻轉"),
        ("04-draw.png", "畫一畫,<br>猜一猜", "在“月光畫室”,一人畫,其他人猜"),
        ("05-result.png", "猜得越快<br>得分越高", "最多15人一起玩"),
    ],
    "ru": [
        ("01-home.png", "Собрались —<br>играем сразу", "iPhone рядом соединяются без интернета"),
        ("02-role.png", "Свою роль<br>знаете только вы", "Найдите затаившихся Теней в «Лунном ордене»"),
        ("03-vote.png", "За<br>или против?", "В момент, когда голоса открыты, всё переворачивается"),
        ("04-draw.png", "Рисуй<br>и угадывай", "Один рисует, остальные угадывают в «Лунной студии»"),
        ("05-result.png", "Чем быстрее,<br>тем больше очков", "Играйте вместе до 15 человек"),
    ],
    "es": [
        ("01-home.png", "Se juntan y<br>juegan al instante", "Los iPhone cercanos se conectan sin internet"),
        ("02-role.png", "Tu rol<br>solo lo sabes tú", "Encuentra a las Sombras escondidas en la Orden Lunar"),
        ("03-vote.png", "¿A favor<br>o en contra?", "En el momento en que se revelan los votos, la partida da un vuelco"),
        ("04-draw.png", "Dibuja<br>y adivina", "Uno dibuja y los demás adivinan en Estudio Lunar"),
        ("05-result.png", "Cuanto antes aciertes,<br>más puntos", "Juega con hasta 15 amigos"),
    ],
    "de": [
        ("01-home.png", "Zusammenkommen,<br>sofort Partyspiel", "iPhones in der Nähe verbinden sich ohne Internet"),
        ("02-role.png", "Deine Rolle<br>kennst nur du", "Finde die versteckten Schatten im Mondorden"),
        ("03-vote.png", "Dafür<br>oder dagegen?", "Im Moment, in dem alle Stimmen offenliegen, kippt das Spiel"),
        ("04-draw.png", "Zeichnen<br>und Raten", "Einer zeichnet, die anderen raten – im Mondlicht-Atelier"),
        ("05-result.png", "Je schneller,<br>desto mehr Punkte", "Spiele mit bis zu 15 Freunden"),
    ],
    "fr": [
        ("01-home.png", "On se retrouve,<br>on joue tout de suite", "Les iPhone à proximité se connectent sans Internet"),
        ("02-role.png", "Votre rôle,<br>vous seul le savez", "Trouvez les Ombres cachées dans l’Ordre Lunaire"),
        ("03-vote.png", "Pour<br>ou contre ?", "Quand les votes de chacun sont révélés, tout bascule"),
        ("04-draw.png", "Dessinez,<br>devinez", "Un dessine, les autres devinent dans Atelier Lunaire"),
        ("05-result.png", "Plus on devine vite,<br>plus on marque", "Jusqu’à 15 amis pour jouer ensemble"),
    ],
    "it": [
        ("01-home.png", "Ci si ritrova,<br>si gioca subito", "Gli iPhone vicini si collegano senza Internet"),
        ("02-role.png", "Il tuo ruolo<br>lo sai solo tu", "Trova le Ombre nascoste nell’Ordine Lunare"),
        ("03-vote.png", "A favore<br>o contro?", "Nel momento in cui i voti vengono svelati, tutto si ribalta"),
        ("04-draw.png", "Disegna<br>e indovina", "Uno disegna, gli altri indovinano in Studio Lunare"),
        ("05-result.png", "Più veloce indovini,<br>più punti fai", "Gioca con un massimo di 15 amici"),
    ],
    "pt-BR": [
        ("01-home.png", "Reuniu o pessoal,<br>já joga na hora", "iPhones por perto se conectam sem internet"),
        ("02-role.png", "Seu papel<br>só você sabe", "Encontre as Sombras escondidas na Ordem Lunar"),
        ("03-vote.png", "A favor<br>ou contra?", "No instante em que os votos são revelados, o jogo vira"),
        ("04-draw.png", "Desenhe<br>e adivinhe", "Um desenha, os outros adivinham no Ateliê Lunar"),
        ("05-result.png", "Quanto mais rápido,<br>mais pontos", "Jogue com até 15 amigos"),
    ],
    "th": [
        ("01-home.png", "มารวมกันแล้ว<br>เล่นเกมปาร์ตี้ทันที", "iPhone ใกล้กันเชื่อมต่อกันได้โดยไม่ต้องมีอินเทอร์เน็ต"),
        ("02-role.png", "บทบาทของคุณ<br>มีแต่คุณที่รู้", "หาเงามืดที่ซ่อนตัวในภาคีแสงจันทร์"),
        ("03-vote.png", "เห็นด้วย<br>หรือไม่?", "ในวินาทีที่เปิดคะแนนโหวต เกมก็พลิก"),
        ("04-draw.png", "วาดแล้ว<br>ทาย", "คนหนึ่งวาด คนอื่นทายใน สตูดิโอแสงจันทร์"),
        ("05-result.png", "ทายเร็วเท่าไร<br>ยิ่งได้คะแนนสูง", "เล่นด้วยกันได้สูงสุด 15 คน"),
    ],
    "vi": [
        ("01-home.png", "Tụ họp là<br>chơi tiệc tùng ngay", "iPhone ở gần kết nối với nhau không cần Internet"),
        ("02-role.png", "Vai của bạn<br>chỉ mình bạn biết", "Tìm Bóng Tối ẩn nấp trong Hội Ánh Trăng"),
        ("03-vote.png", "Đồng ý<br>hay phản đối?", "Khoảnh khắc phiếu của mọi người được công khai, ván chơi lật ngược"),
        ("04-draw.png", "Vẽ đi,<br>đoán đi", "Một người vẽ, những người còn lại đoán trong Xưởng Vẽ Ánh Trăng"),
        ("05-result.png", "Đoán càng nhanh<br>điểm càng cao", "Cùng chơi với tối đa 15 người"),
    ],
    "cs": [
        ("01-home.png", "Sejdete se<br>a hned hrajete", "iPhony poblíž se propojí bez internetu"),
        ("02-role.png", "Svou roli<br>znáš jen ty", "Najdi ukryté Stíny v Měsíčním řádu"),
        ("03-vote.png", "Pro<br>nebo proti?", "V okamžiku, kdy se hlasy odhalí, se hra obrátí"),
        ("04-draw.png", "Kresli<br>a hádej", "Jeden kreslí, ostatní hádají v Měsíčním ateliéru"),
        ("05-result.png", "Čím rychleji,<br>tím víc bodů", "Hrajte spolu až s 15 kamarády"),
    ],
    "da": [
        ("01-home.png", "Mød op,<br>og spil med det samme", "iPhones i nærheden forbindes uden internet"),
        ("02-role.png", "Din rolle<br>kender kun du", "Find de skjulte Skygger i Måneordenen"),
        ("03-vote.png", "For<br>eller imod?", "I det øjeblik alles stemmer afsløres, vender spillet"),
        ("04-draw.png", "Tegn<br>og gæt", "Én tegner, de andre gætter i Måneatelieret"),
        ("05-result.png", "Jo hurtigere,<br>jo flere point", "Spil med op til 15 venner"),
    ],
    "el": [
        ("01-home.png", "Μαζευτείτε<br>και παίξτε πάρτι αμέσως", "Τα iPhone κοντά συνδέονται χωρίς ίντερνετ"),
        ("02-role.png", "Τον ρόλο σου<br>τον ξέρεις μόνο εσύ", "Βρες τις κρυμμένες Σκιές στο Τάγμα της Σελήνης"),
        ("03-vote.png", "Υπέρ<br>ή κατά;", "Τη στιγμή που αποκαλύπτονται οι ψήφοι, το παιχνίδι αλλάζει"),
        ("04-draw.png", "Ζωγράφισε<br>και μάντεψε", "Ένας ζωγραφίζει, οι άλλοι μαντεύουν στο Εργαστήρι του Φεγγαριού"),
        ("05-result.png", "Όσο πιο γρήγορα,<br>τόσο περισσότεροι πόντοι", "Παίξτε μαζί έως και 15 φίλοι"),
    ],
    "fi": [
        ("01-home.png", "Kokoonnutte,<br>pelaatte heti", "Lähellä olevat iPhonet yhdistyvät ilman internetiä"),
        ("02-role.png", "Roolisi tiedät<br>vain sinä", "Etsi piileskelevät Varjot Kuuordosta"),
        ("03-vote.png", "Puolesta<br>vai vastaan?", "Kun kaikkien äänet paljastuvat, peli kääntyy"),
        ("04-draw.png", "Piirrä<br>ja arvaa", "Yksi piirtää, muut arvaavat Kuuateljeessa"),
        ("05-result.png", "Mitä nopeammin,<br>sitä enemmän pisteitä", "Pelaa jopa 15 kaverin kanssa"),
    ],
    "id": [
        ("01-home.png", "Berkumpul,<br>langsung main game pesta", "iPhone terdekat tersambung tanpa internet"),
        ("02-role.png", "Perannya<br>cuma kamu yang tahu", "Temukan Bayangan yang bersembunyi di Ordo Cahaya Bulan"),
        ("03-vote.png", "Setuju<br>atau tolak?", "Saat suara semua orang dibuka, permainan berbalik"),
        ("04-draw.png", "Gambar<br>dan tebak", "Satu menggambar, yang lain menebak di Studio Cahaya Bulan"),
        ("05-result.png", "Makin cepat,<br>makin tinggi skor", "Main bareng hingga 15 teman"),
    ],
    "nb": [
        ("01-home.png", "Møt opp,<br>og spill med en gang", "iPhoner i nærheten kobles sammen uten internett"),
        ("02-role.png", "Rollen din<br>vet bare du", "Finn de skjulte Skyggene i Månordenen"),
        ("03-vote.png", "For<br>eller imot?", "I det alles stemmer avsløres, snur spillet"),
        ("04-draw.png", "Tegn<br>og gjett", "Én tegner, de andre gjetter i Månestudioet"),
        ("05-result.png", "Jo raskere,<br>jo flere poeng", "Spill med opptil 15 venner"),
    ],
    "nl": [
        ("01-home.png", "Samenkomen,<br>meteen een feestspel", "iPhones in de buurt verbinden zonder internet"),
        ("02-role.png", "Jouw rol<br>weet alleen jij", "Vind de verborgen Schaduwen in de Maanorde"),
        ("03-vote.png", "Voor<br>of tegen?", "Op het moment dat ieders stem wordt onthuld, keert het spel"),
        ("04-draw.png", "Teken<br>en raad", "Eén tekent, de rest raadt in het Maanatelier"),
        ("05-result.png", "Hoe sneller,<br>hoe meer punten", "Speel samen met maximaal 15 vrienden"),
    ],
    "pl": [
        ("01-home.png", "Spotykacie się —<br>od razu gra imprezowa", "iPhone’y w pobliżu łączą się bez internetu"),
        ("02-role.png", "Swoją rolę<br>znasz tylko ty", "Znajdź ukryte Cienie w Zakonie Księżyca"),
        ("03-vote.png", "Za<br>czy przeciw?", "W chwili ujawnienia głosów wszystkich gra się odwraca"),
        ("04-draw.png", "Rysuj<br>i zgaduj", "Jeden rysuje, reszta zgaduje w Księżycowej Pracowni"),
        ("05-result.png", "Im szybciej,<br>tym więcej punktów", "Graj razem z maksymalnie 15 znajomymi"),
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
