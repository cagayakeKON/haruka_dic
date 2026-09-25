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
  const exerciseFlow = window.HarukaExerciseBuilder(s);
  const root = document.getElementById("desktop-app");
  const adminRoutes = [
    "adminOverview",
    "adminUsers",
    "adminRoles",
    "adminMenus",
    "adminPolicy",
    "adminJobs",
    "adminAudit",
    "adminUsage",
    "adminSecurity",
  ];
  const names = {
    query: "查询",
    dailyWords: "每日单词",
    sampleReader: "阅读",
    sampleTextbook: "课本学习",
    sampleExamPrep: "试卷准备",
    library: "材料库",
    material: "材料详情",
    import: "导入材料",
    novel: "小说阅读",
    textbook: "课本学习",
    examPrep: "试卷准备",
    examRun: "整卷作答",
    examResult: "成绩复盘",
    notebooks: "单词本",
    notebook: "词本详情",
    word: "词条详情",
    csv: "单词 CSV",
    exercise: "练习",
    exerciseBuilder: "生成 AI 习题",
    textbookPractice: "课后题",
    practice: "逐题练习",
    mistakes: "错题库",
    mistake: "错题详情",
    report: "学习诊断",
    notifications: "站内消息",
    jobs: "任务进度",
    settings: "我的",
    profile: "个人资料",
    languages: "语言选项",
    appearance: "外观与无障碍",
    readingPrefs: "阅读偏好",
    model: "个人模型",
    speech: "朗读与声音",
    usage: "模型用量",
    cache: "本机缓存",
    security: "账号安全",
    connection: "服务连接",
    states: "状态样例",
    login: "登录",
    register: "注册",
    recovery: "找回密码",
    onboarding: "首次设置",
    adminLogin: "管理端登录",
    adminOverview: "运维概览",
    adminUsers: "用户与会话",
    adminRoles: "角色与权限",
    adminMenus: "菜单与页面",
    adminPolicy: "注册策略",
    adminJobs: "任务与资源",
    adminAudit: "审计诊断",
    adminUsage: "模型用量",
    adminSecurity: "管理账号与安全",
  };
  const parentRoute = {
    dailyWords: "notebooks",
    sampleReader: "library",
    sampleTextbook: "library",
    sampleExamPrep: "library",
    material: "library",
    import: "library",
    novel: "library",
    textbook: "library",
    textbookPractice: "textbook",
    examPrep: "library",
    examRun: "examPrep",
    examResult: "examPrep",
    notebook: "notebooks",
    word: "notebook",
    csv: "notebooks",
    exerciseBuilder: "exercise",
    practice: "exercise",
    mistakes: "exercise",
    mistake: "mistakes",
    report: "exercise",
    notifications: "settings",
    jobs: "library",
    profile: "settings",
    languages: "settings",
    appearance: "settings",
    readingPrefs: "settings",
    model: "settings",
    speech: "settings",
    usage: "settings",
    cache: "settings",
    security: "settings",
    connection: "settings",
    states: "settings",
  };
  const navigationKeys = [
    "chosenMaterial",
    "selectedBook",
    "selectedWord",
    "selectedMistake",
    "textbookUnit",
    "examQuestion",
  ];
  const navigationState = () => ({
    harukaDesktop: s.route,
    context: Object.fromEntries(navigationKeys.map((key) => [key, s[key]])),
  });
  let builderStep = 0;
  let pendingRoute = "";
  let pendingOptions = {};
  let modalReturnFocus = "";
  let renderedRoute = "";
  const focusSelector = (element) => {
    if (!element?.attributes) return "";
    const attrs = [...element.attributes].filter(
      (a) => a.name.startsWith("data-") || a.name === "name" || a.name === "id",
    );
    return attrs.length
      ? element.tagName.toLowerCase() +
          attrs.map((a) => `[${a.name}="${CSS.escape(a.value)}"]`).join("")
      : "";
  };
  const pageHash = () =>
    `#${s.route}${s.route === "import" ? `?step=${s.importStep + 1}` : s.route === "exerciseBuilder" ? `?step=${builderStep + 1}` : ""}`;
  const openModal = (name) => {
    if (name === "selectionQuery" && s.route === "novel") {
      s.readerPanelOpen = true;
      s.modal = "";
      render();
      return;
    }
    if (!s.modal) modalReturnFocus = focusSelector(document.activeElement);
    s.modal = name;
    render();
  };
  const closeModal = () => {
    if (extras.returnFromSelection()) return;
    s.modal = "";
    render();
  };
  const go = (route, options = {}) => {
    if (!views[route]) return;
    if (
      s.route === "examRun" &&
      s.examRunning &&
      route !== "examRun" &&
      !options.force
    ) {
      pendingRoute = route;
      pendingOptions = options;
      openModal("examLeave");
      return;
    }
    if (options.materialId) s.chosenMaterial = options.materialId;
    if (route === s.route) {
      s.modal = "";
      render();
      return;
    }
    if (route === "adminLogin" && !s.adminArea) s.signedIn = false;
    if (route === "login" && s.adminArea) {
      s.adminSignedIn = false;
      s.signedIn = false;
    }
    s.previousRoute = s.route;
    s.route = route;
    s.modal = "";
    if (route === "import") {
      s.importStep = 0;
      s.importType = "";
      s.importFile = "";
      s.importAnalyze = false;
    }
    if (route === "exerciseBuilder") builderStep = 0;
    history.pushState(navigationState(), "", pageHash());
    render();
    window.scrollTo(0, 0);
    root.querySelector("#main-content")?.focus({ preventScroll: true });
  };
  const nextStep = (kind, step) => {
    if (kind === "import") s.importStep = step;
    else builderStep = step;
    history.pushState(navigationState(), "", pageHash());
    render();
    window.scrollTo(0, 0);
    root.querySelector("#main-content")?.focus({ preventScroll: true });
  };
  const toast = (message) => {
    s.toast = message;
    render();
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => {
      s.toast = "";
      root.querySelector(".toast")?.remove();
    }, 3500);
  };
  const btn = (label, route, cls = "secondary", icon = "") =>
    `<button type="button" class="${cls}" data-go="${route}">${icon ? I(icon) : ""}${label}</button>`;
  const tag = (label, kind = "") =>
    `<span class="tag ${kind}">${e(label)}</span>`;
  const cover = (m) =>
    `<span class="cover ${m.tone}" aria-hidden="true">${e(m.cover)}</span>`;
  const simpleTitles = {
    exercise: "练习",
    notebooks: "单词本",
    practice: "逐题练习",
    mistakes: "错题库",
    csv: "单词 CSV",
    report: "学习诊断",
    notifications: "站内消息",
    jobs: "任务进度",
    examResult: "考试结果",
    settings: "我的",
    adminOverview: "运维概览",
    adminUsers: "用户与会话",
    adminRoles: "角色与权限",
    adminMenus: "页面与菜单",
    adminPolicy: "注册策略",
    adminJobs: "任务与资源",
    adminAudit: "审计诊断",
    adminUsage: "模型用量",
    adminSecurity: "管理账号与安全",
  };
  const head = (_eyebrow, title, subtitle = "") =>
    `<div class="page-heading"><h1 class="title">${simpleTitles[s.route] || title}</h1>${subtitle && ["word", "notebook", "mistake"].includes(s.route) ? `<p class="subtitle">${subtitle}</p>` : ""}</div>`;

  function sidebar() {
    const admin = s.adminArea;
    const items = admin
      ? [
          ["adminOverview", "运维概览", "grid"],
          ["adminUsers", "用户与会话", "user"],
          ["adminRoles", "角色与权限", "shield"],
          ["adminMenus", "页面与菜单", "layers"],
          ["adminPolicy", "注册策略", "settings"],
          ["adminJobs", "任务与资源", "clock"],
          ["adminAudit", "审计诊断", "book"],
          ["adminUsage", "模型用量", "spark"],
          ["adminSecurity", "账号安全", "shield"],
        ]
      : [
          ["library", "材料库", "library"],
          ["notebooks", "单词本", "layers"],
          ["query", "查询", "message"],
          ["exercise", "练习", "spark"],
          ["settings", "我的", "user"],
        ];
    let active = s.route;
    while (parentRoute[active]) active = parentRoute[active];
    return `<aside class="sidebar ${admin ? "admin-sidebar" : ""}"><a class="brand" href="${admin ? "#adminOverview" : "#library"}" aria-label="Haruka 首页"><span class="brand-mark">h</span><span>haruka</span></a>${admin ? '<span class="admin-ribbon">管理端 · 原型</span>' : ""}<nav class="side-nav" aria-label="${admin ? "管理导航" : "主导航"}">${items.map(([route, label, icon]) => `<button type="button" data-go="${route}" ${active === route ? 'aria-current="page"' : ""}>${I(icon)}<span>${label}</span></button>`).join("")}</nav><div class="sidebar-bottom"><button class="side-account" type="button" data-go="${admin ? "adminSecurity" : "profile"}"><span class="avatar">遥</span><span class="row-copy"><strong>${e(s.profile.displayName)}</strong><small>${admin ? "管理账号" : e(s.activeLanguage || "未设置学习语言")}</small></span>${I("chevron")}</button></div></aside>`;
  }

  function topbar() {
    const parent = parentRoute[s.route];
    return `<header class="topbar"><div class="top-path">${parent ? `<button type="button" class="back-link" data-go="${parent}">${I("back")}<span>${e(names[parent] || "返回")}</span></button>` : `<span>${s.adminArea ? "管理端" : e(s.activeLanguage || "学习空间")}</span>`}</div><div class="top-actions"><button type="button" class="prototype-button" data-modal="prototypeInfo">原型</button>${!s.adminArea ? `<button type="button" class="icon-btn ${s.notifications.some((n) => n.unread) ? "unread-dot" : ""}" data-go="notifications" aria-label="站内消息">${I("bell")}</button>` : ""}</div></header>`;
  }

  function library() {
    return extras.library();
  }

  function importPage() {
    const stage = Math.min(2, s.importStep);
    const stepTitles = ["材料类型", "选择文件", "确认导入"];
    let main = "";
    if (stage === 0)
      main = `<div class="type-grid">${[
        ["novel", "小说", "book"],
        ["textbook", "课本", "layers"],
        ["exam", "试卷", "edit"],
      ]
        .map(
          ([key, label, icon]) =>
            `<button type="button" class="type-choice" data-import-type="${key}" aria-pressed="${s.importType === key}">${I(icon)}<strong>${label}</strong>${s.importType === key ? I("check") : ""}</button>`,
        )
        .join("")}</div>`;
    if (stage === 1)
      main = `<div class="surface form-grid"><label class="field file-field">${I("upload")}选择文件<input type="file" data-file="material"><small>${s.importFile ? `已选择：${e(s.importFile)}` : "仅记录文件名，不读取或上传。"}</small></label><label class="check-row"><input type="checkbox" data-toggle="importAnalyze" ${s.importAnalyze ? "checked" : ""}><span>AI 结构建议（模拟）</span></label></div>`;
    if (stage === 2)
      main = `<div class="surface"><dl class="summary-list"><div><dt>材料类型</dt><dd>${typeLabel[s.importType]}</dd></div><div><dt>文件</dt><dd>${e(s.importFile)}</dd></div><div><dt>处理方式</dt><dd>直接提取${s.importAnalyze ? " · AI 结构建议" : ""}</dd></div></dl><p class="note">确认后创建示例任务，不上传文件。</p></div>`;
    return `<div class="focused-page">${head("", "导入材料")}<ol class="step-labels">${stepTitles.map((t, i) => `<li ${stage === i ? 'aria-current="step"' : ""} class="${i <= stage ? "on" : ""}"><span>${i + 1}</span>${t}</li>`).join("")}</ol><h2 class="section-title">${stepTitles[stage]}</h2>${main}<div class="flow-actions">${stage ? '<button class="secondary" type="button" data-action="importBack">上一步</button>' : ""}<button class="primary" type="button" data-action="${stage === 2 ? "importConfirm" : "importNext"}" ${(stage === 0 && !s.importType) || (stage === 1 && !s.importFile) ? "disabled" : ""}>${stage === 2 ? "确认导入" : "下一步"}${I("arrow")}</button></div></div>`;
  }

  function material() {
    const m =
      s.materials.find((x) => x.id === s.chosenMaterial) || s.materials[0];
    const target = { novel: "novel", textbook: "textbook", exam: "examPrep" }[
      m.type
    ];
    return `<article class="material-detail"><div class="book-art ${m.tone}" aria-hidden="true"><span class="book-art-letter">${e(m.cover)}</span><span class="book-art-line"></span><span class="book-art-label">${e(typeLabel[m.type])}</span></div><div class="detail-copy"><p class="step-caption">${e(m.subtitle)}</p>${head("", e(m.title))}<div>${tag(m.status, m.type === "exam" ? "warn" : "good")}</div><p class="material-description">${e(m.detail)}</p><p class="small muted">更新于 ${e(m.updated)}</p><div class="button-row">${btn({ novel: "打开阅读", textbook: "查看单元", exam: "准备试卷" }[m.type], target, "primary", "arrow")}<button type="button" class="secondary" data-modal="quality">解析状态</button></div></div></article>`;
  }

  function chapterList() {
    return novelLearning.chapterList();
  }

  function readerPanel() {
    if (!novelLearning.panelActive()) return "";
    const result = s.selectionMessage ? extras.selectionResult() : null;
    return `<aside class="reader-analysis-panel" data-reader-panel aria-label="阅读解析"><header><div><span class="small muted">阅读助手</span><h2>${result?.title || "句子解析"}</h2></div><div class="row-wrap">${extras.readerCanGoBack() ? `<button type="button" class="icon-btn" data-reader-back aria-label="返回上一条解析">${I("back")}</button>` : ""}<button type="button" class="icon-btn" data-reader-close aria-label="关闭解析面板">${I("close")}</button></div></header><div class="reader-analysis-body" data-reader-panel-body data-message="${e((s.selectionMessage?.id || "") + (s.selectionMessage?.selection?.novelSentenceId || ""))}" tabindex="-1">${result ? result.content : `<div class="reader-analysis-empty">${I("spark")}<h3>点一句，读懂这一句</h3><p>点击正文查看译文、意群和语法。长按可选择词汇查询。</p><button type="button" class="secondary" data-novel="prepare" data-chapter="${s.novelChapter}">${I("database")}准备本章</button><p class="small muted">已准备的解析和朗读可直接复用。</p></div>`}</div></aside>`;
  }
  function closeReaderPanel() {
    const origin = s.readerSource;
    extras.clearReaderSelection();
    render();
    if (origin) extras.restoreSelectionFocus(origin);
    else
      root
        .querySelector('[data-mode="analysis"]')
        ?.focus({ preventScroll: true });
  }
  root.addEventListener("click", (event) => {
    if (event.target.closest("[data-reader-close]")) closeReaderPanel();
    if (event.target.closest("[data-reader-back]"))
      extras.returnFromSelection();
  });
  function novel() {
    const text = novelLearning.prose();
    return `<div class="novel-workspace ${novelLearning.panelActive() ? "has-analysis" : ""}"><div class="reader-toolbar"><h1>夏の手紙</h1><div class="button-row"><button type="button" class="secondary" data-selection-action="continuous">${I("headphones")}连续朗读</button><button type="button" class="secondary chapter-trigger" data-modal="chapters">${I("library")}目录</button><button type="button" class="secondary" data-modal="readerSettings">${I("settings")}排版</button><button type="button" class="icon-btn" data-action="bookmark" aria-label="添加书签">${I("bookmark")}</button></div></div>${novelLearning.controls()}<div class="reader-shell ${novelLearning.panelActive() ? "has-panel" : ""}"><aside class="chapter-nav">${chapterList()}</aside><div class="reader-main"><article class="reading-paper" data-reader-theme="${s.readingTheme}" style="--reader-font:${s.readingFont === "serif" ? "'Yu Mincho','Noto Serif JP',serif" : "'Segoe UI','Microsoft YaHei',sans-serif"};--reader-size:${s.readingSize}px;--reader-line:${s.lineHeight}"><p class="step-caption">第 ${String(s.novelChapter + 1).padStart(2, "0")} 章 / 12 章</p><h2 lang="ja">${e(novelLearning.current().title)}</h2><div class="prose" lang="ja">${text}</div><footer class="reading-footer"><span>${e(novelLearning.current().title)}</span><span>${s.novelChapter + 1} / 12</span></footer></article><div data-reader-playback></div></div>${readerPanel()}</div></div>`;
  }

  function textbook() {
    const unit =
      data.textbook.units.find((x) => x.id === s.textbookUnit) ||
      data.textbook.units[0];
    return `${head("", "日语的日常表达")}<div class="textbook-layout"><nav class="setting-menu unit-menu" aria-label="单元目录">${data.textbook.units.map((x, i) => `<button type="button" ${x.id === s.textbookUnit ? 'aria-current="page"' : ""} data-unit="${x.id}"><span class="unit-number">${String(i + 1).padStart(2, "0")}</span>${e(x.title.replace(/^Unit \d+ · /, ""))}</button>`).join("")}</nav><section class="surface"><div class="section-head"><h2>${e(unit.title)}</h2>${btn("做课后题", "textbookPractice", "primary", "edit")}</div><div class="unit-content-list">${unit.items.map((item, i) => `<button class="material-row" type="button" ${i === 3 ? 'data-go="textbookPractice"' : `data-modal="textbookItem" data-index="${i}"`}><span class="setting-icon">${I(["book", "library", "spark", "edit"][i])}</span><span class="row-copy"><strong>${e(item)}</strong></span>${I("chevron")}</button>`).join("")}</div></section></div>`;
  }
  function textbookPractice() {
    const q = extras.textbookQuestion();
    return `<div class="focused-page">${head("", "课后题")}<p class="step-caption">${e(data.textbook.units.find((x) => x.id === s.textbookUnit)?.title || "当前单元")} · 示例题</p><section class="surface question-panel"><h2>${e(q.prompt)}</h2>${extras.questionButton("textbook", s.textbookUnit)}<div class="answer-list">${q.options.map((a, i) => `<button type="button" class="answer ${s.textbookSubmitted ? (i === q.correct ? "correct" : i === s.textbookAnswer ? "wrong" : "") : ""}" data-textbook-answer="${i}" aria-pressed="${s.textbookAnswer === i}" ${s.textbookSubmitted ? "disabled" : ""}><span>${String.fromCharCode(65 + i)}</span><span class="answer-copy">${e(a)}</span></button>`).join("")}</div>${s.textbookSubmitted ? `<div class="feedback" role="status"><strong>${s.textbookAnswer === q.correct ? "回答正确" : "这题选 A"}</strong><p>${e(q.explanation)}</p></div><button class="secondary" type="button" data-action="textbookReset">重新作答</button>` : `<button class="primary" type="button" data-action="textbookSubmit" ${s.textbookAnswer < 0 ? "disabled" : ""}>确认答案</button>`}</section></div>`;
  }

  function examPrep() {
    if (s.examRunning)
      return `${head("", "N2 模拟试卷")}<section class="surface focused-page stack"><h2>考试进行中</h2><p>已答 ${Object.keys(s.examAnswers).length} / ${data.exam.questions.length} 道题</p>${btn("返回作答", "examRun", "primary", "arrow")}</section>`;
    return `${head("", "N2 模拟试卷")}<div class="grid-3" style="margin-top:23px"><div class="stat"><strong>3</strong><span>内置示例题</span></div><div class="stat"><strong>60</strong><span>分钟 · 示例时限</span></div><div class="stat"><strong>${s.examReady ? "已冻结" : "待校对"}</strong><span>试卷状态</span></div></div><div class="grid-aside" style="margin-top:23px"><div class="surface stack"><h2 style="font-size:19px">准备清单</h2><div class="check-row">${I("check")}<span>题号、题组与分值</span>${tag("待人工校对", "warn")}</div><div class="check-row">${I("book")}<span>听力脚本与题组候选</span>${tag(s.examScriptMatched ? "已确认" : "待校对", s.examScriptMatched ? "good" : "warn")}</div><div class="check-row">${I("headphones")}<span>私有 TTS 音频</span>${tag(s.examAudioReady ? "示例就绪" : "未生成", s.examAudioReady ? "good" : "warn")}</div><div class="button-row"><button class="secondary" type="button" data-modal="examScript">校对听力候选</button><button class="secondary" type="button" data-action="examTts" ${s.examScriptMatched ? "" : "disabled"}>生成音频（模拟）</button><button class="primary" type="button" data-action="examFreeze" ${s.examScriptMatched && s.examAudioReady ? "" : "disabled"}>${s.examReady ? "查看考前说明" : "确认并冻结版本"}</button></div></div><aside class="callout warn">${I("warning")}<span>原型提供 3 道示例题。交卷后查看答案。</span></aside></div>`;
  }
  function examRun() {
    const q = data.exam.questions[s.examQuestion];
    const count = Object.keys(s.examAnswers).length;
    return `<div class="section-head" style="margin-top:0"><div>${head("", "整卷作答")}</div>${tag("计时示意 42:18", "warn")}</div><div class="grid-aside" style="margin-top:22px"><div class="surface stack-lg"><div class="eyebrow"><span class="signal"></span>${e(q.group)} · 第 ${s.examQuestion + 1} 题</div><h2 style="font-size:20px">${e(q.text)}</h2>${q.group === "听力" ? `<div class="callout">${I("headphones")}<span>原型不播放音频。</span></div><button class="secondary" type="button" data-action="examPlay">播放听力（界面示意）</button>` : ""}<div class="answer-list">${q.options.map((answer, i) => `<button type="button" class="answer" data-exam-answer="${i}" aria-pressed="${s.examAnswers[q.id] === i}"><span>${String.fromCharCode(65 + i)}</span><span class="answer-copy">${e(answer)}</span></button>`).join("")}</div><div class="button-row"><button class="secondary" type="button" data-action="examMark">${I("bookmark")} ${s.examMarked.includes(q.id) ? "取消标记" : "标记此题"}</button><button class="secondary" type="button" data-action="examSave">保存草稿</button><button class="secondary" type="button" data-action="examPrev" ${s.examQuestion === 0 ? "disabled" : ""}>上一题</button><button class="secondary" type="button" data-action="examNext" ${s.examQuestion === data.exam.questions.length - 1 ? "disabled" : ""}>下一题</button></div></div><aside class="stack"><div class="panel"><h2 style="font-size:18px">答题卡</h2><p class="small muted" style="margin:6px 0 15px">已答 ${count} / ${data.exam.questions.length} 个示例题 · ${e(s.examDraft)}</p><div class="button-row">${data.exam.questions.map((item, i) => `<button type="button" class="${s.examQuestion === i ? "primary" : "secondary"}" data-exam-question="${i}">${s.examMarked.includes(item.id) ? "★ " : ""}${i + 1}${s.examAnswers[item.id] !== undefined ? " ·" : ""}</button>`).join("")}</div></div><button class="danger-btn full" type="button" data-modal="examSubmit">交卷</button></aside></div>`;
  }
  function examResult() {
    const score = data.exam.questions.filter(
      (q) => s.examAnswers[q.id] === q.correct,
    ).length;
    return `${head("", "考试结果")}<div class="grid-3" style="margin-top:23px"><div class="stat"><strong>${score} / ${data.exam.questions.length}</strong><span>示例客观题</span></div><div class="stat"><strong>${data.exam.questions.length - score}</strong><span>需要回看的示例题</span></div><div class="stat"><strong>已交卷</strong><span>示例答卷状态</span></div></div><div class="section-head"><h2>逐题复盘</h2>${btn("查看错题库", "mistakes", "secondary")}</div>${extras.examReview()}`;
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

  function csv() {
    return `${head("", "单词 CSV")}<div class="grid-2" style="margin-top:24px"><div class="surface stack"><h2 style="font-size:20px">导出单词</h2><p class="subtitle">仅导出单词示例；不包含语法、句子和习题卡片。</p><button type="button" class="secondary" data-action="csvExport">${I("download")} 下载示例 CSV</button></div><div class="surface stack"><h2 style="font-size:20px">导入预览</h2><label class="field">选择 UTF-8 CSV<input type="file" data-file="csv" accept=".csv,text/csv"><small>${s.csvFile ? `已选择：${e(s.csvFile)}` : "本原型不读取所选文件内容。"}</small></label><button type="button" class="secondary" data-action="csvPreview" ${s.csvFile ? "" : "disabled"}>打开示例预览</button></div></div>${s.csvStep ? `<div class="surface stack" style="margin-top:20px"><div class="eyebrow"><span class="signal"></span>示例预览 · 与所选文件内容无关</div><h2 style="font-size:20px">2 行示例 · 1 行跳过</h2><div class="table-wrap"><table class="table"><thead><tr><th>词形</th><th>释义</th><th>词本</th><th>处理</th></tr></thead><tbody><tr><td>そっと</td><td>轻轻地</td><td>日常的细节</td><td>重复：跳过</td></tr><tr><td>微笑む</td><td>微笑</td><td>阅读时遇见</td><td>补空字段</td></tr></tbody></table></div><div class="button-row"><button class="primary" type="button" data-action="csvConfirm">确认演示导入</button></div></div>` : ""}`;
  }
  function practiceCandidateCount() {
    return exerciseFlow.candidates().length;
  }
  function exercise() {
    return `${head("", "练习")}<div class="practice-home"><button type="button" class="practice-create" data-go="exerciseBuilder"><span class="signal"></span><strong>生成 AI 习题</strong><span class="practice-create-bottom">选择来源 ${I("arrow")}</span></button><section class="surface practice-existing"><p class="step-caption">已有习题</p><h2>语境中的表达</h2><p class="muted">${e(s.activeLanguage)} · 1 道示例题</p>${btn("开始练习", "practice", "secondary", "arrow")}</section></div><div class="section-head"><h2>学习记录</h2></div><div class="grid-2"><button class="entry-card" type="button" data-go="mistakes"><span class="setting-icon">${I("warning")}</span><span class="row-copy"><strong>错题库</strong><small>${s.mistakes.filter((m) => m.state === "当前待纠正").length} 道待纠正</small></span>${I("chevron")}</button><button class="entry-card" type="button" data-go="report"><span class="setting-icon">${I("grid")}</span><span class="row-copy"><strong>学习诊断</strong><small>方向助词 · 语境词义</small></span>${I("chevron")}</button></div>`;
  }
  function exerciseBuilder() {
    return `<div class="exercise-builder">${head("", "生成 AI 习题")}<p class="exercise-step"><strong>步骤 ${builderStep + 1} / 2</strong><span>${builderStep ? "设置与确认" : "选择来源"}</span></p>${!builderStep ? `${exerciseFlow.sources()}<p class="exercise-selection-count" role="status">已选 ${practiceCandidateCount()} 项内容，相同收藏只计一次。</p><div class="flow-actions"><button type="button" class="primary" data-action="builderNext" ${practiceCandidateCount() ? "" : "disabled"}>下一步 · 设置与确认 ${I("arrow")}</button></div>` : `<div class="exercise-config">${exerciseFlow.settings()}${exerciseFlow.review()}</div>`}</div>`;
  }
  function practice() {
    const p =
      s.activeLanguage === "英语" ? data.practiceEnglish : data.practice;
    return `<div class="focused-page">${head("", "逐题练习")}<p class="step-caption">${e(s.activeLanguage)} · 语境填空 · 内置示例 01</p><section class="surface question-panel"><p class="muted">${e(p.translation)}</p><h2 lang="${s.activeLanguage === "英语" ? "en" : "ja"}">${e(p.prompt)}</h2>${extras.questionButton("practice", s.activeLanguage)}<div class="answer-list">${p.options.map((answer, i) => `<button class="answer ${s.practiceSubmitted ? (i === p.correct ? "correct" : i === s.practiceAnswer ? "wrong" : "") : ""}" type="button" data-practice-answer="${i}" aria-pressed="${s.practiceAnswer === i}" ${s.practiceSubmitted ? "disabled" : ""}><span>${String.fromCharCode(65 + i)}</span><span class="answer-copy">${e(answer)}</span></button>`).join("")}</div>${s.practiceSubmitted ? `<div class="feedback ${s.practiceAnswer === p.correct ? "correct" : "wrong"}" role="status"><strong>${s.practiceAnswer === p.correct ? "回答正确" : `这题选 ${String.fromCharCode(65 + p.correct)}`}</strong><p>${e(p.explanation)}</p></div><button class="secondary" type="button" data-action="practiceReset">重新作答</button>` : `<button class="primary" type="button" data-action="practiceSubmit" ${s.practiceAnswer < 0 ? "disabled" : ""}>确认答案</button>`}</section></div>`;
  }

  function mistakes() {
    return `${head("", "错题库")}<div class="grid-3" style="margin-top:23px"><div class="stat"><strong>${s.mistakes.length}</strong><span>历史示例</span></div><div class="stat"><strong>${s.mistakes.filter((m) => m.state === "当前待纠正").length}</strong><span>当前待纠正</span></div><div class="stat"><strong>${s.mistakes.filter((m) => m.favorite).length}</strong><span>已收藏</span></div></div><div class="section-head"><h2>错题记录</h2>${btn("选择习题来源", "exerciseBuilder", "secondary", "spark")}</div><div class="table-wrap"><table class="table"><thead><tr><th>考察点</th><th>来源</th><th>当前状态</th><th>收藏</th><th></th></tr></thead><tbody>${s.mistakes.map((m) => `<tr><td><strong>${e(m.title)}</strong></td><td>${e(m.source)}</td><td>${tag(m.state, m.state === "已经改进" ? "good" : "warn")}</td><td>${m.favorite ? "已收藏" : "—"}</td><td><button type="button" data-mistake="${m.id}">查看 ${I("arrow")}</button></td></tr>`).join("")}</tbody></table></div>`;
  }
  function mistake() {
    const m =
      s.mistakes.find((x) => x.id === s.selectedMistake) || s.mistakes[0];
    return `${head("MISTAKE / DETAIL", e(m.title), e(m.source))}<div class="grid-aside" style="margin-top:22px"><div class="panel stack"><div>${tag(m.state, m.state === "已经改进" ? "good" : "warn")}</div><h2 style="font-size:19px">当时的作答</h2><p>${e(m.answer)}</p></div><aside class="surface stack"><h2 style="font-size:18px">下一步</h2><button type="button" class="secondary" data-action="favoriteMistake">${I("bookmark")} ${m.favorite ? "取消收藏" : "收藏错题"}</button>${btn("选择习题来源", "exerciseBuilder", "primary", "spark")}</aside></div>`;
  }
  function report() {
    return `${head("", "学习诊断")}<div class="grid-3" style="margin-top:22px"><div class="panel"><div class="eyebrow"><span class="signal"></span>薄弱点</div><h2 style="margin:13px 0 8px;font-size:21px">方向助词</h2><p>Unit 02 的有效作答显示「に / へ」容易混淆。</p>${btn("回到教材", "textbook", "text-btn")}</div><div class="surface"><div class="eyebrow"><span class="signal"></span>亮点</div><h2 style="margin:13px 0 8px;font-size:21px">语境词义</h2><p>能留意句子的情绪和动作方式。</p></div><div class="surface"><div class="eyebrow"><span class="signal"></span>下一步</div><h2 style="margin:13px 0 8px;font-size:21px">选源练习</h2><p>从教材或当前错题预览候选，再明确确认生成。</p>${btn("选择来源", "exerciseBuilder", "text-btn")}</div></div>`;
  }
  function notifications() {
    return `${head("IN-APP / UPDATES", "站内消息", "站内提示来自任务与结果状态；本原型没有系统推送或邮件发送。")}<div class="section-head"><h2>消息 <span>${s.notifications.filter((n) => n.unread).length} 条未读</span></h2><button class="text-btn" type="button" data-action="readAll">全部标为已读</button></div><div class="material-list">${s.notifications.map((n) => `<button type="button" class="material-row" data-notification="${n.id}"><span class="signal" style="opacity:${n.unread ? 1 : 0.25}"></span><span class="row-copy"><span class="row-title">${e(n.title)}</span><small>${e(n.detail)}</small></span><small class="muted">${e(n.time)}</small>${I("chevron")}</button>`).join("")}</div>`;
  }
  function jobs() {
    return extras.tasks();
  }

  const settingNav = [
    ["profile", "个人资料", "user"],
    ["languages", "语言选项", "globe"],
    ["appearance", "外观与无障碍", "sun"],
    ["readingPrefs", "阅读偏好", "book"],
    ["model", "个人模型", "spark"],
    ["speech", "朗读与声音", "headphones"],
    ["usage", "模型用量", "grid"],
    ["cache", "本机缓存", "database"],
    ["connection", "服务连接", "globe"],
    ["security", "安全与账号", "shield"],
  ];
  function settings() {
    const groups = [
      ["账号与语言", ["profile", "languages", "security"]],
      ["阅读与显示", ["appearance", "readingPrefs", "speech"]],
      ["模型与设备", ["model", "usage", "cache", "connection"]],
    ];
    return `${head("", "我的")}<button type="button" class="profile-card" data-go="profile"><span class="avatar">遥</span><span class="row-copy"><strong>${e(s.profile.displayName)}</strong><small>${e(s.activeLanguage || "未设置学习语言")} · ${e(s.level)}</small></span>${I("chevron")}</button><div class="settings-groups">${groups
      .map(
        ([title, routes]) =>
          `<section><h2 class="section-title">${title}</h2><div class="settings-list">${routes
            .map((route) => {
              const entry = settingNav.find((x) => x[0] === route);
              return `<button type="button" class="material-row" data-go="${route}"><span class="setting-icon">${I(entry[2])}</span><span class="row-copy"><strong>${entry[1]}</strong></span>${I("chevron")}</button>`;
            })
            .join("")}</div></section>`,
      )
      .join("")}</div>`;
  }

  function settingContentCore(route) {
    if (route === "profile")
      return `<h2>个人资料</h2><p class="subtitle">均为可选信息，仅本人可见。</p><form class="form-grid" data-form="profile"><label class="field">显示名<input name="displayName" maxlength="40" value="${e(s.profile.displayName)}"><small>留空时显示“学习者”。</small></label><label class="field">出生年份（可选）<input type="number" name="birthYear" min="1900" max="2026" value="${e(s.profile.birthYear)}"></label><label class="field">性别（可选）<select name="gender">${["未填写", "女", "男", "非二元", "自我描述", "不愿说明"].map((x) => `<option ${s.profile.gender === x ? "selected" : ""}>${x}</option>`).join("")}</select></label><label class="field">时区<select name="timezone"><option value="Asia/Tokyo" ${s.profile.timezone === "Asia/Tokyo" ? "selected" : ""}>东京 / Asia/Tokyo</option><option value="Asia/Shanghai" ${s.profile.timezone === "Asia/Shanghai" ? "selected" : ""}>上海 / Asia/Shanghai</option><option value="UTC" ${s.profile.timezone === "UTC" ? "selected" : ""}>UTC</option></select></label><button class="primary" type="submit">保存资料</button></form>`;
    if (route === "languages")
      return `<h2>语言选项</h2><div class="form-grid"><label class="field">界面语言<select disabled><option>简体中文 · 当前支持</option></select><small>当前仅提供简体中文界面。</small></label><div class="field">母语（可多选）${["简体中文", "英语", "日语"].map((x) => `<label class="check-row"><input type="checkbox" data-native="${x}" ${s.nativeLanguages.includes(x) ? "checked" : ""}><span>${x}</span></label>`).join("")}</div><label class="field">解释语言<select data-setting="explanationLanguage">${["简体中文", "英语", "日语"].map((x) => `<option ${s.explanationLanguage === x ? "selected" : ""}>${x}</option>`).join("")}</select></label><div class="field">学习语言（可多选）${["日语", "英语"].map((x) => `<label class="check-row"><input type="checkbox" data-target="${x}" ${s.targetLanguages.includes(x) ? "checked" : ""}><span>${x}</span>${s.activeLanguage === x ? tag("当前") : ""}</label>`).join("")}</div><label class="field">当前学习语言<select data-setting="activeLanguage">${s.targetLanguages.map((x) => `<option ${s.activeLanguage === x ? "selected" : ""}>${x}</option>`).join("")}</select></label><label class="field">自评水平<select data-setting="level">${["未填写", "初学", "基础", "中级", "进阶"].map((x) => `<option ${s.level === x ? "selected" : ""}>${x}</option>`).join("")}</select></label><button class="primary" type="button" data-action="saveSettings">保存语言选项</button></div>`;
    if (route === "appearance")
      return `<h2>外观与无障碍</h2><div class="form-grid"><label class="field">应用主题<select data-setting="theme"><option value="system" ${s.theme === "system" ? "selected" : ""}>跟随系统</option><option value="light" ${s.theme === "light" ? "selected" : ""}>浅色</option><option value="dark" ${s.theme === "dark" ? "selected" : ""}>深色</option></select></label><label class="check-row"><input type="checkbox" data-toggle="reduceMotion" ${s.reduceMotion ? "checked" : ""}><span>减少动态</span></label><label class="check-row"><input type="checkbox" data-toggle="highContrast" ${s.highContrast ? "checked" : ""}><span>高对比显示</span></label><div class="soft-panel"><div class="eyebrow"><span class="signal"></span>预览</div><h2 style="margin:13px 0 6px">夏の手紙</h2><p>朝の光が、部屋に広がった。</p></div></div>`;
    if (route === "readingPrefs")
      return `<h2>阅读偏好</h2><div class="form-grid"><label class="field">字体风格<select data-setting="readingFont"><option value="serif" ${s.readingFont === "serif" ? "selected" : ""}>有书感的衬线体</option><option value="sans" ${s.readingFont === "sans" ? "selected" : ""}>清晰的无衬线体</option></select></label><label class="field">字号：${s.readingSize}px<input type="range" min="16" max="24" value="${s.readingSize}" data-range="readingSize"></label><label class="field">行距：${s.lineHeight.toFixed(1)}<input type="range" min="1.6" max="2.4" step="0.1" value="${s.lineHeight}" data-range="lineHeight"></label><label class="field">阅读主题<select data-setting="readingTheme"><option value="light" ${s.readingTheme === "light" ? "selected" : ""}>浅色</option><option value="dark" ${s.readingTheme === "dark" ? "selected" : ""}>深色</option><option value="sepia" ${s.readingTheme === "sepia" ? "selected" : ""}>暖纸色</option></select></label><div class="soft-panel" style="background:${s.readingTheme === "sepia" ? "#f7ead4" : s.readingTheme === "dark" ? "#192535" : "var(--blue-soft)"};color:${s.readingTheme === "dark" ? "#edf3ff" : "#152b42"};font-family:${s.readingFont === "serif" ? "'Yu Mincho',serif" : "'Segoe UI',sans-serif"};font-size:${s.readingSize}px;line-height:${s.lineHeight}">朝の光が、白いカーテンを通して部屋に広がった。</div><button class="primary" type="button" data-action="saveSettings">保存偏好</button></div>`;
    if (route === "model")
      return `<h2>个人模型</h2><p class="subtitle">使用本人 Key。文本、视觉和 TTS 能力独立选择与验证。</p><div class="form-grid"><label class="field">供应商<select data-setting="modelProvider"><option ${s.modelProvider === "OpenRouter" ? "selected" : ""}>OpenRouter</option><option ${s.modelProvider === "Gemini" ? "selected" : ""}>Gemini</option></select></label><label class="field">个人 API Key<input type="password" value="••••••••••••" disabled><small>原型不接收 API Key。</small></label><div class="grid-3"><div class="tile"><strong>文本解释</strong><small>需要文本模型能力</small></div><div class="tile"><strong>视觉识别</strong><small>扫描需明确范围和上限</small></div><div class="tile"><strong>云端朗读</strong><small>需 TTS 能力</small></div></div><button class="secondary" type="button" data-action="modelTest">模拟测试文本能力</button><p class="note">示例状态：${e(s.modelStatus)}。测试不发送任何请求。</p></div>`;
    if (route === "speech")
      return `<h2>朗读与声音</h2><div class="form-grid"><label class="field">TTS 供应商<select data-setting="speechProvider"><option ${s.speechProvider === "Gemini TTS" ? "selected" : ""}>Gemini TTS</option><option ${s.speechProvider === "OpenRouter TTS" ? "selected" : ""}>OpenRouter TTS</option></select></label><label class="field">默认声音<select data-setting="speechVoice">${["日语 · 清晰自然（示例）", "英语 · 清晰自然（示例）"].map((voice) => `<option ${(s.speechVoice || "日语 · 清晰自然（示例）") === voice ? "selected" : ""}>${voice}</option>`).join("")}</select></label><label class="field">播放倍速：${s.speechSpeed.toFixed(1)}×<input type="range" min="0.7" max="1.5" step="0.1" value="${s.speechSpeed}" data-range="speechSpeed"></label><div class="callout">${I("headphones")}<span>试听仅演示控件，不播放音频。</span></div><div class="button-row"><button type="button" class="secondary" data-action="speechPreview">试听界面状态</button><button type="button" class="primary" data-action="saveSettings">保存偏好</button></div></div>`;
    if (route === "usage")
      return `<h2>模型用量</h2><div class="tabs" style="margin-bottom:17px">${["7 天", "30 天", "90 天"].map((x) => `<button type="button" data-usage-range="${x}" aria-pressed="${s.usageRange === x}">${x}</button>`).join("")}</div><div class="grid-3"><div class="stat"><strong>12</strong><span>示例调用</span></div><div class="stat"><strong>2</strong><span>结果复用事件</span></div><div class="stat"><strong>未提供</strong><span>部分音频用量</span></div></div><div class="table-wrap" style="margin-top:17px"><table class="table"><thead><tr><th>能力</th><th>示例调用</th><th>输入</th><th>输出</th><th>缓存读取</th></tr></thead><tbody><tr><td>文本解释</td><td>8</td><td>12,480</td><td>3,240</td><td>1,800</td></tr><tr><td>TTS</td><td>3</td><td>未提供</td><td>未提供</td><td>未提供</td></tr><tr><td>视觉识别</td><td>1</td><td>1,520</td><td>480</td><td>未提供</td></tr></tbody></table></div>`;
    if (route === "cache")
      return `<h2>本机缓存</h2><p class="subtitle">当前账号的阅读、已查解释和允许离线的音频副本。</p><div class="grid-2"><div class="stat"><strong>${s.cacheCleared ? "已清理" : "42 MB"}</strong><span>示例本机副本</span></div><div class="surface"><strong>服务端成果</strong><p class="small muted" style="margin-top:8px">清理本机不会删除已保存的解释和音频。</p></div></div><button class="danger-btn" type="button" data-modal="clearCache">${I("trash")} 清除此账号本机缓存</button>`;
    return `<h2>安全与账号</h2><div class="stack"><div class="surface"><strong>当前设备会话</strong><p class="small muted" style="margin-top:6px">演示账号 · 用户端</p></div><div class="callout">${I("shield")}<span>修改密码后，所有设备需要重新登录。</span></div><div class="button-row"><button class="secondary" type="button" data-modal="password">修改密码</button><button class="danger-btn" type="button" data-action="logout">退出演示账号</button></div><p class="note">此原型不接收真实密码、邮箱或 API Key。</p></div>`;
  }
  function settingContent(route) {
    if (route === "connection")
      return `<h2>服务连接</h2><div class="grid-2"><div class="surface stack"><strong>当前 Web 原型</strong><p class="small muted">当前页面仅运行本地演示，不连接业务服务。</p></div><form class="surface form-grid" data-form="connection"><label class="field">Windows 服务地址示例<input type="url" name="address" required value="${e(s.serviceAddress)}" placeholder="https://your-haruka.example"><small>填写 HTTPS 服务地址，不包含登录信息。</small></label><button class="primary" type="submit">模拟无凭据探测</button></form></div>${s.serviceProbe ? `<div class="callout" style="margin-top:17px">${I("shield")}<span>地址格式有效。原型未实际联网。</span></div>` : ""}`;
    if (route === "states")
      return `<h2>状态样例</h2><p class="subtitle">供设计检查的虚构状态，不代表当前账号真的离线或失权。</p><div class="grid-2"><div class="surface stack"><strong>没有材料</strong><p>添加小说、课本或试卷，材料会出现在本人书库。</p>${btn("添加材料", "import", "secondary")}</div><div class="surface stack"><strong>暂时离线</strong><p>有效权限租期内可以读已缓存章节与解释；新的生成、设置保存和考试场次需联网。</p>${btn("查看缓存", "cache", "secondary")}</div><div class="surface stack"><strong>没有访问权限</strong><p>这份内容目前不可读取。返回材料库或联系有权管理员。</p>${btn("返回材料库", "library", "secondary")}</div><div class="surface stack"><strong>任务未完成</strong><p>示例：网络故障导致结果未知。先查看任务状态，再决定是否重试。</p>${btn("查看任务", "jobs", "secondary")}</div><div class="surface stack"><strong>正在载入</strong><p>保留页面结构，不用动画推算业务完成。</p><div class="stepper"><span class="on"></span><span></span><span></span></div></div></div>`;
    const content = settingContentCore(route);
    if (route === "profile")
      return `${content}<div class="surface stack" style="margin-top:20px"><h2>头像与隐私</h2><div class="button-row"><span class="avatar">遥</span><span>默认头像 · 仅本人可见</span></div><button type="button" class="secondary" data-action="avatarInfo">更换头像</button><label class="check-row"><input type="checkbox" data-toggle="useDemographics" ${s.useDemographics ? "checked" : ""}><span>允许 AI 使用年龄段与性别</span></label></div>`;
    if (route === "languages")
      return `${content}<div class="surface stack" style="margin-top:20px"><h2>${e(s.activeLanguage || "当前语言")}学习目标</h2><div class="grid-2">${["阅读", "教材", "考试", "听力", "口语", "写作", "词汇", "语法"].map((goal) => `<label class="check-row"><input type="checkbox" data-goal="${goal}" ${s.learningGoals.includes(goal) ? "checked" : ""}><span>${goal}</span></label>`).join("")}</div><button type="button" class="primary" data-action="saveSettings">保存学习目标</button></div>`;
    if (route === "model")
      return `${content}<div class="surface stack" style="margin-top:20px"><h2>凭据管理</h2><p>当前凭据：未配置。</p><div class="button-row">${["文本", "视觉", "TTS"].map((cap) => `<button type="button" class="secondary" data-action="modelCapability" data-capability="${cap}">模拟${cap}能力检查</button>`).join("")}</div><button type="button" class="text-btn" data-modal="credential">管理凭据 ${I("arrow")}</button></div>`;
    return content;
  }
  function settingPage(route) {
    if (route === "states")
      return `${head("", "状态样例")}<section class="setting-body">${settingContent(route).replace(/^<h2>.*?<\/h2>/, "")}</section>`;
    return `${head("", names[route])}<div class="settings-layout"><nav class="setting-menu settings-menu" aria-label="设置分类">${settingNav.map(([key, label, icon]) => `<button type="button" data-go="${key}" ${route === key ? 'aria-current="page"' : ""}>${I(icon)}${label}</button>`).join("")}</nav><section class="setting-body">${settingContent(route).replace(/^<h2>.*?<\/h2>/, "")}</section></div>`;
  }

  function auth(route) {
    const admin = route === "adminLogin";
    const title = admin
      ? "管理端，独立登录。"
      : route === "register"
        ? "从这里开始。"
        : route === "recovery"
          ? "找回访问方式。"
          : "欢迎回来。";
    return `<div class="auth-wrap"><div class="auth-graphic"><div class="brand"><span class="brand-mark">h</span><span>haruka</span></div><div><div class="eyebrow" style="color:#d8f36a"><span class="signal"></span>${admin ? "ADMIN / DEMO" : "CLEAR SIGNAL"}</div><h1>${title}</h1><p style="margin-top:18px">${admin ? "" : "把自己的小说、课本与试卷，变成可阅读、理解和练习的语言学习空间。"}</p></div><p class="small">虚构账号演示。</p></div><div class="auth-form"><div><div class="eyebrow"><span class="signal"></span>${admin ? "管理端示例入口" : "个人学习空间"}</div><h2 style="font-size:28px;margin:13px 0 7px">${admin ? "进入管理端演示" : route === "recovery" ? "找回账号" : route === "register" ? "提交演示注册" : "登录演示账号"}</h2><p class="subtitle">仅使用虚构账号，输入不会发送。</p><form data-form="${route}" class="form-grid" style="margin-top:26px"><label class="field">登录邮箱<input type="email" name="email" placeholder="example@demo.test" required></label>${route !== "recovery" ? `<label class="field">密码<input type="password" name="password" placeholder="仅填写演示内容" required minlength="6"></label>` : `<div class="callout">${I("shield")}<span>真实恢复方式尚待确认，演示仅展示统一受理结果。</span></div>`}${route === "register" ? '<label class="field">确认密码<input type="password" name="confirmPassword" placeholder="再次输入演示密码" required minlength="6"></label>' : ""}<button class="primary full" type="submit">${admin ? "进入管理端演示" : route === "register" ? "提交演示注册" : route === "recovery" ? "查看受理结果" : "进入学习空间"}</button></form><div class="button-row" style="margin-top:16px">${admin ? btn("返回用户端登录", "login", "text-btn") : route === "login" ? `${btn("创建账号", "register", "text-btn")}${btn("忘记密码", "recovery", "text-btn")}` : btn("返回登录", "login", "text-btn")}</div></div></div></div>`;
  }
  function onboarding() {
    return `<div class="auth-wrap"><div class="auth-graphic"><div class="brand"><span class="brand-mark">h</span><span>haruka</span></div><div><div class="eyebrow" style="color:#d8f36a"><span class="signal"></span>WELCOME</div><h1>按自己的节奏，开始学习。</h1><p style="margin-top:17px">学习语言、解释语言和模型 Key 都可以之后设置。</p></div></div><div class="auth-form"><div><h2 style="font-size:27px;margin-bottom:8px">先选一个方向</h2><p class="subtitle">这一步可以跳过，不影响登录与基础阅读。</p><div class="form-grid" style="margin-top:24px"><label class="field">当前学习语言<select data-setting="activeLanguage"><option>日语</option><option>英语</option></select></label><label class="field">解释语言<select data-setting="explanationLanguage"><option>简体中文</option><option>英语</option><option>日语</option></select></label><button class="primary" type="button" data-action="finishOnboarding">开始体验</button><button class="secondary" type="button" data-action="finishOnboarding">暂时跳过</button></div></div></div></div>`;
  }
  function registrationStatus() {
    return `<div class="auth-wrap"><div class="auth-graphic"><div class="brand"><span class="brand-mark">h</span><span>haruka</span></div><div><div class="eyebrow" style="color:#d8f36a"><span class="signal"></span>REGISTRATION / DEMO</div><h1>注册请求已受理</h1><p style="margin-top:18px"></p></div></div><div class="auth-form"><div class="stack"><h2 style="font-size:27px">下一步</h2><p class="subtitle">本次为模拟受理，未创建账号或发送邮件。</p><div class="callout">${I("shield")}<span>账号验证或审批完成后，请返回登录。</span></div>${btn("返回登录演示", "login", "primary")}</div></div></div>`;
  }
  function adminOverview() {
    return `${head("", "运维概览")}<div class="grid-3" style="margin-top:25px"><div class="stat"><strong>128</strong><span>示例账号数</span></div><div class="stat"><strong>4</strong><span>待处理任务</span></div><div class="stat"><strong>99.2%</strong><span>示例请求成功率</span></div></div><div class="grid-2" style="margin-top:20px"><div class="panel"><div class="eyebrow"><span class="signal"></span>待关注</div><h2 style="font-size:21px;margin:13px 0 8px">任务队列有 2 项等待重试</h2>${btn("查看任务", "adminJobs", "secondary")}</div><div class="surface"><div class="eyebrow"><span class="signal"></span>授权变化</div><h2 style="font-size:21px;margin:13px 0 8px">角色更新待核对</h2>${btn("查看角色", "adminRoles", "secondary")}</div></div>`;
  }
  function adminUsers() {
    const users = [
      ["学习者 A", "learner-a@example.test", "正常", "用户端"],
      ["学习者 B", "learner-b@example.test", "待审批", "未启用"],
      ["运维示例", "operator@example.test", "正常", "管理端"],
    ];
    return `${head("", "用户与会话")}<div class="section-head"><h2>用户列表</h2><label class="search">${I("search")}<input type="search" data-input="adminSearch" value="${e(s.adminSearch || "")}" placeholder="搜索虚构账号" aria-label="搜索虚构账号"></label></div><div class="table-wrap"><table class="table"><thead><tr><th>用户</th><th>登录邮箱</th><th>状态</th><th>受众</th><th>操作</th></tr></thead><tbody>${users
      .filter((row) =>
        row
          .join(" ")
          .toLowerCase()
          .includes((s.adminSearch || "").toLowerCase()),
      )
      .map(
        (row) =>
          `<tr><td><strong>${e(row[0])}</strong></td><td>${e(row[1])}</td><td>${tag(row[2], row[2] === "正常" ? "good" : "warn")}</td><td>${e(row[3])}</td><td><button type="button" data-admin-item="${e(row[0])}">查看运维摘要</button></td></tr>`,
      )
      .join(
        "",
      )}</tbody></table></div><div class="callout" style="margin-top:18px">${I("shield")}<span>管理端不会默认显示头像原图、人口资料、个人 Key、私有材料或学习内容。</span></div>`;
  }
  function adminRoles() {
    return `${head("", "角色与权限")}<div class="grid-aside" style="margin-top:23px"><div class="table-wrap"><table class="table"><thead><tr><th>角色</th><th>受众</th><th>成员</th><th>状态</th><th></th></tr></thead><tbody><tr><td>学习者</td><td>用户端</td><td>126</td><td>${tag("默认")}</td><td><button type="button" data-admin-item="学习者角色">预览</button></td></tr><tr><td>支持人员</td><td>管理端</td><td>2</td><td>${tag("受限")}</td><td><button type="button" data-admin-item="支持人员角色">预览</button></td></tr><tr><td>超级管理员</td><td>管理端</td><td>1</td><td>${tag("受保护", "warn")}</td><td><button type="button" data-admin-item="超级管理员角色">预览</button></td></tr></tbody></table></div><aside class="callout">${I("shield")}<span>角色变更仅为预览，不会发布。</span></aside></div>`;
  }
  function adminMenus() {
    return `${head("", "页面与菜单")}<div class="grid-2" style="margin-top:23px"><div class="surface stack"><h2 style="font-size:19px">用户端导航</h2>${["材料库", "单词本", "AI 习题", "错题库", "查询", "学习诊断", "设置"].map((x) => `<div class="check-row">${I("check")}<span>${x}</span>${tag("授权后显示")}</div>`).join("")}</div><div class="surface stack"><h2 style="font-size:19px">管理端导航</h2>${["用户与会话", "角色与权限", "注册策略", "任务与资源", "审计诊断"].map((x) => `<div class="check-row">${I("check")}<span>${x}</span>${tag("授权后显示")}</div>`).join("")}</div></div>`;
  }
  function adminPolicy() {
    return `${head("", "注册策略")}<div class="grid-aside" style="margin-top:22px"><div class="surface form-grid"><label class="field">注册方式<select><option>需审批（示例）</option><option>关闭新注册（示例）</option></select></label><label class="field">邮箱验证<select><option>待选择</option><option>启用后校验</option></select></label><label class="field">账号恢复<select><option>待选择</option><option>邮件恢复</option><option>人工恢复</option></select></label><button class="primary" type="button" data-action="adminPreview">预览策略变化（演示）</button></div><aside class="callout warn">${I("warning")}<span>仅预览，不发布策略。</span></aside></div>`;
  }
  function adminJobs() {
    return `${head("", "任务与资源")}<div class="section-head"><h2>任务摘要</h2></div><div class="table-wrap"><table class="table"><thead><tr><th>任务引用</th><th>类型</th><th>阶段</th><th>状态</th><th></th></tr></thead><tbody><tr><td>JOB-D100</td><td>材料解析</td><td>验证后发布</td><td>${tag("已完成", "good")}</td><td><button type="button" data-admin-item="JOB-D100">查看摘要</button></td></tr><tr><td>JOB-D101</td><td>模型调用</td><td>等待本人凭据</td><td>${tag("待配置", "warn")}</td><td><button type="button" data-admin-item="JOB-D101">查看摘要</button></td></tr><tr><td>JOB-D102</td><td>音频生成</td><td>重试检查</td><td>${tag("需处理", "warn")}</td><td><button type="button" data-admin-item="JOB-D102">查看摘要</button></td></tr></tbody></table></div>`;
  }
  function adminAudit() {
    return `${head("", "审计诊断")}<div class="table-wrap" style="margin-top:23px"><table class="table"><thead><tr><th>时间</th><th>操作类别</th><th>目标范围</th><th>结果</th></tr></thead><tbody><tr><td>09:42</td><td>角色授权预览</td><td>管理权限</td><td>待提交</td></tr><tr><td>09:16</td><td>会话撤销</td><td>本人设备</td><td>已提交示例</td></tr><tr><td>昨天</td><td>注册策略读取</td><td>注册入口</td><td>已读取示例</td></tr></tbody></table></div><div class="callout" style="margin-top:17px">${I("shield")}<span>审计不展示密码、Token、Key、原始 Prompt 或用户私有材料正文。</span></div>`;
  }
  function adminUsage() {
    return `${head("", "模型调用概览。")}<div class="grid-3" style="margin-top:23px"><div class="stat"><strong>284</strong><span>虚构供应商 attempts</span></div><div class="stat"><strong>12</strong><span>用量未提供的 attempts</span></div><div class="stat"><strong>3</strong><span>可见供应商类别</span></div></div><div class="table-wrap" style="margin-top:20px"><table class="table"><thead><tr><th>能力</th><th>真实调用数（示例）</th><th>已知用量</th><th>未知用量</th></tr></thead><tbody><tr><td>文本模型</td><td>210</td><td>1,284,000 Token</td><td>8 attempts</td></tr><tr><td>视觉模型</td><td>38</td><td>184,000 Token</td><td>3 attempts</td></tr><tr><td>TTS</td><td>36</td><td>部分音频秒数</td><td>1 attempt</td></tr></tbody></table></div>`;
  }
  function adminSecurity() {
    return `${head("", "管理账号与安全")}<div class="grid-aside" style="margin-top:22px"><div class="surface stack"><h2 style="font-size:19px">当前管理端会话</h2><p>运维示例 · 在线演示会话</p><div class="callout">${I("shield")}<span>修改密码后需要重新登录。</span></div><div class="button-row"><button class="secondary" type="button" data-modal="password">修改密码</button><button class="danger-btn" type="button" data-action="adminLogout">退出管理端演示</button></div></div><aside class="panel stack"><h2 style="font-size:18px">切换到用户端</h2><p>切换受众须重新登录，不能静默沿用管理会话。</p><button class="secondary" type="button" data-action="switchClient">进入用户端登录</button></aside></div>`;
  }
  function modal() {
    if (!s.modal) return "";
    let title = "演示提示";
    let content = "";
    const shared = novelLearning.dialog() || extras.dialog();
    if (shared) {
      title = shared.title;
      content = shared.content;
    } else if (s.modal === "prototypeInfo") {
      title = "原型说明";
      content = `<div class="stack"><p>所有内容均为虚构样本；操作只保留在当前页面，刷新后重置。</p><p>文件不会上传，不连接业务服务，不调用 AI 或 TTS。请勿输入真实密码或 API Key。</p><div class="button-row">${btn("状态样例", "states", "secondary")}${btn("管理端演示", "adminLogin", "secondary")}</div></div>`;
    } else if (s.modal === "chapters") {
      title = "夏の手紙";
      content = `<div class="chapter-nav chapter-dialog">${chapterList()}</div>`;
    } else if (s.modal === "readerSettings") {
      title = "阅读排版";
      content = settingContentCore("readingPrefs")
        .replace(/^<h2>.*?<\/h2>/, "")
        .replace('data-action="saveSettings"', 'data-action="closeModal"')
        .replace("保存偏好", "完成");
    } else if (s.modal === "examLeave") {
      title = "暂时离开考试？";
      content = `<div class="stack"><p>当前答案保留在此页面；刷新页面会丢失。计时仅为示意。</p><div class="button-row"><button class="secondary" type="button" data-action="closeModal">继续作答</button><button class="primary" type="button" data-action="examLeave">暂时离开</button></div></div>`;
    } else if (s.modal === "credential") {
      title = "个人凭据管理";
      content = `<div class="stack"><p>尚未配置凭据。</p><div class="callout warn">${I("shield")}<span>本原型不收集 API Key；停用 Key 不会自动删除已有解释与音频。</span></div></div>`;
    } else if (s.modal === "quality") {
      const m =
        s.materials.find((x) => x.id === s.chosenMaterial) || s.materials[0];
      title = "解析与来源状态";
      content = `<div class="stack"><p><strong>${e(m.title)}</strong> · ${e(m.status)}</p><div class="callout">${I("shield")}<span>${m.type === "exam" ? "试卷的题目、分值、答案依据与听力候选仍需校对；原文可用不等于可以开考。" : m.type === "textbook" ? "可靠单元可学习，未分类内容与缺少答案的题目分别提示。" : "可靠正文可阅读；语言标注与 AI 分析独立呈现状态。"}</span></div></div>`;
    } else if (s.modal === "textbookItem") {
      const unit =
        data.textbook.units.find((x) => x.id === s.textbookUnit) ||
        data.textbook.units[0];
      title = unit.items[s.textbookItemIndex || 0] || "单元内容";
      const samples = {
        unit1: [
          ["よろしくお願いします。", "请多关照。"],
          ["学生 · 先生 · 会社員", "学生 · 老师 · 公司职员"],
          ["わたしは学生です。", "「は」提示话题，「です」表达判断。"],
        ],
        unit2: [
          ["駅まで一緒に行きましょう。", "我们一起去车站吧。"],
          ["駅 · 右 · 左", "车站 · 右 · 左"],
          ["駅へ行きます。", "「へ」表示移动方向。"],
        ],
        unit3: [
          ["コーヒーをください。", "请给我一杯咖啡。"],
          ["水をください。", "请给我水。"],
          ["ケーキをください。", "「ください」表达礼貌请求。"],
        ],
      };
      const sample = (samples[unit.id] || samples.unit1)[
        s.textbookItemIndex || 0
      ];
      const vocabulary = {
        unit1: [
          ["学生", "学生"],
          ["先生", "老师"],
          ["会社員", "公司职员"],
        ],
        unit2: [
          ["駅", "车站"],
          ["右", "右"],
          ["左", "左"],
        ],
        unit3: [
          ["注文", "点单"],
          ["水", "水"],
          ["コーヒー", "咖啡"],
        ],
      };
      content =
        s.textbookItemIndex === 1
          ? `<div class="stack">${vocabulary[unit.id].map(([word, meaning]) => `<div class="textbook-word"><span><strong lang="ja">${e(word)}</strong><small>${e(meaning)}</small></span>${window.HarukaLearningCards.pronounce(word)}</div>`).join("")}</div>`
          : `<div class="stack"><p class="step-caption">${e(unit.title)}</p><p lang="ja" class="sample-sentence">${e(sample[0])}</p><p>${e(sample[1])}</p></div>`;
    } else if (s.modal === "examScript") {
      title = "校对听力候选";
      content = `<div class="stack"><p>题组：听力 · 第 03 题</p><div class="soft-panel"><strong>文字稿候选</strong><p lang="ja" style="margin-top:8px">明日は駅の南口で会いましょう。</p></div><p class="small muted">来源：试卷正文 · 听力题组 1。</p><label class="check-row"><input id="exam-script-confirm" type="checkbox"><span>我已核对脚本与题组、小题的对应关系</span></label><button class="primary" type="button" data-action="confirmScript">确认示例匹配</button></div>`;
    } else if (s.modal === "examIntro") {
      title = "考前说明";
      content = `<div class="stack"><div class="stat"><strong>60 分钟</strong><span>示例整卷时间</span></div><p>开始后可以保存草稿、标记题目和切换题号。交卷会锁定答案；评分与解析只在交卷后显示。</p><div class="callout warn">${I("warning")}<span>本次仅演示 3 道题；计时与保存均为模拟。</span></div><button class="primary" type="button" data-action="examStart">开始模拟考试</button></div>`;
    } else if (s.modal === "examSubmit") {
      title = "确认交卷？";
      content = `<div class="stack"><p>已答 ${Object.keys(s.examAnswers).length} / ${data.exam.questions.length} 个示例题。交卷后答案锁定，再查看复盘。</p><div class="button-row"><button class="secondary" type="button" data-action="closeModal">继续作答</button><button class="danger-btn" type="button" data-action="examSubmitConfirm">确认交卷</button></div></div>`;
    } else if (s.modal === "newNotebook") {
      title = "新建词本";
      content = `<form class="form-grid" data-form="newNotebook"><label class="field">名称<input name="name" maxlength="40" required placeholder="例如：故事里的风景"></label><label class="field">学习语言<select name="language"><option>日语</option><option>英语</option></select></label><label class="field">简介<textarea name="description" placeholder="想把哪些词收在这里？"></textarea></label><button type="submit" class="primary">创建词本</button></form>`;
    } else if (s.modal === "newWord") {
      title = "添加词条";
      content = `<form class="form-grid" data-form="newWord"><label class="field">词形<input name="word" required></label><label class="field">释义<input name="meaning" required></label><label class="field">个人例句（可选）<textarea name="sentence"></textarea></label><button type="submit" class="primary">添加到当前词本</button></form>`;
    } else if (s.modal === "bookActions") {
      title = "整理词本";
      content = `<div class="stack"><button type="button" class="secondary" data-action="renameBook">${I("edit")} 重命名示例词本</button><button type="button" class="danger-btn" data-action="deleteBook">${I("trash")} 删除示例词本</button><p class="note">删本只移除归类，不删除词条或学习历史。</p></div>`;
    } else if (s.modal === "moveWord") {
      title = "整理词条归属";
      const w = s.words.find((x) => x.id === s.selectedWord);
      content = `<div class="stack">${s.notebooks.map((book) => `<label class="check-row"><input type="checkbox" data-word-book="${book.id}" ${w?.book === book.id || w?.books?.includes(book.id) ? "checked" : ""}><span>${e(book.title)}</span></label>`).join("")}<button type="button" class="primary" data-action="saveWordBooks">保存归属</button></div>`;
    } else if (s.modal === "editWord") {
      title = "编辑词条与笔记";
      const w = s.words.find((x) => x.id === s.selectedWord) || s.words[0];
      content = `<form class="form-grid" data-form="wordEdit"><label class="field">词形<input name="word" required value="${e(w.word)}"></label><label class="field">释义<input name="meaning" required value="${e(w.meaning)}"></label><label class="field">个人笔记<textarea name="note">${e(w.note || "")}</textarea></label><button type="submit" class="primary">保存词条</button></form>`;
    } else if (s.modal === "clearCache") {
      title = "清理本机副本？";
      content = `<div class="stack"><p>只清理演示账号的本机状态。正式服务已保存的解释和音频不受影响。</p><div class="button-row"><button class="secondary" type="button" data-action="closeModal">返回</button><button class="danger-btn" type="button" data-action="clearCacheConfirm">确认清理</button></div></div>`;
    } else if (s.modal === "password") {
      title = "修改密码流程";
      content = `<div class="stack"><p>修改密码后，所有设备需要重新登录。</p><div class="callout warn">${I("shield")}<span>原型不接收密码，未执行密码修改。</span></div></div>`;
    } else if (s.modal === "adminItem") {
      title = "运维摘要";
      content = `<div class="stack"><strong>${e(s.adminItem || "示例对象")}</strong><p>当前状态：正常 · 示例运维摘要。</p><div class="callout">${I("shield")}<span>私有材料、个人 Key 与学习内容不在此处显示。</span></div></div>`;
    }
    return `<div class="modal-backdrop" data-action="closeModal"><section class="dialog ${s.modal === "tasks" ? "task-drawer" : s.modal === "materialActions" ? "material-menu-dialog" : ""}" role="dialog" aria-modal="true" tabindex="-1" aria-label="${e(title)}" data-stop="true"><div class="dialog-head"><h2>${e(title)}</h2><button type="button" class="icon-btn" data-action="closeModal" aria-label="关闭">${I("close")}</button></div>${content}</section></div>`;
  }
  const novelLearning = window.HarukaNovelLearning({
    docked: true,
    clearReader: () => extras.clearReaderSelection(),
    s,
    root,
    render,
    open: (name) => openModal(name),
    close: () => closeModal(),
    query: (value, prepared) => extras.querySelection(value, prepared),
  });
  const motion = window.HarukaMotion({ s, root });
  const selection = window.HarukaTextSelection({
    motion,
    novel: novelLearning,
    s,
    root,
    onQuery: (value) => extras.querySelection(value),
  });
  const extras = window.HarukaCollections({
    s,
    root,
    mobile: false,
    novel: novelLearning,
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
    import: importPage,
    material,
    novel,
    textbook,
    textbookPractice,
    examPrep,
    examRun,
    examResult,
    notebooks,
    notebook,
    word,
    csv,
    exercise,
    exerciseBuilder,
    practice,
    mistakes,
    mistake,
    report,
    notifications,
    jobs,
    settings,
    profile: settingPage,
    languages: settingPage,
    appearance: settingPage,
    readingPrefs: settingPage,
    model: settingPage,
    speech: settingPage,
    usage: settingPage,
    cache: settingPage,
    security: settingPage,
    connection: settingPage,
    states: settingPage,
    login: auth,
    register: auth,
    registrationStatus,
    recovery: auth,
    onboarding,
    adminLogin: auth,
    adminOverview,
    adminUsers,
    adminRoles,
    adminMenus,
    adminPolicy,
    adminJobs,
    adminAudit,
    adminUsage,
    adminSecurity,
  };
  function render() {
    novelLearning.refresh();
    motion.beforeRender();
    const oldPanel = root.querySelector("[data-reader-panel-body]");
    const panelScroll = oldPanel?.scrollTop || 0;
    const oldPanelMessage = oldPanel?.dataset.message;
    const oldDialog = root.querySelector(".dialog");
    const dialogScroll = oldDialog?.scrollTop || 0;
    const focused = focusSelector(document.activeElement);
    const samePage = renderedRoute === s.route;
    const oldModal = oldDialog?.getAttribute("aria-label");
    const drafts = samePage
      ? [...root.querySelectorAll("input[name],textarea[name],select[name]")]
          .filter((t) => !t.dataset.practiceAll && !t.closest("[data-x-form]"))
          .map((t) => ({
            selector: focusSelector(t),
            value: t.value,
            checked: t.checked,
            start: t.selectionStart,
            end: t.selectionEnd,
            modal: !!t.closest(".dialog"),
          }))
      : [];
    if (!views[s.route]) s.route = "library";
    if (s.route === "jobs") {
      s.route = "library";
      s.modal = "tasks";
    }
    if (s.route === "notebook") s.route = "notebooks";
    if (s.route === "word" || s.route === "wordEdit") {
      s.route = "notebooks";
      s.modal = "entryDetail";
    }

    const materialForRoute = {
      novel: "summer",
      textbook: "daily",
      textbookPractice: "daily",
      examPrep: "n2",
      examRun: "n2",
      examResult: "n2",
    };
    if (materialForRoute[s.route]) s.chosenMaterial = materialForRoute[s.route];
    if (
      s.route === "notebook" &&
      !s.notebooks.some((book) => book.id === s.selectedBook)
    ) {
      s.route = "notebooks";
    }
    if (
      s.route === "word" &&
      !s.words.some((word) => word.id === s.selectedWord)
    ) {
      s.route = "notebooks";
    }
    if (s.route === "registrationStatus" && !s.registrationAccepted) {
      s.route = "register";
      history.replaceState(null, "", "#register");
    }
    if (s.route === "onboarding" && !s.signedIn) {
      s.route = "login";
      history.replaceState(null, "", "#login");
    }
    if (adminRoutes.includes(s.route) && !s.adminSignedIn) {
      s.route = "adminLogin";
      history.replaceState(null, "", "#adminLogin");
    }
    if (
      !s.signedIn &&
      !adminRoutes.includes(s.route) &&
      ![
        "login",
        "register",
        "registrationStatus",
        "recovery",
        "onboarding",
        "adminLogin",
      ].includes(s.route)
    ) {
      s.route = "login";
      history.replaceState(null, "", "#login");
    }
    if (s.route === "examRun" && s.examFinished) {
      s.route = "examResult";
      history.replaceState(null, "", "#examResult");
    }
    if (s.route === "examRun" && !s.examRunning && !s.examFinished) {
      s.route = "examPrep";
      history.replaceState(null, "", "#examPrep");
    }
    if (s.route === "examResult" && !s.examFinished) {
      s.route = "examPrep";
      history.replaceState(null, "", "#examPrep");
    }
    extras.guardMaterialRoute();
    s.adminArea = adminRoutes.includes(s.route);
    if (!s.signedIn || s.adminArea) extras.resetQueryImages();
    applyTheme();
    document.body.style.overflow = s.modal ? "hidden" : "";
    const authScreen = [
      "login",
      "register",
      "registrationStatus",
      "recovery",
      "onboarding",
      "adminLogin",
    ].includes(s.route);
    root.innerHTML = authScreen
      ? `${views[s.route](s.route)}`
      : `<a class="skip-link" href="#main-content">跳转到内容</a><div class="workspace" ${s.modal ? "inert" : ""}>${sidebar()}<div class="app-main">${topbar()}${!s.adminArea ? `<button class="task-rail" type="button" data-x="tasks" aria-label="展开任务进度">${I("clock")}<span>任务进度</span></button>` : ""}<main class="desktop-screen" id="main-content" tabindex="-1" data-page="${s.route}">${views[s.route](s.route)}</main></div></div>${modal()}`;
    if (s.toast)
      root.insertAdjacentHTML(
        "beforeend",
        `<div class="toast" role="status">${e(s.toast)}</div>`,
      );
    const dialog = root.querySelector(".dialog");
    if (samePage)
      drafts.forEach((d) => {
        if (
          d.modal &&
          (!dialog || dialog.getAttribute("aria-label") !== oldModal)
        )
          return;
        const t = root.querySelector(d.selector);
        if (t) {
          t.value = d.value;
          t.checked = d.checked;
          if (
            d.start !== null &&
            ["text", "search", "password", "url", "tel"].includes(t.type)
          )
            t.setSelectionRange(d.start, d.end);
        }
      });
    if (dialog) {
      dialog.scrollTop = dialogScroll;
      ((oldDialog && focused && dialog.querySelector(focused)) || dialog).focus(
        { preventScroll: true },
      );
    } else if (oldDialog && modalReturnFocus) {
      root.querySelector(modalReturnFocus)?.focus({ preventScroll: true });
      modalReturnFocus = "";
    } else if (samePage && focused)
      root.querySelector(focused)?.focus({ preventScroll: true });
    const panel = root.querySelector("[data-reader-panel-body]");
    if (panel) {
      if (panel.dataset.message === oldPanelMessage)
        panel.scrollTop = panelScroll;
      if (!oldPanel)
        panel.closest("[data-reader-panel]").classList.add("is-entering");
    }
    extras.restoreListFocus();
    selection.refresh();
    novelLearning.afterRender();
    motion.afterRender();
    renderedRoute = s.route;
    history.replaceState(navigationState(), "", pageHash());
    root.querySelectorAll(".table-wrap").forEach((table) => {
      table.tabIndex = 0;
      table.setAttribute("role", "region");
      table.setAttribute("aria-label", `${names[s.route] || "数据"}表格`);
    });
  }
  function applyTheme() {
    document.body.dataset.theme =
      s.theme === "system"
        ? matchMedia("(prefers-color-scheme: dark)").matches
          ? "dark"
          : "light"
        : s.theme;
    document.body.dataset.contrast = s.highContrast ? "on" : "off";
    document.body.dataset.reduceMotion = s.reduceMotion ? "on" : "off";
  }
  function hashRoute() {
    if (location.hash === "#main-content") {
      root.querySelector("#main-content")?.focus();
      return;
    }
    const [requestedRoute, query = ""] = location.hash.slice(1).split("?");
    const route = requestedRoute === "agent" ? "exercise" : requestedRoute;
    if (!views[route]) return;
    if (s.route === "examRun" && s.examRunning && route !== "examRun") {
      const destinationMaterial = history.state?.context?.chosenMaterial;
      history.pushState(navigationState(), "", "#examRun");
      pendingRoute = route;
      pendingOptions = { materialId: destinationMaterial };
      openModal("examLeave");
      return;
    }
    const step = Number(new URLSearchParams(query).get("step") || 1) - 1;
    if (history.state?.harukaDesktop === route) {
      navigationKeys.forEach((key) => {
        if (Object.hasOwn(history.state.context || {}, key))
          s[key] = history.state.context[key];
      });
    }
    s.route = route;
    s.modal = "";
    if (route === "import")
      s.importStep = s.importType
        ? Math.max(0, Math.min(s.importFile ? 2 : 1, step))
        : 0;
    if (route === "exerciseBuilder")
      builderStep = Math.max(0, Math.min(1, step));
    render();
    window.scrollTo(0, 0);
    root.querySelector("#main-content")?.focus({ preventScroll: true });
  }
  window.addEventListener("hashchange", hashRoute);
  matchMedia("(prefers-color-scheme: dark)").addEventListener(
    "change",
    applyTheme,
  );
  window.addEventListener("keydown", (event) => {
    const dialog = root.querySelector(".dialog");
    if (dialog) {
      if (event.key === "Escape") {
        event.preventDefault();
        closeModal();
        return;
      }
      if (event.key === "Tab") {
        const elements = [
          ...dialog.querySelectorAll(
            'button:not(:disabled),a[href],input:not(:disabled),select:not(:disabled),textarea:not(:disabled),[tabindex="0"]',
          ),
        ].filter((x) => x.getClientRects().length);
        const first = elements[0],
          last = elements[elements.length - 1];
        if (
          event.shiftKey &&
          (document.activeElement === first ||
            document.activeElement === dialog)
        ) {
          event.preventDefault();
          last?.focus();
        } else if (
          !event.shiftKey &&
          (document.activeElement === last || document.activeElement === dialog)
        ) {
          event.preventDefault();
          first?.focus();
        }
      }
      return;
    }
    if (event.key === "Escape" && novelLearning.panelActive()) {
      event.preventDefault();
      closeReaderPanel();
      return;
    }
    if (
      event.key === "/" &&
      !event.ctrlKey &&
      !event.metaKey &&
      !event.altKey &&
      !event.target.closest("input,select,textarea,[contenteditable]")
    ) {
      const search = root.querySelector('input[type="search"]');
      if (search) {
        event.preventDefault();
        search.focus();
      }
    }
  });
  root.addEventListener("click", (event) => {
    const target = event.target.closest(
      "[data-action],[data-go],[data-modal],[data-filter],[data-material],[data-import-type],[data-unit],[data-book],[data-word],[data-mistake],[data-notification],[data-practice-answer],[data-textbook-answer],[data-exam-question],[data-exam-answer],[data-usage-range],[data-admin-item]",
    );
    if (!target || target.disabled) return;
    if (
      event.target.closest("[data-stop]") &&
      target.classList.contains("modal-backdrop")
    )
      return;
    if (target.dataset.modal) {
      if (target.dataset.index !== undefined)
        s.textbookItemIndex = Number(target.dataset.index);
      openModal(target.dataset.modal);
      return;
    }
    if (target.dataset.go) {
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
      go("material");
      return;
    }
    if (target.dataset.importType) {
      s.importType = target.dataset.importType;
      render();
      return;
    }

    if (target.dataset.unit) {
      s.textbookUnit = target.dataset.unit;
      s.textbookAnswer = -1;
      s.textbookSubmitted = false;
      render();
      return;
    }
    if (target.dataset.book) {
      s.selectedBook = target.dataset.book;
      go("notebook");
      return;
    }
    if (target.dataset.word) {
      s.selectedWord = target.dataset.word;
      go("word");
      return;
    }
    if (target.dataset.mistake) {
      s.selectedMistake = target.dataset.mistake;
      go("mistake");
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
    if (target.dataset.adminItem) {
      s.adminItem = target.dataset.adminItem;
      openModal("adminItem");
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
      render();
      return;
    }
    if (target.dataset.examAnswer !== undefined) {
      if (s.examFinished || !s.examRunning) return;
      s.examAnswers[data.exam.questions[s.examQuestion].id] = Number(
        target.dataset.examAnswer,
      );
      s.examDraft = "未保存的演示选择";
      render();
      return;
    }
    if (target.dataset.usageRange) {
      s.usageRange = target.dataset.usageRange;
      render();
      return;
    }
    const action = target.dataset.action;
    if (action === "closeModal") {
      closeModal();
      return;
    }
    if (action === "builderNext") {
      if (!practiceCandidateCount()) return;
      nextStep("builder", 1);
      return;
    }
    if (action === "builderBack") {
      nextStep("builder", 0);
      return;
    }
    if (action === "examLeave") {
      go(pendingRoute, { ...pendingOptions, force: true });
      pendingOptions = {};
      pendingRoute = "";
      return;
    }
    if (action === "clearSearch") {
      s.search = "";
      s.filter = "all";
      render();
      return;
    }
    if (action === "importBack") {
      nextStep("import", Math.max(0, s.importStep - 1));
      return;
    }
    if (action === "importNext") {
      if (s.importStep === 0 && !s.importType)
        return toast("请先选择小说、课本或试卷。");
      if (s.importStep === 1 && !s.importFile)
        return toast("请先选择一个示例文件。");
      nextStep("import", Math.min(2, s.importStep + 1));
      return;
    }
    if (action === "importConfirm") {
      s.importComplete = true;
      s.notifications.unshift({
        id: `local-${Date.now()}`,
        title: `${s.importFile} · 示例任务已受理`,
        detail: "仅本地演示，文件未读取或上传。",
        time: "刚刚",
        route: "jobs",
        unread: true,
      });
      s.importStep = 0;
      go("jobs");
      toast("本地演示任务已创建；文件没有上传。");
      return;
    }

    if (action === "bookmark") return toast("示例书签已加入本地阅读状态。");
    if (action === "textbookSubmit") {
      s.textbookSubmitted = true;
      render();
      return;
    }
    if (action === "textbookReset") {
      s.textbookSubmitted = false;
      s.textbookAnswer = -1;
      render();
      return;
    }
    if (action === "confirmScript") {
      if (!root.querySelector("#exam-script-confirm")?.checked)
        return toast("请先核对并勾选确认。");
      s.examScriptMatched = true;
      s.modal = "";
      toast("候选匹配已确认（本地演示）。");
      return;
    }
    if (action === "examTts") {
      s.examAudioReady = true;
      toast("私有 TTS 状态已就绪（模拟），没有生成音频。");
      return;
    }
    if (action === "examFreeze") {
      if (s.examFinished) return go("examResult");
      s.examReady = true;
      openModal("examIntro");
      return;
    }
    if (action === "examStart") {
      if (s.examFinished) return go("examResult");
      s.modal = "";
      s.examRunning = true;
      go("examRun");
      return;
    }
    if (action === "examPlay")
      return toast("听力按钮仅演示界面；没有播放或消耗次数。");
    if (action === "examMark") {
      const id = data.exam.questions[s.examQuestion].id;
      s.examMarked = s.examMarked.includes(id)
        ? s.examMarked.filter((x) => x !== id)
        : [...s.examMarked, id];
      render();
      return;
    }
    if (action === "examSave") {
      s.examDraft = "本地演示草稿已保存";
      toast("演示草稿保留在当前页面内存。");
      return;
    }
    if (action === "examPrev" || action === "examNext") {
      s.examQuestion += action === "examPrev" ? -1 : 1;
      render();
      return;
    }
    if (action === "examSubmitConfirm") {
      if (s.examFinished || !s.examRunning) return;
      s.examFinished = true;
      s.examRunning = false;
      s.modal = "";
      go("examResult");
      return;
    }
    if (action === "useNotebook") {
      s.practiceAllowRepeat = false;
      s.practiceSources = [...new Set([...s.practiceSources, "notebook"])];
      s.practiceAllWords = false;
      s.practiceBookIds = [s.selectedBook];
      s.activeLanguage =
        s.notebooks.find((b) => b.id === s.selectedBook)?.language ||
        s.activeLanguage;

      go("exerciseBuilder");
      return;
    }

    if (action === "generateDemo") {
      if (!exerciseFlow.canGenerate()) return;
      s.practiceAnswer = -1;
      s.practiceSubmitted = false;
      s.practiceGenerated = true;
      s.modal = "";
      go("practice");
      return;
    }
    if (action === "practiceSubmit") {
      s.practiceSubmitted = true;
      render();
      return;
    }
    if (action === "practiceReset") {
      s.practiceSubmitted = false;
      s.practiceAnswer = -1;
      render();
      return;
    }
    if (action === "favoriteMistake") {
      const m = s.mistakes.find((x) => x.id === s.selectedMistake);
      if (m) m.favorite = !m.favorite;
      render();
      return;
    }
    if (action === "readAll") {
      s.notifications.forEach((n) => {
        n.unread = false;
      });
      render();
      return;
    }
    if (["saveLanguages", "saveReading", "saveSpeech"].includes(action))
      return toast("演示偏好已保存在当前页面内存。");
    if (action === "modelTest") {
      s.modelStatus = "文本能力模拟测试已完成";
      toast("模拟测试完成，没有调用供应商。");
      return;
    }
    if (action === "modelCapability") {
      s.modelStatus = `${target.dataset.capability}能力模拟检查已完成`;
      toast(
        `${target.dataset.capability}能力只完成本地界面演示，没有调用供应商。`,
      );
      return;
    }
    if (action === "avatarInfo") return toast("原型不接收图片。");
    if (action === "saveSettings")
      return toast("演示偏好已保存在当前页面内存。");
    if (action === "speechPreview")
      return toast("试听状态已演示，没有合成或播放音频。");
    if (action === "csvPreview") {
      s.csvStep = 1;
      render();
      return;
    }
    if (action === "csvConfirm") {
      s.csvStep = 0;
      toast("示例预览已确认；未读取或导入真实 CSV。");
      return;
    }
    if (action === "csvExport") {
      const content =
        "\uFEFFword,reading,meaning,notebook\r\nそっと,sotto,轻轻地,日常的细节\r\n微笑む,ほほえむ,微笑,阅读时遇见\r\n";
      const link = document.createElement("a");
      link.href = URL.createObjectURL(
        new Blob([content], { type: "text/csv;charset=utf-8" }),
      );
      link.download = "haruka-demo-words.csv";
      link.click();
      setTimeout(() => URL.revokeObjectURL(link.href), 1000);
      toast("已生成虚构样本 CSV。");
      return;
    }
    if (action === "clearCacheConfirm") {
      s.cacheCleared = true;
      s.modal = "";
      toast("本地演示缓存状态已清理。");
      return;
    }
    if (action === "logout") {
      s.signedIn = false;
      go("login");
      return;
    }
    if (action === "adminLogout") {
      s.adminSignedIn = false;
      go("adminLogin");
      return;
    }
    if (action === "switchClient") {
      s.adminSignedIn = false;
      s.signedIn = false;
      go("login");
      return;
    }
    if (action === "finishOnboarding") {
      s.signedIn = true;
      go("library");
      return;
    }
    if (action === "renameBook") {
      const book = s.notebooks.find((x) => x.id === s.selectedBook);
      if (book) book.title += " · 整理中";
      s.modal = "";
      toast("示例词本已重命名。");
      return;
    }
    if (action === "deleteBook") {
      s.notebooks = s.notebooks.filter((x) => x.id !== s.selectedBook);
      s.modal = "";
      go("notebooks");
      toast("词本已删除；词条和历史仍保留。");
      return;
    }
    if (action === "saveWordBooks") {
      const word = s.words.find((x) => x.id === s.selectedWord);
      if (word) {
        const selected = [
          ...root.querySelectorAll("[data-word-book]:checked"),
        ].map((x) => x.dataset.wordBook);
        word.book = selected[0] || "";
        word.books = selected.slice(1);
      }
      s.modal = "";
      toast("示例归属已更新。");
      return;
    }
    if (action === "adminPreview")
      return toast("只展示演示状态；没有发布管理策略。");
  });
  root.addEventListener("change", (event) => {
    const t = event.target;
    if (t.dataset.file === "material") {
      s.importFile = t.files?.[0]?.name || "";
      render();
      return;
    }
    if (t.dataset.file === "csv") {
      s.csvFile = t.files?.[0]?.name || "";
      s.csvStep = 0;
      render();
      return;
    }
    if (t.dataset.source) {
      s.practiceAllowRepeat = false;
      s.practiceSources = t.checked
        ? [...s.practiceSources, t.dataset.source]
        : s.practiceSources.filter((x) => x !== t.dataset.source);

      render();
      return;
    }
    if (t.dataset.practiceAll !== undefined) {
      s.practiceAllowRepeat = false;
      s.practiceAllWords = t.dataset.practiceAll === "true";

      render();
      return;
    }
    if (t.dataset.practiceBook) {
      s.practiceAllowRepeat = false;
      s.practiceBookIds = t.checked
        ? [...s.practiceBookIds, t.dataset.practiceBook]
        : s.practiceBookIds.filter((id) => id !== t.dataset.practiceBook);

      render();
      return;
    }
    if (t.dataset.practiceCollection) {
      s.practiceAllowRepeat = false;
      s.practiceCollectionIds = t.checked
        ? [...s.practiceCollectionIds, t.dataset.practiceCollection]
        : s.practiceCollectionIds.filter(
            (id) => id !== t.dataset.practiceCollection,
          );
      render();
      return;
    }
    if (t.dataset.practiceRepeat !== undefined) {
      s.practiceAllowRepeat = t.checked;
      render();
      return;
    }
    if (t.dataset.practiceUnit !== undefined) {
      s.practiceAllowRepeat = false;
      s.practiceTextbookUnit = t.value;

      render();
      return;
    }
    if (t.dataset.practiceMistakes !== undefined) {
      s.practiceAllowRepeat = false;
      s.practiceMistakeScope = t.value;

      render();
      return;
    }
    if (t.dataset.practiceType !== undefined) {
      s.practiceAllowRepeat = false;
      s.practiceQuestionType = t.value;

      render();
      return;
    }
    if (t.dataset.practiceCount !== undefined) {
      s.practiceAllowRepeat = false;
      s.practiceCount = t.value;

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
        s.activeLanguage = s.targetLanguages[0] || "";
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
      if (s.route === "exerciseBuilder") {
        if (t.dataset.setting === "activeLanguage") {
          exerciseFlow.syncLanguage();
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
    }
  });
  root.addEventListener("input", (event) => {
    const t = event.target;
    if (t.name === "password" || t.name === "confirmPassword")
      root.querySelector('[name="confirmPassword"]')?.setCustomValidity("");
    if (t.dataset.input === "search" || t.dataset.input === "adminSearch") {
      const key = t.dataset.input;
      const pos = t.selectionStart;
      s[key] = t.value;
      render();
      const next = root.querySelector(`[data-input="${key}"]`);
      next?.focus();
      next?.setSelectionRange(pos, pos);
    }
  });
  root.addEventListener("submit", (event) => {
    const form = event.target.closest("[data-form]");
    if (!form) return;
    event.preventDefault();
    const values = Object.fromEntries(new FormData(form));
    if (form.dataset.form === "profile") {
      s.profile = {
        displayName: String(values.displayName || "").trim() || "学习者",
        birthYear: values.birthYear || "",
        gender: values.gender || "未填写",
        timezone: values.timezone || "Asia/Tokyo",
      };
      toast("演示资料已保存在当前页面内存。");
      return;
    }
    if (form.dataset.form === "connection") {
      s.serviceAddress = String(values.address || "");
      try {
        const url = new URL(s.serviceAddress);
        if (
          url.protocol !== "https:" ||
          url.username ||
          url.password ||
          url.search ||
          url.hash
        )
          throw new Error("invalid");
        s.serviceAddress = url.origin + url.pathname.replace(/\/$/, "");
        s.serviceProbe = true;
        toast("已生成探测预览，没有实际联网。");
      } catch {
        toast("请输入无账号密码、查询参数或片段的 HTTPS 地址。");
      }
      return;
    }
    if (form.dataset.form === "newNotebook") {
      const name = String(values.name || "").trim();
      if (!name) return;
      const id = `book-${Date.now()}`;
      s.notebooks.push({
        id,
        title: name,
        language: values.language,
        count: 0,
        tone: "blue",
        description: String(values.description || ""),
      });
      s.selectedBook = id;
      s.modal = "";
      go("notebook");
      return;
    }
    if (form.dataset.form === "newWord") {
      const word = String(values.word || "").trim();
      if (!word) return;
      const id = `word-${Date.now()}`;
      s.words.push({
        id,
        word,
        reading: "个人录入",
        meaning: String(values.meaning || "").trim(),
        source: "手动添加 · 本人词条",
        book: s.selectedBook,
        mastery: "尚无有效证据",
        sentence: String(values.sentence || "") || "暂无个人例句",
      });
      s.selectedWord = id;
      s.modal = "";
      go("word");
      return;
    }
    if (form.dataset.form === "wordEdit") {
      const w = s.words.find((x) => x.id === s.selectedWord);
      if (w) {
        w.word = String(values.word || "").trim();
        w.meaning = String(values.meaning || "").trim();
        w.note = String(values.note || "");
      }
      s.modal = "";
      go("word");
      toast("示例词条已更新。");
      return;
    }
    if (
      ["login", "register", "recovery", "adminLogin"].includes(
        form.dataset.form,
      )
    ) {
      if (form.dataset.form === "recovery")
        return toast("演示受理结果：若账号可用，将按正式配置的恢复方式处理。");
      if (form.dataset.form === "register") {
        if (String(values.password) !== String(values.confirmPassword)) {
          const input = form.querySelector('[name="confirmPassword"]');
          input.setCustomValidity("两次输入的密码不一致");
          input.reportValidity();
          return;
        }
        s.registrationAccepted = true;
        s.signedIn = false;
        go("registrationStatus");
        return;
      }
      if (form.dataset.form === "adminLogin") {
        s.adminSignedIn = true;
        go("adminOverview");
        return;
      }
      s.signedIn = true;
      if (s.registrationAccepted) {
        s.registrationAccepted = false;
        go("onboarding");
      } else go("library");
    }
  });
  const [requestedHash, initialQuery = ""] = location.hash.slice(1).split("?");
  const hash = requestedHash === "agent" ? "exercise" : requestedHash;
  if (views[hash]) s.route = hash;
  if (hash === "exerciseBuilder")
    builderStep =
      Number(new URLSearchParams(initialQuery).get("step")) === 2 ? 1 : 0;
  render();
})();
