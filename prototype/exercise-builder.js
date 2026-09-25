/* Local selection preview only; no generation, model calls or learning evidence. */
window.HarukaExerciseBuilder = (s) => {
  const { data, escape: e, icon: I } = window.HarukaCore;
  s.practiceCollectionIds = [...s.collected];
  s.practiceAllowRepeat = false;
  const sourceTypes = [
    ['notebook', '单词本', '按词本选择单词', 'layers'],
    ['collection', '手选收藏', '逐条选择词句或卡片', 'bookmark'],
    ['textbook', '教材', '选择一个学习单元', 'book'],
    ['mistake', '错题', '按当前状态或收藏选题', 'warning'],
    ['report', '诊断薄弱点', '围绕已有诊断练习', 'spark'],
  ];
  const words = () => s.words.filter((w) => w.language === s.activeLanguage);
  const available = (key) => {
    if (key === 'notebook') return true;
    if (key === 'collection') return words().length > 0;
    if (s.activeLanguage !== '日语') return false;
    return key !== 'textbook' || s.materials.some((m) => m.id === 'daily');
  };
  function candidates() {
    const entries = new Map();
    const add = (id, title, detail, source) => {
      const old = entries.get(id);
      if (old) old.sources.push(source);
      else entries.set(id, { id, title, detail, sources: [source] });
    };
    for (const key of s.practiceSources.filter(available)) {
      if (key === 'notebook' || key === 'collection') {
        const books = s.notebooks.filter(
          (b) =>
            b.language === s.activeLanguage && s.practiceBookIds.includes(b.id),
        );
        for (const w of words()) {
          const chosen =
            key === 'collection'
              ? s.practiceCollectionIds.includes(w.id)
              : w.kind === 'word' &&
                (s.practiceAllWords ||
                  books.some(
                    (b) => w.book === b.id || w.books?.includes(b.id),
                  ));
          if (chosen)
            add(
              `collection:${w.id}`,
              w.word,
              w.meaning,
              key === 'collection' ? '手选收藏' : '单词本',
            );
        }
      }
      if (key === 'textbook') {
        const unit = data.textbook.units.find(
          (u) => u.id === s.practiceTextbookUnit,
        );
        unit?.items.forEach((item, index) =>
          add(`textbook:${unit.id}:${index}`, item, unit.title, '教材'),
        );
      }
      if (key === 'mistake') {
        s.mistakes
          .filter(
            (m) =>
              s.practiceMistakeScope === 'all' ||
              (s.practiceMistakeScope === 'current' &&
                m.state === '当前待纠正') ||
              (s.practiceMistakeScope === 'favorite' && m.favorite),
          )
          .forEach((m) => add(`mistake:${m.id}`, m.title, m.state, '错题'));
      }
      if (key === 'report')
        add(
          'report:direction',
          '方向助词：に / へ',
          '已有诊断中的薄弱点',
          '诊断',
        );
    }
    return [...entries.values()];
  }
  function details(key) {
    if (key === 'notebook') {
      const books = s.notebooks.filter((b) => b.language === s.activeLanguage);
      return `<div class="exercise-scope"><label class="exercise-check"><input type="radio" name="wordScope" data-practice-all="true" ${s.practiceAllWords ? 'checked' : ''}><span>全部本人单词</span></label><label class="exercise-check"><input type="radio" name="wordScope" data-practice-all="false" ${!s.practiceAllWords ? 'checked' : ''}><span>选择单词本</span></label></div>${!s.practiceAllWords ? `<div class="exercise-options">${books.map((b) => `<label class="exercise-check"><input type="checkbox" data-practice-book="${b.id}" ${s.practiceBookIds.includes(b.id) ? 'checked' : ''}><span>${e(b.title)}</span></label>`).join('') || '<p class="note">还没有这个语种的单词本。</p>'}</div>` : ''}`;
    }
    if (key === 'collection')
      return `<div class="exercise-options">${words()
        .map(
          (w) =>
            `<label class="exercise-check"><input type="checkbox" data-practice-collection="${w.id}" ${s.practiceCollectionIds.includes(w.id) ? 'checked' : ''}><span><strong>${e(w.word)}</strong><small>${e(w.meaning)}</small></span></label>`,
        )
        .join('')}</div>`;
    if (key === 'textbook')
      return `<label class="field">教材单元<select data-practice-unit>${data.textbook.units.map((u) => `<option value="${u.id}" ${s.practiceTextbookUnit === u.id ? 'selected' : ''}>${e(u.title)}</option>`).join('')}</select></label>`;
    if (key === 'mistake')
      return `<label class="field">错题范围<select data-practice-mistakes>${[
        ['current', '当前待纠正'],
        ['favorite', '已收藏历史'],
        ['all', '全部历史'],
      ]
        .map(
          ([value, label]) =>
            `<option value="${value}" ${s.practiceMistakeScope === value ? 'selected' : ''}>${label}</option>`,
        )
        .join('')}</select></label>`;
    return '<p class="note">方向助词：に / へ</p>';
  }
  function sources() {
    return `<label class="field exercise-language">学习语言<select data-setting="activeLanguage">${['日语', '英语'].map((lang) => `<option ${s.activeLanguage === lang ? 'selected' : ''}>${lang}</option>`).join('')}</select></label><div class="exercise-sources">${sourceTypes
      .map(([key, title, description, icon]) => {
        const enabled = available(key);
        const selected = enabled && s.practiceSources.includes(key);
        return `<section class="exercise-source ${selected ? 'selected' : ''}"><label class="exercise-source-heading"><input type="checkbox" data-source="${key}" ${selected ? 'checked' : ''} ${enabled ? '' : 'disabled'} ${selected ? `aria-controls="source-${key}"` : ''}>${I(icon)}<span><strong>${title}</strong><small>${enabled ? description : `暂无可用${e(s.activeLanguage)}${title}`}</small></span></label>${selected ? `<div class="exercise-source-detail" id="source-${key}">${details(key)}</div>` : ''}</section>`;
      })
      .join('')}</div>`;
  }
  function settings() {
    return `<div class="exercise-settings surface"><h2>题目设置</h2><div class="exercise-settings-fields"><label class="field">题型<select data-practice-type>${['语境填空', '词义选择', '翻译判断'].map((type) => `<option ${s.practiceQuestionType === type ? 'selected' : ''}>${type}</option>`).join('')}</select></label><label class="field">题量<select data-practice-count>${['1 题', '5 题', '10 题'].map((count) => `<option ${s.practiceCount === count ? 'selected' : ''}>${count}</option>`).join('')}</select></label></div><button class="text-btn" type="button" data-action="builderBack">${I('back')}修改来源</button></div>`;
  }
  const canGenerate = () =>
    candidates().length > 0 &&
    (parseInt(s.practiceCount, 10) <= candidates().length ||
      s.practiceAllowRepeat);
  function review() {
    const items = candidates();
    return `<section class="exercise-review surface" aria-labelledby="exercise-preview-title"><div class="exercise-review-heading"><h2 id="exercise-preview-title">出题范围</h2><span>${items.length} 项内容</span></div><p class="note">${e(s.activeLanguage)} · ${e(s.practiceQuestionType)} · ${e(s.practiceCount)}，相同收藏只计一次。</p>${items.length ? `<ul class="exercise-preview-list">${items.map((item) => `<li><strong>${e(item.title)}</strong><small>${e(item.sources.join(' / '))} · ${e(item.detail)}</small></li>`).join('')}</ul>` : '<p class="exercise-selection-warning">当前范围没有内容，请返回调整来源。</p>'}${items.length && parseInt(s.practiceCount, 10) > items.length ? `<div class="exercise-repeat"><p>当前 ${items.length} 项来源少于计划的 ${e(s.practiceCount)}。可减少题量，或允许同一来源出多题。</p><label class="exercise-check"><input type="checkbox" data-practice-repeat ${s.practiceAllowRepeat ? 'checked' : ''}><span>允许同一来源出多题</span></label></div>` : ''}<p class="exercise-demo-note">本次体验打开 1 道内置语境填空题；以上选项演示出题配置，不调用模型。</p><button type="button" class="primary full" data-action="generateDemo" ${canGenerate() ? '' : 'disabled'}>确认并体验示例 ${I('arrow')}</button></section>`;
  }
  function syncLanguage() {
    s.practiceSources = s.practiceSources.filter(available);
    s.practiceCollectionIds = s.practiceCollectionIds.filter((id) =>
      words().some((w) => w.id === id),
    );
    s.practiceAllowRepeat = false;
  }
  return { candidates, sources, settings, review, canGenerate, syncLanguage };
};
