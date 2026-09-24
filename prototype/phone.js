(() => {
  const {
    data,
    escape: e,
    icon: I,
    initialState,
    typeLabel,
    visibleMaterials,
  } = window.HarukaCore;
  const s = initialState();
  const root = document.getElementById('phone-app');
  const primary = ['library', 'notebooks', 'query', 'exercise', 'settings'];
  const parentRoute = {
    dailyWords: 'notebooks',
    sampleReader: 'library',
    sampleTextbook: 'library',
    sampleExamPrep: 'library',
    import: 'library',
    material: 'library',
    novel: 'library',
    textbookUnits: 'material',
    textbook: 'textbookUnits',
    textbookPractice: 'textbook',
    examPrep: 'library',
    examRun: 'examPrep',
    examResult: 'examPrep',
    notebook: 'notebooks',
    word: 'notebook',
    wordEdit: 'word',
    csv: 'notebooks',
    exerciseBuilder: 'exercise',
    practice: 'exercise',
    mistakes: 'exercise',
    mistake: 'mistakes',
    agent: 'exercise',
    report: 'exercise',
    notifications: 'settings',
    jobs: 'settings',
    profile: 'settings',
    languages: 'settings',
    appearance: 'settings',
    readingPrefs: 'settings',
    model: 'settings',
    speech: 'settings',
    usage: 'settings',
    cache: 'settings',
    security: 'settings',
    connection: 'settings',
    states: 'settings',
  };
  let navigationIndex = Number(history.state?.harukaMobileIndex || 0);
  let builderStep = location.hash.includes('exerciseBuilder?step=2') ? 1 : 0;
  let examPaused = false;
  let modalReturnFocus = '';
  const focusSelector = (element) => {
    if (!element?.attributes) return '';
    const attributes = [...element.attributes].filter(
      (a) => a.name.startsWith('data-') || a.name === 'name',
    );
    return attributes.length
      ? element.tagName.toLowerCase() +
          attributes.map((a) => `[${a.name}="${CSS.escape(a.value)}"]`).join('')
      : '';
  };
  const titles = {
    query: '查询',
    dailyWords: '每日单词',
    sampleReader: '阅读',
    sampleTextbook: '课本学习',
    sampleExamPrep: '试卷准备',
    import: '导入材料',
    material: '材料详情',
    novel: '夏の手紙',
    textbookUnits: '课本',
    textbook: '单元内容',
    textbookPractice: '课后题',
    examPrep: '试卷准备',
    examRun: '模拟考试',
    examResult: '考试结果',
    notebooks: '单词本',
    notebook: '词本详情',
    word: '词条详情',
    wordEdit: '编辑词条',
    csv: '单词 CSV',
    exercise: '练习',
    exerciseBuilder: '生成习题',
    practice: '逐题练习',
    mistakes: '错题库',
    mistake: '错题详情',
    agent: '学习 Agent',
    report: '学习诊断',
    notifications: '站内消息',
    settings: '设置',
    profile: '个人资料',
    languages: '语言选项',
    appearance: '外观与无障碍',
    readingPrefs: '阅读偏好',
    model: '个人模型',
    speech: '朗读与声音',
    usage: '模型用量',
    cache: '本机缓存',
    security: '安全与账号',
    connection: '服务连接',
    states: '状态样例',
    jobs: '任务进度',
    login: '登录',
    register: '注册',
    recovery: '找回密码',
    onboarding: '首次设置',
  };
  const go = (route, options = {}) => {
    if (!views[route]) return;
    if (options.materialId) s.chosenMaterial = options.materialId;
    if (route === s.route) {
      if (s.modal) closeModal();
      else render();
      window.scrollTo({ top: 0 });
      return;
    }
    s.previousRoute = s.route;
    s.route = route;
    s.modal = '';
    if (route === 'exerciseBuilder') builderStep = 0;
    if (route === 'import') {
      s.importStep = 0;
      s.importComplete = false;
      s.importType = '';
      s.importFile = '';
      s.importAnalyze = false;
    }
    if (!options.noHash) {
      if (options.replace || history.state?.harukaModal)
        history.replaceState(
          { harukaMobileIndex: navigationIndex },
          '',
          `#${route}`,
        );
      else
        history.pushState(
          { harukaMobileIndex: ++navigationIndex },
          '',
          `#${route}`,
        );
    }
    render();
    window.scrollTo({ top: 0 });
  };
  const toast = (message) => {
    s.toast = message;
    render();
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => {
      s.toast = '';
      root.querySelector('.toast')?.remove();
    }, 3500);
  };
  const openModal = (name) => {
    const nested = !!s.modal;
    if (!nested) modalReturnFocus = focusSelector(document.activeElement);
    s.modal = name;
    const state = {
      harukaMobileIndex: nested ? navigationIndex : ++navigationIndex,
      harukaModal: name,
      harukaBuilderStep: builderStep,
    };
    history[nested ? 'replaceState' : 'pushState'](state, '', location.href);
    render();
  };
  const closeModal = () => {
    if (history.state?.harukaModal) history.back();
    else {
      s.modal = '';
      render();
    }
  };
  const back = () => {
    if (s.modal) return closeModal();
    if (s.route === 'examRun' && s.examRunning) return openModal('examLeave');
    if (
      (s.route === 'exerciseBuilder' && builderStep === 1) ||
      (s.route === 'import' && s.importStep > 0)
    ) {
      history.back();
      return;
    }
    if (navigationIndex > 0) {
      history.back();
      return;
    }
    go(parentRoute[s.route] || 'library');
  };
  const btn = (label, route, kind = 'secondary', icon = '') =>
    `<button class="${kind}" type="button" data-go="${route}">${icon ? I(icon) : ''}${label}</button>`;
  const cover = (material) =>
    `<span class="cover ${material.tone}" aria-hidden="true">${e(material.cover)}</span>`;
  const badge = (text, kind = '') =>
    `<span class="tag ${kind}">${e(text)}</span>`;
  const head = () => {
    if (
      [
        'login',
        'register',
        'registrationStatus',
        'recovery',
        'onboarding',
      ].includes(s.route) ||
      (!s.signedIn && s.route === 'connection')
    )
      return '';
    const top = primary.includes(s.route);
    const unread = s.notifications.some((n) => n.unread);

    return `<header class="phone-head ${top ? 'root-head' : ''}">${top ? '<div class="head-brand"><span class="head-mark" aria-hidden="true">h</span>haruka</div>' : `<button class="head-back" type="button" data-action="back" aria-label="返回上一页">${I('back')}</button><div class="head-title">${e(titles[s.route] || 'Haruka')}</div>`}<div class="head-actions">${top ? `<button class="preview-label" type="button" data-modal="prototypeInfo">原型</button><button class="icon-btn ${unread ? 'unread-dot' : ''}" type="button" data-go="notifications" aria-label="站内消息">${I('bell')}</button>` : ''}</div></header>`;
  };
  const nav = () =>
    `<nav class="bottom-nav" aria-label="主要导航">${[
      ['library', '材料', 'library'],
      ['notebooks', '词本', 'layers'],
      ['query', '查询', 'message'],
      ['exercise', '练习', 'spark'],
      ['settings', '我的', 'user'],
    ]
      .map(
        ([route, label, icon]) =>
          `<button type="button" data-go="${route}" ${s.route === route ? 'aria-current="page"' : ''}>${I(icon)}<span>${label}</span></button>`,
      )
      .join('')}</nav>`;
  function materialRow(m) {
    return `<button class="mobile-material" type="button" data-material="${m.id}">${cover(m)}<span class="mobile-material-copy"><strong>${e(m.title)}</strong><small>${e(m.subtitle)}</small><span class="mobile-material-status ${m.type === 'exam' ? 'needs-review' : ''}">${m.type === 'exam' ? I('warning') : I('check')}${e(m.status)}</span></span>${I('chevron')}</button>`;
  }
  function library() {
    return extras.library();
  }

  function importScreen() {
    const steps = ['选择类型', '选择文件', '确认导入'];
    const current = Math.min(s.importStep, 2);
    let body = '';
    if (current === 0)
      body = `<div class="import-options">${[
        ['novel', '小说', '按章节阅读', 'book'],
        ['textbook', '课本', '按单元学习与练习', 'layers'],
        ['exam', '试卷', '整卷作答与评分', 'edit'],
      ]
        .map(
          ([k, t, d, icon]) =>
            `<button class="import-option" type="button" data-import-type="${k}" aria-pressed="${s.importType === k}"><span class="setting-icon">${I(icon)}</span><span class="row-copy"><strong>${t}</strong><small>${d}</small></span><span class="selection-dot">${s.importType === k ? I('check') : ''}</span></button>`,
        )
        .join(
          '',
        )}</div><div class="mobile-action-dock"><button class="primary full" type="button" data-go="import" ${s.importType ? '' : 'disabled'}>下一步 ${I('arrow')}</button></div>`;
    if (current === 1)
      body = `<div class="surface form-grid"><label class="field file-field">${I('upload')}<span>${s.importFile ? e(s.importFile) : '选择文件'}</span><input type="file" data-file="material" aria-label="选择材料文件"><small>原型仅记录文件名，不上传内容</small></label><label class="choice-row"><input type="checkbox" data-toggle="importAnalyze" ${s.importAnalyze ? 'checked' : ''}><span>AI 结构建议<small>使用个人模型整理章节或题目</small></span></label></div><div class="mobile-action-dock"><button class="primary full" type="button" data-action="importNext" ${s.importFile ? '' : 'disabled'}>下一步 ${I('arrow')}</button></div>`;
    if (current === 2)
      body = `<div class="surface summary-list"><div><span>材料类型</span><strong>${typeLabel[s.importType]}</strong></div><div><span>文件</span><strong>${e(s.importFile || '未选文件')}</strong></div><div><span>处理方式</span><strong>文本提取${s.importAnalyze ? '、AI 结构建议' : ''}</strong></div></div><p class="note mobile-end-note">原型仅创建示例任务，不处理文件或调用模型。</p><div class="mobile-action-dock"><button class="primary full" type="button" data-action="importConfirm">确认导入</button></div>`;
    return `<div class="step-caption">${current + 1} / 3${s.importType ? ` · ${typeLabel[s.importType]}` : ''}</div><h1 class="page-title">${steps[current]}</h1><div class="stepper" aria-hidden="true">${steps.map((_, i) => `<span class="${i <= current ? 'on' : ''}"></span>`).join('')}</div>${body}`;
  }
  function materialScreen() {
    const m =
      s.materials.find((x) => x.id === s.chosenMaterial) || s.materials[0];
    const target =
      m.type === 'novel'
        ? 'novel'
        : m.type === 'textbook'
          ? 'textbookUnits'
          : 'examPrep';
    return `<div class="material-identity">${cover(m)}<div><p class="small muted">${typeLabel[m.type]}</p><h1>${e(m.title)}</h1><p class="small muted">${e(m.subtitle)}</p></div></div>
      <p class="material-description">${e(m.detail)}</p>
      <div class="mobile-plain-list"><div class="row-wrap"><span class="row-copy"><strong>解析状态</strong><small>更新于 ${e(m.updated)}</small></span>${badge(m.status, m.type === 'exam' ? 'warn' : 'good')}</div><button class="setting-row" type="button" data-action="materialQuality"><span class="row-copy"><strong>解析与来源</strong></span>${I('chevron')}</button></div>
      <div class="mobile-action-dock">${btn(m.type === 'novel' ? '开始阅读' : m.type === 'textbook' ? '查看单元' : '校对试卷', target, 'primary full', 'arrow')}</div>`;
  }
  function novel() {
    const readerPaper =
      s.readingTheme === 'sepia'
        ? '#f7ead4'
        : s.readingTheme === 'dark'
          ? '#192535'
          : '#ffffff';
    const readerInk = s.readingTheme === 'dark' ? '#edf3ff' : '#152b42';
    const readerFont =
      s.readingFont === 'serif'
        ? "'Yu Mincho','Noto Serif JP',serif"
        : "'Segoe UI','Microsoft YaHei',sans-serif";
    const text = data.novel.paragraphs
      .map((paragraph, i) => {
        const key = i === 0 ? 'soft' : i === 1 ? 'smile' : null;
        const token =
          key === 'soft' ? 'そっと' : key === 'smile' ? '微笑んだ' : '';
        return `<p>${key ? e(paragraph).replace(token, `<button class="term-button" type="button" data-term="${key}" aria-pressed="${s.selectedTerm === key}">${token}</button>`) : e(paragraph)}</p>`;
      })
      .join('');
    return `<div class="mobile-reader-meta">第 03 章 / 12 章</div><h1 class="mobile-reader-title" lang="ja">窓の向こう</h1><article class="reader mobile-reader" style="--reader-paper:${readerPaper};--reader-ink:${readerInk};--reader-font:${readerFont}"><div class="reading-prose" lang="ja" style="--reader-size:${s.readingSize}px;--reader-line:${s.lineHeight}">${text}</div><div class="reader-bottom"><span>窓の向こう</span><span>03 / 12</span></div></article><div class="reader-dock" aria-label="阅读操作"><button type="button" data-modal="chapters">${I('library')}<span>目录</span></button><button type="button" data-modal="readerSettings">${I('settings')}<span>排版</span></button><button type="button" data-action="toggleSpeech">${I(s.playing ? 'pause' : 'headphones')}<span>${s.playing ? '暂停' : '朗读'}</span></button><button type="button" data-action="bookmark">${I('bookmark')}<span>书签</span></button></div>`;
  }
  function textbookUnits() {
    return `<div class="mobile-intro"><p class="step-caption">课本 · 日语</p><h1>日语的日常表达</h1></div><div class="mobile-list-heading"><h2>单元目录</h2><span>${data.textbook.units.length} 个可用单元</span></div><div class="mobile-plain-list">${data.textbook.units.map((unit, i) => `<button class="mobile-unit-row" type="button" data-textbook-unit="${unit.id}"><span class="mobile-unit-number">${String(i + 1).padStart(2, '0')}</span><span class="row-copy"><strong>${e(unit.title.replace(/^Unit \d+ · /, ''))}</strong><small>课文 · 词汇 · 语法 · 练习</small></span>${I('chevron')}</button>`).join('')}</div>`;
  }
  function textbook() {
    const unit =
      data.textbook.units.find((x) => x.id === s.textbookUnit) ||
      data.textbook.units[0];
    return `<div class="mobile-intro"><h1>${e(unit.title)}</h1></div><div class="mobile-list-heading"><h2>单元内容</h2></div><div class="mobile-plain-list">${unit.items.map((item, i) => `<button type="button" class="mobile-unit-row" data-action="textbookItem" data-index="${i}"><span class="setting-icon">${I(['book', 'library', 'spark', 'edit'][i])}</span><span class="row-copy"><strong>${e(item)}</strong><small>${['会话与课文', '词汇与释义', '用法与例句', '逐题练习'][i]}</small></span>${I('chevron')}</button>`).join('')}</div><div class="mobile-action-dock"><button class="primary full" type="button" data-go="textbookPractice">做课后题 ${I('arrow')}</button></div>`;
  }
  function textbookPractice() {
    const examples = {
      unit1: {
        prompt: '「わたしは学生です」中的「は」有什么作用？',
        options: ['提示话题', '表示移动方向', '表示过去时间', '连接并列句'],
        correct: 0,
        explanation: '「は」提示句子的话题。',
      },
      unit2: {
        ...data.textbook.question,
        explanation: '「へ」标示移动的方向。',
      },
      unit3: {
        prompt: '在咖啡馆点餐时，「ください」通常表达什么？',
        options: ['请给我', '欢迎回来', '我已吃完', '请稍等'],
        correct: 0,
        explanation: '「ください」在这里表达礼貌请求。',
      },
    };
    const q = examples[s.textbookUnit] || examples.unit1;
    return `<div class="mobile-step-label">${e(data.textbook.units.find((x) => x.id === s.textbookUnit)?.title || '当前单元')} · 示例题</div><div class="mobile-intro"><h1>课后题</h1></div><div class="surface stack"><h2 class="mobile-question">${e(q.prompt)}</h2><div class="answer-list">${q.options.map((answer, i) => `<button type="button" class="answer ${s.textbookSubmitted ? (i === q.correct ? 'correct' : i === s.textbookAnswer ? 'wrong' : '') : ''}" data-textbook-answer="${i}" aria-pressed="${s.textbookAnswer === i}" ${s.textbookSubmitted ? 'disabled' : ''}><span>${String.fromCharCode(65 + i)}</span>${e(answer)}</button>`).join('')}</div>${s.textbookSubmitted ? `<div class="feedback ${s.textbookAnswer === q.correct ? 'correct' : 'wrong'}"><strong>${s.textbookAnswer === q.correct ? '回答正确' : `这题选 ${String.fromCharCode(65 + q.correct)}`}</strong><div>${e(q.explanation)}</div></div><button type="button" class="secondary full" data-action="textbookReset">重新作答</button>` : `<button type="button" class="primary full" data-action="textbookSubmit" ${s.textbookAnswer < 0 ? 'disabled' : ''}>确认答案</button>`}</div>`;
  }
  function examPrep() {
    if (s.examRunning)
      return `<div class="mobile-intro"><h1>考试进行中</h1><p>答案已保留在当前页面。</p></div><div class="surface stack"><strong>已答 ${Object.keys(s.examAnswers).length} / ${data.exam.questions.length} 题</strong><p class="small muted">继续第 ${s.examQuestion + 1} 题 · 共 3 道示例题</p><button class="primary full" type="button" data-action="examResume">继续考试</button></div>`;
    return `<h1 class="page-title">N2 模拟试卷</h1><p class="page-subtitle">听力准备完成后即可开考。</p><div class="two" style="margin-top:20px"><div class="stat"><strong>38</strong><span>原卷题量</span></div><div class="stat"><strong>60</strong><span>分钟</span></div></div><p class="note" style="margin-top:12px">原型可试答其中 3 题，计时与听力为模拟状态。</p><div class="section-head"><h2>准备清单</h2></div><div class="surface stack"><div class="timeline-item"><span class="timeline-dot"></span><div class="timeline-content"><strong>题号与分值</strong><small>已提取 · 待校对</small></div></div><div class="timeline-item"><span class="timeline-dot"></span><div class="timeline-content"><strong>听力文字稿</strong><small>${s.examScriptMatched ? '匹配已确认' : '待确认脚本与题组'}</small></div></div><div class="timeline-item"><span class="timeline-dot"></span><div class="timeline-content"><strong>私有朗读音频</strong><small>${s.examAudioReady ? '已就绪（模拟）' : '等待脚本确认'}</small></div></div></div><div class="stack" style="margin-top:18px"><button type="button" class="secondary full" data-modal="examScript">校对听力稿</button><button type="button" class="secondary full" data-action="examTts" ${s.examScriptMatched ? '' : 'disabled'}>生成听力音频（模拟）</button><button type="button" class="primary full" data-action="examFreeze" ${s.examScriptMatched && s.examAudioReady ? '' : 'disabled'}>${s.examReady ? '进入考前说明' : '确认版本并开考'}</button></div>`;
  }
  function examRun() {
    const q = data.exam.questions[s.examQuestion];
    const answered = Object.keys(s.examAnswers).length;
    return `<div class="mobile-exam-status"><span>示例剩余 42:18</span><span>已答 ${answered} / ${data.exam.questions.length}</span></div><div class="mobile-exam-commands"><button type="button" class="text-btn" data-modal="answerSheet">${I('grid')} 答题卡</button><button type="button" class="text-btn" data-action="examSave">${I('check')} 保存</button><button type="button" class="text-btn mobile-submit" data-modal="examSubmit">交卷</button></div><div class="mobile-intro"><h1>第 ${s.examQuestion + 1} 题</h1><p>${e(q.group)} · ${e(s.examDraft)}</p></div><div class="surface stack"><h2 class="mobile-question">${e(q.text)}</h2>${q.group === '听力' ? `<div class="callout">${I('headphones')}<span>原型没有可播放的听力音频。</span></div><button type="button" class="secondary full" data-action="examPlay">${I('play')} 播放听力（示意）</button>` : ''}<div class="answer-list">${q.options.map((answer, i) => `<button type="button" class="answer" data-exam-answer="${i}" aria-pressed="${s.examAnswers[q.id] === i}"><span>${String.fromCharCode(65 + i)}</span>${e(answer)}</button>`).join('')}</div><button type="button" class="text-btn mobile-mark" data-action="examMark">${I('bookmark')} ${s.examMarked.includes(q.id) ? '取消标记' : '标记稍后检查'}</button></div><div class="mobile-action-dock mobile-exam-dock"><button class="secondary" type="button" data-action="examPrev" ${s.examQuestion === 0 ? 'disabled' : ''}>${I('back')} 上一题</button><button class="primary" type="button" data-action="examNext" ${s.examQuestion === data.exam.questions.length - 1 ? 'disabled' : ''}>下一题 ${I('arrow')}</button></div>`;
  }
  function examResult() {
    const count = data.exam.questions.filter(
      (q) => s.examAnswers[q.id] === q.correct,
    ).length;
    return `<h1 class="page-title">这次模拟已交卷。</h1><p class="page-subtitle">3 道示例题 · 本次作答结果</p><div class="brand-panel" style="margin-top:22px"><div class="eyebrow" style="color:#d8f36a">示例客观题</div><h2 style="font-size:42px;margin:6px 0">${count} / ${data.exam.questions.length}</h2><p>答对题数</p></div><div class="section-head"><h2>逐题复盘</h2></div><div class="list">${data.exam.questions.map((q, i) => `<div class="row-wrap"><span class="pill-count">${i + 1}</span><span class="row-copy"><strong>${e(q.group)} · ${e(q.text)}</strong><small>你的选择：${s.examAnswers[q.id] === undefined ? '未作答' : e(q.options[s.examAnswers[q.id]])} · 参考答案：${e(q.options[q.correct])}</small></span></div>`).join('')}</div><div class="button-row" style="margin-top:20px">${btn('查看错题库', 'mistakes', 'secondary')}${btn('返回书库', 'library', 'primary')}</div>`;
  }
  function notebooks() {
    return extras.notebooks();
  }

  function notebook() {
    return extras.notebooks();
  }

  function word() {
    return extras.notebooks();
  }

  function wordEdit() {
    return extras.notebooks();
  }

  function csv() {
    return `<h1 class="page-title">单词导入与导出</h1><p class="page-subtitle">导入前可预览词条与重复项。</p><div class="stack" style="margin-top:22px"><div class="surface stack"><h2 style="font-size:18px">导出词条</h2><p class="small muted">示例范围：全部词条 · 词本归属 · 释义与个人笔记。作答、错题和 AI 历史不在 CSV 中。</p><button class="secondary full" type="button" data-action="csvExport">${I('download')} 生成示例 CSV</button></div><div class="surface stack"><h2 style="font-size:18px">导入预览</h2><label class="field">选择 UTF-8 CSV<input type="file" data-file="csv" accept=".csv,text/csv"><small>${s.csvFile ? `已选择：${e(s.csvFile)}` : '仅演示文件选择，不读取文件内容。'}</small></label>${s.csvStep ? `<div class="soft-panel"><strong>示例预览 · 与所选文件内容无关</strong><p class="small">2 个词条 · 1 个重复项；导入不会恢复可信掌握历史。</p><div class="divider"></div><label class="choice-row"><input type="radio" name="duplicate" checked><span>重复项跳过</span></label><label class="choice-row"><input type="radio" name="duplicate"><span>只补充空字段</span></label></div><button class="primary full" type="button" data-action="csvConfirm">确认示例导入</button>` : `<button class="secondary full" type="button" data-action="csvPreview" ${s.csvFile ? '' : 'disabled'}>查看示例预览</button>`}</div></div>`;
  }
  function practiceCandidateCount() {
    let count = 0;
    if (s.practiceSources.includes('notebook')) {
      const ids = s.notebooks
        .filter(
          (b) =>
            b.language === s.activeLanguage &&
            (s.practiceAllWords || s.practiceBookIds.includes(b.id)),
        )
        .map((b) => b.id);
      count += s.words.filter(
        (w) =>
          w.kind === 'word' &&
          w.language === s.activeLanguage &&
          (s.practiceAllWords ||
            ids.includes(w.book) ||
            w.books?.some((id) => ids.includes(id))),
      ).length;
    }
    if (s.activeLanguage === '日语') {
      if (s.practiceSources.includes('collection')) count += s.collected.length;
      if (s.practiceSources.includes('textbook'))
        count += (
          data.textbook.units.find((x) => x.id === s.practiceTextbookUnit) ||
          data.textbook.units[0]
        ).items.length;
      if (s.practiceSources.includes('mistake'))
        count += s.mistakes.filter(
          (m) =>
            s.practiceMistakeScope === 'all' ||
            (s.practiceMistakeScope === 'current' &&
              m.state === '当前待纠正') ||
            (s.practiceMistakeScope === 'favorite' && m.favorite),
        ).length;
      if (s.practiceSources.includes('report')) count += 1;
    }
    return count;
  }
  function practiceSelectionSummary() {
    const parts = [];
    if (s.practiceSources.includes('notebook'))
      parts.push(
        s.practiceAllWords
          ? `全部本人${s.activeLanguage}单词`
          : `词本：${
              s.notebooks
                .filter((b) => s.practiceBookIds.includes(b.id))
                .map((b) => b.title)
                .join('、') || '未选词本'
            }`,
      );
    if (s.practiceSources.includes('collection'))
      parts.push(`手选收藏 ${s.collected.length} 项`);
    if (s.practiceSources.includes('textbook'))
      parts.push(
        `教材：${(data.textbook.units.find((x) => x.id === s.practiceTextbookUnit) || data.textbook.units[0]).title}`,
      );
    if (s.practiceSources.includes('mistake'))
      parts.push(
        `错题：${{ all: '全部历史', current: '当前待纠正', favorite: '已收藏' }[s.practiceMistakeScope]}`,
      );
    if (s.practiceSources.includes('report')) parts.push('诊断：方向助词');
    return parts.join(' · ');
  }
  function exerciseDetails() {
    return `<div class="stack" style="margin-top:14px">${
      s.practiceSources.includes('notebook')
        ? `<div class="surface stack"><h2 style="font-size:16px">单词范围</h2><label class="choice-row"><input type="radio" name="wordScope" data-practice-all="true" ${s.practiceAllWords ? 'checked' : ''}><span>全部本人单词</span></label><label class="choice-row"><input type="radio" name="wordScope" data-practice-all="false" ${s.practiceAllWords ? '' : 'checked'}><span>选择词本</span></label>${
            s.practiceAllWords
              ? ''
              : s.notebooks
                  .filter((book) => book.language === s.activeLanguage)
                  .map(
                    (book) =>
                      `<label class="choice-row"><input type="checkbox" data-practice-book="${book.id}" ${s.practiceBookIds.includes(book.id) ? 'checked' : ''}><span>${e(book.title)} · ${e(book.language)}</span></label>`,
                  )
                  .join('')
          }</div>`
        : ''
    }${s.practiceSources.includes('collection') ? `<div class="soft-panel"><strong>手选收藏</strong><p class="small">已选 ${s.collected.length} 个词句</p></div>` : ''}${s.practiceSources.includes('textbook') ? `<div class="surface"><label class="field">教材单元<select data-practice-unit>${data.textbook.units.map((unit) => `<option value="${unit.id}" ${s.practiceTextbookUnit === unit.id ? 'selected' : ''}>${e(unit.title)}</option>`).join('')}</select></label></div>` : ''}${s.practiceSources.includes('mistake') ? `<div class="surface"><label class="field">错题范围<select data-practice-mistakes><option value="current" ${s.practiceMistakeScope === 'current' ? 'selected' : ''}>当前待纠正</option><option value="favorite" ${s.practiceMistakeScope === 'favorite' ? 'selected' : ''}>已收藏历史</option><option value="all" ${s.practiceMistakeScope === 'all' ? 'selected' : ''}>全部历史</option></select></label></div>` : ''}${s.practiceSources.includes('report') ? `<div class="soft-panel"><strong>诊断薄弱点：方向助词</strong><p class="small">方向助词：に / へ</p></div>` : ''}</div>`;
  }
  function exercise() {
    return `<div class="page-heading"><h1>练习</h1><span>${e(s.activeLanguage)}</span></div>
      <button class="practice-create" type="button" data-go="exerciseBuilder"><span class="signal" aria-hidden="true"></span><strong>生成 AI 习题</strong><small>从词本、教材或错题中选源</small><span class="practice-create-action">选择来源 ${I('arrow')}</span></button>
      <div class="mobile-list-heading"><h2>已有习题</h2></div><div class="mobile-plain-list">${settingRow('practice', s.activeLanguage === '英语' ? '微光与希望' : '动作里的语气', '语境填空 · 1 题 · 示例', 'edit')}</div>
      <div class="mobile-list-heading"><h2>学习记录</h2></div><div class="mobile-plain-list">${settingRow('mistakes', '错题库', `${s.mistakes.filter((m) => m.state === '当前待纠正').length} 题待纠正`, 'warning')}${settingRow('report', '学习诊断', '最近 7 天', 'grid')}</div>
      <button class="mobile-activity agent-entry" type="button" data-go="agent">${I('message')}<span>问学习 Agent</span>${I('arrow')}</button>`;
  }
  function exerciseBuilder() {
    const selected = s.practiceSources;
    if (builderStep === 0) {
      return `<div class="mobile-step-label">步骤 1 / 2</div><div class="mobile-intro"><h1>选择来源</h1><p>可选择多个来源。</p></div><label class="field mobile-language-select">学习语言<select data-setting="activeLanguage"><option ${s.activeLanguage === '日语' ? 'selected' : ''}>日语</option><option ${s.activeLanguage === '英语' ? 'selected' : ''}>英语</option></select></label><div class="mobile-plain-list mobile-source-list">${[
        ['notebook', '我的词本', '选择一个或多个词本', 'layers'],
        ['collection', '手选收藏', '已保存的词句', 'bookmark'],
        ['textbook', '教材内容', '课文和原生题', 'book'],
        ['mistake', '当前错题', '尚待纠正的题目', 'warning'],
        ['report', '诊断薄弱点', '需要加强的内容', 'spark'],
      ]
        .map(
          ([key, label, detail, icon]) =>
            `<label class="choice-row"><input type="checkbox" data-source="${key}" ${selected.includes(key) ? 'checked' : ''}>${I(icon)}<span><strong>${label}</strong><small style="display:block;color:var(--muted)">${detail}</small></span></label>`,
        )
        .join(
          '',
        )}</div>${exerciseDetails()}<div class="mobile-action-dock"><button type="button" class="primary full" data-action="builderNext" ${selected.length && practiceCandidateCount() ? '' : 'disabled'}>下一步 · 设置题目 ${I('arrow')}</button></div>`;
    }
    return `<div class="mobile-step-label">步骤 2 / 2</div><div class="mobile-intro"><h1>设置题目</h1><p>设置后可预览出题范围。</p></div><div class="mobile-source-summary"><strong>已选来源</strong><p>${e(practiceSelectionSummary())}</p><button class="text-btn" type="button" data-action="builderBack">修改来源 ${I('arrow')}</button></div><div class="surface form-grid"><label class="field">题型<select data-practice-type>${['语境填空', '词义选择', '翻译判断'].map((x) => `<option ${s.practiceQuestionType === x ? 'selected' : ''}>${x}</option>`).join('')}</select></label><label class="field">题量<select data-practice-count>${['5 题', '10 题'].map((x) => `<option ${s.practiceCount === x ? 'selected' : ''}>${x}</option>`).join('')}</select></label></div><button type="button" class="primary full" style="margin-top:18px" data-action="practicePreview" ${practiceCandidateCount() ? '' : 'disabled'}>预览候选范围</button>${s.practicePreview ? `<div class="panel stack" style="margin-top:18px"><div class="eyebrow"><span class="signal"></span>候选预览</div><h2 style="font-size:19px">${practiceCandidateCount()} 项候选来源</h2><p class="small muted">${e(s.activeLanguage)} · ${e(s.practiceQuestionType)} · ${e(s.practiceCount)}。</p><button type="button" class="primary full" data-modal="generateConfirm">确认生成示例习题</button></div>` : ''}`;
  }
  function practice() {
    const p =
      s.activeLanguage === '英语' ? data.practiceEnglish : data.practice;
    return `<div class="question-meta"><span>${e(s.activeLanguage)} · 语境填空</span><span>1 / 1</span></div><div class="question-progress" aria-hidden="true"><span></span></div>
      <h1 class="question-title">选择合适的词</h1><p class="question-translation">${e(p.translation)}</p><p class="question-prompt" lang="${s.activeLanguage === '英语' ? 'en' : 'ja'}">${e(p.prompt)}</p>
      <div class="answer-list">${p.options.map((option, i) => `<button class="answer ${s.practiceSubmitted ? (i === p.correct ? 'correct' : i === s.practiceAnswer ? 'wrong' : '') : ''}" type="button" data-practice-answer="${i}" aria-pressed="${s.practiceAnswer === i}" ${s.practiceSubmitted ? 'disabled' : ''}><span class="answer-letter">${String.fromCharCode(65 + i)}</span><span class="answer-copy">${e(option)}</span>${s.practiceSubmitted && i === p.correct ? I('check') : ''}</button>`).join('')}</div>
      ${s.practiceSubmitted ? `<div class="feedback ${s.practiceAnswer === p.correct ? 'correct' : 'wrong'}"><strong>${s.practiceAnswer === p.correct ? '答对了' : `正确答案是 ${String.fromCharCode(65 + p.correct)}`}</strong><p>${e(p.explanation)}</p></div>` : ''}
      <div class="mobile-action-dock">${s.practiceSubmitted ? '<button type="button" class="primary full" data-action="practiceReset">再练一次</button>' : `<button class="primary full" type="button" data-action="practiceSubmit" ${s.practiceAnswer < 0 ? 'disabled' : ''}>确认答案</button>`}</div>`;
  }
  function mistakes() {
    return `<h1 class="page-title">错题库</h1><div class="two" style="margin-top:19px"><div class="stat"><strong>${s.mistakes.length}</strong><span>历史示例</span></div><div class="stat"><strong>${s.mistakes.filter((m) => m.favorite).length}</strong><span>已收藏</span></div></div><div class="section-head"><h2>错题列表</h2></div><div class="stack">${s.mistakes.map((m) => `<button class="surface" style="text-align:left;border:0;color:var(--ink)" data-mistake="${m.id}" type="button"><div class="button-row" style="justify-content:space-between">${badge(m.state, m.state === '已经改进' ? 'good' : 'warn')}${m.favorite ? I('bookmark') : ''}</div><strong style="display:block;margin:13px 0 4px;font-size:16px">${e(m.title)}</strong><small class="muted">${e(m.source)}</small></button>`).join('')}</div><button type="button" class="secondary full" style="margin-top:16px" data-go="exerciseBuilder">从错题选择习题来源</button>`;
  }
  function mistake() {
    const m =
      s.mistakes.find((x) => x.id === s.selectedMistake) || s.mistakes[0];
    return `<h1 class="page-title">${e(m.title)}</h1><p class="page-subtitle">${e(m.source)}</p><div style="margin:17px 0">${badge(m.state, m.state === '已经改进' ? 'good' : 'warn')}</div><div class="surface stack"><h2 style="font-size:16px">当时的作答</h2><p>${e(m.answer)}</p><div class="divider"></div></div><div class="button-row" style="margin-top:18px"><button class="secondary" type="button" data-action="favoriteMistake">${I('bookmark')} ${m.favorite ? '取消收藏' : '收藏错题'}</button><button class="primary" type="button" data-go="exerciseBuilder">针对它出题</button></div>`;
  }
  function agent() {
    return `<div class="chat-context">${I('book')}<span>夏の手紙 · 第 03 章</span></div><h1 class="sr-only">学习 Agent</h1><div class="mobile-chat-thread">${s.messages.map((m) => `<article class="mobile-chat-bubble ${m.from === 'user' ? 'from-user' : 'from-agent'}"><span class="mobile-chat-name">${m.from === 'agent' ? 'HARUKA' : '你'}</span><p>${e(m.text)}</p>${m.source ? `<button class="text-btn" type="button" data-go="novel">${I('book')} ${e(m.source)} ${I('arrow')}</button>` : ''}</article>`).join('')}</div><form class="mobile-chat-compose" data-form="chat"><label class="field"><span class="sr-only">继续提问</span><textarea name="message" rows="1" required placeholder="继续提问…"></textarea></label><button class="primary" type="submit" aria-label="发送问题">${I('arrow')}</button></form>`;
  }
  function report() {
    return `<h1 class="page-title">学习诊断</h1><p class="page-subtitle">依据可靠作答和来源形成诊断；本页是虚构示例。</p><div class="stack" style="margin-top:23px"><div class="panel"><div class="eyebrow"><span class="signal"></span>最近 7 天</div><h2 style="font-size:20px;margin:12px 0">方向助词值得再练</h2><p>教材 Unit 02 的有效作答显示，「に / へ」仍容易混淆。</p><button class="text-btn" data-go="textbook" type="button">回到教材 ${I('arrow')}</button></div><div class="surface"><h2 style="font-size:18px;margin-bottom:10px">亮点</h2><p>在有语境的词义选择题里，你能留意句子的情绪与动作方式。</p></div><div class="surface"><h2 style="font-size:18px;margin-bottom:10px">下一步</h2><p class="muted">从教材或当前错题明确选源，预览后再生成针对性习题。</p><button class="primary full" style="margin-top:14px" type="button" data-go="exerciseBuilder">选择习题来源</button></div></div>`;
  }
  function notifications() {
    return `<div class="eyebrow"><span class="signal"></span>IN-APP UPDATES</div><div class="section-head"><h2>消息</h2><button class="text-btn" type="button" data-action="readAll">全部标为已读</button></div><div class="stack">${s.notifications.map((n) => `<button type="button" class="surface" style="border:0;text-align:left;color:var(--ink)" data-notification="${n.id}"><div class="button-row" style="justify-content:space-between"><span class="eyebrow">${n.unread ? '<span class="signal"></span>新消息' : '已读'}</span><small class="muted">${e(n.time)}</small></div><strong style="display:block;font-size:16px;margin:11px 0 4px">${e(n.title)}</strong><p class="page-subtitle">${e(n.detail)}</p></button>`).join('')}</div>`;
  }
  function jobs() {
    return extras.tasks();
  }

  const settingRow = (route, label, detail, icon) =>
    `<button class="setting-row" type="button" data-go="${route}"><span class="setting-icon">${I(icon)}</span><span class="row-copy"><strong>${label}</strong><small>${detail}</small></span>${I('chevron')}</button>`;
  function settingsCore() {
    return `<div class="page-heading"><h1>我的</h1></div><button type="button" class="mobile-profile-row" data-go="profile"><span class="mobile-avatar">遥</span><span class="row-copy"><strong>${e(s.profile.displayName)}</strong><small>个人资料与隐私</small></span>${I('chevron')}</button><div class="mobile-list-heading"><h2>学习偏好</h2></div><div class="mobile-plain-list">${settingRow('languages', '语言选项', `学习：${e(s.activeLanguage)} · 解释：${e(s.explanationLanguage)}`, 'globe')}${settingRow('appearance', '外观与无障碍', '主题、动态与对比度', 'sun')}${settingRow('readingPrefs', '阅读偏好', '字体、字号与阅读主题', 'book')}${settingRow('speech', '朗读与声音', '声音和播放倍速', 'headphones')}</div><div class="mobile-list-heading"><h2>模型与数据</h2></div><div class="mobile-plain-list">${settingRow('model', '个人模型', '模型与 API Key', 'spark')}${settingRow('usage', '模型用量', '调用次数与 Token', 'grid')}${settingRow('cache', '本机缓存', '阅读与音频', 'database')}</div><div class="mobile-list-heading"><h2>账号与动态</h2></div><div class="mobile-plain-list">${settingRow('notifications', '站内消息', '任务和结果提醒', 'bell')}${settingRow('jobs', '任务进度', '导入与生成结果', 'clock')}${settingRow('security', '安全与账号', '会话与退出', 'shield')}</div>`;
  }
  function profileCore() {
    return `<h1 class="page-title">你好，${e(s.profile.displayName)}。</h1><p class="page-subtitle">资料仅自己可见。</p><form class="surface form-grid" data-form="profile" style="margin-top:22px"><label class="field">显示名<input name="displayName" value="${e(s.profile.displayName)}" maxlength="40"><small>可以留空，界面会显示“学习者”。</small></label><label class="field">出生年份（可选）<input name="birthYear" type="number" min="1900" max="2026" placeholder="不填写也可以" value="${e(s.profile.birthYear)}"></label><label class="field">性别（可选）<select name="gender">${['未填写', '女', '男', '非二元', '自我描述', '不愿说明'].map((x) => `<option ${s.profile.gender === x ? 'selected' : ''}>${x}</option>`).join('')}</select></label><label class="field">时区<select name="timezone"><option value="Asia/Tokyo" ${s.profile.timezone === 'Asia/Tokyo' ? 'selected' : ''}>东京 / Asia/Tokyo</option><option value="Asia/Shanghai" ${s.profile.timezone === 'Asia/Shanghai' ? 'selected' : ''}>上海 / Asia/Shanghai</option><option value="UTC" ${s.profile.timezone === 'UTC' ? 'selected' : ''}>UTC</option></select></label><div class="callout">${I('shield')}<span>出生年份与性别默认不用于 AI。</span></div><button type="submit" class="primary full">保存资料</button></form>`;
  }
  function languagesCore() {
    return `<div class="stack" style="margin-top:22px"><div class="surface stack"><label class="field">界面语言<select disabled><option>简体中文 · 当前支持</option></select><small>当前支持简体中文。</small></label></div><div class="surface stack"><h2 style="font-size:17px">母语</h2><label class="choice-row"><input type="checkbox" data-native="简体中文" ${s.nativeLanguages.includes('简体中文') ? 'checked' : ''}><span>简体中文</span></label><label class="choice-row"><input type="checkbox" data-native="英语" ${s.nativeLanguages.includes('英语') ? 'checked' : ''}><span>英语</span></label><label class="choice-row"><input type="checkbox" data-native="日语" ${s.nativeLanguages.includes('日语') ? 'checked' : ''}><span>日语</span></label></div><div class="surface stack"><label class="field">解释语言<select data-setting="explanationLanguage">${['简体中文', '英语', '日语'].map((x) => `<option ${s.explanationLanguage === x ? 'selected' : ''}>${x}</option>`).join('')}</select></label></div><div class="surface stack"><h2 style="font-size:17px">学习语言</h2>${['日语', '英语'].map((x) => `<label class="choice-row"><input type="checkbox" data-target="${x}" ${s.targetLanguages.includes(x) ? 'checked' : ''}><span>${x}</span>${s.activeLanguage === x ? badge('当前') : ''}</label>`).join('')}<label class="field">当前学习语言<select data-setting="activeLanguage">${s.targetLanguages.map((x) => `<option ${s.activeLanguage === x ? 'selected' : ''}>${x}</option>`).join('')}</select></label><label class="field">自评水平<select data-setting="level">${['未填写', '初学', '基础', '中级', '进阶'].map((x) => `<option ${s.level === x ? 'selected' : ''}>${x}</option>`).join('')}</select></label></div><button type="button" class="primary full" data-action="saveLanguages">保存语言档案</button></div>`;
  }
  function appearance() {
    return `<div class="surface stack" style="margin-top:22px"><label class="field">应用主题<select data-setting="theme"><option value="system" ${s.theme === 'system' ? 'selected' : ''}>跟随系统</option><option value="light" ${s.theme === 'light' ? 'selected' : ''}>浅色</option><option value="dark" ${s.theme === 'dark' ? 'selected' : ''}>深色</option></select></label><label class="toggle"><span>减少动态<small style="display:block;color:var(--muted)">降低位移与弹跳</small></span><input type="checkbox" data-toggle="reduceMotion" ${s.reduceMotion ? 'checked' : ''}></label><label class="toggle"><span>高对比<small style="display:block;color:var(--muted)">增强边界与焦点</small></span><input type="checkbox" data-toggle="highContrast" ${s.highContrast ? 'checked' : ''}></label></div><div class="panel" style="margin-top:18px"><h2 style="font-size:20px;margin:13px 0">一页故事，一点新发现。</h2><p>阅读、解释和作答会沿用同一套色彩与文字层级。</p></div>`;
  }
  function readingPrefs() {
    return `<div class="surface form-grid" style="margin-top:22px"><label class="field">字体风格<select data-setting="readingFont"><option value="serif" ${s.readingFont === 'serif' ? 'selected' : ''}>有书感的衬线体</option><option value="sans" ${s.readingFont === 'sans' ? 'selected' : ''}>清晰的无衬线体</option></select></label><label class="field">字号 <span class="muted">${s.readingSize}px</span><input type="range" data-range="readingSize" min="16" max="24" step="1" value="${s.readingSize}"></label><label class="field">行距 <span class="muted">${s.lineHeight.toFixed(1)}</span><input type="range" data-range="lineHeight" min="1.6" max="2.4" step="0.1" value="${s.lineHeight}"></label><label class="field">阅读主题<select data-setting="readingTheme"><option value="light" ${s.readingTheme === 'light' ? 'selected' : ''}>浅色</option><option value="dark" ${s.readingTheme === 'dark' ? 'selected' : ''}>深色</option><option value="sepia" ${s.readingTheme === 'sepia' ? 'selected' : ''}>暖纸色</option></select></label></div><div class="reader" style="margin-top:18px;background:${s.readingTheme === 'sepia' ? '#f7ead4' : s.readingTheme === 'dark' ? '#192535' : 'var(--paper)'};color:${s.readingTheme === 'dark' ? '#edf3ff' : '#152b42'}"><div class="eyebrow">预览</div><div style="font-family:${s.readingFont === 'serif' ? "'Yu Mincho',serif" : "'Segoe UI',sans-serif"};font-size:${s.readingSize}px;line-height:${s.lineHeight};margin-top:12px">朝の光が、白いカーテンを通して部屋に広がった。</div></div><button class="primary full" type="button" data-action="saveReading" style="margin-top:18px">保存阅读偏好</button>`;
  }
  function modelCore() {
    return `<p class="page-subtitle">解释、视觉识别和 TTS 分别显示能力与调用范围。</p><div class="surface form-grid" style="margin-top:22px"><label class="field">供应商<select data-setting="modelProvider"><option ${s.modelProvider === 'OpenRouter' ? 'selected' : ''}>OpenRouter</option><option ${s.modelProvider === 'Gemini' ? 'selected' : ''}>Gemini</option></select></label><label class="field">个人 API Key<input type="password" value="••••••••••••" disabled><small>原型不接收 API Key。</small></label><div class="divider"></div><div class="row-copy"><strong>文本解释</strong><small>用于词句解释与对话</small></div><div class="row-copy"><strong>视觉识别</strong><small>用于识别图片中的文字</small></div><div class="row-copy"><strong>朗读 TTS</strong><small>Gemini / OpenRouter TTS</small></div><button type="button" class="secondary full" data-action="modelTest">模拟测试所选文本能力</button><p class="note">当前示例状态：${e(s.modelStatus)}。模拟测试不发送请求、Key 或材料。</p></div><button class="text-btn" type="button" data-go="usage" style="margin-top:12px">查看模型用量 ${I('arrow')}</button>`;
  }
  function speech() {
    return `<p class="page-subtitle">朗读使用本人配置的 Gemini / OpenRouter TTS；已有音频会标注生成时的配置。</p><div class="surface form-grid" style="margin-top:22px"><label class="field">TTS 供应商<select data-setting="speechProvider"><option ${s.speechProvider === 'Gemini TTS' ? 'selected' : ''}>Gemini TTS</option><option ${s.speechProvider === 'OpenRouter TTS' ? 'selected' : ''}>OpenRouter TTS</option></select></label><label class="field">默认声音<select><option>日语 · 清晰自然（示例）</option><option>英语 · 清晰自然（示例）</option></select></label><label class="field">播放倍速：${s.speechSpeed.toFixed(1)}×<input type="range" min="0.7" max="1.5" step="0.1" value="${s.speechSpeed}" data-range="speechSpeed"></label><div class="callout">${I('headphones')}<span>试听为模拟状态，不播放音频。</span></div><button class="secondary full" type="button" data-action="speechPreview">${I('play')} 试听界面状态</button><button class="primary full" type="button" data-action="saveSpeech">保存朗读偏好</button></div>`;
  }
  function usage() {
    return `<p class="page-subtitle">以下为示例用量。</p><div class="tabs" aria-label="时间范围">${['7 天', '30 天', '90 天'].map((x) => `<button type="button" data-usage-range="${x}" aria-pressed="${s.usageRange === x}">${x}</button>`).join('')}</div><div class="two"><div class="stat"><strong>12</strong><span>示例调用</span></div><div class="stat"><strong>2</strong><span>示例结果复用</span></div></div><div class="section-head"><h2>按能力</h2></div><div class="list"><div class="row-wrap">${I('spark')}<span class="row-copy"><strong>文本解释 · 8 次</strong><small>输入 12,480 · 输出 3,240 · 缓存读取 1,800</small></span></div><div class="row-wrap">${I('headphones')}<span class="row-copy"><strong>朗读 TTS · 3 次</strong><small>音频用量：未提供</small></span></div><div class="row-wrap">${I('grid')}<span class="row-copy"><strong>视觉识别 · 1 次</strong><small>供应商部分指标：未提供</small></span></div></div>`;
  }
  function cache() {
    return `<p class="page-subtitle">查看本机存储与可离线内容。</p><div class="stack" style="margin-top:22px"><div class="surface"><div class="section-head" style="margin-top:0"><h2>本机副本</h2>${badge(s.cacheCleared ? '已清理' : '示例 42 MB')}</div><div class="row-copy"><strong>已读章节与解释</strong><small>已读章节与查过的解释</small></div><div class="divider"></div><div class="row-copy"><strong>允许离线的音频</strong><small>不包含限制播放次数的试卷听力</small></div></div><button class="danger-btn full" type="button" data-modal="clearCache">${I('trash')} 清除此账号本机缓存</button><div class="callout">${I('shield')}<span>清理后可重新下载，不会删除已保存的材料与解释。</span></div></div>`;
  }
  function security() {
    return `<div class="surface" style="margin-top:22px">${settingRow('profile', '本人资料', '头像、显示名与可选资料', 'user')}<div class="setting-row"><span class="setting-icon">${I('lock')}</span><span class="row-copy"><strong>修改密码</strong><small>正式成功后所有会话需重新登录</small></span><button class="text-btn" type="button" data-modal="password">查看流程</button></div><div class="setting-row"><span class="setting-icon">${I('shield')}</span><span class="row-copy"><strong>当前设备会话</strong><small>演示身份 · 用户端</small></span></div></div><button class="danger-btn full" type="button" data-action="logout" style="margin-top:19px">退出演示账号</button><p class="note" style="margin-top:15px">本原型不接收密码、真实登录邮箱或 API Key。</p>`;
  }
  function authCore() {
    const route = s.route;
    const title =
      route === 'register'
        ? '从这里开始。'
        : route === 'recovery'
          ? '找回访问方式。'
          : '欢迎回来。';
    return `<div class="auth-screen"><div class="login-logo"><span class="head-mark">h</span>haruka</div><h1 class="hero-title">${title}</h1><p class="page-subtitle">体验登录/注册页面结构。请输入演示内容，页面不会向外发送。</p><form data-form="${route}" class="surface form-grid" style="margin-top:23px">${route === 'recovery' ? `<label class="field">登录邮箱<input type="email" name="email" placeholder="example@demo.test" required></label><div class="callout">${I('shield')}<span>真实找回方式尚待产品确定；此处只显示统一受理结果。</span></div>` : `<label class="field">登录邮箱<input type="email" name="email" placeholder="example@demo.test" required></label><label class="field">密码<input type="password" name="password" placeholder="仅填写演示内容" required minlength="6"></label>`}${route === 'register' ? '<label class="field">确认密码<input type="password" name="confirmPassword" placeholder="再次输入演示密码" required minlength="6"></label>' : ''}<button type="submit" class="primary full">${route === 'register' ? '提交演示注册' : route === 'recovery' ? '查看受理结果' : '进入演示账号'}</button></form><div class="button-row" style="margin-top:12px">${route !== 'login' ? btn('返回登录', 'login', 'text-btn') : btn('创建账号', 'register', 'text-btn')}${route === 'login' ? btn('忘记密码', 'recovery', 'text-btn') : ''}</div><p class="note" style="margin-top:17px">注册只需身份字段；语言、资料与模型配置可登录后选择。</p></div>`;
  }
  function onboarding() {
    return `<div class="auth-screen"><h1 class="hero-title">按自己的节奏，<br>开始学习。</h1><p class="page-subtitle">这些设置都可以跳过，之后在设置里修改。</p><div class="surface form-grid" style="margin-top:22px"><label class="field">先学哪门语言？<select data-setting="activeLanguage"><option>日语</option><option>英语</option></select></label><label class="field">解释语言<select data-setting="explanationLanguage"><option>简体中文</option><option>英语</option><option>日语</option></select></label><div class="callout">${I('spark')}<span>个人模型 Key 也可以之后配置。没有 Key 仍能使用基础阅读与已有结果。</span></div><button class="primary full" type="button" data-action="finishOnboarding">开始体验</button><button class="secondary full" type="button" data-action="finishOnboarding">暂时跳过</button></div></div>`;
  }
  function registrationStatus() {
    return `<div class="auth-screen"><div class="login-logo"><span class="head-mark">h</span>haruka</div><h1 class="hero-title">注册请求，已模拟受理。</h1><p class="page-subtitle">本原型没有创建账号或发送邮件。正式注册是否需要邮箱验证或管理员审批，取决于发布时的公开策略；满足激活条件后仍需单独登录。</p><div class="surface stack" style="margin-top:22px"><strong>下一步</strong><p>查看实际激活方式，完成要求后回到登录页。本地演示可继续体验登录与可跳过的首次设置。</p><button class="primary full" type="button" data-go="login">返回登录演示</button></div></div>`;
  }
  function modal() {
    if (!s.modal) return '';
    let content = '';
    let title = '';
    const shared = extras.dialog();
    if (shared) {
      title = shared.title;
      content = shared.content;
    } else
      switch (s.modal) {
        case 'prototypeInfo':
          title = '原型说明';
          content = `<div class="stack"><p>所有材料与记录均为虚构示例。操作只保留在本页，刷新后重置。</p><p>文件不上传，不调用模型，不生成音频。请勿输入真实密码或 API Key。</p><button class="secondary full" type="button" data-go="states">查看空白、离线与失败状态</button></div>`;
          break;
        case 'term': {
          const term = data.novel.terms[s.selectedTerm];
          title = '放回这句话';
          content = `<div class="eyebrow"><span class="signal"></span>语境解释 · 示例</div><h2 style="font-size:31px;margin:11px 0 4px" lang="ja">${term.word}</h2><p class="small muted">${term.reading}</p><p style="margin:16px 0;line-height:1.85">${term.meaning}</p><div class="soft-panel"><strong lang="ja">${term.sentence}</strong><p class="small" style="margin-top:6px">${term.translation}</p></div><p class="note" style="margin:13px 0">出处：夏の手紙 · ${term.source}</p><div class="button-row"><button class="secondary" type="button" data-action="collectTerm">${I('bookmark')} ${s.collected.includes(s.selectedTerm) ? '已收藏' : '收藏词条'}</button><button class="secondary" type="button" data-action="askAgent">${I('message')} 问 Agent</button></div>`;
          break;
        }
        case 'chapters':
          title = '章节目录';
          content = `<div class="list">${data.novel.chapters.map((chapter, i) => `<button class="row" type="button" data-action="chapter" data-index="${i}"><span class="pill-count">${i + 1}</span><span class="row-copy"><strong>${e(chapter)}</strong><small>${i === 2 ? '正在阅读' : '章节示例'}</small></span>${I('chevron')}</button>`).join('')}</div>`;
          break;
        case 'readerSettings':
          title = '阅读排版';
          content = `<div class="form-grid"><label class="field">字号 · ${s.readingSize}<input type="range" data-range="readingSize" min="16" max="24" step="1" value="${s.readingSize}"></label><label class="field">行距 · ${s.lineHeight.toFixed(1)}<input type="range" data-range="lineHeight" min="1.6" max="2.4" step="0.1" value="${s.lineHeight}"></label><label class="field">字体<select data-setting="readingFont"><option value="serif" ${s.readingFont === 'serif' ? 'selected' : ''}>衬线体</option><option value="sans" ${s.readingFont === 'sans' ? 'selected' : ''}>无衬线体</option></select></label><label class="field">主题<select data-setting="readingTheme"><option value="light" ${s.readingTheme === 'light' ? 'selected' : ''}>浅色</option><option value="sepia" ${s.readingTheme === 'sepia' ? 'selected' : ''}>暖纸色</option><option value="dark" ${s.readingTheme === 'dark' ? 'selected' : ''}>深色</option></select></label><button class="primary full" type="button" data-action="closeModal">完成</button></div>`;
          break;
        case 'examScript':
          title = '校对听力候选';
          content = `<div class="stack"><div class="callout">${I('warning')}<span>AI 标记的是待确认候选。需要核对脚本内容与题组/小题关系，确认后才可生成 TTS。</span></div><div class="soft-panel"><strong>候选文字稿 · 题组 1</strong><p style="margin-top:8px" lang="ja">駅の南口で待ち合わせましょう。午後三時に会いましょう。</p><p class="small muted" style="margin-top:7px">候选关联：听力题组 1 / 小题 01</p></div><label class="choice-row"><input type="checkbox" id="exam-script-confirm" ${s.examScriptMatched ? 'checked' : ''}><span>我已核对脚本与题目对应关系</span></label><button type="button" class="primary full" data-action="confirmScript">确认匹配</button></div>`;
          break;
        case 'examIntro':
          title = '考前说明';
          content = `<div class="stack"><div class="stat"><strong>60 分钟</strong><span>示例整卷时间</span></div><p>开始后可以保存草稿、标记题目和切换题号。交卷会锁定答案，评分与解析只在交卷后显示。</p><div class="callout warn">${I('warning')}<span>真实考试的时间与听力播放次数由服务端管理。本原型只演示界面。</span></div><button class="primary full" type="button" data-action="examStart">开始模拟考试</button></div>`;
          break;
        case 'examLeave':
          title = '暂时离开考试？';
          content = `<div class="stack"><p>作答和标记会保留在当前本地演示会话中。下次从试卷准备页点“继续考试”，会回到这一题。</p><div class="button-row"><button class="secondary" type="button" data-action="closeModal">继续作答</button><button class="primary" type="button" data-action="examLeaveConfirm">保存并离开</button></div></div>`;
          break;
        case 'answerSheet':
          title = '答题卡';
          content = `<div class="stack"><p class="small muted">点按题号跳转；圆点表示已作答，星号表示标记。</p><div class="mobile-answer-grid">${data.exam.questions.map((q, i) => `<button type="button" data-exam-question="${i}" class="${s.examQuestion === i ? 'current' : ''}"><strong>${i + 1}</strong><small>${s.examMarked.includes(q.id) ? '★ 标记' : s.examAnswers[q.id] !== undefined ? '● 已答' : '未答'}</small></button>`).join('')}</div><button class="secondary full" type="button" data-action="closeModal">继续作答</button></div>`;
          break;
        case 'examSubmit':
          title = '确认交卷？';
          content = `<div class="stack"><p>已答 ${Object.keys(s.examAnswers).length} / ${data.exam.questions.length} 个示例题。交卷后答案锁定，再查看复盘。</p><div class="button-row"><button class="secondary" type="button" data-action="closeModal">继续作答</button><button class="danger-btn" type="button" data-action="examSubmitConfirm">确认交卷</button></div></div>`;
          break;
        case 'generateConfirm':
          title = '确认生成示例习题';
          content = `<div class="stack"><p>所选来源已经预览。正式生成需本人有效 Key、授权和调用上限确认。</p><div class="callout">${I('spark')}<span>此原型将打开内置示例题，不调用模型或记录用量。</span></div><button class="primary full" type="button" data-action="generateDemo">打开示例习题</button></div>`;
          break;
        case 'newNotebook':
          title = '新建词本';
          content = `<form class="form-grid" data-form="newNotebook"><label class="field">名称<input name="name" maxlength="40" required placeholder="例如：故事里的风景"></label><label class="field">学习语言<select name="language"><option>日语</option><option>英语</option></select></label><label class="field">简介<textarea name="description" placeholder="想把哪些词收在这里？"></textarea></label><button type="submit" class="primary full">创建词本</button></form>`;
          break;
        case 'newWord':
          title = '添加词条';
          content = `<form class="form-grid" data-form="newWord"><label class="field">词形<input name="word" required></label><label class="field">释义<input name="meaning" required></label><label class="field">个人例句（可选）<textarea name="sentence"></textarea></label><button type="submit" class="primary full">添加到当前词本</button></form>`;
          break;
        case 'bookActions':
          title = '整理词本';
          content = `<div class="stack"><button class="secondary full" type="button" data-action="renameBook">${I('edit')} 重命名</button><button class="danger-btn full" type="button" data-action="deleteBook">${I('trash')} 删除词本</button><p class="note">删本仅移除归类，不删除词条或学习历史。</p></div>`;
          break;
        case 'moveWord':
          title = '整理词条归属';
          content = `<div class="stack"><p class="small muted">一个词条可以进入多个词本，共用同一学习状态。</p>${s.notebooks.map((book) => `<label class="choice-row"><input type="checkbox" data-word-book="${book.id}" ${s.words.find((w) => w.id === s.selectedWord)?.book === book.id || s.words.find((w) => w.id === s.selectedWord)?.books?.includes(book.id) ? 'checked' : ''}><span>${e(book.title)}</span></label>`).join('')}<button class="primary full" type="button" data-action="saveWordBooks">保存归属</button></div>`;
          break;
        case 'clearCache':
          title = '清理本机副本？';
          content = `<div class="stack"><p>只清理本演示账号的本机副本状态。服务端完整解释与音频仍由正式服务保存。</p><div class="button-row"><button class="secondary" type="button" data-action="closeModal">返回</button><button class="danger-btn" type="button" data-action="clearCacheConfirm">确认清理</button></div></div>`;
          break;
        case 'password':
          title = '修改密码流程';
          content = `<div class="stack"><p>正式应用会先验证旧密码与当前会话，提交成功后撤销两端旧会话，并要求重新登录。</p><div class="callout warn">${I('shield')}<span>本原型不收集真实密码，也不模拟已完成的安全变更。</span></div><button class="secondary full" type="button" data-action="closeModal">我知道了</button></div>`;
          break;
        case 'credential':
          title = '个人凭据管理';
          content = `<div class="stack"><p>正式流程会分别提供保存、能力测试、轮换与停用。测试前需看到最小样本、能力、调用次数与可能消耗的用量。</p><div class="callout warn">${I('shield')}<span>本原型不收集 API Key；已保存的解释与音频不会因停用 Key 而自动删除。</span></div><button class="secondary full" type="button" data-action="closeModal">返回设置</button></div>`;
          break;
        case 'quality': {
          const m =
            s.materials.find((x) => x.id === s.chosenMaterial) ||
            s.materials[0];
          title = '解析与来源状态';
          content = `<div class="stack"><p><strong>${e(m.title)}</strong> · ${e(m.status)}</p><div class="callout">${I('shield')}<span>${m.type === 'exam' ? '题目、分值与听力稿仍待校对。' : m.type === 'textbook' ? '正文可学习；部分题目待补充答案。' : '章节与正文已就绪。'}</span></div><p class="note">示例文件、版本与源锚点未接入真实解析服务。</p></div>`;
          break;
        }
        case 'textbookItem': {
          const unit =
            data.textbook.units.find((x) => x.id === s.textbookUnit) ||
            data.textbook.units[0];
          const index = s.textbookItemIndex || 0;
          const line = {
            unit1: 'はじめまして。よろしくお願いします。',
            unit2: '駅まで一緒に行きましょう。',
            unit3: 'コーヒーを一つください。',
          }[unit.id];
          const sample =
            index === 0
              ? `<p lang="ja" class="mobile-sample-line">${line}</p><p>${unit.id === 'unit1' ? '初次见面，请多关照。' : unit.id === 'unit2' ? '一起去车站吧。' : '请给我一杯咖啡。'}</p>`
              : index === 1
                ? `<div class="mobile-plain-list"><div class="row-wrap"><strong lang="ja">${unit.id === 'unit2' ? '駅' : unit.id === 'unit3' ? '注文' : '名前'}</strong><span class="row-copy"><small>${unit.id === 'unit2' ? '车站' : unit.id === 'unit3' ? '点单' : '姓名'}</small></span></div></div>`
                : `<p lang="ja" class="mobile-sample-line">${unit.id === 'unit2' ? '駅へ行きます。' : unit.id === 'unit3' ? 'コーヒーをください。' : 'わたしは学生です。'}</p><p>${unit.id === 'unit1' ? '「は」提示话题，「です」表示礼貌判断。' : unit.id === 'unit2' ? '「へ」表示移动的方向。' : '「ください」表达礼貌请求。'}</p>`;
          title = unit.items[index] || '单元内容';
          content = `<div class="stack">${sample}<div class="callout">${I('book')}<span>出处：${e(unit.title)}</span></div><button class="secondary full" type="button" data-action="closeModal">回到单元</button></div>`;
          break;
        }
        default:
          title = '提示';
          content = '<p>这是一个本地演示状态。</p>';
      }
    return `<div class="modal-cover" data-action="closeModal"><section class="sheet" tabindex="-1" role="dialog" aria-modal="true" aria-label="${e(title)}" data-stop="true"><div class="sheet-handle"></div><div class="sheet-head"><h2>${e(title)}</h2><button class="icon-btn" type="button" data-action="closeModal" aria-label="关闭">${I('close')}</button></div>${content}</section></div>`;
  }
  function settings() {
    return `${settingsCore()}<div class="mobile-list-heading"><h2>更多</h2></div><div class="mobile-plain-list">${settingRow('connection', '服务连接', '服务器地址', 'globe')}</div>`;
  }
  function profile() {
    return `${profileCore()}<div class="surface stack" style="margin-top:18px"><h2 style="font-size:17px">头像与隐私</h2><div class="button-row"><span class="head-mark" style="width:48px;height:48px;border-radius:50%;font-size:25px">遥</span><span class="row-copy"><strong>默认头像</strong><small>只有本人可见，可选</small></span></div><button class="secondary" type="button" data-action="avatarInfo">头像说明</button><label class="toggle"><span>允许 AI 使用可选个人资料<small style="display:block;color:var(--muted)">年龄段与性别，用于个性化解释</small></span><input type="checkbox" data-toggle="useDemographics" ${s.useDemographics ? 'checked' : ''}></label></div>`;
  }
  function languages() {
    return `${languagesCore()}<div class="surface stack" style="margin-top:18px"><h2 style="font-size:17px">${e(s.activeLanguage || '当前语言')}学习目标</h2>${['阅读', '教材', '考试', '听力', '口语', '写作', '词汇', '语法'].map((goal) => `<label class="choice-row"><input type="checkbox" data-goal="${goal}" ${s.learningGoals.includes(goal) ? 'checked' : ''}><span>${goal}</span></label>`).join('')}<button class="primary full" type="button" data-action="saveLanguages">保存学习目标</button></div>`;
  }
  function model() {
    return `${modelCore()}<div class="surface stack" style="margin-top:18px"><h2 style="font-size:17px">个人凭据与能力</h2><div class="row-copy"><strong>当前凭据：未配置</strong><small>添加 API Key 后可测试模型能力。</small></div>${['文本', '视觉', 'TTS'].map((cap) => `<div class="button-row" style="justify-content:space-between"><span>${cap}能力 · 待验证</span><button class="text-btn" type="button" data-action="modelCapability" data-capability="${cap}">模拟单项检查</button></div>`).join('')}<button class="secondary full" type="button" data-modal="credential">查看凭据管理流程</button></div>`;
  }
  function auth() {
    return `${authCore()}<button class="text-btn full" type="button" data-go="connection" style="margin-top:10px">配置服务地址（Android 演示）</button>`;
  }
  function connection() {
    return `<p class="page-subtitle">Android 与 Windows 在登录前可配置 HTTPS 服务地址；Web 固定连接当前部署。</p><form class="surface form-grid" data-form="connection" style="margin-top:22px"><label class="field">Haruka 服务地址<input type="url" name="address" required value="${e(s.serviceAddress)}" placeholder="https://your-haruka.example"><small>不能包含账号密码、查询参数或片段。</small></label><button class="primary full" type="submit">模拟无凭据连接探测</button></form>${s.serviceProbe ? `<div class="panel stack" style="margin-top:18px"><strong>本地预览 · 未实际联网</strong><p>实例标识、版本和兼容性会在真实探测后显示；切换实例会退出并清理原账号本机副本。</p></div>` : ''}<div class="callout" style="margin-top:18px">${I('shield')}<span>连接探测不发送 Cookie、Token 或个人 Key；本原型不请求输入地址。</span></div>${!s.signedIn ? `<button class="secondary full" type="button" data-go="login" style="margin-top:16px">返回登录</button>` : ''}`;
  }
  function states() {
    return `<h1 class="page-title">每种状态，都说清原因。</h1><p class="page-subtitle">以下是原型状态样例，不代表当前账号真的离线或失权。</p><div class="stack" style="margin-top:22px"><div class="surface stack"><strong>没有材料</strong><p>添加小说、课本或试卷后，材料会出现在本人书库。</p>${btn('添加材料', 'import', 'secondary', 'plus')}</div><div class="surface stack"><strong>暂时离线</strong><p>有效权限租期内可阅读已缓存章节与解释；新的生成、设置保存和考试场次需要联网。</p>${btn('查看本机副本', 'cache', 'secondary')}</div><div class="surface stack"><strong>没有访问权限</strong><p>这份内容现在不可读取。请返回材料库或联系有权的管理员。</p>${btn('返回材料库', 'library', 'secondary')}</div><div class="surface stack"><strong>任务未完成</strong><p>示例：模型调用遇到网络故障，结果仍未知；可去任务页查看状态后再决定下一步。</p>${btn('查看任务', 'jobs', 'secondary')}</div><div class="surface stack"><strong>正在载入</strong><p>保留当前标题和列表骨架，等候服务结果，不用动画推算完成。</p><div class="meter"><span style="width:40%"></span></div></div></div>`;
  }
  const extras = window.HarukaCollections({
    s,
    root,
    mobile: true,
    render: () => render(),
    open: (name) => openModal(name),
    close: () => closeModal(),
    go: (route, options) => go(route, options),
  });
  const views = {
    query: () => extras.query(),
    dailyWords: () => extras.dailyWords(),
    sampleReader: () => extras.sampleReader(),
    sampleTextbook: () => extras.sampleReader(),
    sampleExamPrep: () => extras.sampleReader(),
    library,
    import: importScreen,
    material: materialScreen,
    novel,
    textbookUnits,
    textbook,
    textbookPractice,
    examPrep,
    examRun,
    examResult,
    notebooks,
    notebook,
    word,
    wordEdit,
    csv,
    exercise,
    exerciseBuilder,
    practice,
    mistakes,
    mistake,
    agent,
    report,
    notifications,
    settings,
    profile,
    languages,
    appearance,
    readingPrefs,
    model,
    speech,
    usage,
    cache,
    security,
    connection,
    states,
    jobs,
    login: auth,
    register: auth,
    registrationStatus,
    recovery: auth,
    onboarding,
  };
  function render() {
    const previousSheet = root.querySelector('.sheet');
    const sheetScroll = previousSheet?.scrollTop || 0;
    const focusedControl = previousSheet?.contains(document.activeElement)
      ? focusSelector(document.activeElement)
      : '';
    if (!views[s.route]) s.route = 'library';
    if (s.route === 'notebook') s.route = 'notebooks';
    if (s.route === 'word' || s.route === 'wordEdit') {
      s.route = 'notebooks';
      s.modal = 'entryDetail';
    }

    if (s.route === 'registrationStatus' && !s.registrationAccepted) {
      s.route = 'register';
      history.replaceState(
        { harukaMobileIndex: navigationIndex },
        '',
        '#register',
      );
    }
    if (s.route === 'onboarding' && !s.signedIn) {
      s.route = 'login';
      history.replaceState(
        { harukaMobileIndex: navigationIndex },
        '',
        '#login',
      );
    }
    if (s.route === 'examRun' && s.examFinished) {
      s.route = 'examResult';
      history.replaceState(
        { harukaMobileIndex: navigationIndex },
        '',
        '#examResult',
      );
    }
    if (s.route === 'examRun' && !s.examRunning && !s.examFinished) {
      s.route = 'examPrep';
      history.replaceState(
        { harukaMobileIndex: navigationIndex },
        '',
        '#examPrep',
      );
    }
    if (s.route === 'examResult' && !s.examFinished) {
      s.route = 'examPrep';
      history.replaceState(
        { harukaMobileIndex: navigationIndex },
        '',
        '#examPrep',
      );
    }
    if (
      !s.signedIn &&
      ![
        'login',
        'register',
        'registrationStatus',
        'recovery',
        'onboarding',
        'connection',
      ].includes(s.route)
    ) {
      s.route = 'login';
      history.replaceState(
        { harukaMobileIndex: navigationIndex },
        '',
        '#login',
      );
    }
    document.body.dataset.theme = s.theme === 'system' ? 'light' : s.theme;
    document.body.dataset.contrast = s.highContrast ? 'on' : 'off';
    document.body.dataset.reduceMotion = s.reduceMotion ? 'on' : 'off';
    document.body.style.overflow = s.modal ? 'hidden' : '';
    const mainTab = primary.includes(s.route);
    root.innerHTML = `<div class="phone-shell" data-page="${s.route}"><div class="page-content" ${s.modal ? 'inert' : ''}>${head()}<main class="screen ${mainTab ? 'main-screen' : 'detail-screen'} ${['novel', 'material', 'import', 'notebook', 'agent', 'textbook', 'examRun', 'practice'].includes(s.route) || (s.route === 'exerciseBuilder' && builderStep === 0) ? 'with-dock' : ''}" id="main-content">${views[s.route]()}</main>${s.signedIn && mainTab ? nav() : ''}</div>${s.toast ? `<div class="toast" role="status">${e(s.toast)}</div>` : ''}${modal()}</div>`;
    const sheet = root.querySelector('.sheet');
    if (s.route === 'novel') {
      const shell = root.querySelector('.phone-shell');
      const palette =
        s.readingTheme === 'dark'
          ? [
              '#192535',
              '#edf3ff',
              '#a8b8cc',
              '#344255',
              '#9ab6ff',
              '#2954d3',
              '#273b60',
            ]
          : s.readingTheme === 'sepia'
            ? [
                '#f7ead4',
                '#152b42',
                '#58697b',
                '#d8cab2',
                '#2457ed',
                '#2457ed',
                '#e8efff',
              ]
            : [
                '#ffffff',
                '#152b42',
                '#58697b',
                '#dde5ee',
                '#2457ed',
                '#2457ed',
                '#e8efff',
              ];
      [
        '--paper',
        '--ink',
        '--muted',
        '--line',
        '--blue',
        '--blue-fill',
        '--blue-soft',
      ].forEach((name, i) => shell.style.setProperty(name, palette[i]));
    }
    if (sheet) {
      sheet.scrollTop = sheetScroll;
      ((focusedControl && sheet.querySelector(focusedControl)) || sheet).focus({
        preventScroll: true,
      });
    } else if (previousSheet && modalReturnFocus) {
      root.querySelector(modalReturnFocus)?.focus({ preventScroll: true });
      modalReturnFocus = '';
    }
  }
  function setHashRoute() {
    const hash = decodeURIComponent(location.hash.slice(1));
    const route = hash.split('?')[0];
    if (!views[route]) return;
    if (route === 'examRun' && examPaused) {
      history.replaceState(
        { harukaMobileIndex: Number(history.state?.harukaMobileIndex || 0) },
        '',
        '#examPrep',
      );
      s.route = 'examPrep';
      s.modal = '';
      render();
      window.scrollTo({ top: 0 });
      return;
    }
    if (
      s.route === 'examRun' &&
      route !== 'examRun' &&
      s.examRunning &&
      !examPaused
    ) {
      history.pushState(
        { harukaMobileIndex: ++navigationIndex },
        '',
        '#examRun',
      );
      openModal('examLeave');
      return;
    }
    const step = route === 'exerciseBuilder' && hash.includes('step=2') ? 1 : 0;
    const importStep =
      route === 'import'
        ? Math.max(
            0,
            Math.min(2, Number(hash.match(/step=(\d)/)?.[1] || 1) - 1),
          )
        : 0;
    const sameView =
      route === s.route && step === builderStep && importStep === s.importStep;
    const position = window.scrollY;
    navigationIndex = Number(history.state?.harukaMobileIndex || 0);
    s.route = route;
    builderStep = step;
    if (route === 'import') s.importStep = importStep;
    s.modal = history.state?.harukaModal || '';
    render();
    window.scrollTo({ top: sameView ? position : 0 });
  }
  window.addEventListener('hashchange', setHashRoute);
  window.addEventListener('popstate', setHashRoute);
  window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && s.modal) {
      event.preventDefault();
      closeModal();
    }
  });
  window.addEventListener('keydown', (event) => {
    if (event.key !== 'Tab' || !s.modal) return;
    const sheet = root.querySelector('.sheet');
    const controls = [
      ...sheet.querySelectorAll(
        'button:not(:disabled),input:not(:disabled),select:not(:disabled),textarea:not(:disabled),a[href]',
      ),
    ];
    const first = controls[0];
    const last = controls.at(-1);
    if (
      event.shiftKey &&
      (document.activeElement === first || document.activeElement === sheet)
    ) {
      event.preventDefault();
      last?.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first?.focus();
    }
  });
  const updateViewport = () => {
    const viewport = window.visualViewport;
    if (!viewport) return;
    // Pin controls above an on-screen keyboard, without treating pinch zoom as a keyboard.
    const inset =
      viewport.scale === 1
        ? Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop)
        : 0;
    document.documentElement.style.setProperty(
      '--keyboard-inset',
      `${inset}px`,
    );
    document.documentElement.style.setProperty(
      '--visual-height',
      `${viewport.height}px`,
    );
    document.documentElement.style.setProperty(
      '--visual-top',
      `${viewport.offsetTop}px`,
    );
  };
  window.visualViewport?.addEventListener('resize', updateViewport);
  window.visualViewport?.addEventListener('scroll', updateViewport);
  updateViewport();
  root.addEventListener('click', (event) => {
    const target = event.target.closest(
      '[data-action],[data-go],[data-modal],[data-filter],[data-material],[data-import-type],[data-term],[data-textbook-unit],[data-book],[data-word],[data-mistake],[data-notification],[data-practice-answer],[data-textbook-answer],[data-exam-question],[data-exam-answer],[data-usage-range]',
    );
    if (!target || target.disabled) return;
    if (
      event.target.closest('[data-stop]') &&
      target.classList.contains('modal-cover')
    )
      return;
    if (target.dataset.modal) {
      openModal(target.dataset.modal);
      return;
    }
    if (target.dataset.go) {
      if (
        target.dataset.go === 'import' &&
        s.route === 'import' &&
        s.importStep === 0
      ) {
        if (!s.importType) return toast('请先选择小说、课本或试卷。');
        s.importStep = 1;
        history.pushState(
          { harukaMobileIndex: ++navigationIndex },
          '',
          '#import?step=2',
        );
        render();
        window.scrollTo({ top: 0 });
        return;
      }
      go(target.dataset.go);
      return;
    }
    if (target.dataset.filter) {
      s.filter = target.dataset.filter;
      render();
      return;
    }
    if (target.dataset.material) {
      s.chosenMaterial = target.dataset.material;
      go('material');
      return;
    }
    if (target.dataset.importType) {
      s.importType = target.dataset.importType;
      render();
      return;
    }
    if (target.dataset.term) {
      s.selectedTerm = target.dataset.term;
      openModal('term');
      return;
    }
    if (target.dataset.textbookUnit) {
      s.textbookUnit = target.dataset.textbookUnit;
      s.textbookAnswer = -1;
      s.textbookSubmitted = false;
      go('textbook');
      return;
    }
    if (target.dataset.book) {
      s.selectedBook = target.dataset.book;
      go('notebook');
      return;
    }
    if (target.dataset.word) {
      s.selectedWord = target.dataset.word;
      go('word');
      return;
    }
    if (target.dataset.mistake) {
      s.selectedMistake = target.dataset.mistake;
      go('mistake');
      return;
    }
    if (target.dataset.notification) {
      const n = s.notifications.find(
        (x) => x.id === target.dataset.notification,
      );
      if (n) {
        n.unread = false;
        go(n.route);
      }
      return;
    }
    if (target.dataset.practiceAnswer !== undefined) {
      s.practiceAnswer = Number(target.dataset.practiceAnswer);
      render();
      return;
    }
    if (target.dataset.textbookAnswer !== undefined) {
      s.textbookAnswer = Number(target.dataset.textbookAnswer);
      render();
      return;
    }
    if (target.dataset.examQuestion !== undefined) {
      s.examQuestion = Number(target.dataset.examQuestion);
      if (s.modal) closeModal();
      else render();
      window.scrollTo({ top: 0 });
      return;
    }
    if (target.dataset.examAnswer !== undefined) {
      if (s.examFinished || !s.examRunning) return;
      s.examAnswers[data.exam.questions[s.examQuestion].id] = Number(
        target.dataset.examAnswer,
      );
      s.examDraft = '未保存的演示选择';
      render();
      return;
    }
    if (target.dataset.usageRange) {
      s.usageRange = target.dataset.usageRange;
      render();
      return;
    }
    const action = target.dataset.action;
    if (!action) return;
    if (action === 'closeModal') {
      closeModal();
      return;
    }
    if (action === 'back') return back();
    if (action === 'builderBack') {
      history.back();
      return;
    }
    if (action === 'builderNext') {
      if (!practiceCandidateCount())
        return toast('当前范围没有示例候选，请调整来源。');
      builderStep = 1;
      history.pushState(
        { harukaMobileIndex: ++navigationIndex, harukaBuilderStep: 1 },
        '',
        '#exerciseBuilder?step=2',
      );
      render();
      window.scrollTo({ top: 0 });
      return;
    }
    if (['materialQuality', 'textbookItem'].includes(action)) {
      if (action === 'textbookItem') {
        s.textbookItemIndex = Number(target.dataset.index);
        if (s.textbookItemIndex === 3) return go('textbookPractice');
      }
      openModal(action === 'materialQuality' ? 'quality' : action);
      return;
    }
    if (action === 'clearSearch') {
      s.search = '';
      s.filter = 'all';
      render();
      return;
    }
    if (action === 'importBack') {
      history.back();
      return;
    }
    if (action === 'importNext') {
      if (!s.importFile) return toast('先选择一个示例文件。');
      s.importStep = 2;
      history.pushState(
        { harukaMobileIndex: ++navigationIndex },
        '',
        '#import?step=3',
      );
      render();
      window.scrollTo({ top: 0 });
      return;
    }
    if (action === 'importConfirm') {
      if (s.importComplete) return toast('本次示例任务已创建。');
      s.importComplete = true;
      s.notifications.unshift({
        id: `local-${Date.now()}`,
        title: `${s.importFile} · 示例任务已受理`,
        detail: '仅本地演示，文件未读取或上传。',
        time: '刚刚',
        route: 'jobs',
        unread: true,
      });
      s.importStep = 0;
      go('jobs');
      toast('本地演示任务已创建；文件没有上传。');
      return;
    }
    if (action === 'toggleSpeech') {
      s.playing = !s.playing;
      toast(
        s.playing
          ? '朗读控件已切换为播放状态；没有实际音频。'
          : '朗读控件已暂停。',
      );
      return;
    }
    if (action === 'bookmark') return toast('示例书签已加入本地阅读状态。');
    if (action === 'chapter') {
      toast(
        `第 ${Number(target.dataset.index) + 1} 章为目录示例；当前正文仍是第 03 章。`,
      );
      closeModal();
      return;
    }
    if (action === 'collectTerm') {
      if (s.collected.includes(s.selectedTerm))
        s.collected = s.collected.filter((x) => x !== s.selectedTerm);
      else s.collected.push(s.selectedTerm);
      render();
      return;
    }
    if (action === 'askAgent') {
      go('agent');
      return;
    }
    if (action === 'textbookSubmit') {
      s.textbookSubmitted = true;
      render();
      return;
    }
    if (action === 'textbookReset') {
      s.textbookSubmitted = false;
      s.textbookAnswer = -1;
      render();
      return;
    }
    if (action === 'confirmScript') {
      const checked = root.querySelector('#exam-script-confirm')?.checked;
      if (!checked) return toast('请先核对并勾选确认。');
      s.examScriptMatched = true;
      toast('候选匹配已确认（本地演示）。');
      closeModal();
      return;
    }
    if (action === 'examTts') {
      s.examAudioReady = true;
      toast('私有 TTS 状态已就绪（模拟），没有生成音频。');
      return;
    }
    if (action === 'examFreeze') {
      if (s.examFinished) return go('examResult');
      s.examReady = true;
      openModal('examIntro');
      return;
    }
    if (action === 'examStart') {
      if (s.examFinished) return go('examResult');
      s.examRunning = true;
      examPaused = false;
      go('examRun');
      return;
    }
    if (action === 'examResume') {
      if (s.examRunning) {
        examPaused = false;
        go('examRun');
      }
      return;
    }
    if (action === 'examLeaveConfirm') {
      s.examDraft = '本地演示草稿已保留';
      examPaused = true;
      history.go(-2);
      return;
    }
    if (action === 'examPlay')
      return toast('听力按钮状态演示；没有播放或消耗次数。');
    if (action === 'examMark') {
      const id = data.exam.questions[s.examQuestion].id;
      s.examMarked = s.examMarked.includes(id)
        ? s.examMarked.filter((x) => x !== id)
        : [...s.examMarked, id];
      render();
      return;
    }
    if (action === 'examSave') {
      s.examDraft = '本地演示草稿已保存';
      toast('演示草稿已保留在当前页面内存。');
      return;
    }
    if (action === 'examPrev' || action === 'examNext') {
      s.examQuestion += action === 'examPrev' ? -1 : 1;
      render();
      return;
    }
    if (action === 'examSubmitConfirm') {
      if (s.examFinished || !s.examRunning) return;
      s.examFinished = true;
      s.examRunning = false;
      go('examResult', { replace: true });
      return;
    }
    if (action === 'useNotebook') {
      s.practiceSources = [...new Set([...s.practiceSources, 'notebook'])];
      s.practiceAllWords = false;
      s.practiceBookIds = [s.selectedBook];
      s.activeLanguage =
        s.notebooks.find((b) => b.id === s.selectedBook)?.language ||
        s.activeLanguage;
      s.practicePreview = false;
      go('exerciseBuilder');
      return;
    }
    if (action === 'practicePreview') {
      if (!practiceCandidateCount())
        return toast('当前范围没有示例候选，请调整来源。');
      s.practicePreview = true;
      render();
      return;
    }
    if (action === 'generateDemo') {
      s.practiceGenerated = true;
      go('practice');
      return;
    }
    if (action === 'practiceSubmit') {
      s.practiceSubmitted = true;
      render();
      return;
    }
    if (action === 'practiceReset') {
      s.practiceSubmitted = false;
      s.practiceAnswer = -1;
      render();
      return;
    }
    if (action === 'favoriteMistake') {
      const m = s.mistakes.find((x) => x.id === s.selectedMistake);
      if (m) m.favorite = !m.favorite;
      render();
      return;
    }
    if (action === 'readAll') {
      s.notifications.forEach((n) => {
        n.unread = false;
      });
      render();
      return;
    }
    if (
      action === 'saveLanguages' ||
      action === 'saveReading' ||
      action === 'saveSpeech'
    )
      return toast('演示偏好已保存到当前页面内存。');
    if (action === 'modelTest') {
      s.modelStatus = '文本能力模拟测试已完成';
      toast('模拟测试完成；没有调用供应商。');
      return;
    }
    if (action === 'modelCapability') {
      s.modelStatus = `${target.dataset.capability}能力模拟检查已完成`;
      toast(
        `${target.dataset.capability}能力仅完成本地界面演示；没有调用供应商。`,
      );
      return;
    }
    if (action === 'avatarInfo')
      return toast(
        '头像需经本人临时上传、安全解码、去元数据与发布；本原型不接收图片。',
      );
    if (action === 'speechPreview')
      return toast('试听按钮状态已演示；没有合成或播放音频。');
    if (action === 'csvPreview') {
      s.csvStep = 1;
      render();
      return;
    }
    if (action === 'csvConfirm') {
      s.csvStep = 0;
      toast('示例预览已确认；未读取或导入真实 CSV。');
      return;
    }
    if (action === 'csvExport') {
      const content =
        '\uFEFFword,reading,meaning,notebook\r\nそっと,sotto,轻轻地,日常的细节\r\n微笑む,ほほえむ,微笑,阅读时遇见\r\n';
      const link = document.createElement('a');
      link.href = URL.createObjectURL(
        new Blob([content], { type: 'text/csv;charset=utf-8' }),
      );
      link.download = 'haruka-demo-words.csv';
      link.click();
      setTimeout(() => URL.revokeObjectURL(link.href), 1000);
      toast('已生成虚构样本 CSV。');
      return;
    }
    if (action === 'clearCacheConfirm') {
      s.cacheCleared = true;
      toast('已清理本地演示缓存状态。');
      closeModal();
      return;
    }
    if (action === 'logout') {
      s.signedIn = false;
      go('login', { replace: true });
      return;
    }
    if (action === 'finishOnboarding') {
      s.signedIn = true;
      go('library');
      return;
    }
    if (action === 'renameBook') {
      const book = s.notebooks.find((x) => x.id === s.selectedBook);
      if (book) book.title += ' · 整理中';
      toast('已重命名。');
      closeModal();
      return;
    }
    if (action === 'deleteBook') {
      s.notebooks = s.notebooks.filter((x) => x.id !== s.selectedBook);
      go('notebooks', { replace: true });
      toast('示例词本已删除；词条和历史仍保留。');
      return;
    }
    if (action === 'saveWordBooks') {
      const word = s.words.find((x) => x.id === s.selectedWord);
      if (word) {
        const selected = [
          ...root.querySelectorAll('[data-word-book]:checked'),
        ].map((x) => x.dataset.wordBook);
        word.book = selected[0] || '';
        word.books = selected.slice(1);
      }
      toast('示例归属已更新。');
      closeModal();
      return;
    }
  });
  root.addEventListener('change', (event) => {
    const t = event.target;
    if (t.dataset.file === 'material') {
      s.importFile = t.files?.[0]?.name || '';
      render();
      return;
    }
    if (t.dataset.file === 'csv') {
      s.csvFile = t.files?.[0]?.name || '';
      s.csvStep = 0;
      render();
      return;
    }
    if (t.dataset.source) {
      s.practiceSources = t.checked
        ? [...s.practiceSources, t.dataset.source]
        : s.practiceSources.filter((x) => x !== t.dataset.source);
      s.practicePreview = false;
      render();
      return;
    }
    if (t.dataset.practiceAll !== undefined) {
      s.practiceAllWords = t.dataset.practiceAll === 'true';
      s.practicePreview = false;
      render();
      return;
    }
    if (t.dataset.practiceBook) {
      s.practiceBookIds = t.checked
        ? [...s.practiceBookIds, t.dataset.practiceBook]
        : s.practiceBookIds.filter((id) => id !== t.dataset.practiceBook);
      s.practicePreview = false;
      render();
      return;
    }
    if (t.dataset.practiceUnit !== undefined) {
      s.practiceTextbookUnit = t.value;
      s.practicePreview = false;
      render();
      return;
    }
    if (t.dataset.practiceMistakes !== undefined) {
      s.practiceMistakeScope = t.value;
      s.practicePreview = false;
      render();
      return;
    }
    if (t.dataset.practiceType !== undefined) {
      s.practiceQuestionType = t.value;
      s.practicePreview = false;
      render();
      return;
    }
    if (t.dataset.practiceCount !== undefined) {
      s.practiceCount = t.value;
      s.practicePreview = false;
      render();
      return;
    }
    if (t.dataset.native) {
      s.nativeLanguages = t.checked
        ? [...s.nativeLanguages, t.dataset.native]
        : s.nativeLanguages.filter((x) => x !== t.dataset.native);
      render();
      return;
    }
    if (t.dataset.target) {
      s.targetLanguages = t.checked
        ? [...s.targetLanguages, t.dataset.target]
        : s.targetLanguages.filter((x) => x !== t.dataset.target);
      if (!s.targetLanguages.includes(s.activeLanguage))
        s.activeLanguage = s.targetLanguages[0] || '';
      render();
      return;
    }
    if (t.dataset.goal) {
      s.learningGoals = t.checked
        ? [...s.learningGoals, t.dataset.goal]
        : s.learningGoals.filter((x) => x !== t.dataset.goal);
      render();
      return;
    }
    if (t.dataset.toggle) {
      s[t.dataset.toggle] = t.checked;
      render();
      return;
    }
    if (t.dataset.range) {
      s[t.dataset.range] = Number(t.value);
      render();
      return;
    }
    if (t.dataset.setting) {
      s[t.dataset.setting] = t.value;
      if (s.route === 'exerciseBuilder') {
        s.practicePreview = false;
        if (t.dataset.setting === 'activeLanguage') {
          s.practiceBookIds = s.practiceBookIds.filter((id) =>
            s.notebooks.some(
              (b) => b.id === id && b.language === s.activeLanguage,
            ),
          );
          if (!s.practiceBookIds.length) {
            const first = s.notebooks.find(
              (b) => b.language === s.activeLanguage,
            );
            if (first) s.practiceBookIds = [first.id];
          }
        }
      }
      render();
      return;
    }
  });
  root.addEventListener('input', (event) => {
    const t = event.target;
    if (t.name === 'password' || t.name === 'confirmPassword')
      root.querySelector('[name="confirmPassword"]')?.setCustomValidity('');
    if (t.dataset.input === 'search') {
      const pos = t.selectionStart;
      s.search = t.value;
      render();
      const next = root.querySelector('[data-input="search"]');
      next?.focus();
      next?.setSelectionRange(pos, pos);
    }
  });
  root.addEventListener('submit', (event) => {
    const form = event.target.closest('[data-form]');
    if (!form) return;
    event.preventDefault();
    const values = Object.fromEntries(new FormData(form));
    if (form.dataset.form === 'profile') {
      s.profile = {
        displayName: String(values.displayName || '').trim() || '学习者',
        birthYear: values.birthYear || '',
        gender: values.gender || '未填写',
        timezone: values.timezone || 'Asia/Tokyo',
      };
      toast('演示资料已保存到当前页面内存。');
      return;
    }
    if (form.dataset.form === 'connection') {
      s.serviceAddress = String(values.address || '');
      try {
        const url = new URL(s.serviceAddress);
        if (
          url.protocol !== 'https:' ||
          url.username ||
          url.password ||
          url.search ||
          url.hash
        )
          throw new Error('invalid');
        s.serviceAddress = url.origin + url.pathname.replace(/\/$/, '');
        s.serviceProbe = true;
        toast('已生成连接探测预览；没有实际联网。');
      } catch {
        toast('请输入无账号密码、查询参数或片段的 HTTPS 地址。');
      }
      return;
    }
    if (form.dataset.form === 'newNotebook') {
      const name = String(values.name || '').trim();
      if (!name) return;
      const id = `book-${Date.now()}`;
      s.notebooks.push({
        id,
        title: name,
        language: values.language,
        count: 0,
        tone: 'blue',
        description: String(values.description || ''),
      });
      s.selectedBook = id;
      go('notebook');
      return;
    }
    if (form.dataset.form === 'newWord') {
      const word = String(values.word || '').trim();
      if (!word) return;
      const id = `word-${Date.now()}`;
      s.words.push({
        id,
        word,
        reading: '个人录入',
        meaning: String(values.meaning || '').trim(),
        source: '手动添加 · 本人词条',
        book: s.selectedBook,
        mastery: '尚无有效证据',
        sentence: String(values.sentence || '') || '暂无个人例句',
      });
      s.selectedWord = id;
      go('word');
      return;
    }
    if (form.dataset.form === 'wordEdit') {
      const w = s.words.find((x) => x.id === s.selectedWord);
      if (w) {
        w.word = String(values.word || '').trim();
        w.meaning = String(values.meaning || '').trim();
        w.note = String(values.note || '');
      }
      go('word', { replace: true });
      toast('示例词条已更新。');
      return;
    }
    if (form.dataset.form === 'chat') {
      const message = String(values.message || '').trim();
      if (!message) return;
      s.messages.push(
        { from: 'user', text: message },
        {
          from: 'agent',
          text: '示例回复：「そっと」强调轻柔、不打扰；「静かに」更偏向没有声音。这里写夏风触碰脸颊，用「そっと」更贴近触感。',
          source: '夏の手紙 · 第 03 章 · 第 1 段',
        },
      );
      render();
      requestAnimationFrame(() => {
        root
          .querySelector('.mobile-chat-compose textarea')
          ?.focus({ preventScroll: true });
        const last = root.querySelector(
          '.mobile-chat-thread article:last-child',
        );
        const composer = root.querySelector('.mobile-chat-compose');
        if (last && composer)
          window.scrollTo({
            top:
              window.scrollY +
              Math.max(
                0,
                last.getBoundingClientRect().bottom -
                  composer.getBoundingClientRect().top +
                  16,
              ),
            behavior: 'smooth',
          });
      });
      return;
    }
    if (['login', 'register', 'recovery'].includes(form.dataset.form)) {
      if (form.dataset.form === 'recovery')
        return toast('演示受理结果：若账号可用，会按已配置的恢复方式处理。');
      if (form.dataset.form === 'register') {
        if (String(values.password) !== String(values.confirmPassword)) {
          const input = form.querySelector('[name="confirmPassword"]');
          input.setCustomValidity('两次输入的密码不一致');
          input.reportValidity();
          return;
        }
        s.registrationAccepted = true;
        s.signedIn = false;
        go('registrationStatus');
        return;
      }
      s.signedIn = true;
      if (s.registrationAccepted) {
        s.registrationAccepted = false;
        go('onboarding');
      } else go('library');
      return;
    }
  });
  const hash = decodeURIComponent(location.hash.slice(1)).split('?')[0];
  if (views[hash]) s.route = hash;
  if (hash === 'import' && location.hash.includes('?'))
    history.replaceState({ harukaMobileIndex: navigationIndex }, '', '#import');
  history.replaceState(
    { harukaMobileIndex: navigationIndex },
    '',
    location.href,
  );
  render();
})();
