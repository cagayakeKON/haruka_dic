/* Local timing/cache demonstration only. No audio or supplier requests. */
window.HarukaSpeechPlayer = ({ s, root, novel }) => {
  const { escape: e, icon: I } = window.HarukaCore;
  let playback,
    suspended,
    player,
    tick,
    lastTick,
    context,
    cursor,
    modalContext;
  const prepared = novel.audioCache;
  const host = () => root.querySelector('[role="dialog"]') || root;
  const contextKey = () =>
    `${s.signedIn}:${s.adminArea}:${s.serviceAddress}:${s.route}:${s.chosenMaterial}:${s.route === "novel" ? s.novelChapter : ""}`;
  const sentenceElements = () => [
    ...root.querySelectorAll("[data-reading-sentence]"),
  ];
  const clearHighlight = () =>
    sentenceElements().forEach((el) => {
      el.classList.remove("is-speaking");
      el.removeAttribute("aria-current");
    });
  function highlight(follow = false) {
    clearHighlight();
    const queue = playback?.mode === "continuous" ? playback : suspended;
    if (!queue) return;
    const el = sentenceElements()[queue.index];
    el?.classList.add("is-speaking");
    el?.setAttribute("aria-current", "true");
    if (follow && queue.follow !== false && !s.modal && el) {
      const rect = el.getBoundingClientRect();
      if (rect.top < 120 || rect.bottom > innerHeight - 260)
        el.scrollIntoView({ block: "center", behavior: "instant" });
    }
  }
  function prepare() {
    if (!playback || playback.paused) return;
    // At most the current sentence and two successors, never the whole chapter.
    playback.items
      .slice(playback.index, playback.index + 3)
      .forEach((item) => prepared.add(item.key));
  }
  function paint() {
    if (!player || !playback) return;
    const p = playback,
      item = p.items[p.index];
    player.querySelector('[role="status"]').textContent =
      `${p.completed ? (p.mode === "continuous" ? "本章已读完" : "播放完毕") : p.paused ? "已暂停" : "播放中"} · 无实际音频`;
    player.querySelector(".playback-text").textContent = item.text;
    player.querySelector(".playback-count").textContent =
      p.mode === "continuous"
        ? `第 ${p.index + 1} / ${p.items.length} 句`
        : "单次朗读";
    player.querySelector("progress").value = p.elapsed / item.duration;
    const button = player.querySelector('[data-selection-action="pause"]');
    button.innerHTML = `${I(p.paused ? "play" : "pause")}${p.completed ? "重新播放" : p.paused ? "继续" : "暂停"}`;
    player.dataset.sentence = String(p.index);
    player.dataset.elapsed = String(Math.floor(p.elapsed));
    player.dataset.prepared = String(prepared.size);
    player.dataset.mode = p.mode;
  }
  function mount() {
    player?.remove();
    if (!playback || (playback.mode === "continuous" && s.modal)) return;
    player = document.createElement("section");
    player.className = "selection-player";
    player.setAttribute("aria-label", "朗读演示");
    player.innerHTML = `<div><strong>${playback.mode === "continuous" ? "连续朗读" : "朗读演示"}</strong><span role="status"></span></div><p class="playback-text"></p><div class="playback-position"><span class="playback-count"></span><progress max="1" value="0" aria-label="本句播放进度"></progress></div><div class="selection-playback"><button type="button" data-selection-action="pause"></button><label>语速<select aria-label="朗读语速">${[0.7, 1, 1.2, 1.5].map((speed) => `<option value="${speed}" ${speed === playback.speed ? "selected" : ""}>${speed.toFixed(1)}×</option>`).join("")}</select></label><button type="button" data-selection-action="stop">${I("close")}停止</button></div>`;
    host().append(player);
    paint();
    highlight();
  }
  function run() {
    clearInterval(tick);
    if (!playback || playback.paused) return;
    lastTick = performance.now();
    tick = setInterval(() => {
      if (!playback || playback.paused) return;
      const now = performance.now();
      playback.elapsed += (now - lastTick) * playback.speed;
      lastTick = now;
      const item = playback.items[playback.index];
      if (playback.elapsed >= item.duration) {
        if (playback.index + 1 < playback.items.length) {
          playback.index++;
          playback.elapsed = 0;
          prepare();
          highlight(true);
        } else {
          playback.elapsed = item.duration;
          playback.paused = true;
          playback.completed = true;
          clearInterval(tick);
        }
      }
      paint();
    }, 100);
  }
  function pause() {
    if (!playback || playback.paused) return;
    playback.elapsed = Math.min(
      playback.items[playback.index].duration,
      playback.elapsed + (performance.now() - lastTick) * playback.speed,
    );
    playback.paused = true;
    clearInterval(tick);
    paint();
  }
  function stop(all = false) {
    clearInterval(tick);
    player?.remove();
    player = null;
    playback = !all ? suspended : null;
    suspended = null;
    clearHighlight();
    if (playback) mount(); // Return to the paused chapter; never auto-resume.
  }
  function item(text, key) {
    return { text, key, duration: Math.max(2600, text.length * 100) };
  }
  function read(text, language = "") {
    pause();
    if (playback?.mode === "continuous") suspended = playback;
    playback = {
      mode: "single",
      items: [
        item(
          text,
          novel.audioKey(text) ||
            `${context}:${language === "日语" ? "ja" : language}:${text.trim()}`,
        ),
      ],
      index: 0,
      elapsed: 0,
      speed: 1,
      paused: false,
    };
    prepare();
    mount();
    run();
    player.querySelector("button").focus({ preventScroll: true });
  }
  function continuous() {
    if (
      !["novel", "sampleReader"].includes(s.route) ||
      s.modal ||
      !s.signedIn ||
      s.adminArea
    )
      return;
    if (suspended) {
      stop();
    }
    if (playback?.mode === "continuous") {
      if (playback.paused) toggle();
      return;
    }
    const elements = sentenceElements();
    if (!elements.length) return;
    const visible = elements.findIndex(
      (el) => el.getBoundingClientRect().bottom > 140,
    );
    const index = cursor ?? Math.max(0, visible);
    playback = {
      mode: "continuous",
      items: elements.map((el, i) =>
        item(
          window.HarukaStudyText.plain(el),
          novel.audioKey(window.HarukaStudyText.plain(el)) ||
            `${context}:ja:${window.HarukaStudyText.plain(el).trim()}`,
        ),
      ),
      index,
      startIndex: index,
      elapsed: 0,
      speed: 1,
      paused: false,
    };
    prepare();
    mount();
    highlight(true);
    run();
  }
  function toggle() {
    if (!playback) return;
    if (!playback.paused) return pause();
    // A chapter cannot start playing behind an open study/settings dialog.
    if (playback.mode === "continuous" && s.modal) return;
    if (playback.completed) {
      playback.index =
        playback.mode === "continuous" ? playback.startIndex : playback.index;
      playback.elapsed = 0;
      playback.completed = false;
    }
    playback.paused = false;
    playback.follow = true;
    prepare();
    paint();
    highlight(true);
    run();
  }
  function refresh() {
    const next = contextKey();
    if (context !== next) {
      stop(true);
      cursor = undefined;
      if (
        context?.split(":").slice(0, 3).join(":") !==
        next.split(":").slice(0, 3).join(":")
      )
        prepared.clear();
      context = next;
    }
    const nextModal = `${s.modal}:${s.modal === "selectionQuery" ? s.selectionMessage?.selection?.novelSentenceId || "" : ""}`;
    if (modalContext !== nextModal && playback?.mode === "single") stop();
    modalContext = nextModal;
    if (
      s.modal === "selectionQuery" &&
      s.selectionMessage?.selection?.novelSentenceId
    ) {
      const selectedIndex = sentenceElements().findIndex(
        (el) =>
          el.dataset.novelSentence ===
          s.selectionMessage.selection.novelSentenceId,
      );
      if (selectedIndex >= 0) cursor = selectedIndex;
    }
    if (["novel", "sampleReader"].includes(s.route)) {
      root
        .querySelectorAll(".prose p,.reading-prose p,[data-novel-prose] p")
        .forEach((p) => {
          if (p.querySelector("[data-reading-sentence]")) return;
          const parts = [
            ...new Intl.Segmenter("ja", { granularity: "sentence" }).segment(
              p.textContent,
            ),
          ];
          p.innerHTML = parts
            .map(
              (part) => `<span data-reading-sentence>${e(part.segment)}</span>`,
            )
            .join("");
        });
    }
    if (s.modal) pause();
    // Keep the chapter checkpoint across modal/query renders, but hide its controls behind the modal.
    if (playback?.mode === "continuous" && s.modal) {
      player?.remove();
      player = null;
    } else mount();
  }
  document.addEventListener("change", (event) => {
    if (
      playback &&
      player?.contains(event.target) &&
      event.target.matches("select")
    ) {
      playback.speed = Number(event.target.value);
    }
  });
  for (const eventName of ["wheel", "touchmove"])
    document.addEventListener(
      eventName,
      () => {
        if (playback?.mode === "continuous") playback.follow = false;
      },
      { passive: true },
    );
  window.addEventListener("pagehide", () => stop(true));
  return {
    refresh,
    read,
    pause,
    stop,
    continuous,
    toggle,
    focus: (node) => {
      const el = (node?.nodeType === 1 ? node : node?.parentElement)?.closest(
        "[data-reading-sentence]",
      );
      if (el) cursor = sentenceElements().indexOf(el);
    },
  };
};
