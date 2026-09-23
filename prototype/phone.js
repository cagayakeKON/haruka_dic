"use strict";

// Phone screens share data and actions with desktop, but use their own composition.

function mobileHeader() {
  return `<header class="m-app-header"><a href="#library" class="m-brand" aria-label="Haruka 书库"><span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i><i></i></span>haruka<span>.</span></a><div class="m-header-actions"><span class="m-demo">原型体验</span><button class="m-profile" data-action="settings" aria-label="偏好设置"><span>K</span></button></div></header>`;
}

function renderMobileLibrary() {
  const activeFilters = Number(state.language !== "全部语言") + Number(state.sort !== "default");
  main.innerHTML = `<header class="m-home-header"><div class="m-home-title"><span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i><i></i></span><h1>我的书库</h1></div><div class="m-home-actions"><button class="m-add" data-action="import" aria-label="导入材料">${icon("plus")}</button><button class="m-profile" data-action="settings" aria-label="偏好设置"><span>K</span></button></div></header>
    <section class="m-home-materials" aria-label="书库材料"><div class="m-library-tools"><div class="m-search-row">${searchBox("library-search", "搜索材料名称", state.query)}<button class="m-filter-button ${activeFilters ? "has-filters" : ""}" data-action="mobile-filters" aria-label="筛选与排序${activeFilters ? `，已启用 ${activeFilters} 项` : ""}">${icon("filter")}${activeFilters ? '<i aria-hidden="true"></i>' : ""}</button></div><div class="m-category-tabs" aria-label="材料类型">${["全部材料", "小说", "教材", "试卷", "其他"].map((type) => `<button class="filter-tab ${state.filter === type ? "active" : ""}" data-action="filter" data-value="${type}" aria-label="${type}" aria-pressed="${state.filter === type}">${type === "全部材料" ? "全部" : type}</button>`).join("")}</div></div><div class="m-list-caption"><span id="material-count" role="status" aria-live="polite"></span><span>示例书库</span></div><div id="book-list" class="m-book-list"></div></section>`;
  renderBookList();
}

function renderMobileBooks(books) {
  document.querySelector("#book-list").innerHTML = books.length ? books.map((book) => {
    const exam = book.type === "试卷";
    const tag = exam ? "button" : "a";
    const action = exam ? 'data-action="exam"' : `href="#reader/${book.id}/0"`;
    return `<article class="m-book"><${tag} class="m-book-open" ${action} aria-label="打开 ${escapeHtml(book.title)}"><div class="m-book-jacket">${cover(book)}</div><div class="m-book-copy"><p class="m-book-category">${book.type}<span>·</span>${book.language}</p><h2>${escapeHtml(book.title)}</h2><p class="m-book-subtitle">${escapeHtml(book.subtitle)}</p><div class="m-book-bottom"><span>${exam ? "查看试卷流程" : `${book.chapters.length} 个章节`}<span class="m-format">${book.format}</span></span>${icon("arrow")}</div></div></${tag}></article>`;
  }).join("") : `<div class="empty-state">${icon("search")}<h2>没有找到这份材料</h2><p>换个关键词，或清除筛选再看看。</p><button class="secondary" data-action="reset-filters">清除筛选</button></div>`;
  document.querySelector("#material-count").textContent = `${books.length} 份材料${state.language !== "全部语言" ? ` · ${state.language}` : ""}`;
}

function showMobileFilters() {
  openDialog("筛选与排序", `<fieldset class="m-filter-group"><legend>材料语言</legend><div class="m-radio-chips">${["全部语言", "日语", "英语"].map((language) => `<label><input type="radio" name="mobile-language" value="${language}" ${state.language === language ? "checked" : ""}><span>${language}</span></label>`).join("")}</div></fieldset><fieldset class="m-filter-group"><legend>排列方式</legend>${[["default", "默认顺序", "按书库原有顺序排列"], ["title", "按标题排列", "快速找到熟悉的名字"]].map(([value, label, hint]) => `<label class="m-radio-row"><span>${label}<small>${hint}</small></span><input type="radio" name="mobile-sort" value="${value}" ${state.sort === value ? "checked" : ""}></label>`).join("")}</fieldset><div class="dialog-actions m-filter-actions"><button class="secondary" data-action="mobile-reset-filters">重置</button><button class="primary" data-action="mobile-apply-filters">显示材料</button></div>`, "filters");
}

