/* Shared, in-memory prototype interactions. No production API or model calls. */
window.HarukaCollections = ({
  s,
  root,
  mobile,
  render,
  open,
  close,
  go,
  novel,
}) => {
  const { escape: e, icon: I, data, typeLabel } = window.HarukaCore;
  const learningCards = window.HarukaLearningCards;
  const { kinds } = learningCards;
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
  s.queryImages = [];
  let selectionBackstack = [];
  const promptLimitMessage = "草稿已接近字数上限，请先精简后再添加示例。";
  let queryImageError = "";
  let preparingImages = false;
  let imageEpoch = 0;
  let queryPicker = null;
  let collectionFocusFallback = "";
  let savedCardFocus = "";
  const imageUrls = new Set();
  function releaseImage(url) {
    URL.revokeObjectURL(url);
    imageUrls.delete(url);
  }
  function resetQueryImages() {
    imageEpoch++;
    imageUrls.forEach(releaseImage);
    s.queryImages = [];
    s.queryMessages = [];
    s.selectionMessage = null;
    s.saveCardReturn = false;
    s.questionDraft = null;
    selectionBackstack = [];
    s.queryDraft = "";
    queryImageError = "";
    preparingImages = false;
    queryPicker = null;
  }
  window.addEventListener("pagehide", (event) => {
    if (!event.persisted) resetQueryImages();
  });
  function queryImageStrip(images, editable = false) {
    return images
      .map(
        (item, index) =>
          `<div class="query-image-tile"><button class="query-image-open" type="button" data-x="viewQueryImage" data-id="${item.id}" aria-label="查看图片 ${index + 1}"><img src="${item.url}" alt="${e(item.name)}"></button>${editable ? `<button class="query-image-remove" type="button" data-x="removeQueryImage" data-id="${item.id}" aria-label="移除图片 ${index + 1}">${I("close")}</button>` : ""}</div>`,
      )
      .join("");
  }
  function refreshQueryAttachments() {
    const form = root.querySelector('[data-x-form="query"]');
    if (!form) return;
    form.querySelector("[data-query-images]").innerHTML = queryImageStrip(
      s.queryImages,
      true,
    );
    form.querySelector("[data-query-images]").hidden = !s.queryImages.length;
    form.querySelector("[data-query-error]").textContent = queryImageError;
    form.querySelector("[data-query-error]").hidden = !queryImageError;
    form.querySelector("[data-query-status]").textContent = preparingImages
      ? "正在准备图片…"
      : s.queryImages.length
        ? `${s.queryImages.length} / 4 张图片 · 仅本机预览`
        : mobile
          ? "本地示例 · 不调用模型"
          : "可粘贴图片 · 本地示例";
    form.querySelectorAll('[data-x="pickQueryImage"]').forEach((button) => {
      button.disabled = preparingImages;
    });
    form.querySelector('[type="submit"]').disabled = !canSendQuery();
    form.setAttribute("aria-busy", String(preparingImages));
  }
  async function addQueryImages(files, picker = null) {
    if (!files.length || !s.signedIn) return;
    if (preparingImages || s.queryImages.length + files.length > 4) {
      queryImageError = preparingImages
        ? "图片正在准备，请稍后再添加。"
        : "每次最多添加 4 张图片，请移除部分图片后重试。";
      refreshQueryAttachments();
      return;
    }
    const epoch = imageEpoch;
    const batch = [];
    preparingImages = true;
    queryImageError = "";
    refreshQueryAttachments();
    try {
      for (const file of files) {
        if (!["image/png", "image/jpeg", "image/webp"].includes(file.type))
          throw new Error("请选择 PNG、JPEG 或 WebP 图片。");
        if (!file.size || file.size > 10_000_000)
          throw new Error("单张图片需大于 0 且不超过 10 MB。");
        const signature = new Uint8Array(await file.slice(0, 12).arrayBuffer());
        if (epoch !== imageEpoch || !s.signedIn) return;
        const match =
          file.type === "image/png"
            ? [137, 80, 78, 71, 13, 10, 26, 10].every(
                (value, index) => signature[index] === value,
              )
            : file.type === "image/jpeg"
              ? signature[0] === 255 &&
                signature[1] === 216 &&
                signature[2] === 255
              : String.fromCharCode(...signature.slice(0, 4)) === "RIFF" &&
                String.fromCharCode(...signature.slice(8, 12)) === "WEBP";
        if (!match) throw new Error("无法读取图片，请重新选择有效的图片文件。");
        const url = URL.createObjectURL(file);
        imageUrls.add(url);
        batch.push({ id: id(), name: file.name || "粘贴的图片", url });
        const img = new Image();
        img.src = url;
        await img.decode();
        if (
          !img.naturalWidth ||
          img.naturalWidth * img.naturalHeight > 24_000_000
        )
          throw new Error("图片尺寸过大，请选择不超过 2400 万像素的图片。");
        if (epoch !== imageEpoch || !s.signedIn) return;
      }
      s.queryImages.push(...batch);
    } catch (error) {
      batch.forEach((item) => releaseImage(item.url));
      if (epoch === imageEpoch)
        queryImageError =
          error instanceof Error && error.name === "Error"
            ? error.message
            : "无法读取图片，请重新选择。";
    } finally {
      if (epoch !== imageEpoch) batch.forEach((item) => releaseImage(item.url));
      else {
        preparingImages = false;
        refreshQueryAttachments();
        if (picker)
          requestAnimationFrame(() => {
            if (
              epoch === imageEpoch &&
              picker.form === root.querySelector('[data-x-form="query"]') &&
              [document.body, picker.button, picker.input].includes(
                document.activeElement,
              )
            )
              root
                .querySelector("#query-input")
                ?.focus({ preventScroll: true });
          });
      }
    }
  }
  s.materials = data.materials.map((m) => ({ ...m }));
  const deletedMaterials = new Set();
  let deletedFocusIndex = null;
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
    return `<article class="collection-row" data-kind="${e(w.kind)}"><button class="collection-row-open" type="button" data-x="entry" data-id="${w.id}" aria-label="查看 ${e(w.word)}"><span class="collection-type-icon" aria-hidden="true">${I(learningCards.icons[w.kind])}</span><span class="collection-copy"><span class="collection-word-line"><strong>${e(w.word)}</strong>${w.reading ? `<small>${e(w.reading)}</small>` : ""}</span><span class="collection-meaning">${e(w.meaning)}</span></span><span class="collection-kind">${e(kinds[w.kind])}</span><span class="collection-open-label" aria-hidden="true">${I("chevron")}</span></button>${w.kind === "word" ? learningCards.pronounce(w.word, w.language) : ""}</article>`;
  }
  function emptyCollection() {
    if (s.collectionSearch.trim() || s.collectionKind !== "all")
      return `<div class="empty"><strong>没有匹配的收藏</strong><p>${s.collectionSearch.trim() ? `没有找到“${e(s.collectionSearch.trim())}”相关内容。` : `当前单词本中还没有${e(kinds[s.collectionKind])}。`}</p><button class="secondary" type="button" data-x="resetCollectionFilters">清除搜索与筛选</button></div>`;
    return `<div class="empty"><strong>${s.selectedBook === "all" ? "还没有收藏" : "这个单词本还没有收藏"}</strong><p>从阅读或查询中收藏，也可以手动添加。</p><button class="secondary" type="button" data-x="add" data-id="empty">${I("plus")}添加收藏</button>${s.selectedBook !== "all" ? '<button class="text-btn" type="button" data-x="switch" data-id="empty">切换单词本</button>' : ""}</div>`;
  }
  function emptyLibrary() {
    if (s.search.trim() || s.filter !== "all")
      return `<div class="empty"><strong>没有匹配的材料</strong><p>${s.search.trim() ? `没有找到“${e(s.search.trim())}”相关材料。` : `材料库中还没有${e(typeLabel[s.filter])}。`}</p><button class="secondary" type="button" data-x="resetMaterialFilters">清除搜索与筛选</button></div>`;
    return `<div class="empty"><strong>材料库还是空的</strong><p>添加一份小说、课本或试卷，开始学习。</p><button class="primary" type="button" data-go="import">${I("plus")}导入材料</button></div>`;
  }
  function notebooks() {
    const list = inBook().filter(
      (w) =>
        (s.collectionKind === "all" || w.kind === s.collectionKind) &&
        `${w.word} ${w.reading || ""} ${w.meaning}`
          .toLowerCase()
          .includes(s.collectionSearch.trim().toLowerCase()),
    );
    return `<div class="collection-page">${mobile ? "" : `<div class="collection-heading"><h1>单词本</h1><button class="secondary" type="button" data-x="add">${I("plus")}添加</button></div>`}<div class="collection-tools"><button class="book-switcher" type="button" data-x="switch">${I("layers")}<span>${e(selected()?.title || "全部收藏")}</span>${I("chevron")}</button><button class="daily-shortcut" type="button" data-go="dailyWords">${I("clock")}每日单词${I("arrow")}</button></div>${mobile ? "" : `<form class="collection-search" data-x-form="search"><label>${I("search")}<input name="search" type="search" aria-label="搜索收藏" placeholder="搜索收藏内容" value="${e(s.collectionSearch)}"></label><button class="text-btn" type="submit">搜索</button></form>`}<div class="collection-filters" aria-label="收藏类型">${[["all", "全部"], ...Object.entries(kinds)].map(([key, label]) => `<button type="button" data-x="kind" data-id="${key}" aria-pressed="${s.collectionKind === key}">${label}</button>`).join("")}</div><div class="collection-caption"><span>${list.length} 条收藏</span><div class="collection-list-actions"><button class="text-btn" type="button" data-x="practice">生成 AI 习题 ${I("spark")}</button><button class="text-btn" type="button" data-go="csv">单词 CSV ${I("download")}</button></div></div><div class="collection-list" id="collection-list">${list.map(row).join("") || emptyCollection()}</div></div>`;
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
          .includes(s.search.trim().toLowerCase()),
    );
    return `<div class="collection-page material-library">${mobile ? "" : `<div class="collection-heading"><h1>材料库</h1><button class="primary" type="button" data-go="import">${I("plus")}导入材料</button></div>`}<div class="collection-library-tools"><div class="collection-filters" aria-label="材料类型">${[["all", "全部"], ...Object.entries(typeLabel)].map(([key, label]) => `<button type="button" data-filter="${key}" aria-pressed="${s.filter === key}">${label}</button>`).join("")}</div>${mobile ? "" : `<label class="search">${I("search")}<input type="search" data-input="search" aria-label="搜索材料" placeholder="搜索标题或语言" value="${e(s.search)}"></label>`}</div><div class="collection-caption"><span>${list.length} 份材料</span>${mobile ? '<button class="text-btn" type="button" data-x="tasks">任务进度</button>' : "<span>最近更新</span>"}</div><div class="direct-material-list" id="material-list">${list.map((m) => `<article class="direct-material"><button class="direct-material-main" type="button" data-material="${m.id}"><span class="cover ${m.tone}" aria-hidden="true">${e(m.cover)}</span><span class="direct-material-copy"><strong>${e(m.title)}</strong><small>${e(m.subtitle)}</small>${m.demoJob ? progress(m) : `<span class="collection-kind">${e(status(m))}</span>`}</span>${I("chevron")}</button><button class="material-details-button" type="button" data-x="materialActions" data-id="${m.id}" aria-label="更多：${e(m.title)}" aria-haspopup="dialog" title="更多操作">${I("more")}</button></article>`).join("") || emptyLibrary()}</div>${mobile && s.materials.length ? `<div class="floating-action"><button class="primary" type="button" data-go="import">${I("plus")}导入材料</button></div>` : ""}</div>`;
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
    return `<div class="sample-reader"><span class="collection-kind">内置示例正文</span><h1>${e(m.title)}</h1>${m.id === "rain" ? '<button class="secondary" type="button" data-selection-action="continuous">连续朗读</button><div data-novel-prose><h2>雨停之后</h2><p lang="ja">雨が上がった。窓を開けると、庭の木々が光っていた。私は本を閉じて、外へ出た。</p></div><p>雨停了。推开窗，庭院里的树木闪着光。我合上书，走到屋外。</p>' : "<p>此文件没有被读取或解析。当前仅演示任务进度，实际正文需要正式解析服务。</p>"}<button class="secondary" type="button" data-go="library">返回材料库</button></div>`;
  }
  function canSendQuery() {
    return !preparingImages && !!(s.queryDraft?.trim() || s.queryImages.length);
  }
  function query() {
    const empty = !s.queryMessages.length;
    const composer = `<form class="query-composer" data-x-form="query" aria-busy="${preparingImages}"><div class="query-image-strip" data-query-images ${s.queryImages.length ? "" : "hidden"}>${queryImageStrip(s.queryImages, true)}</div><label class="sr-only" for="query-input">输入问题</label><textarea id="query-input" name="question" maxlength="2000" rows="2" placeholder="输入单词、句子、语法问题，或添加图片…">${e(s.queryDraft || "")}</textarea>${s.learningDemo.composerContext()}<p class="query-image-error" data-query-error role="alert" ${queryImageError ? "" : "hidden"}>${e(queryImageError)}</p><div class="query-composer-actions"><div class="query-attach-actions"><button class="query-attach-button" type="button" data-x="pickQueryImage" data-id="album" aria-label="添加图片" title="${mobile ? "从相册添加" : "选择图片"}" ${preparingImages ? "disabled" : ""}>${I("image")}<span>${mobile ? "相册" : "图片"}</span></button>${mobile ? `<button class="query-attach-button" type="button" data-x="pickQueryImage" data-id="camera" aria-label="拍照" ${preparingImages ? "disabled" : ""}>${I("camera")}<span>拍照</span></button>` : ""}</div><button class="primary" type="submit" aria-label="发送问题" ${canSendQuery() ? "" : "disabled"}>发送 ${I("arrow")}</button></div><p class="note query-composer-note" data-query-status role="status">${preparingImages ? "正在准备图片…" : s.queryImages.length ? `${s.queryImages.length} / 4 张图片 · 仅本机预览` : mobile ? "本地示例 · 不调用模型" : "可粘贴图片 · 本地示例"}</p><input type="file" data-query-file="album" accept="image/png,image/jpeg,image/webp" multiple hidden>${mobile ? '<input type="file" data-query-file="camera" accept="image/*" capture="environment" hidden>' : ""}</form>`;
    const welcome = `<div class="query-welcome"><h2>试试这样查询</h2><div class="query-prompts">${learningCards.prompts.map((prompt) => `<button class="query-prompt" type="button" data-x="prompt" data-question="${e(prompt)}" aria-label="${e(prompt)}"><span>${e(prompt)}</span></button>`).join("")}</div></div>`;
    const messages = `<div class="query-messages" aria-live="polite">${s.queryMessages.map((message) => `<div class="query-question">${message.images?.length ? `<div class="query-image-strip">${queryImageStrip(message.images)}</div>` : ""}${message.question ? `<p>${e(message.question)}</p>` : ""}</div>${s.learningDemo.contextSummary(message)}${message.card ? learningCards.render(message.card, `<button class="text-btn" type="button" data-x="saveCard" data-id="${message.card.id}" ${s.words.some((w) => w.cardId === message.card.id) ? "disabled" : ""}>${I("bookmark")}${s.words.some((w) => w.cardId === message.card.id) ? "已收藏" : "收藏"}</button>`) : `<div class="query-notice" role="status">${I("book")}<p>${e(message.notice)}</p></div>`}`).join("")}</div>`;
    return `<div class="query-page ${empty ? "is-empty" : ""}">${mobile ? "" : `<div class="collection-heading"><h1>查询</h1><span class="collection-kind">语言学习</span></div>`}${empty ? `<p class="query-intro">理解一个词，读懂一句话。</p>${composer}${welcome}` : `${messages}${composer}`}</div>`;
  }
  function querySelection(selection, prepared) {
    if (
      prepared?.replace &&
      (s.modal === "selectionQuery" || novel.panelActive())
    ) {
      const message = s.selectionMessage;
      message.selection = selection;
      if (novel.panelActive()) s.readerSource = selection;
      message.question = selection.text;
      message.card = prepared.card ? { ...prepared.card, selection } : null;
      message.notice = "";
      const context = s.learningDemo.captureContext(selection, novel);
      Object.assign(
        message,
        s.learningDemo.rememberQuery(message.card, context, selection.text),
      );
      render();
      return;
    }
    if (!mobile && s.route === "novel" && !selection.panel) {
      selectionBackstack = [];
      s.readerSource = selection;
    }
    if (mobile)
      history.replaceState(
        {
          ...history.state,
          harukaSelectionMessage: s.selectionMessage?.id,
          harukaModalScroll:
            root.querySelector("[role=dialog]")?.scrollTop || 0,
        },
        "",
        location.href,
      );
    else if (s.route !== "novel" || selection.panel)
      selectionBackstack.push({
        route: s.route,
        modal: s.modal,
        message: s.selectionMessage,
        scroll:
          root.querySelector("[role=dialog],[data-reader-panel-body]")
            ?.scrollTop || 0,
        panel: novel.panelActive(),
      });
    const queryContext = s.learningDemo.captureContext(selection, novel);
    const parts =
      selection.queryMode === "separate_words"
        ? selection.ranges
        : [{ text: selection.text }];
    const messages = parts.map((part) => {
      const cached = novel.cached(selection, part.text);
      const result = prepared
        ? prepared.card
        : cached || learningCards.sample(part.text);
      const saved = s.learningDemo.rememberQuery(
        result
          ? { ...result, id: prepared || cached ? result.id : id() }
          : null,
        queryContext,
        part.text,
      );
      return {
        ...saved,
        id: id(),
        question: part.text,
        selection,
        images: [],
        card: saved.card
          ? {
              ...saved.card,
              source: `${selection.source} · ${prepared ? "已准备解析示例" : "选区查询"}`,
              selection,
            }
          : null,
        notice: prepared
          ? ""
          : `“${part.text}”没有内置查询示例。本原型未调用 AI，未生成可收藏的结果。`,
      };
    });
    const message = messages[0];
    if (messages.length > 1)
      message.relatedIds = messages.map((item) => item.id);
    s.queryMessages.push(...messages);
    s.selectionMessage = message;
    show("selectionQuery");
    const surface = root.querySelector(
      "[role=dialog],[data-reader-panel-body]",
    );
    if (surface) {
      surface.scrollTop = 0;
      if (novel.panelActive()) {
        surface.focus({ preventScroll: true });
        if (innerWidth < 1180)
          surface
            .closest("[data-reader-panel]")
            .scrollIntoView({ block: "start" });
      }
    }
  }
  function textbookQuestion(unit = s.textbookUnit) {
    return {
      unit1: {
        prompt: "「わたしは学生です」中的「は」有什么作用？",
        options: ["提示话题", "表示移动方向", "表示过去时间", "连接并列句"],
        correct: 0,
        explanation: "「は」提示句子的话题。",
      },
      unit2: {
        ...data.textbook.question,
        explanation: "「へ」标示移动的方向。",
      },
      unit3: {
        prompt: "在咖啡馆点餐时，「ください」通常表达什么？",
        options: ["请给我", "欢迎回来", "我已吃完", "请稍等"],
        correct: 0,
        explanation: "「ください」在这里表达礼貌请求。",
      },
    }[unit];
  }
  function questionSnapshot(kind, questionId) {
    if (!s.signedIn || s.adminArea) return null;
    let question,
      submitted,
      answer,
      source,
      language = "日语";
    if (kind === "practice" && questionId === s.activeLanguage) {
      language = s.activeLanguage;
      question = language === "英语" ? data.practiceEnglish : data.practice;
      submitted = s.practiceSubmitted;
      answer = s.practiceAnswer;
      source = `AI 习题 · ${language} · 语境填空`;
    } else if (kind === "textbook") {
      question = textbookQuestion(questionId);
      if (questionId !== s.textbookUnit) return null;
      submitted = s.textbookSubmitted;
      answer = s.textbookAnswer;
      source = `日语的日常表达 · ${data.textbook.units.find((unit) => unit.id === questionId)?.title}`;
    } else if (kind === "exam" && s.examFinished && !s.examRunning) {
      question = data.exam.questions.find((q) => q.id === questionId);
      submitted = true;
      answer = s.examAnswers[questionId];
      source = `${data.exam.title} · ${question?.group} · ${questionId}`;
    }
    if (!question) return null;
    return {
      kind: "exercise",
      word: question.prompt || question.text,
      meaning: source,
      language,
      questionKey: `${kind}:${questionId}:v1`,
      questionOrigin: { kind, id: questionId, version: 1 },
      questionOptions: [...question.options],
      source,
      ...(submitted
        ? {
            originalAnswer: question.options[answer] || "未作答",
            referenceAnswer: question.options[question.correct],
            detail: question.explanation || "交卷后的客观题参考答案示例。",
          }
        : { detail: "作答前收藏，仅保存题面和选项。" }),
    };
  }
  function questionButton(kind, questionId) {
    const question = questionSnapshot(kind, questionId);
    if (!question) return "";
    const saved = s.words.some(
      (word) => word.questionKey === question.questionKey,
    );
    return `<button class="secondary question-collect" type="button" data-x="saveQuestion" data-question-kind="${kind}" data-id="${e(questionId)}" ${saved ? "disabled" : ""}>${I("bookmark")}${saved ? "已收藏题目" : "收藏题目"}</button>`;
  }
  function examReview() {
    if (!s.examFinished || s.examRunning) return "";
    return `<div class="exam-review-list">${data.exam.questions.map((q, i) => `<article class="exam-review-item" data-question-id="${q.id}"><div class="section-head"><h3>第 ${i + 1} 题 · ${e(q.group)}</h3>${questionButton("exam", q.id)}</div><div class="exam-review-text"><h4>${e(q.text)}</h4><ol type="A">${q.options.map((option) => `<li>${e(option)}</li>`).join("")}</ol><p>你的选择：${s.examAnswers[q.id] === undefined ? "未作答" : e(q.options[s.examAnswers[q.id]])}</p><p>参考答案：${e(q.options[q.correct])}</p></div></article>`).join("")}</div>`;
  }
  function returnFromSelection() {
    if (mobile) return false;
    if (s.modal === "chapterPrepare" && s.novelPrepareReturn) {
      s.novelPrepareReturn = false;
      show("selectionQuery");
      return true;
    }
    if (s.modal === "saveCard" && s.saveCardReturn) {
      s.saveCardReturn = false;
      show("selectionQuery");
      return true;
    }
    if (s.modal !== "selectionQuery" && !(novel.panelActive() && !s.modal))
      return false;
    const origin = s.selectionMessage?.selection;
    const previous = selectionBackstack.pop();
    if (!previous || previous.route !== s.route) {
      selectionBackstack = [];
      return false;
    }
    s.selectionMessage = previous.message;
    s.modal = previous.modal;
    render();
    const dialog = root.querySelector("[role=dialog],[data-reader-panel-body]");
    if (dialog) dialog.scrollTop = previous.scroll;
    restoreSelectionFocus(origin);
    return true;
  }
  function restoreSelectionFocus(origin) {
    if (!origin || origin.route !== s.route || origin.modal !== s.modal) return;
    const container = root.querySelector("[role=dialog]") || root;
    const element = origin.novelSentenceId
      ? container.querySelector(
          `[data-novel-sentence="${CSS.escape(origin.novelSentenceId)}"]`,
        )
      : container.querySelectorAll("[data-study-text]")[origin.scopeIndex];
    if (element) {
      element.tabIndex = origin.novelSentenceId ? 0 : -1;
      element.focus({ preventScroll: true });
    }
  }
  function restoreSelectionMessage(messageId) {
    const previous = s.selectionMessage;
    s.selectionMessage =
      s.queryMessages.find((message) => message.id === messageId) || null;
    return previous?.id !== messageId ? previous?.selection : null;
  }
  function selectionResult() {
    const message = s.selectionMessage;
    const title = message?.selection?.novelSentenceId ? "句子解析" : "查询结果";
    const group = message?.relatedIds
      ? message.relatedIds
          .map((id) => s.queryMessages.find((item) => item.id === id))
          .filter(Boolean)
      : message
        ? [message]
        : [];
    const content = message
      ? `${novel.panelHeader(message)}${s.learningDemo.contextSummary(message)}<div class="selection-query-origin"><small>${e(message.selection.source)}</small>${e(message.selection.sentence || message.question)}${group.length > 1 ? "<p>分别查询所选词汇</p>" : ""}</div>${group
          .map((item) => {
            const saved =
              item.card && s.words.some((w) => w.cardId === item.card.id);
            return item.card
              ? learningCards.render(
                  item.card,
                  `<button type="button" class="text-btn" data-x="saveCard" data-id="${item.card.id}" ${saved ? "disabled" : ""}>${I("bookmark")}${saved ? "已收藏" : "收藏"}</button>`,
                  false,
                )
              : `<p role="status">${e(item.notice)}</p>`;
          })
          .join("")}`
      : "<p>选区已失效，请重新选择。</p>";
    return { title, content };
  }
  function dialog() {
    let title;
    let content;
    const w = s.words.find((x) => x.id === s.selectedWord);
    if (s.modal === "selectionQuery") {
      ({ title, content } = selectionResult());
    } else if (s.modal === "queryImagePreview") {
      const item = [
        ...s.queryImages,
        ...s.queryMessages.flatMap((message) => message.images || []),
      ].find((image) => image.id === s.queryImagePreview);
      title = "图片预览";
      content = item
        ? `<figure class="query-image-preview"><img src="${item.url}" alt="${e(item.name)}"><figcaption>${e(item.name)}</figcaption></figure>`
        : "<p>图片已移除。</p>";
    } else if (s.modal === "switchBook") {
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
        ? `<article class="entry-detail"><div class="saved-card-heading">${I(learningCards.icons[w.kind])}<span>${e(kinds[w.kind])} · ${e(w.language || "日语")}</span></div>${learningCards.content(w)}${w.note ? `<p>笔记：${e(w.note)}</p>` : ""}<p class="note">${e(w.source)} · ${day(w.createdAt)} 加入</p>${w.kind === "word" ? `<span class="tag">${e(w.mastery || "尚无有效证据")}</span>` : ""}<div class="entry-books">${
            s.notebooks
              .filter((b) => belongs(w, b.id))
              .map((b) => `<span class="tag">${e(b.title)}</span>`)
              .join("") || '<span class="note">尚未归类</span>'
          }</div><button class="secondary" type="button" data-x="organizeEntry">${I("layers")}归入单词本</button><button class="secondary" type="button" data-x="editEntry">编辑与笔记</button>${(w.source.startsWith("夏の手紙") && deletedMaterials.has("summer")) || (w.source.startsWith("N2") && deletedMaterials.has("n2")) ? '<p class="note">原材料已删除，保留收藏快照。</p>' : w.source.startsWith("夏の手紙") ? `<button class="text-btn" type="button" data-go="novel">回到原文 ${I("arrow")}</button>` : w.source.startsWith("N2") ? `<button class="text-btn" type="button" data-go="examPrep">查看试卷 ${I("arrow")}</button>` : ""}</article>`
        : "<p>该收藏已不可用。</p>";
    } else if (s.modal === "editEntry") {
      title = "编辑收藏";
      content = `<form class="form-grid" data-x-form="editEntry">${w.cardId || w.questionKey ? `<p class="note">学习卡片保留收藏时的完整内容。</p>` : `<label class="field">内容<textarea name="word" required maxlength="2000">${e(w.word)}</textarea></label><label class="field">释义<textarea name="meaning" required maxlength="4000">${e(w.meaning)}</textarea></label>`}<label class="field">个人笔记<textarea name="note" maxlength="4000">${e(w.note || "")}</textarea></label><button class="primary" type="submit">保存</button></form>`;
    } else if (["entryBooks", "saveCard", "saveQuestion"].includes(s.modal)) {
      title =
        s.modal === "saveQuestion"
          ? "收藏题目"
          : s.modal === "saveCard"
            ? "收藏卡片"
            : "归入单词本";
      const card = s.queryMessages.find(
        (m) => m.card?.id === s.savingCard,
      )?.card;
      const target =
        s.modal === "saveQuestion"
          ? s.questionDraft
          : s.modal === "saveCard"
            ? card
            : w;
      if (
        s.modal === "saveQuestion" &&
        (!target ||
          s.words.some((word) => word.questionKey === target.questionKey))
      ) {
        return {
          title,
          content: `<p>${target ? "这道题已收藏。" : "此收藏步骤已失效，请回到题目重新操作。"}</p><button class="secondary" type="button" data-action="closeModal">返回题目</button>`,
        };
      }
      const books = s.notebooks.filter((b) => b.language === target?.language);
      content = `<form class="form-grid" data-x-form="${s.modal}">${s.modal === "saveQuestion" ? `<p>${e(target?.word || "题目已不可用")}</p><p class="note">保存完整题目和当前可见内容，可选单词本归类。</p>` : ""}${books.map((b) => `<label class="check-row choice-row"><input type="checkbox" name="books" value="${b.id}" ${s.modal === "entryBooks" && belongs(w, b.id) ? "checked" : ""}><span>${e(b.title)}</span></label>`).join("") || "<p>暂无同语言单词本，可先收藏到全部收藏。</p>"}<button class="primary" type="submit">${s.modal === "entryBooks" ? "保存归类" : "确认收藏"}</button></form>`;
    } else if (s.modal === "addEntry") {
      title = "添加收藏";
      content = `<form class="form-grid" data-x-form="entry"><label class="field">类型<select name="kind">${Object.entries(
        kinds,
      )
        .filter(([k]) => k !== "exercise")
        .map(([k, v]) => `<option value="${k}">${v}</option>`)
        .join(
          "",
        )}</select></label><label class="field">语言<select name="language">${["日语", "英语", "简体中文"].map((l) => `<option ${selected()?.language === l ? "selected" : ""}>${l}</option>`).join("")}</select></label><label class="field">内容<textarea name="word" required maxlength="2000"></textarea></label><label class="field">释义或笔记<textarea name="meaning" required maxlength="4000"></textarea></label><button class="primary" type="submit">添加</button></form>`;
    } else if (s.modal === "materialActions") {
      const m = s.materials.find((x) => x.id === s.chosenMaterial);
      title = "材料操作";
      content = m
        ? `<p class="material-menu-name">${e(m.title)}</p><div class="material-action-list"><button type="button" data-x="materialDetails" data-id="${m.id}">${I("book")}<span>查看详情</span>${I("chevron")}</button><button class="material-delete-action" type="button" data-x="deleteMaterial" data-id="${m.id}"><span>删除</span></button></div>`
        : "<p>材料已删除。</p>";
    } else if (s.modal === "deleteMaterialConfirm") {
      const m = s.materials.find((x) => x.id === s.chosenMaterial);
      title = "删除材料";
      content = m
        ? `<div class="entry-detail"><h3>删除「${e(m.title)}」？</h3><p>移除材料和阅读入口，收藏与历史作答保留。</p><p class="note">本地演示，刷新后恢复。</p><button class="danger-btn" type="button" data-x="confirmDeleteMaterial">确认删除</button><button class="secondary" type="button" data-x="materialActions" data-id="${m.id}">取消</button></div>`
        : "<p>材料已删除。</p>";
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
      if (key === "pickQueryImage") {
        const input = root.querySelector(`[data-query-file="${value}"]`);
        if (input) {
          queryPicker = { form: input.form, input, button: target };
          input.click();
        }
      }
      if (key === "viewQueryImage") {
        s.queryImagePreview = value;
        show("queryImagePreview");
      }
      if (key === "removeQueryImage") {
        const item = s.queryImages.find((image) => image.id === value);
        if (item) releaseImage(item.url);
        s.queryImages = s.queryImages.filter((image) => image.id !== value);
        queryImageError = "";
        refreshQueryAttachments();
        root.querySelector("#query-input")?.focus({ preventScroll: true });
      }
      if (key === "switch") {
        if (value === "empty") collectionFocusFallback = "switch";
        show("switchBook");
      }
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
      if (key === "resetCollectionFilters" || key === "resetMaterialFilters") {
        const collection = key === "resetCollectionFilters";
        if (collection) {
          s.collectionSearch = "";
          s.collectionKind = "all";
        } else {
          s.search = "";
          s.filter = "all";
        }
        render();
        root
          .querySelector(
            collection
              ? '[data-x="kind"][data-id="all"]'
              : '[data-filter="all"]',
          )
          ?.focus({ preventScroll: true });
      }
      if (key === "kind") {
        s.collectionKind = value;
        render();
      }
      if (key === "practice") {
        s.practiceSources = ["notebook"];
        s.practiceAllWords = s.selectedBook === "all";
        s.practiceBookIds = selected() ? [s.selectedBook] : [];
        s.activeLanguage = selected()?.language || s.activeLanguage;
        s.practiceAllowRepeat = false;
        go("exerciseBuilder");
      }
      if (key === "add") {
        if (value === "empty") collectionFocusFallback = "add";
        show("addEntry");
      }
      if (
        ["materialActions", "materialDetails", "deleteMaterial"].includes(key)
      ) {
        if (!s.materials.some((m) => m.id === value)) return;
        s.chosenMaterial = value;
        show(key === "deleteMaterial" ? "deleteMaterialConfirm" : key);
      }
      if (key === "confirmDeleteMaterial") {
        const material = s.materials.find((m) => m.id === s.chosenMaterial);
        if (!material) return close();
        deletedFocusIndex = [
          ...root.querySelectorAll(".material-details-button"),
        ].findIndex((button) => button.dataset.id === material.id);
        deletedMaterials.add(material.id);
        s.materials = s.materials.filter((m) => m.id !== material.id);
        if (material.id === "daily") {
          s.practiceSources = s.practiceSources.filter(
            (source) => source !== "textbook",
          );
          s.practiceAllowRepeat = false;
        }
        subscribe();
        close();
      }
      if (key === "tasks") show("tasks");
      if (key === "openJob") openMaterial(value);
      if (key === "saveQuestion") {
        const card = questionSnapshot(target.dataset.questionKind, value);
        if (
          !card ||
          s.words.some((word) => word.questionKey === card.questionKey)
        )
          return;
        s.questionDraft = card;
        show("saveQuestion");
      }
      if (key === "saveCard") {
        if (!s.queryMessages.some((message) => message.card?.id === value))
          return;
        s.saveCardReturn = s.modal === "selectionQuery" || novel.panelActive();
        s.savingCard = value;
        show("saveCard");
      }
      if (key === "queryAgain") {
        root
          .querySelector(".query-composer")
          ?.scrollIntoView({ block: "center" });
        root.querySelector("#query-input")?.focus({ preventScroll: true });
      }
      if (key === "prompt") {
        const input = root.querySelector("#query-input");
        if (!input) return;
        const addition = `${input.value ? "\n" : ""}${target.dataset.question}`;
        if (input.value.length + addition.length > input.maxLength) {
          queryImageError = promptLimitMessage;
          refreshQueryAttachments();
          root.querySelector("#query-input")?.focus();
          return;
        }
        input.setRangeText(
          addition,
          input.value.length,
          input.value.length,
          "end",
        );
        input.dispatchEvent(new Event("input", { bubbles: true }));
        render();
        const updated = root.querySelector("#query-input");
        updated?.focus();
        updated?.setSelectionRange(updated.value.length, updated.value.length);
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
    if (event.target.id === "query-input") {
      s.queryDraft = event.target.value;
      if (queryImageError === promptLimitMessage) {
        queryImageError = "";
        refreshQueryAttachments();
      }
      const button = event.target.form.querySelector('[type="submit"]');
      button.disabled = !canSendQuery();
    }
  });
  root.addEventListener("paste", (event) => {
    if (!event.target.closest('[data-x-form="query"]') || s.modal) return;
    const files = [...(event.clipboardData?.items || [])]
      .filter((item) => item.kind === "file")
      .map((item) => item.getAsFile())
      .filter(Boolean);
    if (!files.length) return;
    event.preventDefault();
    const text = event.clipboardData.getData("text/plain");
    const input = root.querySelector("#query-input");
    if (text && input) {
      const available = Math.max(
        0,
        input.maxLength -
          input.value.length +
          input.selectionEnd -
          input.selectionStart,
      );
      input.setRangeText(
        text.slice(0, available),
        input.selectionStart,
        input.selectionEnd,
        "end",
      );
      s.queryDraft = input.value;
    }
    void addQueryImages(files);
  });
  root.addEventListener("change", (event) => {
    if (event.target.hasAttribute("data-query-file")) {
      const files = [...event.target.files];
      const picker = queryPicker?.input === event.target ? queryPicker : null;
      queryPicker = null;
      event.target.value = "";
      void addQueryImages(files, picker);
      return;
    }
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
        if (!w.cardId && !w.questionKey) {
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
        if (!canSendQuery()) return;
        const extraInput = form.querySelector('[name="explicitContext"]');
        const contextPreview = s.learningDemo.captureContext(null, novel);
        if (
          Math.ceil([...contextPreview.explicit].length / 2) >
          contextPreview.budget
        ) {
          extraInput.setCustomValidity(
            "补充上下文超过当前预算（示例估算），请精简或在查询与上下文设置中提高预算。",
          );
          extraInput.closest("details").open = true;
          extraInput.reportValidity();
          return;
        }
        const images = s.queryImages;
        const result = !images.length ? learningCards.sample(question) : null;
        const context = s.learningDemo.captureContext(null, novel);
        context.attachments = images.map((image) => image.id);
        const saved = s.learningDemo.rememberQuery(
          result ? { ...result, id: id() } : null,
          context,
          question,
        );
        s.queryMessages.push({
          question,
          images,
          ...saved,
          notice: images.length
            ? `已收到 ${images.length} 张图片，图片尚未识别；本地原型不调用模型，因此没有可收藏的学习结果。`
            : "查询仅用于单词、句段翻译、语法和语言习题。当前原型只展示四个内置语言示例；本次未生成学习卡片，也不会回答非语言问题。",
        });
        s.queryDraft = "";
        s.explicitQueryContext = "";
        s.queryImages = [];
        queryImageError = "";
        form.reset();
        render();
        const resultElement = root.querySelector(
          ".query-messages > :last-child",
        );
        resultElement.tabIndex = -1;
        resultElement.focus({ preventScroll: true });
        resultElement.scrollIntoView({ block: "start" });
      }
      if (action === "saveQuestion") {
        const card = s.questionDraft;
        if (
          !card ||
          !questionSnapshot(card.questionOrigin.kind, card.questionOrigin.id)
        )
          return;
        const books = values.getAll("books");
        if (
          books.some(
            (book) =>
              !s.notebooks.some(
                (b) => b.id === book && b.language === card.language,
              ),
          )
        )
          return;
        if (!s.words.some((word) => word.questionKey === card.questionKey)) {
          s.words.unshift({
            ...card,
            id: id(),
            books,
            createdAt: new Date().toISOString(),
          });
        }
        close();
        s.questionDraft = null;
      }
      if (action === "saveCard") {
        const card = s.queryMessages.find(
          (m) => m.card?.id === s.savingCard,
        )?.card;
        if (card && !s.words.some((w) => w.cardId === card.id)) {
          s.words.unshift({
            ...card,
            id: id(),
            cardId: card.id,
            source: card.source || "查询 · 学习卡片示例",
            books: values.getAll("books"),
            createdAt: new Date().toISOString(),
            mastery: "尚无有效证据",
          });
          savedCardFocus = card.id;
        }
        if (s.saveCardReturn && !mobile) show("selectionQuery");
        else close();
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
  function guardMaterialRoute() {
    const fixed = {
      novel: "summer",
      textbookUnits: "daily",
      textbook: "daily",
      textbookPractice: "daily",
      examPrep: "n2",
    };
    if (fixed[s.route]) s.chosenMaterial = fixed[s.route];
    const resourcePage =
      !!fixed[s.route] ||
      ["material", "sampleReader", "sampleTextbook", "sampleExamPrep"].includes(
        s.route,
      );
    const resourceDialog = [
      "materialActions",
      "materialDetails",
      "deleteMaterialConfirm",
    ].includes(s.modal);
    if (
      (resourcePage || resourceDialog) &&
      deletedMaterials.has(s.chosenMaterial)
    ) {
      s.route = "library";
      s.modal = "";
      return true;
    }
    return false;
  }
  function restoreListFocus() {
    if (s.modal) return;
    if (savedCardFocus) {
      const card = root.querySelector(
        `[data-card-id="${CSS.escape(savedCardFocus)}"]`,
      );
      if (card) {
        card.tabIndex = -1;
        card.focus({ preventScroll: true });
      }
      savedCardFocus = "";
    }
    if (collectionFocusFallback) {
      // Successful creation or switching can remove the original empty-state CTA.
      const target =
        root.querySelector(
          `[data-x="${collectionFocusFallback}"][data-id="empty"]`,
        ) ||
        root.querySelector(
          collectionFocusFallback === "add"
            ? `[data-x="entry"][data-id="${CSS.escape(s.selectedWord)}"]`
            : ".book-switcher",
        );
      target?.focus({ preventScroll: true });
      collectionFocusFallback = "";
    }
    if (deletedFocusIndex === null || s.modal) return;
    const rows = root.querySelectorAll(".material-details-button");
    const target =
      rows[Math.min(Math.max(0, deletedFocusIndex), rows.length - 1)] ||
      root.querySelector("#tab-search") ||
      root.querySelector("h1");
    if (target) {
      if (target.tagName === "H1") target.tabIndex = -1;
      target.focus({ preventScroll: true });
    }
    deletedFocusIndex = null;
  }
  return {
    resetQueryImages,
    guardMaterialRoute,
    restoreListFocus,
    querySelection,
    selectionResult,
    readerCanGoBack: () => selectionBackstack.length > 0,
    clearReaderSelection: () => {
      selectionBackstack = [];
      s.readerPanelOpen = false;
      s.readerSource = null;
      s.selectionMessage = null;
      s.novelPrepareReturn = false;
    },
    textbookQuestion,
    questionButton,
    examReview,
    restoreQuestionDraft: (ref) => {
      s.questionDraft = ref ? questionSnapshot(ref.kind, ref.id) : null;
    },
    returnFromSelection,
    restoreSelectionMessage,
    restoreSelectionFocus,
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
