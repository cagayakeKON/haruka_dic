/* Shared text selection interaction. Local UI demonstration; no model or audio. */
window.HarukaTextSelection = ({ s, root, onQuery }) => {
  const { escape: e, icon: I } = window.HarukaCore;
  let snapshot,
    toolbar,
    timer,
    pointer,
    suppressClick = false;
  const speech = window.HarukaSpeechPlayer({ s, root });
  let selectedTokens = new Set(),
    adjustedRange;
  let epoch = 0,
    gestureOwner = null;
  const scopeOf = (node) =>
    (node?.nodeType === 1 ? node : node?.parentElement)?.closest(
      "[data-study-text]",
    );
  const allowed = () =>
    s.signedIn &&
    !s.adminArea &&
    (!/exam/i.test(s.route) ||
      (s.route === "examResult" && s.examFinished && !s.examRunning)) &&
    !/exam/i.test(s.modal);
  const host = () => root.querySelector('[role="dialog"]') || root;
  const clearToolbar = () => {
    toolbar?.remove();
    toolbar = null;
    snapshot = null;
    CSS.highlights?.delete("haruka-focus");
  };
  function capture() {
    if (toolbar?.contains(document.activeElement)) return;
    const selection = window.getSelection();
    if (!allowed() || !selection?.rangeCount || selection.isCollapsed)
      return clearToolbar();
    const range = selection.getRangeAt(0);
    const start = scopeOf(range.startContainer),
      end = scopeOf(range.endContainer);
    if (
      !start ||
      start !== end ||
      !host().contains(start) ||
      start.closest("[inert]")
    )
      return clearToolbar();
    const text = selection.toString().trim();
    if (!text) return clearToolbar();
    const source =
      s.modal === "selectionQuery"
        ? "查询结果"
        : s.modal === "entryDetail"
          ? "收藏详情"
          : {
              novel: "夏の手紙 · 第 03 章",
              textbook: "课本 · 当前单元",
              query: "查询结果",
              examResult: "试卷 · 已交卷复盘",
              report: "学习诊断",
              practice: "AI 习题",
              textbookPractice: "课后题",
            }[s.route] || "学习内容";
    const prefix = range.cloneRange();
    prefix.selectNodeContents(start);
    prefix.setEnd(range.startContainer, range.startOffset);
    speech.pause();
    speech.focus(range.startContainer);
    selectedTokens = new Set();
    adjustedRange = null;
    snapshot = {
      text,
      source,
      route: s.route,
      modal: s.modal,
      epoch,
      range: range.cloneRange(),
      element: start,
      offset: prefix.toString().length,
      tokens: [
        ...new Intl.Segmenter(undefined, { granularity: "word" }).segment(text),
      ],
    };
    toolbar?.remove();
    toolbar = document.createElement("div");
    toolbar.className = "text-selection-toolbar";
    toolbar.setAttribute("role", "toolbar");
    toolbar.setAttribute("aria-label", "选中文字");
    toolbar.innerHTML = `<div class="sentence-panel-head"><span>选句学习</span><button type="button" data-selection-action="read" aria-label="朗读整句" title="朗读整句">${I("speaker")}</button><button type="button" data-selection-action="dismiss" aria-label="收起选区工具">${I("close")}</button></div><span class="selection-preview sr-only">${e(text)}</span><div class="sentence-tokens" role="group" aria-label="选择要查询的词">${snapshot.tokens.map((part, i) => (part.isWordLike ? `<button type="button" class="word-bubble" data-selection-token="${i}" aria-pressed="false">${e(part.segment)}</button>` : `<span class="sentence-punctuation">${e(part.segment)}</span>`)).join("")}</div><div class="selection-query-line"><span class="selection-scope" role="status">查询整句</span><button type="button" data-selection-action="query">${I("search")}查询</button></div><details class="selection-adjust"><summary>调整范围</summary><p>可在原文拖选，或在这里调整字词边界。</p><div><label>起点<select data-selection-boundary="start" aria-label="选区起点"></select></label><label>终点<select data-selection-boundary="end" aria-label="选区终点"></select></label></div></details>`;
    const graphemes = [
      ...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(
        text,
      ),
    ];
    toolbar.querySelector('[data-selection-boundary="start"]').innerHTML =
      graphemes
        .map(
          (part) =>
            `<option value="${part.index}">${part.index + 1} · ${e(text.slice(part.index, part.index + 10))}</option>`,
        )
        .join("");
    toolbar.querySelector('[data-selection-boundary="end"]').innerHTML =
      graphemes
        .map(
          (part) =>
            `<option value="${part.index + part.segment.length}">${part.index + part.segment.length} · ${e(part.segment)}</option>`,
        )
        .join("");
    toolbar.querySelector('[data-selection-boundary="end"]').value = String(
      text.length,
    );
    if (window.Highlight)
      CSS.highlights?.set("haruka-focus", new Highlight(range));
    host().append(toolbar);
    position();
  }
  function position() {
    if (!toolbar || !snapshot?.element.isConnected) return;
    const rect = snapshot.range.getBoundingClientRect();
    const width = Math.min(340, window.innerWidth - 24);
    toolbar.style.width = `${width}px`;
    toolbar.style.left = `${Math.max(12, Math.min(rect.left, window.innerWidth - width - 12))}px`;
    toolbar.style.top = `${Math.max(12, Math.min(rect.bottom + 10, window.innerHeight - toolbar.offsetHeight - 12))}px`;
  }
  function queryRanges() {
    if (adjustedRange) return [adjustedRange];
    if (!selectedTokens.size) return [{ start: 0, end: snapshot.text.length }];
    const indices = [...selectedTokens].sort((a, b) => a - b),
      ranges = [];
    let previous;
    for (const i of indices) {
      const part = snapshot.tokens[i];
      const contiguous =
        previous !== undefined &&
        snapshot.tokens.slice(previous + 1, i).every((p) => !p.isWordLike);
      if (contiguous) ranges.at(-1).end = part.index + part.segment.length;
      else
        ranges.push({
          start: part.index,
          end: part.index + part.segment.length,
        });
      previous = i;
    }
    return ranges;
  }
  function updateScope() {
    if (!snapshot || !toolbar) return;
    const ranges = queryRanges();
    toolbar
      .querySelectorAll("[data-selection-token]")
      .forEach((button) =>
        button.setAttribute(
          "aria-pressed",
          String(selectedTokens.has(Number(button.dataset.selectionToken))),
        ),
      );
    const invalid = ranges.some((part) => part.end <= part.start);
    const tooMany = ranges.length > 3;
    toolbar.querySelector(".selection-scope").textContent = invalid
      ? "终点需要在起点之后"
      : tooMany
        ? "每次最多查询3组，请减少选择"
        : !selectedTokens.size && !adjustedRange
          ? "查询整句"
          : ranges
              .map((part) => snapshot.text.slice(part.start, part.end))
              .join(" / ");
    toolbar.querySelector('[data-selection-action="query"]').disabled =
      invalid || tooMany;
    position();
  }
  // Capture before page-level click handlers, so selecting a list row never opens it.
  document.addEventListener(
    "click",
    (event) => {
      const bubble = event.target.closest("[data-selection-token]");
      if (bubble && toolbar?.contains(bubble)) {
        event.preventDefault();
        event.stopImmediatePropagation();
        const index = Number(bubble.dataset.selectionToken);
        if (selectedTokens.has(index)) selectedTokens.delete(index);
        else selectedTokens.add(index);
        adjustedRange = null;
        updateScope();
        return;
      }
      const pronunciation = event.target.closest("[data-pronounce]");
      if (
        pronunciation &&
        root.contains(pronunciation) &&
        allowed() &&
        !pronunciation.closest("[inert]")
      ) {
        event.preventDefault();
        event.stopImmediatePropagation();
        clearToolbar();
        window.getSelection()?.removeAllRanges();
        speech.read(
          pronunciation.dataset.pronounce,
          pronunciation.dataset.language,
        );
        return;
      }
      const action = event.target.closest("[data-selection-action]");
      if (action && root.contains(action)) {
        event.preventDefault();
        event.stopImmediatePropagation();
        const kind = action.dataset.selectionAction;
        if (kind === "continuous") {
          clearToolbar();
          window.getSelection()?.removeAllRanges();
          speech.continuous();
          return;
        }
        if (kind === "stop") return speech.stop();
        if (kind === "pause") return speech.toggle();
        const selected = snapshot;
        if (kind === "dismiss") {
          clearToolbar();
          window.getSelection()?.removeAllRanges();
          return;
        }
        if (
          !selected ||
          selected.epoch !== epoch ||
          !selected.element.isConnected ||
          !allowed()
        )
          return clearToolbar();
        if (kind === "read")
          speech.read(
            selected.text,
            selected.element.closest("[lang]")?.lang || "",
          );
        if (kind === "query")
          onQuery({
            text: queryRanges()
              .map((part) => selected.text.slice(part.start, part.end))
              .join(" / "),
            sentence: selected.text,
            ranges: queryRanges().map((part) => ({
              ...part,
              text: selected.text.slice(part.start, part.end),
            })),
            queryMode:
              queryRanges().length > 1 ? "separate_words" : "contiguous",
            source: selected.source,
            route: selected.route,
            offset: selected.offset,
            modal: selected.modal,
            scopeIndex: [
              ...host().querySelectorAll("[data-study-text]"),
            ].indexOf(selected.element),
          });
        clearToolbar();
        window.getSelection()?.removeAllRanges();
        return;
      }
      if (
        suppressClick &&
        gestureOwner &&
        (gestureOwner.contains(event.target) ||
          event.target.contains(gestureOwner))
      ) {
        event.preventDefault();
        event.stopImmediatePropagation();
        suppressClick = false;
      }
    },
    true,
  );
  document.addEventListener("selectionchange", capture);
  document.addEventListener("change", (event) => {
    if (
      !toolbar?.contains(event.target) ||
      !event.target.matches("[data-selection-boundary]")
    )
      return;
    adjustedRange = {
      start: Number(
        toolbar.querySelector('[data-selection-boundary="start"]').value,
      ),
      end: Number(
        toolbar.querySelector('[data-selection-boundary="end"]').value,
      ),
    };
    selectedTokens.clear();
    updateScope();
  });
  document.addEventListener(
    "toggle",
    (event) => {
      if (event.target.matches?.(".selection-adjust")) position();
    },
    true,
  );
  document.addEventListener(
    "pointerdown",
    (event) => {
      if (event.target.closest(".text-selection-toolbar")) {
        if (!event.target.closest("select,summary,details"))
          event.preventDefault();
        return;
      }
      if (
        event.target.closest(
          "[data-pronounce],.selection-player,[data-selection-action]",
        )
      )
        return;
      suppressClick = false;
      gestureOwner = null;
      clearTimeout(timer);
      if (!root.contains(event.target) || !allowed()) return;
      const scope = scopeOf(event.target);
      pointer = scope
        ? { x: event.clientX, y: event.clientY, scope, epoch }
        : null;
      if (!pointer || !event.isPrimary || event.button > 0) return;
      const initial = pointer;
      timer = setTimeout(() => {
        if (pointer !== initial || initial.epoch !== epoch) return;
        const caret = document.caretRangeFromPoint?.(initial.x, initial.y);
        if (!caret || !initial.scope.contains(caret.startContainer)) return;
        const block =
          caret.startContainer.parentElement.closest(
            "[data-reading-sentence],p,h2,h3,h4,strong,small,.answer-copy",
          ) || initial.scope;
        if (!initial.scope.contains(block) && block !== initial.scope) return;
        const before = caret.cloneRange();
        before.selectNodeContents(block);
        before.setEnd(caret.startContainer, caret.startOffset);
        const offset = before.toString().length,
          value = block.textContent;
        const sentences = [
          ...new Intl.Segmenter(undefined, { granularity: "sentence" }).segment(
            value,
          ),
        ];
        const sentence =
          sentences.find(
            (part) =>
              offset >= part.index && offset < part.index + part.segment.length,
          ) || sentences.at(-1);
        if (!sentence) return;
        const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
        const range = document.createRange();
        let count = 0,
          started = false,
          node;
        while ((node = walker.nextNode())) {
          const next = count + node.length;
          if (!started && sentence.index < next) {
            range.setStart(node, Math.max(0, sentence.index - count));
            started = true;
          }
          if (started && sentence.index + sentence.segment.length <= next) {
            range.setEnd(
              node,
              sentence.index + sentence.segment.length - count,
            );
            break;
          }
          count = next;
        }
        if (!started) return;
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        suppressClick = true;
        gestureOwner = initial.scope.closest("button") || initial.scope;
        capture();
      }, 500);
    },
    true,
  );
  document.addEventListener(
    "pointermove",
    (event) => {
      if (
        pointer &&
        Math.hypot(event.clientX - pointer.x, event.clientY - pointer.y) > 10
      )
        clearTimeout(timer);
    },
    true,
  );
  document.addEventListener(
    "pointerup",
    () => {
      clearTimeout(timer);
      if (pointer && !window.getSelection()?.isCollapsed) {
        suppressClick = true;
        gestureOwner = pointer.scope.closest("button") || pointer.scope;
        capture();
      }
      pointer = null;
    },
    true,
  );
  document.addEventListener(
    "pointercancel",
    () => {
      clearTimeout(timer);
      pointer = null;
    },
    true,
  );
  document.addEventListener("contextmenu", (event) => {
    if (snapshot && scopeOf(event.target)) event.preventDefault();
  });
  document.addEventListener(
    "keydown",
    (event) => {
      if (
        event.key === "Tab" &&
        toolbar &&
        !toolbar.contains(document.activeElement)
      ) {
        event.preventDefault();
        toolbar.querySelector("button").focus();
        return;
      }
      if (event.key === "Escape" && toolbar) {
        event.preventDefault();
        event.stopImmediatePropagation();
        clearToolbar();
        window.getSelection()?.removeAllRanges();
      }
    },
    true,
  );
  window.addEventListener("resize", position);
  document.addEventListener(
    "scroll",
    () => {
      clearTimeout(timer);
      position();
    },
    true,
  );
  window.addEventListener("pagehide", () => {
    clearTimeout(timer);
    pointer = null;
    epoch++;
    clearToolbar();
    speech.stop(true);
  });
  function refresh() {
    epoch++;
    clearTimeout(timer);
    pointer = null;
    clearToolbar();
    speech.refresh();
    if (!allowed()) return;
    const selectors = {
      novel: ".prose,.reading-prose",
      sampleReader: ".sample-reader p",
      query: ".learning-card-content,.query-question p",
      notebooks: ".collection-copy",
      dailyWords: ".collection-copy",
      practice:
        ".question-prompt,.question-translation,.question-panel > p,.question-panel h2,.answer-copy,.feedback p",
      textbookPractice:
        ".question-prompt,.question-panel h2,.mobile-question,.answer-copy,.feedback p,.feedback > div",
      mistakes: "[data-mistake] strong,.table td strong",
      mistake:
        ".page-title,.page-heading h1,.surface p,.panel p,.question-panel p",
      examResult: ".exam-review-text",
      report: ".panel h2,.panel p,.surface h2,.surface p",
    };
    const modalSelectors = {
      selectionQuery: ".learning-card-content",
      entryDetail: ".learning-card-content,.entry-detail > p:not(.note)",
      textbookItem:
        ".stack > p:not(.step-caption),.row-wrap strong,.row-wrap small,.textbook-word strong,.textbook-word small",
    };
    const selector = s.modal ? modalSelectors[s.modal] : selectors[s.route];
    if (!selector) return;
    host()
      .querySelectorAll(selector)
      .forEach((el) => el.setAttribute("data-study-text", ""));
  }
  return { refresh };
};
