/* DESIGN22: in-memory settings, context and cache examples; no model or storage API. */
window.HarukaLearningPreferences = ({ s, root, render }) => {
  const { escape: e, icon: I } = window.HarukaCore;
  const models = {
    gemini: {
      label: 'Gemini · 自然朗读（示例）',
      provider: 'Gemini TTS',
      voices: ['日语 · 清晰', '英语 · 自然'],
      formats: ['wav'],
      style: true,
    },
    routerSpeech: {
      label: 'OpenRouter · 专用朗读（示例）',
      provider: 'OpenRouter TTS',
      voices: ['日语 · 柔和', '英语 · 清晰'],
      formats: ['mp3', 'wav'],
      style: false,
    },
    routerAudio: {
      label: 'OpenRouter · 音频输出（示例）',
      provider: 'OpenRouter TTS',
      voices: ['日语 · 明亮'],
      formats: ['wav'],
      style: true,
    },
  };
  let budget = 10000,
    model = 'gemini',
    voice = models.gemini.voices[0],
    format = 'wav',
    style = '自然';
  let status = '',
    textLimit = 100,
    audioLimit = 500,
    owner;
  const queries = new Map(),
    localQueries = new Set(),
    audio = new Set(),
    localAudio = new Set(),
    preparedQueries = new Set(),
    localPreparedQueries = new Set();
  const estimate = (text) => Math.ceil([...text].length / 2); // Labelled demo estimate, never supplier usage.
  let activeSpeech = JSON.stringify([model, voice, style]);
  const speechIdentity = () => activeSpeech;
  function sync() {
    const next = `${s.signedIn}:${s.adminArea}:${s.serviceAddress}`;
    if (owner !== undefined && owner !== next) {
      queries.clear();
      preparedQueries.clear();
      localPreparedQueries.clear();
      localQueries.clear();
      audio.clear();
      localAudio.clear();
      budget = 10000;
      textLimit = 100;
      audioLimit = 500;
      status = '';
      model = 'gemini';
      voice = models.gemini.voices[0];
      format = 'wav';
      style = '自然';
      activeSpeech = JSON.stringify([model, voice, style]);
      s.speechProvider = models.gemini.provider;
      s.explicitQueryContext = '';
    }
    owner = next;
  }
  function contextSettings() {
    return `<section class="surface learning-preferences"><h2>查询与上下文</h2><p>查询会携带当前句和前后文，帮助理解词义与指代。</p><form data-learning-form="context" class="form-grid"><label class="field">前后文预算（tokens）<input name="contextBudget" type="number" min="1000" max="64000" step="1" required value="${budget}" aria-describedby="context-budget-help"></label><div class="button-row context-presets">${[5000, 10000, 20000].map((n) => `<button type="button" class="secondary" data-context-preset="${n}">${n.toLocaleString('en-US')}</button>`).join('')}</div><p class="note" id="context-budget-help">默认 10,000，支持 1,000–64,000。Token 是模型计算文字的单位，不等于字数。前后文合计计算，当前完整句另计；内容不足时不凑满。</p><div class="context-budget-example"><strong>本次最多 ${budget.toLocaleString('en-US')} tokens 前后文</strong><p>从当前句向两侧取同章或同单元内容。模型容量不足时，会显示实际缩减范围。</p></div><button class="primary" type="submit">保存查询偏好</button><p role="status" data-learning-status>${e(status)}</p></form><p class="note">仅影响下一次查询，已有结果和正在进行的任务保持原样。</p></section>`;
  }
  function speechSettings() {
    const m = models[model];
    return `<div class="learning-preferences stack"><p>每个模型使用自己的声音与能力配置。所有成功朗读都会保存，再次播放优先复用。</p><div class="surface form-grid"><label class="field">TTS 模型<select data-learning-setting="model">${Object.entries(
      models,
    )
      .map(
        ([key, item]) =>
          `<option value="${key}" ${model === key ? 'selected' : ''}>${item.label}</option>`,
      )
      .join(
        '',
      )}</select></label><label class="field">默认声音<select data-learning-setting="voice">${m.voices.map((v) => `<option ${voice === v ? 'selected' : ''}>${v}</option>`).join('')}</select></label><label class="field">本机播放格式<select data-learning-setting="format">${m.formats.map((f) => `<option value="${f}" ${format === f ? 'selected' : ''}>${f.toUpperCase()}</option>`).join('')}</select></label>${m.style ? `<label class="field">朗读风格<select data-learning-setting="style">${['自然', '轻柔'].map((v) => `<option ${style === v ? 'selected' : ''}>${v}</option>`).join('')}</select></label>` : '<p class="note">此示例模型使用固定自然风格。</p>'}<label class="field">播放倍速：${s.speechSpeed.toFixed(1)}×<input type="range" min="0.7" max="1.5" step="0.1" value="${s.speechSpeed}" data-range="speechSpeed"></label><p class="note">倍速与本机格式转换复用已有音频；更换模型、声音或朗读风格会匹配另一份音频，旧版仍保留。</p><button type="button" class="primary" data-learning-action="saveSpeech">保存朗读偏好</button><p role="status" data-learning-status>${e(status)}</p></div><div class="surface stack"><h2>单词与全文朗读</h2><p>收藏中的标准单词优先使用已发布的标准声音。查询词汇、例句、AI解释和小说逐句朗读也都会缓存；私人上下文不会进入共享词音。</p><p class="note">模型与声音均为内置能力示例，不测试凭据、不播放真实音频。</p></div></div>`;
  }
  function cacheSettings() {
    const savedCount = new Set(
      [...queries.values()].map((card) => card.id).concat([...preparedQueries]),
    ).size;
    const localCount = new Set(
      [...localQueries]
        .map((key) => queries.get(key)?.id)
        .filter(Boolean)
        .concat([...localPreparedQueries]),
    ).size;
    return `<div class="learning-preferences stack"><p>已查解释和生成音频会自动保存，收藏用于归类。清理本机后，可重新下载已有成果。</p><div class="cache-layer-grid"><section class="surface stack"><h2>本机可用</h2><p><strong data-local-query-count>${localCount}</strong> 份解释 · <strong data-local-audio-count>${localAudio.size}</strong> 段音频</p><small>当前账号在本次演示中的副本</small><button class="danger-btn" type="button" data-modal="clearCache">${I('trash')}清除此账号本机缓存</button></section><section class="surface stack"><h2>已保存成果</h2><p><strong data-saved-query-count>${savedCount}</strong> 份解释 · <strong data-saved-audio-count>${audio.size}</strong> 段音频</p><small>模拟服务端记录，本机清理不删除</small><p>已有结果直接复用；缺少音频时需明确生成。试卷限次听力按考试播放规则处理。</p></section></div><form class="surface form-grid" data-learning-form="cache"><h2>本机空间</h2><label class="field">解释副本上限<select name="textLimit">${[50, 100, 250].map((n) => `<option value="${n}" ${textLimit === n ? 'selected' : ''}>${n} MB</option>`).join('')}</select></label><label class="field">音频副本上限<select name="audioLimit">${[250, 500, 1000, 2000].map((n) => `<option value="${n}" ${audioLimit === n ? 'selected' : ''}>${n} MB</option>`).join('')}</select></label><p class="note">空间不足时清理较久未使用的本机副本；正在播放和使用的内容优先保留。</p><button class="primary" type="submit">保存本机上限</button><p role="status" data-learning-status>${e(status)}</p></form><p class="note">当前为内存演示，刷新重置，不写入音频文件或实际占用上述空间。</p></div>`;
  }
  function captureContext(selection, novel) {
    if (!selection)
      return {
        budget,
        before: '',
        after: '',
        center: '',
        explicit: s.explicitQueryContext || '',
        source: '本次输入',
        identity: 'manual',
      };
    const host = root.querySelector('[role=dialog]') || root;
    const element =
      host.querySelectorAll('[data-study-text]')[selection.scopeIndex];
    const field = element
      ? window.HarukaStudyText.plain(element)
      : selection.sentence || selection.text;
    const target = selection.sentence || selection.text;
    let start = Math.max(0, selection.offset ?? field.indexOf(target));
    const segments = [
      ...new Intl.Segmenter(undefined, { granularity: 'sentence' }).segment(
        field,
      ),
    ];
    const touched = segments.filter(
      (part) =>
        part.index < start + target.length &&
        part.index + part.segment.length > start,
    );
    let center = touched.length
      ? touched.map((part) => part.segment).join('')
      : target;
    let at = touched[0]?.index ?? start;
    let text = field;
    let identity = `${selection.source}:${selection.scopeIndex}:${selection.offset}:${element?.closest('[data-card-id]')?.dataset.cardId || s.selectedWord || ''}`;
    if (selection.route === 'novel' && !selection.modal && !selection.panel) {
      const paragraphs = novel
        .current()
        .paragraphs.map((parts) => parts.map((item) => item.text).join(''));
      text = paragraphs.join('\n');
      const paragraphIndex = [
        ...root.querySelectorAll('.prose p,.reading-prose p'),
      ].indexOf(element);
      if (paragraphIndex >= 0)
        at += paragraphs
          .slice(0, paragraphIndex)
          .reduce((n, value) => n + value.length + 1, 0);
      else at = Math.max(0, text.indexOf(center));
      if (selection.novelSentenceId) {
        const sentence = novel
          .current()
          .sentences.find((item) => item.id === selection.novelSentenceId);
        if (sentence) {
          center = sentence.text;
          at = text.indexOf(center);
        }
      }
      identity = `summer-v1:chapter-${s.novelChapter}:${selection.novelSentenceId || `${selection.scopeIndex}:${selection.offset}`}`;
    }
    const beforeParts = [
      ...new Intl.Segmenter(undefined, { granularity: 'sentence' }).segment(
        text.slice(0, at),
      ),
    ].map((part) => part.segment);
    const afterParts = [
      ...new Intl.Segmenter(undefined, { granularity: 'sentence' }).segment(
        text.slice(at + center.length),
      ),
    ].map((part) => part.segment);
    const before = [],
      after = [];
    let available = budget;
    // Alternate nearest complete sentences; unused space naturally passes to the other side.
    while (beforeParts.length || afterParts.length) {
      const left = beforeParts.pop();
      if (left && estimate(left) <= available) {
        before.unshift(left);
        available -= estimate(left);
      }
      const right = afterParts.shift();
      if (right && estimate(right) <= available) {
        after.push(right);
        available -= estimate(right);
      }
    }
    return {
      budget,
      center,
      before: before.join(''),
      after: after.join(''),
      explicit: '',
      source: selection.source,
      identity,
    };
  }
  function rememberQuery(card, context, target) {
    const key = JSON.stringify([
      context.identity,
      target,
      context.center,
      context.before,
      context.after,
      context.explicit,
      context.attachments || [],
      s.explanationLanguage,
    ]);
    const saved = queries.get(key);
    const reuse = saved
      ? localQueries.has(key)
        ? '已复用本机解释'
        : '已取回保存的解释'
      : '解释已保存';
    if (!saved && card) queries.set(key, card);
    if (saved || card) localQueries.add(key);
    return {
      card: saved || card,
      cacheNotice: saved || card ? reuse : '未生成结果',
      context,
    };
  }
  function contextSummary(message) {
    const c = message.context;
    if (!c) return '';
    const actual = estimate(c.before + c.after + c.explicit);
    return `<details class="query-context-detail"><summary>${e(message.cacheNotice || '查询上下文')} · ${actual ? '已带前后文' : c.center ? '已带当前句' : '无额外上下文'}</summary><p>预算 ${c.budget.toLocaleString('en-US')} tokens · 本次约 ${actual} tokens 前后文（示例估算）</p>${c.before ? `<div><small>前文</small><p>${e(c.before)}</p></div>` : ''}${c.center ? `<div><small>当前句</small><p>${e(c.center)}</p></div>` : ''}${c.after ? `<div><small>后文</small><p>${e(c.after)}</p></div>` : ''}${c.explicit ? `<div><small>补充上下文</small><p>${e(c.explicit)}</p></div>` : ''}<p class="note">只使用当前来源中的已有内容。完整取文、权限和模型Token校验由正式服务完成。</p></details>`;
  }
  const composerContext = () =>
    `<details class="query-context-input"><summary>补充上下文（可选）</summary><label class="field">相关原文<textarea name="explicitContext" rows="3" maxlength="20000" placeholder="可粘贴这个词所在的句段…">${e(s.explicitQueryContext || '')}</textarea></label><p class="note">无材料来源时只使用本次输入，不自动带入其他查询。前后文预算 ${budget.toLocaleString('en-US')} tokens。</p></details>`;
  root.addEventListener(
    'click',
    (event) => {
      const preset = event.target.closest('[data-context-preset]');
      if (preset) {
        const input = root.querySelector('[name=contextBudget]');
        input.value = preset.dataset.contextPreset;
        input.focus();
      }
      if (event.target.closest('[data-learning-action="saveSpeech"]')) {
        activeSpeech = JSON.stringify([model, voice, style]);
        s.speechProvider = models[model].provider;
        status = '朗读偏好已保存，本次演示未调用模型。';
        render();
      }
      if (event.target.closest('[data-action="clearCacheConfirm"]')) {
        localQueries.clear();
        localPreparedQueries.clear();
        localAudio.clear();
      }
    },
    true,
  );
  root.addEventListener('change', (event) => {
    const setting = event.target.dataset.learningSetting;
    if (!setting) return;
    if (setting === 'model') {
      model = event.target.value;
      voice = models[model].voices[0];
      format = models[model].formats[0];
      style = '自然';
    }
    if (setting === 'voice') voice = event.target.value;
    if (setting === 'format') format = event.target.value;
    if (setting === 'style') style = event.target.value;
    status = '';
    render();
  });
  root.addEventListener('input', (event) => {
    if (event.target.name === 'explicitContext') {
      s.explicitQueryContext = event.target.value;
      event.target.setCustomValidity('');
    }
  });
  root.addEventListener(
    'submit',
    (event) => {
      const type = event.target.dataset.learningForm;
      if (!type) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      if (!event.target.reportValidity()) return;
      const values = new FormData(event.target);
      if (type === 'context') budget = Number(values.get('contextBudget'));
      if (type === 'cache') {
        textLimit = Number(values.get('textLimit'));
        audioLimit = Number(values.get('audioLimit'));
      }
      status =
        type === 'context'
          ? '查询偏好已保存，从下一次查询生效。'
          : '本机上限已保存（演示）。';
      render();
    },
    true,
  );
  const api = {
    sync,
    contextSettings,
    speechSettings,
    cacheSettings,
    speechIdentity,
    captureContext,
    rememberQuery,
    contextSummary,
    composerContext,
    rememberPrepared: (card, local = false) => {
      if (!card) return;
      preparedQueries.add(card.id);
      if (local) localPreparedQueries.add(card.id);
    },
    rememberAudio: (key, local = true) => {
      const hit = audio.has(key);
      audio.add(key);
      if (local) localAudio.add(key);
      return hit;
    },
  };
  s.learningDemo = api;
  return api;
};
