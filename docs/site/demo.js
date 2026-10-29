// 달빛 오락실 웹 체험: 라이어 게임 한 판. 아이폰 다섯 대를 하나씩 눌러 제시어를 확인한다.
// 규칙은 앱과 같다 (LiarRules): 라이어만 빼고 전원이 같은 제시어, 같은 카테고리에서 뽑은
// 12개 후보 중 하나로 라이어가 마지막 추측. 문구 · 단어 · 봇 이름은 앱 번역 그대로.
(() => {
  const root = document.getElementById("demo");
  if (!root) return;
  const T = JSON.parse(root.dataset.text), A = T.app;
  const f = (s, v) => s.replace("{1}", v);
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  const pick = a => a[Math.floor(Math.random() * a.length)];
  const shuffle = a => a.map(x => [Math.random(), x]).sort((p, q) => p[0] - q[0]).map(p => p[1]);
  const names = [A.me, ...A.bots];

  let g;
  function deal() {
    const category = pick(Object.keys(A.words)), word = pick(A.words[category]);
    // LiarRules.guessChoices: 같은 카테고리에서 정답 포함 12개
    const choices = shuffle([...shuffle(A.words[category].filter(w => w !== word)).slice(0, 11), word]);
    g = { category, word, choices, liar: Math.floor(Math.random() * names.length), open: -1, seen: new Set(), stage: "peek", guess: null };
    render();
  }

  root.innerHTML = `
    <div class="ml-table">
      <p class="ml-head"><strong>${esc(A.game)}</strong> <span class="ml-cat"></span></p>
      <div class="ml-phones"></div>
    </div>
    <div class="ml-side" aria-live="polite"></div>`;
  const phones = root.querySelector(".ml-phones"), side = root.querySelector(".ml-side"), cat = root.querySelector(".ml-cat");

  function face(i) {
    const isLiar = i === g.liar;
    if (g.stage !== "peek") return `<span class="ml-big">${isLiar ? esc(A.liar) : esc(g.word)}</span>`;
    if (g.open !== i) return g.seen.has(i) ? `<span class="ml-check" aria-hidden="true">✓</span>` : `<span class="ml-q">${esc(T.tap)}</span>`;
    return (isLiar
      ? `<span class="ml-liar">${esc(A.liarYou)}</span><span class="ml-small">${esc(A.liarHint)}</span>`
      : `<span class="ml-small">${esc(A.word)}</span><span class="ml-big">${esc(g.word)}</span>`)
      + `<span class="ml-ok">${esc(A.gotIt)}</span>`;
  }

  function render() {
    cat.textContent = "· " + f(A.cat, g.category);
    phones.innerHTML = names.map((n, i) => `
      <button type="button" class="ml-phone${g.open === i ? " open" : ""}${g.stage !== "peek" && i === g.liar ? " liar" : ""}"
        data-i="${i}" ${g.stage !== "peek" ? "disabled" : ""} aria-expanded="${g.open === i}">
        <span class="ml-name">${esc(n)}</span><span class="ml-screen">${face(i)}</span>
      </button>`).join("");
    if (g.stage === "peek") {
      side.innerHTML = `<p class="ml-sub">${esc(A.sub)}</p>
        <p class="muted small">${esc(g.open >= 0 ? A.secret : A.arrived)}</p>
        <div class="ml-actions"><button type="button" class="ml-btn main" data-act="reveal">${esc(T.reveal)}</button>
        <button type="button" class="ml-btn" data-act="again">${esc(T.again)}</button></div>
        <p class="muted small">${esc(T.note)}</p>`;
    } else if (g.stage === "guess") {
      side.innerHTML = `<p class="ml-title">${esc(A.caught)}</p><p class="muted small">${esc(T.caughtNote)}</p>
        <p class="ml-sub">${esc(A.pick)}</p>
        <div class="ml-choices">${g.choices.map(w => `<button type="button" class="ml-chip" data-guess="${esc(w)}">${esc(w)}</button>`).join("")}</div>`;
    } else {
      const liarWins = g.guess === g.word;
      side.innerHTML = `<p class="ml-title ${liarWins ? "red" : ""}">${esc(liarWins ? A.liarWin : A.citizenWin)}</p>
        <dl class="ml-result"><div><dt>${esc(A.liar)}</dt><dd>${esc(names[g.liar])}</dd></div>
        <div><dt>${esc(A.word)}</dt><dd>${esc(g.word)}</dd></div></dl>
        <div class="ml-actions"><button type="button" class="ml-btn main" data-act="again">${esc(T.again)}</button></div>`;
    }
  }

  root.addEventListener("click", e => {
    const b = e.target.closest("button");
    if (!b) return;
    if (b.dataset.i != null) {
      const i = +b.dataset.i;
      if (g.open === i) { g.seen.add(i); g.open = -1; } else g.open = i;
      render();
      root.querySelector(`[data-i="${i}"]`).focus();
    } else if (b.dataset.act === "reveal") { g.open = -1; g.stage = "guess"; render(); side.querySelector("button").focus(); }
    else if (b.dataset.act === "again") deal();
    else if (b.dataset.guess) { g.guess = b.dataset.guess; g.stage = "end"; render(); side.querySelector("button").focus(); }
  });

  deal();
})();
