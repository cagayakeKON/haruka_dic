/* Shared text selection interaction. Local UI demonstration; no model or audio. */
window.HarukaTextSelection = ({ s, root, onQuery }) => {
  const { escape: e, icon: I } = window.HarukaCore;
  let snapshot,
    toolbar,
    player,
    timer,
    pointer,
    suppressClick = false;
  let epoch = 0,
    gestureOwner = null;
  const scopeOf = (node) =>
    (node?.nodeType === 1 ? node : node?.parentElement)?.closest(
      "[data-study-text]",
    );
  const allowed = () =>
    s.signedIn &&
    !s.adminArea &&
    !/exam/i.test(s.route) &&
    !/exam/i.test(s.modal);
  const host = () => root.querySelector('[role="dialog"]') || root;
  const clearToolbar = () => {
    toolbar?.remove();
    toolbar = null;
    snapshot = null;
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
              report: "学习诊断",
              practice: "AI 习题",
              textbookPractice: "课后题",
            }[s.route] || "学习内容";
    const prefix = range.cloneRange();
    prefix.selectNodeContents(start);
    prefix.setEnd(range.startContainer, range.startOffset);
    snapshot = {
      text,
      source,
      route: s.route,
      modal: s.modal,
      epoch,
      range: range.cloneRange(),
      element: start,
      offset: prefix.toString().length,
    };
    toolbar?.remove();
    toolbar = document.createElement("div");
    toolbar.className = "text-selection-toolbar";
    toolbar.setAttribute("role", "toolbar");
    toolbar.setAttribute("aria-label", "选中文字");
    toolbar.innerHTML = `<span class="selection-preview">${e(text)}</span><div><button type="button" data-selection-action="read">${I("headphones")}朗读</button><button type="button" data-selection-action="query">${I("search")}查询</button><button type="button" data-selection-action="dismiss" aria-label="收起选区工具">${I("close")}</button></div>`;
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
  function read(selected) {
    player?.remove();
    player = document.createElement("section");
    player.className = "selection-player";
    player.setAttribute("aria-label", "朗读演示");
    player.innerHTML = `<div><strong>朗读演示</strong><span role="status">播放中 · 无实际音频</span></div><p>${e(selected.text)}</p><div class="selection-playback"><button type="button" data-selection-action="pause">${I("pause")}暂停</button><label>语速<select aria-label="朗读语速"><option>0.7×</option><option selected>1.0×</option><option>1.2×</option><option>1.5×</option></select></label><button type="button" data-selection-action="stop">${I("close")}停止</button></div>`;
    host().append(player);
    player.querySelector("button").focus({ preventScroll: true });
  }
  // Capture before page-level click handlers, so selecting a list row never opens it.
  document.addEventListener(
    "click",
    (event) => {
      const action = event.target.closest("[data-selection-action]");
      if (action && root.contains(action)) {
        event.preventDefault();
        event.stopImmediatePropagation();
        const kind = action.dataset.selectionAction;
        if (kind === "stop") {
          player?.remove();
          player = null;
          return;
        }
        if (kind === "pause") {
          const paused = action.dataset.paused !== "true";
          action.dataset.paused = String(paused);
          action.innerHTML = `${I(paused ? "play" : "pause")}${paused ? "继续" : "暂停"}`;
          player.querySelector('[role="status"]').textContent =
            `${paused ? "已暂停" : "播放中"} · 无实际音频`;
          return;
        }
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
        if (kind === "read") read(selected);
        if (kind === "query")
          onQuery({
            text: selected.text,
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
  document.addEventListener(
    "pointerdown",
    (event) => {
      if (event.target.closest(".text-selection-toolbar")) {
        event.preventDefault();
        return;
      }
      suppressClick = false;
      gestureOwner = null;
      clearTimeout(timer);
      if (!root.contains(event.target) || !allowed()) return;
      const scope = scopeOf(event.target);
      pointer = scope
        ? { x: event.clientX, y: event.clientY, scope, epoch }
        : null;
      if (!pointer || event.pointerType !== "touch" || !event.isPrimary) return;
      const initial = pointer;
      timer = setTimeout(() => {
        if (pointer !== initial || initial.epoch !== epoch) return;
        const caret = document.caretRangeFromPoint?.(initial.x, initial.y);
        if (!caret || !initial.scope.contains(caret.startContainer)) return;
        const block =
          caret.startContainer.parentElement.closest(
            "p,h2,h3,strong,small,.answer-copy",
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
    player?.remove();
  });
  function refresh() {
    epoch++;
    clearTimeout(timer);
    pointer = null;
    clearToolbar();
    player?.remove();
    player = null;
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
      report: ".panel h2,.panel p,.surface h2,.surface p",
    };
    const modalSelectors = {
      selectionQuery: ".learning-card-content",
      entryDetail: ".learning-card-content,.entry-detail > p:not(.note)",
      textbookItem:
        ".stack > p:not(.step-caption),.row-wrap strong,.row-wrap small",
    };
    const selector = s.modal ? modalSelectors[s.modal] : selectors[s.route];
    if (!selector) return;
    host()
      .querySelectorAll(selector)
      .forEach((el) => el.setAttribute("data-study-text", ""));
  }
  return { refresh };
};
