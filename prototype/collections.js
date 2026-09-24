/* Shared, in-memory prototype interactions. No production API or model calls. */
window.HarukaCollections = ({ s, root, mobile, render, open, close, go }) => {
  const { escape: e, icon: I, data, typeLabel } = window.HarukaCore;
  const kinds = {
    word: "单词",
    phrase: "短语",
    grammar: "语法",
    sentence: "句子",
    excerpt: "摘录",
    answer: "回答卡片",
  };
  const id = () => crypto.randomUUID();
  const day = (value) =>
    value && Number.isFinite(new Date(value).getTime())
      ? new Intl.DateTimeFormat("sv-SE", {
          timeZone: s.profile.timezone || "Asia/Tokyo",
          year: "numeric",
          month: "2-digit",
          day: "2-digit",
        }).format(new Date(value))
      : "日期未知";
  const today = () => day(Date.now());
  const belongs = (item, book) =>
    item.book === book || item.books?.includes(book);
  const selected = () => s.notebooks.find((b) => b.id === s.selectedBook);
  const inBook = () =>
    s.words.filter(
      (w) => s.selectedBook === "all" || belongs(w, s.selectedBook),
    );
  s.selectedBook = "all";
  s.collectionKind = "all";
  s.collectionSearch = "";
  s.dailyDate = today();
  s.queryMessages = [];
  s.materials = data.materials.map((m) => ({ ...m }));
  s.words.forEach((w, index) =>
    Object.assign(w, {
      kind: "word",
      language: w.book === "englishwords" ? "英语" : "日语",
      createdAt: new Date(
        Date.now() - (index > 1 ? 86400000 : 0),
      ).toISOString(),
    }),
  );
  s.words.push(
    {
      id: "grammar-direction",
      kind: "grammar",
      word: "に / へ",
      meaning: "目的地与移动方向",
      sentence: "駅に行きます。／ 駅へ行きます。",
      detail:
        "「に」着重到达的地点；「へ」着重移动的方向。表示前往车站时两者常可互换，但其他用法并不相同。",
      source: "日语的日常表达 · Unit 02",
      book: "dailywords",
      language: "日语",
      createdAt: new Date().toISOString(),
    },
    {
      id: "sentence-wind",
      kind: "sentence",
      word: "夏の風がそっと頬に触れた。",
      meaning: "夏风轻轻拂过脸颊。",
      detail: "「そっと」修饰「触れた」，表达轻柔的触碰。",
      source: "夏の手紙 · 第 03 章",
      book: "readingwords",
      language: "日语",
      createdAt: new Date().toISOString(),
    },
  );
  s.materials.push({
    id: "rain",
    type: "novel",
    title: "雨上がり",
    subtitle: "小说 · 日语",
    status: "解析中",
    cover: "雨",
    tone: "blue",
    detail: "内置解析进度示例。",
    updated: "刚刚",
    demoJob: true,
    progress: 0,
    sequence: 0,
    ready: false,
  });
  let connection = "connecting";
  let socket;
  let retry;
  let stopped = false;
  const session = id();
  const status = (m) => (m.demoJob && !m.ready ? "解析中" : m.status);
  const progress = (m) =>
    `<div class="collection-progress" data-progress="${m.id}"><span data-progress-label>${e(m.ready ? m.status : connection === "connected" ? `解析中 · ${m.progress}%` : "解析中 · 等待进度连接")}</span><progress max="100" value="${m.progress}" aria-label="${e(m.title)}解析进度"></progress></div>`;
  function refreshProgress() {
    root.querySelectorAll("[data-progress]").forEach((el) => {
      const m = s.materials.find((x) => x.id === el.dataset.progress);
      if (!m) return;
      el.querySelector("[data-progress-label]").textContent = m.ready
        ? m.status
        : connection === "connected"
          ? `解析中 · ${m.progress}%`
          : "解析中 · 连接中断，等待重连";
      el.querySelector("progress").value = m.progress;
    });
    root.querySelectorAll("[data-job-open]").forEach((el) => {
      const m = s.materials.find((x) => x.id === el.dataset.jobOpen);
      el.disabled = !m?.ready;
    });
    root.querySelectorAll("[data-connection]").forEach((el) => {
      el.textContent =
        connection === "connected" ? "进度已连接" : "进度连接中断，正在重连";
    });
  }
  function subscribe() {
    if (socket?.readyState === WebSocket.OPEN)
      socket.send(
        JSON.stringify({
          session,
          jobs: s.materials
            .filter((m) => m.demoJob)
            .map((m) => ({ id: m.id, type: m.type })),
        }),
      );
  }
  function connect() {
    if (stopped || !["127.0.0.1", "localhost"].includes(location.hostname))
      return;
    socket = new WebSocket(`ws://${location.hostname}:8768`);
    socket.onopen = () => {
      connection = "connected";
      subscribe();
      refreshProgress();
    };
    socket.onmessage = (event) => {
      let message;
      try {
        message = JSON.parse(event.data);
      } catch {
        return;
      }
      const m = s.materials.find((x) => x.id === message.id && x.demoJob);
      if (
        !m ||
        !Number.isInteger(message.sequence) ||
        message.sequence <= m.sequence ||
        !Number.isFinite(message.progress)
      )
        return;
      m.sequence = message.sequence;
      m.progress = Math.max(m.progress, Math.min(100, message.progress));
      m.ready = message.status === "completed";
      if (m.ready && m.id !== "rain") m.status = "演示结束 · 无正文";
      else if (m.ready)
        m.status =
          m.type === "exam"
            ? "待校对"
            : m.type === "textbook"
              ? "可学习"
              : "可阅读";
      refreshProgress();
    };
    socket.onerror = () => socket.close();
    socket.onclose = () => {
      connection = "disconnected";
      refreshProgress();
      if (!stopped) retry = setTimeout(connect, 2500);
    };
  }
  window.addEventListener("pagehide", () => {
    stopped = true;
    clearTimeout(retry);
    socket?.close();
  });
  window.addEventListener("pageshow", (event) => {
    if (event.persisted) {
      stopped = false;
      connect();
    }
  });
  connect();

  function row(w) {
    return `<article class="collection-row"><div class="collection-copy"><span class="collection-kind">${e(kinds[w.kind] || "单词")}</span><strong>${e(w.word)}</strong>${w.reading ? `<small>${e(w.reading)}</small>` : ""}<p>${e(w.meaning)}</p></div><div class="collection-row-meta"><span>${e(w.kind === "word" ? w.mastery || "尚无有效证据" : w.source)}</span><button class="text-btn" type="button" data-x="entry" data-id="${w.id}" aria-label="查看 ${e(w.word)}">查看 ${I("chevron")}</button></div></article>`;
  }
  function notebooks() {
    const list = inBook().filter(
      (w) =>
        (s.collectionKind === "all" || w.kind === s.collectionKind) &&
        `${w.word} ${w.meaning}`
          .toLowerCase()
          .includes(s.collectionSearch.toLowerCase()),
    );
    return `<div class="collection-page"><div class="collection-heading"><h1>单词本</h1><button class="secondary" type="button" data-x="add">${I("plus")}添加</button></div><div class="collection-tools"><button class="book-switcher" type="button" data-x="switch">${I("layers")}<span>${e(selected()?.title || "全部收藏")}</span>${I("chevron")}</button><button class="daily-shortcut" type="button" data-go="dailyWords">${I("clock")}每日单词${I("arrow")}</button></div><form class="collection-search" data-x-form="search"><label>${I("search")}<input name="search" type="search" aria-label="搜索收藏" placeholder="搜索收藏内容" value="${e(s.collectionSearch)}"></label><button class="text-btn" type="submit">搜索</button></form><div class="collection-filters" aria-label="收藏类型">${[["all", "全部"], ...Object.entries(kinds)].map(([key, label]) => `<button type="button" data-x="kind" data-id="${key}" aria-pressed="${s.collectionKind === key}">${label}</button>`).join("")}</div><div class="collection-caption"><span>${list.length} 条收藏</span><div class="collection-list-actions"><button class="text-btn" type="button" data-x="practice">生成 AI 习题 ${I("spark")}</button><button class="text-btn" type="button" data-go="csv">单词 CSV ${I("download")}</button></div></div><div class="collection-list">${list.map(row).join("") || '<div class="empty"><strong>没有找到收藏</strong><p>换个词，或添加一条收藏。</p></div>'}</div></div>`;
  }
  function dailyWords() {
    const words = s.words.filter(
      (w) => w.kind === "word" && day(w.createdAt) === s.dailyDate,
    );
    return `<div class="collection-page"><div class="collection-heading"><h1>每日单词</h1></div><div class="daily-calendar"><div><span class="collection-kind">当日加入</span><strong>${words.length}<small> 个单词</small></strong></div><label class="field">日期<input type="date" data-x-date value="${e(s.dailyDate)}" max="${today()}"></label></div><p class="collection-caption">${e(s.profile.timezone)} · 全部单词本，重复归类只计一次</p><div class="collection-list">${words.map(row).join("") || '<div class="empty"><strong>这天没有加入单词</strong><p>选择其他日期查看。</p></div>'}</div></div>`;
  }
  function library() {
    const list = s.materials.filter(
      (m) =>
        (s.filter === "all" || m.type === s.filter) &&
        `${m.title} ${m.subtitle}`
          .toLowerCase()
          .includes(s.search.toLowerCase()),
    );
    return `<div class="collection-page material-library"><div class="collection-heading"><h1>材料库</h1>${mobile ? "" : `<button class="primary" type="button" data-go="import">${I("plus")}导入材料</button>`}</div><div class="collection-library-tools"><div class="collection-filters" aria-label="材料类型">${[["all", "全部"], ...Object.entries(typeLabel)].map(([key, label]) => `<button type="button" data-filter="${key}" aria-pressed="${s.filter === key}">${label}</button>`).join("")}</div>${mobile ? "" : `<label class="search">${I("search")}<input type="search" data-input="search" aria-label="搜索材料" placeholder="搜索标题或语言" value="${e(s.search)}"></label>`}</div><div class="collection-caption"><span>${list.length} 份材料</span>${mobile ? '<button class="text-btn" type="button" data-x="tasks">任务进度</button>' : "<span>最近更新</span>"}</div><div class="direct-material-list" id="material-list">${list.map((m) => `<article class="direct-material"><button class="direct-material-main" type="button" data-material="${m.id}"><span class="cover ${m.tone}" aria-hidden="true">${e(m.cover)}</span><span class="direct-material-copy"><strong>${e(m.title)}</strong><small>${e(m.subtitle)}</small>${m.demoJob ? progress(m) : `<span class="collection-kind">${e(status(m))}</span>`}</span>${I("chevron")}</button><button class="material-details-button" type="button" data-x="materialDetails" data-id="${m.id}" aria-label="更多：${e(m.title)}" aria-haspopup="dialog" title="材料详情">${I("more")}</button></article>`).join("") || '<div class="empty">没有找到材料</div>'}</div>${mobile ? `<div class="floating-action"><button class="primary" type="button" data-go="import">${I("plus")}导入材料</button></div>` : ""}</div>`;
  }
  function tasks() {
    return `<div class="task-content"><p class="collection-caption" data-connection>${connection === "connected" ? "进度已连接" : "等待进度连接"}</p>${s.materials
      .filter((m) => m.demoJob)
      .map(
        (m) =>
          `<article class="task-item"><span class="collection-kind">${e(typeLabel[m.type])} · 示例任务</span><h3>${e(m.title)}</h3>${progress(m)}<button class="secondary" type="button" data-x="openJob" data-id="${m.id}" data-job-open="${m.id}" ${m.ready ? "" : "disabled"}>打开材料 ${I("arrow")}</button></article>`,
      )
      .join(
        "",
      )}<p class="note">本地 WebSocket 演示，不上传文件或执行真实解析。</p></div>`;
  }
  function openMaterial(materialId) {
    const m = s.materials.find((x) => x.id === materialId);
    if (!m) return;
    if (m.demoJob && !m.ready) {
      s.chosenMaterial = m.id;
      return open("tasks");
    }
    go(
      m.demoJob
        ? {
            novel: "sampleReader",
            textbook: "sampleTextbook",
            exam: "sampleExamPrep",
          }[m.type]
        : m.type === "novel"
          ? "novel"
          : m.type === "textbook"
            ? "textbook"
            : "examPrep",
      { materialId: m.id },
    );
  }
  function sampleReader() {
    const m = s.materials.find((x) => x.id === s.chosenMaterial);
    if (!m?.demoJob || !m.ready) return '<div class="empty">材料尚未就绪</div>';
    if (m.type === "exam")
      return `<div class="sample-reader"><span class="collection-kind">试卷准备 · 导入演示</span><h1>${e(m.title)}</h1><p>文件未解析，暂无题目可校对。</p><div class="callout"><span>本地任务只演示进度，不能开始考试。</span></div><button class="primary" type="button" disabled>开始考试</button><button class="secondary" type="button" data-go="library">返回材料库</button></div>`;
    if (m.type === "textbook")
      return `<div class="sample-reader"><span class="collection-kind">课本学习 · 导入演示</span><h1>${e(m.title)}</h1><p>文件未解析，暂无可学习单元。</p><button class="secondary" type="button" data-go="library">返回材料库</button></div>`;
    return `<div class="sample-reader"><span class="collection-kind">内置示例正文</span><h1>${e(m.title)}</h1>${m.id === "rain" ? '<h2>雨停之后</h2><p lang="ja">雨が上がった。窓を開けると、庭の木々が光っていた。私は本を閉じて、外へ出た。</p><p>雨停了。推开窗，庭院里的树木闪着光。我合上书，走到屋外。</p>' : "<p>此文件没有被读取或解析。当前仅演示任务进度，实际正文需要正式解析服务。</p>"}<button class="secondary" type="button" data-go="library">返回材料库</button></div>`;
  }
  function answer(question) {
    if (/そっと/.test(question) && !/夏の風|翻译/.test(question))
      return {
        kind: "word",
        word: "そっと",
        reading: "sotto",
        meaning: "轻轻地；悄悄地",
        detail: "用于动作轻柔，或不希望打扰别人的场景。",
        sentence: "ドアをそっと閉めた。",
        language: "日语",
      };
    if (/に.*へ|へ.*に/.test(question))
      return {
        kind: "grammar",
        word: "に / へ",
        meaning: "目的地与移动方向",
        detail:
          "「に」强调到达的地点；「へ」强调移动的方向。表示移动的句子中常可互换。",
        sentence: "駅に行きます。／ 駅へ行きます。",
        language: "日语",
      };
    if (/夏の風がそっと頬に触れた/.test(question))
      return {
        kind: "sentence",
        word: "夏の風がそっと頬に触れた。",
        meaning: "夏风轻轻拂过脸颊。",
        detail: "「そっと」表达轻柔的动作。「頬」读作「ほお」，意思是脸颊。",
        language: "日语",
      };
    if (/天空|蓝色/.test(question))
      return {
        kind: "answer",
        word: "天空为什么是蓝色的？",
        meaning: "空气对短波长可见光的散射更强。",
        detail:
          "阳光进入大气后，蓝光比红光更容易被空气分子散射到各个方向。我们从地面看向天空，接收到的散射光便以蓝色为主。",
        language: "简体中文",
      };
    return {
      kind: "answer",
      word: question,
      meaning: "未生成回答",
      detail: "这是本地交互原型，不调用模型。可以体验回答卡片的收藏与归类。",
      language: "简体中文",
    };
  }
  function query() {
    return `<div class="query-page"><div class="collection-heading"><h1>查询</h1><span class="collection-kind">示例会话</span></div><div class="query-messages" aria-live="polite">${s.queryMessages.length ? s.queryMessages.map((message) => `<div class="query-question">${e(message.question)}</div><article class="answer-card"><div class="collection-caption"><span class="collection-kind">${e(kinds[message.card.kind])} · 示例</span><button class="text-btn" type="button" data-x="saveCard" data-id="${message.card.id}" ${s.words.some((w) => w.cardId === message.card.id) ? "disabled" : ""}>${I("bookmark")}${s.words.some((w) => w.cardId === message.card.id) ? "已收藏" : "收藏"}</button></div><h2>${e(message.card.word)}</h2><p>${e(message.card.meaning)}</p><p>${e(message.card.detail)}</p>${message.card.sentence ? `<blockquote>${e(message.card.sentence)}</blockquote>` : ""}</article>`).join("") : `<div class="query-welcome"><span class="query-symbol">${I("message")}</span><h2>有什么想了解的？</h2><div class="query-prompts">${["そっと 是什么意思？", "に 和 へ 有什么区别？", "翻译：夏の風がそっと頬に触れた。", "天空为什么是蓝色的？"].map((q) => `<button class="secondary" type="button" data-x="prompt" data-question="${e(q)}">${e(q)} ${I("arrow")}</button>`).join("")}</div></div>`}</div><form class="query-composer" data-x-form="query"><label class="sr-only" for="query-input">输入问题</label><textarea id="query-input" name="question" required maxlength="2000" rows="2" placeholder="输入问题…">${e(s.queryDraft || "")}</textarea><div><span class="note">本地示例 · 不调用模型</span><button class="primary" type="submit" aria-label="发送问题">发送 ${I("arrow")}</button></div></form></div>`;
  }
  function dialog() {
    let title;
    let content;
    const w = s.words.find((x) => x.id === s.selectedWord);
    if (s.modal === "switchBook") {
      title = "切换单词本";
      content = `<div class="book-picker"><button class="book-picker-row" type="button" data-x="chooseBook" data-id="all"><span>全部收藏<small>${s.words.length} 条</small></span>${s.selectedBook === "all" ? I("check") : ""}</button>${s.notebooks.map((b) => `<div class="book-picker-line"><button class="book-picker-row" type="button" data-x="chooseBook" data-id="${b.id}"><span>${e(b.title)}<small>${e(b.language)} · ${s.words.filter((w) => belongs(w, b.id)).length} 条</small></span>${s.selectedBook === b.id ? I("check") : ""}</button><button class="icon-btn" type="button" data-x="manageBook" data-id="${b.id}" aria-label="管理 ${e(b.title)}">${I("more")}</button></div>`).join("")}<button class="secondary full" type="button" data-x="newBook">${I("plus")}新建单词本</button></div>`;
    } else if (s.modal === "manageBook") {
      const b = s.notebooks.find((x) => x.id === s.managedBook);
      if (!b) return null;
      title = "管理单词本";
      content = `<form class="form-grid" data-x-form="rename"><label class="field">名称<input name="title" required maxlength="40" value="${e(b.title)}"></label><label class="field">简介<textarea name="description">${e(b.description || "")}</textarea></label><button class="primary" type="submit">保存</button></form><button class="danger-btn full" type="button" data-x="deleteBook">删除单词本</button><p class="note">仅移除归类，保留收藏与学习记录。</p><button class="text-btn" type="button" data-x="switch">返回单词本列表</button>`;
    } else if (s.modal === "deleteBookConfirm") {
      const b = s.notebooks.find((x) => x.id === s.managedBook);
      title = "删除单词本？";
      content = `<div class="stack"><p>${e(b?.title)} · ${s.words.filter((w) => belongs(w, s.managedBook)).length} 条收藏</p><p>删除后保留全部收藏，仅移除这个单词本的归类。</p><button class="danger-btn" type="button" data-x="confirmDeleteBook">确认删除</button><button class="secondary" type="button" data-x="manageBook" data-id="${e(s.managedBook)}">取消</button></div>`;
    } else if (s.modal === "createBook") {
      title = "新建单词本";
      content = `<form class="form-grid" data-x-form="book"><label class="field">名称<input name="title" required maxlength="40"></label><label class="field">语言<select name="language"><option>日语</option><option>英语</option><option>简体中文</option></select></label><button class="primary" type="submit">创建</button></form>`;
    } else if (s.modal === "entryDetail") {
      title = "收藏详情";
      content = w
        ? `<article class="entry-detail"><span class="collection-kind">${e(kinds[w.kind] || "单词")} · ${e(w.language || "日语")}</span><h2>${e(w.word)}</h2>${w.reading ? `<p class="muted">${e(w.reading)}</p>` : ""}<p>${e(w.meaning)}</p>${w.detail ? `<p>${e(w.detail)}</p>` : ""}${w.note ? `<p>笔记：${e(w.note)}</p>` : ""}${w.sentence ? `<blockquote>${e(w.sentence)}</blockquote>` : ""}<p class="note">${e(w.source)} · ${day(w.createdAt)} 加入</p>${w.kind === "word" ? `<span class="tag">${e(w.mastery || "尚无有效证据")}</span>` : ""}<div class="entry-books">${
            s.notebooks
              .filter((b) => belongs(w, b.id))
              .map((b) => `<span class="tag">${e(b.title)}</span>`)
              .join("") || '<span class="note">尚未归类</span>'
          }</div><button class="secondary" type="button" data-x="organizeEntry">${I("layers")}归入单词本</button><button class="secondary" type="button" data-x="editEntry">编辑与笔记</button>${w.source.startsWith("夏の手紙") ? `<button class="text-btn" type="button" data-go="novel">回到原文 ${I("arrow")}</button>` : w.source.startsWith("N2") ? `<button class="text-btn" type="button" data-go="examPrep">查看试卷 ${I("arrow")}</button>` : ""}</article>`
        : "<p>该收藏已不可用。</p>";
    } else if (s.modal === "editEntry") {
      title = "编辑收藏";
      content = `<form class="form-grid" data-x-form="editEntry">${w.cardId ? `<p class="note">回答保留收藏时的完整快照。</p>` : `<label class="field">内容<textarea name="word" required maxlength="2000">${e(w.word)}</textarea></label><label class="field">释义<textarea name="meaning" required maxlength="4000">${e(w.meaning)}</textarea></label>`}<label class="field">个人笔记<textarea name="note" maxlength="4000">${e(w.note || "")}</textarea></label><button class="primary" type="submit">保存</button></form>`;
    } else if (s.modal === "entryBooks" || s.modal === "saveCard") {
      title = s.modal === "saveCard" ? "收藏卡片" : "归入单词本";
      const card = s.queryMessages.find(
        (m) => m.card.id === s.savingCard,
      )?.card;
      const target = s.modal === "saveCard" ? card : w;
      const books = s.notebooks.filter((b) => b.language === target?.language);
      content = `<form class="form-grid" data-x-form="${s.modal === "saveCard" ? "saveCard" : "entryBooks"}">${books.map((b) => `<label class="check-row choice-row"><input type="checkbox" name="books" value="${b.id}" ${s.modal === "entryBooks" && belongs(w, b.id) ? "checked" : ""}><span>${e(b.title)}</span></label>`).join("") || "<p>暂无同语言单词本，可先收藏到全部收藏。</p>"}<button class="primary" type="submit">${s.modal === "saveCard" ? "确认收藏" : "保存归类"}</button></form>`;
    } else if (s.modal === "addEntry") {
      title = "添加收藏";
      content = `<form class="form-grid" data-x-form="entry"><label class="field">类型<select name="kind">${Object.entries(
        kinds,
      )
        .filter(([k]) => k !== "answer")
        .map(([k, v]) => `<option value="${k}">${v}</option>`)
        .join(
          "",
        )}</select></label><label class="field">语言<select name="language">${["日语", "英语", "简体中文"].map((l) => `<option ${selected()?.language === l ? "selected" : ""}>${l}</option>`).join("")}</select></label><label class="field">内容<textarea name="word" required maxlength="2000"></textarea></label><label class="field">释义或笔记<textarea name="meaning" required maxlength="4000"></textarea></label><button class="primary" type="submit">添加</button></form>`;
    } else if (s.modal === "materialDetails") {
      const m = s.materials.find((x) => x.id === s.chosenMaterial);
      title = "材料详情";
      content = `<div class="entry-detail"><span class="collection-kind">${e(typeLabel[m.type])}</span><h2>${e(m.title)}</h2><p>${e(m.subtitle)}</p><p>${e(m.detail)}</p>${m.demoJob ? progress(m) : `<span class="tag">${e(status(m))}</span>`}<p class="note">更新：${e(m.updated)}</p><button class="primary" type="button" data-x="openJob" data-id="${m.id}">打开材料 ${I("arrow")}</button></div>`;
    } else if (s.modal === "tasks") {
      title = "任务进度";
      content = tasks();
    } else return null;
    return { title, content };
  }
  function show(name) {
    open(name);
  }
  root.addEventListener(
    "click",
    (event) => {
      const target = event.target.closest("[data-x],[data-material]");
      if (!target || target.disabled) return;
      event.stopImmediatePropagation();
      if (target.dataset.material) return openMaterial(target.dataset.material);
      const key = target.dataset.x,
        value = target.dataset.id;
      if (key === "switch") show("switchBook");
      if (key === "chooseBook") {
        s.selectedBook = value;
        close();
      }
      if (key === "manageBook") {
        s.managedBook = value;
        show("manageBook");
      }
      if (key === "newBook") show("createBook");
      if (key === "deleteBook") show("deleteBookConfirm");
      if (key === "confirmDeleteBook") {
        s.notebooks = s.notebooks.filter((b) => b.id !== s.managedBook);
        s.words.forEach((w) => {
          if (w.book === s.managedBook) w.book = "";
          w.books = (w.books || []).filter((b) => b !== s.managedBook);
        });
        if (s.selectedBook === s.managedBook) s.selectedBook = "all";
        s.practiceBookIds = s.practiceBookIds.filter(
          (b) => b !== s.managedBook,
        );
        show("switchBook");
      }
      if (key === "entry") {
        s.selectedWord = value;
        show("entryDetail");
      }
      if (key === "editEntry") show("editEntry");
      if (key === "organizeEntry") show("entryBooks");
      if (key === "kind") {
        s.collectionKind = value;
        render();
      }
      if (key === "practice") {
        s.practiceSources = ["notebook"];
        s.practiceAllWords = s.selectedBook === "all";
        s.practiceBookIds = selected() ? [s.selectedBook] : [];
        s.activeLanguage = selected()?.language || s.activeLanguage;
        s.practicePreview = false;
        go("exerciseBuilder");
      }
      if (key === "add") show("addEntry");
      if (key === "materialDetails") {
        s.chosenMaterial = value;
        show("materialDetails");
      }
      if (key === "tasks") show("tasks");
      if (key === "openJob") openMaterial(value);
      if (key === "saveCard") {
        s.savingCard = value;
        show("saveCard");
      }
      if (key === "prompt") {
        s.queryDraft = target.dataset.question;
        render();
        root.querySelector("#query-input")?.focus();
      }
    },
    true,
  );
  root.addEventListener("keydown", (event) => {
    if (
      event.target.id === "query-input" &&
      event.key === "Enter" &&
      (event.ctrlKey || event.metaKey) &&
      !event.isComposing
    ) {
      event.preventDefault();
      event.stopPropagation();
      event.target.form.requestSubmit();
    }
  });
  root.addEventListener("input", (event) => {
    if (event.target.id === "query-input") s.queryDraft = event.target.value;
  });
  root.addEventListener("change", (event) => {
    if (event.target.hasAttribute("data-x-date")) {
      s.dailyDate = event.target.value || today();
      render();
    }
  });
  root.addEventListener(
    "submit",
    (event) => {
      const form = event.target.closest("[data-x-form]");
      if (!form) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      const values = new FormData(form),
        action = form.dataset.xForm;
      const text = (key) => String(values.get(key) || "").trim();
      if (action === "search") {
        s.collectionSearch = text("search");
        render();
      }
      if (action === "book") {
        if (!text("title")) return;
        s.notebooks.push({
          id: id(),
          title: text("title"),
          language: text("language"),
          tone: "blue",
        });
        show("switchBook");
      }
      if (action === "rename") {
        const b = s.notebooks.find((x) => x.id === s.managedBook);
        b.title = text("title") || b.title;
        b.description = text("description");
        show("switchBook");
      }
      if (action === "entry") {
        if (!text("word") || !text("meaning")) return;
        const w = {
          id: id(),
          kind: text("kind"),
          word: text("word"),
          meaning: text("meaning"),
          language: text("language"),
          source: "手动添加",
          createdAt: new Date().toISOString(),
          book: selected()?.language === text("language") ? s.selectedBook : "",
          mastery: "尚无有效证据",
        };
        s.words.unshift(w);
        s.selectedWord = w.id;
        show("entryDetail");
      }
      if (action === "editEntry") {
        const w = s.words.find((x) => x.id === s.selectedWord);
        if (!w.cardId) {
          w.word = text("word") || w.word;
          w.meaning = text("meaning") || w.meaning;
        }
        w.note = text("note");
        show("entryDetail");
      }
      if (action === "entryBooks") {
        const w = s.words.find((x) => x.id === s.selectedWord);
        w.book = "";
        w.books = values.getAll("books");
        show("entryDetail");
      }
      if (action === "query") {
        const question = text("question");
        if (!question) return;
        s.queryMessages.push({
          question,
          card: { ...answer(question), id: id() },
        });
        s.queryDraft = "";
        form.reset();
        render();
        root.querySelector("#query-input")?.focus({ preventScroll: true });
        root
          .querySelector(".answer-card:last-child")
          ?.scrollIntoView({ block: "nearest" });
      }
      if (action === "saveCard") {
        const card = s.queryMessages.find(
          (m) => m.card.id === s.savingCard,
        )?.card;
        if (card && !s.words.some((w) => w.cardId === card.id))
          s.words.unshift({
            ...card,
            id: id(),
            cardId: card.id,
            source: "查询 · 示例回答",
            books: values.getAll("books"),
            createdAt: new Date().toISOString(),
            mastery: "尚无有效证据",
          });
        close();
      }
    },
    true,
  );
  function importMaterial() {
    if (!s.importFile || !s.importType) return;
    const material = {
      id: id(),
      type: s.importType,
      title: s.importFile,
      subtitle: `${typeLabel[s.importType]} · 示例导入`,
      cover: typeLabel[s.importType][0],
      tone: "lime",
      detail: "仅记录文件名，没有上传或解析文件。",
      updated: "刚刚",
      demoJob: true,
      ready: false,
      progress: 0,
      sequence: 0,
      status: "解析中",
    };
    s.materials.unshift(material);
    subscribe();
    go("library");
    show("tasks");
  }
  root.addEventListener(
    "click",
    (event) => {
      if (event.target.closest('[data-action="importConfirm"]')) {
        event.stopImmediatePropagation();
        importMaterial();
      }
    },
    true,
  );
  return {
    notebooks,
    dailyWords,
    query,
    library,
    dialog,
    tasks,
    sampleReader,
    openMaterial,
  };
};