function renderMobileReader() {
  const book = bookById(state.bookId);
  const chapter = book.chapters[state.chapter];
  main.innerHTML = `<header class="m-reader-header"><a href="#library" class="icon-button" aria-label="返回书库">${icon("back")}</a><div><strong>${escapeHtml(book.title)}</strong><span>${state.chapter + 1} / ${book.chapters.length} 章 · ${book.language}</span></div><button class="icon-button" data-action="about" aria-label="原型说明">${icon("more")}</button></header>
    <article class="m-reader-page"><p class="m-chapter-label">CHAPTER ${String(state.chapter + 1).padStart(2, "0")}</p><h1 lang="${book.language === "日语" ? "ja" : "en"}">${escapeHtml(chapter.title)}</h1><p class="m-reader-byline">Haruka 原创示例</p><div class="m-reading-tip">${icon("spark")}轻点蓝色词语，释义就在手边</div><div class="reading-text" lang="${book.language === "日语" ? "ja" : "en"}">${chapter.paragraphs.map((text, index) => `<p id="paragraph-${index}">${readingParagraph(text, index)}</p>`).join("")}</div><div class="m-chapter-end"><span>本章结束</span><div><button class="secondary" data-action="chapter" data-offset="-1" ${state.chapter === 0 ? "disabled" : ""}>${icon("back")}上一章</button><button class="primary" data-action="chapter" data-offset="1" ${state.chapter === book.chapters.length - 1 ? "disabled" : ""}>下一章${icon("arrow")}</button></div></div></article>
    <nav class="m-reader-dock" aria-label="阅读工具"><button data-action="mobile-chapters">${icon("list")}<span>目录</span></button><button data-action="mobile-appearance">${icon("type")}<span>字号</span></button><button data-action="tts">${icon("sound")}<span>朗读</span></button></nav>`;
  document.body.style.setProperty("--reading-size", `${state.fontSize}px`);
}

function showMobileChapters() {
  const book = bookById(state.bookId);
  openDialog("章节目录", `<p class="m-sheet-subtitle">${escapeHtml(book.title)} · 共 ${book.chapters.length} 章</p><nav class="m-chapter-list" aria-label="章节目录">${book.chapters.map((chapter, index) => `<a href="#reader/${book.id}/${index}" data-action="mobile-chapter-link" class="${index === state.chapter ? "active" : ""}" ${index === state.chapter ? 'aria-current="page"' : ""}><span>${String(index + 1).padStart(2, "0")}</span><strong>${escapeHtml(chapter.title)}</strong>${icon(index === state.chapter ? "check" : "chevron")}</a>`).join("")}</nav>`, "chapters");
}

function showMobileAppearance() {
  openDialog("舒服地读下去", `<p class="m-sheet-subtitle">字号随时调整，阅读位置会保留。</p><div class="m-font-controls"><button class="secondary" data-action="mobile-font" data-offset="-2" aria-label="减小字号" ${state.fontSize <= 16 ? "disabled" : ""}>A−</button><output id="font-value" aria-live="polite">${state.fontSize}<small>px</small></output><button class="secondary" data-action="mobile-font" data-offset="2" aria-label="增大字号" ${state.fontSize >= 22 ? "disabled" : ""}>A＋</button></div><p class="m-font-preview" lang="ja">まだ知らない言葉が、<br>ページの向こうで待っている。</p><div class="dialog-actions"><button class="primary" data-action="close-dialog">完成</button></div>`, "appearance");
}

function renderMobileExplanation() {
  const entry = state.explanation;
  const info = DICTIONARY[entry.text];
  const saved = isSaved(entry);
  const sentence = sourceSentence(entry);
  openDialog("词句释义", `<div class="m-word-heading"><div><h3>${escapeHtml(entry.text)}</h3><p class="pronunciation">${escapeHtml(info.reading)}</p></div><span class="word-type">${info.kind}</span></div><p class="m-word-meaning">${escapeHtml(info.meaning)}</p><div class="m-word-example"><span>在这句话里</span><p>${escapeHtml(sentence)}</p>${sentence === info.example ? `<small>${escapeHtml(info.translation)}</small>` : ""}</div><details class="m-word-details"><summary>词语用法</summary><p>${escapeHtml(info.detail)}</p></details><p class="m-word-source">第 ${entry.chapter + 1} 章 · 预置词条示例</p><div class="dialog-actions m-word-actions"><button class="secondary" data-action="close-dialog">返回原文</button><button class="primary" data-action="save-word" ${saved ? "disabled" : ""}>${icon(saved ? "check" : "bookmark")}${saved ? "已加入收藏" : "收藏这个词"}</button></div>`, "word");
}

function handleMobileAction(action, button, event) {
  if (action === "mobile-filters") showMobileFilters();
  else if (action === "mobile-apply-filters") {
    state.language = dialog.querySelector('[name="mobile-language"]:checked').value;
    state.sort = dialog.querySelector('[name="mobile-sort"]:checked').value;
    dialog.close(); renderLibrary(); main.querySelector('[data-action="mobile-filters"]').focus({ preventScroll: true });
  }
  else if (action === "mobile-reset-filters") {
    dialog.querySelector('[name="mobile-language"][value="全部语言"]').checked = true;
    dialog.querySelector('[name="mobile-sort"][value="default"]').checked = true;
  }
  else if (action === "mobile-chapters") showMobileChapters();
  else if (action === "mobile-chapter-link") {
    if (button.getAttribute("href") === `#reader/${state.bookId}/${state.chapter}`) event.preventDefault();
    dialog.close();
  }
  else if (action === "mobile-appearance") showMobileAppearance();
  else if (action === "mobile-font") {
    state.fontSize = Math.max(16, Math.min(22, state.fontSize + Number(button.dataset.offset)));
    document.body.style.setProperty("--reading-size", `${state.fontSize}px`);
    restoreReadingAnchor(readingAnchor);
    dialog.querySelector("#font-value").innerHTML = `${state.fontSize}<small>px</small>`;
    dialog.querySelector('[data-offset="-2"]').disabled = state.fontSize <= 16;
    dialog.querySelector('[data-offset="2"]').disabled = state.fontSize >= 22;
  }
  else return false;
  return true;
}
