/* Chapter preparation is an in-memory timing demo; no NLP, AI, audio or downloads. */
window.HarukaNovelLearning = ({
  s,
  root,
  render,
  open,
  close,
  query,
  docked = false,
  clearReader = () => {},
}) => {
  const { escape: e, icon: I } = window.HarukaCore;
  const chapters = window.HarukaNovelSamples;
  const labels = { analysis: 'AI 解析', audio: '朗读' };
  const records = new Map();
  const audioCache = new Set();
  let timer, owner;
  let prepareChapter = 2;
  s.novelChapter = 2;
  s.novelAnalysis = false;
  const current = () => chapters[s.novelChapter];
  const panelActive = () =>
    docked && s.route === 'novel' && !!s.readerPanelOpen;
  const allowed = () =>
    s.signedIn && !s.adminArea && s.materials.some((m) => m.id === 'summer');
  const key = (sentence) => `summer-v1:${sentence.id}:ja:default`;
  const record = (c) => {
    if (!records.has(c))
      records.set(c, {
        draft: ['analysis', 'audio'],
        analysis: new Set(),
        audio: new Set(),
        localAnalysis: new Set(),
        running: new Set(),
        failed: false,
        paused: false,
        generated: { analysis: 0, audio: 0 },
      });
    const r = records.get(c);
    chapters[c].sentences.forEach((sentence) => {
      if (audioCache.has(key(sentence))) r.audio.add(sentence.id);
    });
    return r;
  };
  const local = (c, type, sentence) =>
    type === 'audio'
      ? audioCache.has(key(sentence))
      : record(c).localAnalysis.has(sentence.id);
  const count = (c, type) =>
    chapters[c].sentences.filter((sentence) => local(c, type, sentence)).length;
  const hasMissing = (c) =>
    record(c).draft.some(
      (type) => count(c, type) < chapters[c].sentences.length,
    );
  function card(sentence, c = s.novelChapter) {
    if (!record(c).analysis.has(sentence.id)) return null;
    return {
      id: `${sentence.id}-analysis`,
      kind: 'sentence',
      word: sentence.text,
      meaning: sentence.meaning,
      segments: sentence.segments,
      rule: sentence.rule,
      detail: sentence.detail,
      language: '日语',
      source: `夏の手紙 · 第 ${c + 1} 章 · 已准备解析示例`,
    };
  }
  function summary(c) {
    const total = chapters[c].sentences.length;
    const r = record(c);
    return `解析 ${count(c, 'analysis')}/${total} · 朗读 ${count(c, 'audio')}/${total}${r.running.size ? ' · 准备中' : r.failed ? ' · 已中断' : r.paused ? ' · 已暂停' : ''}`;
  }
  function ruby(sentence) {
    let result = '',
      offset = 0;
    const readings = [...sentence.readings].sort(
      (a, b) => b[0].length - a[0].length,
    );
    while (offset < sentence.text.length) {
      const item = readings.find(([word]) =>
        sentence.text.startsWith(word, offset),
      );
      if (item) {
        result += `<ruby>${e(item[0])}<rt aria-hidden="true">${e(item[1])}</rt></ruby>`;
        offset += item[0].length;
      } else {
        result += e(sentence.text[offset]);
        offset++;
      }
    }
    return result;
  }
  function prose() {
    return current()
      .paragraphs.map(
        (paragraph) =>
          `<p>${paragraph.map((sentence) => `<span data-reading-sentence data-novel-sentence="${sentence.id}" data-canonical-text="${e(sentence.text)}" ${s.novelAnalysis ? 'role="button" tabindex="0"' : ''} ${s.novelAnalysis ? `aria-label="查看句子解析：${e(sentence.text)}"` : ''} class="${s.novelAnalysis ? 'novel-sentence-action' : ''} ${s.selectionMessage?.selection?.novelSentenceId === sentence.id && (s.modal === 'selectionQuery' || panelActive()) ? 'is-analyzing' : ''}">${s.novelAnalysis ? ruby(sentence) : e(sentence.text)}</span>`).join('')}</p>`,
      )
      .join('');
  }
  function controls() {
    return `<div class="novel-study-controls"><div class="novel-mode" role="group" aria-label="小说阅读模式"><button type="button" data-novel="mode" data-mode="read" aria-pressed="${!s.novelAnalysis}">阅读</button><button type="button" data-novel="mode" data-mode="analysis" aria-pressed="${s.novelAnalysis}">解析</button></div><button class="text-btn" type="button" data-novel="prepare" data-chapter="${s.novelChapter}">${I('database')}准备本章</button></div><p class="selection-hint">${s.novelAnalysis ? '点击句子看解析，长按可选词查询。' : '长按一句，点选词汇后查询。'}</p><p class="novel-cache-summary" data-novel-status="${s.novelChapter}">${summary(s.novelChapter)}</p>`;
  }
  function chapterList() {
    return `<div class="novel-chapter-list"><p class="small muted">4 章内置节选，可分别准备。</p>${chapters.map((chapter, c) => `<div class="novel-chapter-row"><button type="button" data-novel="chapter" data-chapter="${c}" ${c === s.novelChapter ? 'aria-current="page"' : ''}><span>${String(c + 1).padStart(2, '0')}</span><strong>${e(chapter.title)}</strong><small data-novel-status="${c}">${summary(c)}</small></button><button type="button" class="icon-btn" data-novel="prepare" data-chapter="${c}" aria-label="准备第 ${c + 1} 章">${I('database')}</button></div>`).join('')}</div>`;
  }
  function progressHTML(c) {
    const r = record(c),
      total = chapters[c].sentences.length;
    return Object.keys(labels)
      .map(
        (type) =>
          `<div class="novel-progress" data-kind="${type}" data-generated="${r.generated[type]}"><div><strong>${labels[type]}</strong><span>${count(c, type)}/${total} 句本机就绪</span></div><progress max="${total}" value="${count(c, type)}" aria-label="${labels[type]}缓存进度"></progress><small>${r[type].size}/${total} 句已准备${count(c, type) === total ? ' · 可直接使用' : ''}</small></div>`,
      )
      .join('');
  }
  function dialog() {
    if (s.modal !== 'chapterPrepare') return null;
    const r = record(prepareChapter);
    return {
      title: '准备章节',
      content: `<div class="novel-prepare"><label class="field">选择章节<select data-novel-chapter>${chapters.map((chapter, c) => `<option value="${c}" ${c === prepareChapter ? 'selected' : ''}>第 ${c + 1} 章 · ${e(chapter.title)}</option>`).join('')}</select></label><fieldset class="novel-cache-options"><legend>缓存内容 · 可多选</legend>${Object.keys(
        labels,
      )
        .map(
          (type) =>
            `<label><input type="checkbox" data-novel-cache="${type}" ${r.draft.includes(type) ? 'checked' : ''} ${r.running.size ? 'disabled' : ''}><span><strong>${labels[type]}</strong><small>${type === 'analysis' ? '逐句译文、意群与语法释义' : '逐句音频，单句与连续朗读共用'}</small></span></label>`,
        )
        .join(
          '',
        )}</fieldset><div data-novel-progress="${prepareChapter}">${progressHTML(prepareChapter)}</div><p class="note" data-novel-preparation-state role="status"></p><div class="button-row"><button class="primary" type="button" data-novel="start">开始准备</button><button class="secondary" type="button" data-novel="pause">暂停准备</button></div><p class="note">内置节选演示，无实际 AI、音频或下载。正式准备使用本人模型配置，已有内容直接复用。</p><details class="novel-demo"><summary>原型状态演示</summary><button class="text-btn" type="button" data-novel="fail">模拟准备中断</button></details></div>`,
    };
  }
  function panelHeader(message) {
    const id = message?.selection?.novelSentenceId;
    if (!id) return '';
    const c = message.selection.novelChapter,
      chapter = chapters[c];
    const index = chapter.sentences.findIndex((sentence) => sentence.id === id),
      sentence = chapter.sentences[index];
    if (!sentence) return '';
    const readyAudio = local(c, 'audio', sentence);
    return `<div class="novel-analysis-actions"><span>第 ${index + 1} / ${chapter.sentences.length} 句</span>${readyAudio ? `<button type="button" class="secondary" data-pronounce="${e(sentence.text)}" data-language="ja" aria-label="朗读原句">${I('speaker')}朗读原句</button>` : `<button type="button" class="secondary" data-novel="prepareAudio" data-chapter="${c}">${I('speaker')}准备朗读</button>`}</div><div class="novel-sentence-nav"><button class="text-btn" type="button" data-novel="previous" ${index === 0 ? 'disabled' : ''}>上一句</button><button class="text-btn" type="button" data-novel="next" ${index === chapter.sentences.length - 1 ? 'disabled' : ''}>下一句</button></div>${message.card ? '' : `<p>本句解析尚未准备。可以先准备本章，再回来逐句查看。</p><button class="primary" type="button" data-novel="prepareAnalysis" data-chapter="${c}">准备本章解析</button>`}`;
  }
  function openSentence(index, replace = false) {
    const sentence = current().sentences[index];
    if (!sentence || !allowed()) return;
    const element = root.querySelector(
      `[data-novel-sentence="${sentence.id}"]`,
    );
    const selection = {
      text: sentence.text,
      sentence: sentence.text,
      source: `夏の手紙 · 第 ${s.novelChapter + 1} 章 · ${current().title}`,
      route: s.route,
      modal: '',
      offset: 0,
      scopeIndex: [...root.querySelectorAll('[data-study-text]')].indexOf(
        element,
      ),
      novelSentenceId: sentence.id,
      novelChapter: s.novelChapter,
    };
    query(selection, { card: card(sentence), replace });
  }
  function paint() {
    root.querySelectorAll('[data-novel-status]').forEach((el) => {
      el.textContent = summary(Number(el.dataset.novelStatus));
    });
    root.querySelectorAll('[data-novel-progress]').forEach((el) => {
      el.innerHTML = progressHTML(Number(el.dataset.novelProgress));
    });
    const button = root.querySelector('[data-novel="start"]');
    if (!button) return;
    const r = record(prepareChapter);
    button.disabled =
      !r.draft.length || !!r.running.size || !hasMissing(prepareChapter);
    button.textContent = r.running.size
      ? '准备中…'
      : r.failed
        ? '重试未完成内容'
        : r.paused
          ? '继续准备'
          : r.draft.length && !hasMissing(prepareChapter)
            ? '所选内容已就绪'
            : '开始准备';
    root.querySelector('[data-novel="pause"]').disabled = !r.running.size;
    root.querySelector('[data-novel="fail"]').disabled = !r.running.size;
    root.querySelectorAll('[data-novel-cache]').forEach((el) => {
      el.disabled = !!r.running.size;
    });
    root.querySelector('[data-novel-preparation-state]').textContent = !r.draft
      .length
      ? '请至少选择一种缓存内容。'
      : r.failed
        ? '准备已中断，已完成内容保留；重试只补缺失部分。'
        : r.running.size
          ? '正在准备所选内容，可以关闭面板继续阅读。'
          : r.paused
            ? '已暂停，已完成内容保留。'
            : !hasMissing(prepareChapter)
              ? '所选内容已在本机就绪。'
              : '只处理勾选项，已有结果不会重复生成。';
  }
  function step() {
    if (!allowed()) return reset();
    let panelChanged = false;
    for (const [c, r] of records) {
      for (const type of [...r.running]) {
        const sentence = chapters[c].sentences.find(
          (item) => !local(c, type, item),
        );
        if (!sentence) {
          r.running.delete(type);
          continue;
        }
        if (!r[type].has(sentence.id)) {
          r[type].add(sentence.id);
          r.generated[type]++;
        } else if (type === 'audio') audioCache.add(key(sentence));
        else r.localAnalysis.add(sentence.id);
        if (
          (s.modal === 'selectionQuery' || panelActive()) &&
          s.selectionMessage?.selection?.novelSentenceId === sentence.id
        ) {
          const ready = card(sentence, c);
          s.selectionMessage.card = ready
            ? { ...ready, selection: s.selectionMessage.selection }
            : null;
          panelChanged = true;
        }
        if (count(c, type) === chapters[c].sentences.length)
          r.running.delete(type);
      }
    }
    if (panelChanged) render();
    else paint();
    if (![...records.values()].some((r) => r.running.size)) {
      clearInterval(timer);
      timer = null;
    }
  }
  function reset() {
    clearInterval(timer);
    timer = null;
    records.clear();
    audioCache.clear();
    s.novelAnalysis = false;
    s.novelChapter = 2;
    if (docked && s.readerPanelOpen) clearReader();
  }
  function refresh() {
    if (s.route !== 'novel') {
      s.novelPrepareReturn = false;
      if (docked && s.readerPanelOpen) clearReader();
    }
    const next = `${s.signedIn}:${s.adminArea}:${s.serviceAddress}`;
    if (owner !== undefined && owner !== next) reset();
    owner = next;
    if (!allowed()) reset();
  }
  function afterRender() {
    paint();
    const isPanel =
      s.modal === 'selectionQuery' &&
      s.selectionMessage?.selection?.novelSentenceId;
    root
      .querySelector('[role="dialog"]')
      ?.classList.toggle('novel-analysis-dialog', !!isPanel);
  }
  // Chromium cannot drag-select a focusable inline span across wrapped lines.
  // Keep keyboard stops between gestures, but let pointer selection use native text.
  let pointerSentence;
  function restoreSentenceTabStop() {
    if (pointerSentence?.element.isConnected)
      pointerSentence.element.setAttribute(
        'tabindex',
        pointerSentence.tabIndex,
      );
    pointerSentence = null;
  }
  document.addEventListener(
    'pointerdown',
    (event) => {
      if (!event.isPrimary || event.button !== 0) return;
      restoreSentenceTabStop();
      const element = event.target.closest('[data-novel-sentence][tabindex]');
      if (!element || !root.contains(element) || element.closest('[inert]'))
        return;
      pointerSentence = { element, tabIndex: element.getAttribute('tabindex') };
      element.removeAttribute('tabindex');
    },
    true,
  );
  document.addEventListener('pointerup', restoreSentenceTabStop, true);
  document.addEventListener('pointercancel', restoreSentenceTabStop, true);
  document.addEventListener('change', (event) => {
    if (!root.contains(event.target) || !allowed()) return;
    if (event.target.matches('[data-novel-chapter]')) {
      prepareChapter = Number(event.target.value);
      render();
    }
    if (event.target.matches('[data-novel-cache]')) {
      record(prepareChapter).draft = [
        ...root.querySelectorAll('[data-novel-cache]:checked'),
      ].map((el) => el.dataset.novelCache);
      paint();
    }
  });
  document.addEventListener('click', (event) => {
    if (
      !allowed() ||
      !root.contains(event.target) ||
      event.target.closest('[inert]')
    )
      return;
    const sentence = event.target.closest('[data-novel-sentence]');
    if (sentence && s.novelAnalysis && !s.modal) {
      event.preventDefault();
      sentence.focus({ preventScroll: true });
      openSentence(
        current().sentences.findIndex(
          (item) => item.id === sentence.dataset.novelSentence,
        ),
      );
      return;
    }
    const button = event.target.closest('[data-novel]');
    if (!button) return;
    const action = button.dataset.novel;
    if (action === 'mode') {
      const anchor = [...root.querySelectorAll('[data-novel-sentence]')].find(
        (el) => el.getBoundingClientRect().bottom > 140,
      )?.dataset.novelSentence;
      s.novelAnalysis = button.dataset.mode === 'analysis';
      if (docked) {
        clearReader();
        s.readerPanelOpen = s.novelAnalysis;
      }
      render();
      root
        .querySelector(`[data-novel-sentence="${anchor}"]`)
        ?.scrollIntoView({ block: 'nearest' });
      root
        .querySelector(`[data-mode="${button.dataset.mode}"]`)
        ?.focus({ preventScroll: true });
    }
    if (action === 'chapter') {
      if (docked) {
        clearReader();
        s.readerPanelOpen = s.novelAnalysis;
      }
      s.novelChapter = Number(button.dataset.chapter);
      if (s.modal) close();
      else render();
    }
    if (['prepare', 'prepareAudio', 'prepareAnalysis'].includes(action)) {
      s.novelPrepareReturn =
        (s.modal === 'selectionQuery' || panelActive()) &&
        !!s.selectionMessage?.selection?.novelSentenceId;
      prepareChapter = Number(button.dataset.chapter);
      if (action !== 'prepare' && !record(prepareChapter).running.size)
        record(prepareChapter).draft = [
          action === 'prepareAudio' ? 'audio' : 'analysis',
        ];
      open('chapterPrepare');
    }
    if (
      action === 'start' &&
      record(prepareChapter).draft.length &&
      !record(prepareChapter).running.size
    ) {
      const r = record(prepareChapter);
      r.failed = false;
      r.paused = false;
      r.running = new Set(r.draft);
      if (!timer) timer = setInterval(step, 420);
      paint();
    }
    if (action === 'pause' || action === 'fail') {
      const r = record(prepareChapter);
      r.running.clear();
      r.paused = action === 'pause';
      r.failed = action === 'fail';
      paint();
    }
    if (action === 'previous' || action === 'next') {
      const index = current().sentences.findIndex(
        (item) => item.id === s.selectionMessage?.selection?.novelSentenceId,
      );
      openSentence(index + (action === 'next' ? 1 : -1), true);
    }
  });
  document.addEventListener('keydown', (event) => {
    if (
      s.novelAnalysis &&
      !s.modal &&
      allowed() &&
      event.target.matches('[data-novel-sentence]') &&
      ['Enter', ' '].includes(event.key) &&
      !event.altKey
    ) {
      event.preventDefault();
      event.target.click();
    }
  });
  window.addEventListener('pagehide', () => {
    clearInterval(timer);
    timer = null;
  });
  return {
    current,
    panelActive,
    prose,
    controls,
    chapterList,
    dialog,
    panelHeader,
    refresh,
    afterRender,
    audioCache,
    cached: (selection, text) => {
      if (selection.route !== 'novel' || selection.modal || selection.panel)
        return null;
      const element =
        root.querySelectorAll('[data-study-text]')[selection.scopeIndex];
      const sentence = current().sentences.find(
        (item) =>
          item.id === element?.dataset.novelSentence && item.text === text,
      );
      return sentence ? card(sentence) : null;
    },
    audioKey: (text) =>
      s.route === 'novel'
        ? key(
            current().sentences.find(
              (sentence) => sentence.text.trim() === text.trim(),
            ) || { id: text.trim() },
          )
        : null,
    tokens: (text, element) =>
      s.route === 'novel' &&
      !s.modal &&
      !element?.closest('[data-reader-panel]') &&
      current().sentences.find((sentence) => sentence.text === text)?.tokens,
    source: () => `夏の手紙 · 第 ${s.novelChapter + 1} 章`,
  };
};
