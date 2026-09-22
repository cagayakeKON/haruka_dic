"use strict";

const ICONS = {
  more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
  filter: '<path d="M4 7h16M4 17h16"/><circle cx="9" cy="7" r="3" fill="currentColor" stroke="none"/><circle cx="15" cy="17" r="3" fill="currentColor" stroke="none"/>',
  book: '<path d="M3 4h6a3 3 0 0 1 3 3v14a4 4 0 0 0-4-2H3zM12 7a3 3 0 0 1 3-3h6v15h-5a4 4 0 0 0-4 2"/>',
  bookmark: '<path d="M6 3h12v18l-6-4-6 4z"/>',
  practice: '<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 3h6v4H9zM9 12h6M9 16h4"/>',
  spark: '<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5zM20 2v4m-2-2h4"/>',
  settings: '<path d="m9 3-.7 2.3-2 .9L4 5.8 2 9.2l1.7 1.7v2.2L2 14.8l2 3.4 2.3-.4 2 .9L9 21h4l.7-2.3 2-.9 2.3.4 2-3.4-1.7-1.7v-2.2L20 9.2l-2-3.4-2.3.4-2-.9L13 3z"/><circle cx="11" cy="12" r="3"/>',
  chevron: '<path d="m9 5 7 7-7 7"/>',
  arrow: '<path d="M4 12h16m-6-6 6 6-6 6"/>',
  back: '<path d="M20 12H4m6-6-6 6 6 6"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  close: '<path d="m6 6 12 12M18 6 6 18"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  grid: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
  list: '<path d="M9 5h12M9 12h12M9 19h12M3 5h1M3 12h1M3 19h1"/>',
  check: '<path d="m5 12 4 4L20 5"/>',
  help: '<circle cx="12" cy="12" r="9"/><path d="M9 9a3 3 0 0 1 6 0c0 2-3 2-3 4m0 4h.01"/>',
  sound: '<path d="m11 4-6 5H2v6h3l6 5zM15 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>',
  focus: '<path d="M9 3H3v6m12-6h6v6M3 15v6h6m12-6v6h-6"/>',
  type: '<path d="m3 19 6-14 6 14M5 14h8m3-5h6m-3 0v10"/>',
  upload: '<path d="M4 15v5h16v-5M12 16V3m-5 5 5-5 5 5"/>',
  trash: '<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7"/>',
  link: '<path d="m10 13 4-4M8 16l-1 1a4 4 0 0 1-6-6l5-5a4 4 0 0 1 6 0m4 2 1-1a4 4 0 0 1 6 6l-5 5a4 4 0 0 1-6 0"/>'
};
const icon = (name) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ICONS.book}</svg>`;
const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]));
const state = {
  books: structuredClone(DEMO_BOOKS), collections: structuredClone(INITIAL_COLLECTIONS),
  page: "library", query: "", filter: "全部材料", language: "全部语言", view: "grid", sort: "default",
  collectionQuery: "", collectionFilter: "全部词句", bookId: "cafe", chapter: 0,
  explanation: null, fontSize: 18, focus: false, importMode: "material", nextId: 1
};
const main = document.querySelector("#main");
const dialog = document.querySelector("#dialog");
let dialogTrigger = null;
let explanationTrigger = null;
let toastTimer;
const bookById = (id) => state.books.find((book) => book.id === id);

function toast(message) {
  const element = document.querySelector("#toast");
  clearTimeout(toastTimer);
  element.textContent = message;
  element.classList.add("visible");
  toastTimer = setTimeout(() => element.classList.remove("visible"), 3400);
}

function renderNavigation() {
  const active = state.page === "reader" ? "library" : state.page;
  const desktopNavigation = document.querySelector("#navigation");
  const phoneNavigation = document.querySelector("#mobile-navigation");
  if (isMobile()) {
    desktopNavigation.innerHTML = "";
    phoneNavigation.innerHTML = [
      ["library", "book", "书库", "我的书库"],
      ["collections", "bookmark", "收藏", "词句收藏"]
    ].map(([route, symbol, label, accessibleLabel]) => `<a class="m-nav-item ${route === active ? "active" : ""}" href="#${route}" aria-label="${accessibleLabel}" ${route === active ? 'aria-current="page"' : ""}><span class="m-nav-icon">${icon(symbol)}</span><span>${label}</span></a>`).join("") +
      `<button class="m-nav-item" data-action="planned" data-feature="practice" aria-label="学习练习，查看规划"><span class="m-nav-icon">${icon("practice")}</span><span>练习</span></button><button class="m-nav-item" data-action="planned" data-feature="agent" aria-label="AI 助手，查看规划"><span class="m-nav-icon">${icon("spark")}</span><span>助手</span></button>`;
    return;
  }
  phoneNavigation.innerHTML = "";
  document.querySelector("#navigation").innerHTML = [
    ["library", "book", "我的书库", state.books.length],
    ["collections", "bookmark", "词句收藏", state.collections.length]
  ].map(([route, symbol, label, count]) => `<a class="nav-item ${route === active ? "active" : ""}" href="#${route}" aria-label="${label}" title="${label}" ${route === active ? 'aria-current="page"' : ""}>${icon(symbol)}<span>${label}</span><span class="nav-count">${String(count).padStart(2, "0")}</span></a>`).join("") +
    `<button class="nav-item" data-action="planned" data-feature="practice" aria-label="学习练习，查看规划" title="学习练习 · 规划中">${icon("practice")}<span>学习练习</span><span class="soon">稍后</span></button>
     <button class="nav-item" data-action="planned" data-feature="agent" aria-label="AI 助手，查看规划" title="AI 助手 · 规划中">${icon("spark")}<span>AI 助手</span><span class="soon">稍后</span></button>`;
}

const COVER_ART = {
  cafe: '<path d="M151 30a64 64 0 0 1 64 64v130H87V94a64 64 0 0 1 64-64Z" fill="#f8f5ec"/><path d="M151 34v186M91 104h119M91 164h119" stroke="#a9bfd4" stroke-width="3"/><circle cx="175" cy="74" r="23" fill="#e6bc70"/><path d="M103 192c-4-42 4-64 27-83-1 35-8 62-27 83Z" fill="#87a5c5"/><path d="M107 190c0-28-12-43-29-49 1 21 10 41 29 49Z" fill="#5d83aa"/><ellipse cx="162" cy="229" rx="80" ry="15" fill="#a5b6c8"/><ellipse cx="164" cy="221" rx="39" ry="9" fill="#eeecdf"/><path d="M140 184h46v21c0 23-46 23-46 0Z" fill="#f8f5e9"/><path d="M186 188h8c16 0 16 22-8 22" fill="none" stroke="#f8f5e9" stroke-width="6"/><ellipse cx="163" cy="184" rx="23" ry="5" fill="#b49572"/><path d="M159 171c-11-12 11-12 0-28m15 25c-8-9 8-11 0-19" fill="none" stroke="#8aa1b8" stroke-width="2"/>',
  morning: '<circle cx="252" cy="67" r="37" fill="#d99a6d"/><path d="M164 245 272 118l94 127" fill="#dfcbb2"/><ellipse cx="245" cy="231" rx="82" ry="10" fill="#bfac91"/><path d="M221 152h43v70h-43z" fill="#f8eddb"/><ellipse cx="242" cy="152" rx="21" ry="5" fill="#efe1cb"/><path d="M241 148v-11" stroke="#6c5d46" stroke-width="2"/><path d="M242 114c-12 17-9 24 0 24s11-10 0-24Z" fill="#b97945"/><path d="m178 208 33-10 10 24-33 10z" fill="#8d9eb4"/><path d="M286 217c-20-33 0-69 22-85-1 32-8 63-22 85" fill="#aaa39c"/>',
  walk: '<circle cx="112" cy="78" r="53" fill="#dbcda9"/><path d="M20 229v-95h42v95m4 0V92h51v137m7 0V152h38v77" fill="#62788c"/><path d="M1 233h332" stroke="#9cabb6"/><path d="M80 115h8m12 0h8m-28 23h8m12 0h8m-28 23h8m12 0h8m-28 23h8m12 0h8M31 155h17m-17 24h17m-17 24h17" stroke="#ced9dd" stroke-width="5"/><path d="M24 261c59-30 143-12 194-36" fill="none" stroke="#d6dce2" stroke-width="2"/>',
  notes: '<path d="M0 56h360M0 88h360M0 120h360M0 152h360M0 184h360M0 216h360" stroke="#cac5d8"/><path d="M230 0v265" stroke="#c5bbd5"/><path d="m265 87 13 27 30 4-22 21 5 30-26-14-27 14 6-30-22-21 30-4Z" fill="#9dabc9"/><path d="m252 197 38-13 10 27-38 13Z" fill="#b5aac6"/><circle cx="269" cy="55" r="5" fill="#b3a6c6"/>',
  everyday: '<path d="M249 128c-30 0-50 21-50 47v18l-17 19h33c10 8 22 12 34 12 31 0 54-20 54-48s-23-48-54-48Z" fill="#f2ce9c"/><path d="M229 172h41m-41 14h26" stroke="#b97851" stroke-width="3" stroke-linecap="round"/><path d="m261 29 6 12 13 2-10 10 2 14-12-7-12 7 3-14-10-10 14-2Z" fill="#f1c58f"/><path d="m36 211 78 0" stroke="#f2ce9c" stroke-width="2"/>',
  exam: '<path d="M0 45h360M0 74h360M0 103h360M0 132h360M0 161h360M0 190h360M0 219h360" stroke="#d6dce4"/><path d="M238 58h54v137h-54z" fill="#cfd9e7"/><path d="M249 79h31m-31 20h31m-31 20h22m-22 20h31m-31 20h16" stroke="#8796ab" stroke-width="2"/><circle cx="265" cy="191" r="26" fill="#a4b6d1"/><path d="m252 192 8 8 17-19" stroke="#f5f7fb" stroke-width="3" fill="none"/>'
};
const COVER_TITLES = {
  cafe: "雨あがりの<br>喫茶店", morning: "The art of<br>slow<br>mornings.", walk: "街角を<br>歩けば", notes: "ことば<br>ノート。", everyday: "Everyday,<br>in English.", exam: "日本語読解<strong>練習</strong>"
};
const COVER_CAPTIONS = { cafe: "AFTER THE RAIN", morning: "MAKE ROOM FOR LITTLE THINGS", walk: "A WALK THROUGH THE CITY", notes: "LITTLE WORDS, BIG FEELINGS", everyday: "SMALL TALK. REAL CONNECTIONS.", exam: "READ · THINK · UNDERSTAND" };
function cover(book) {
  return `<div class="cover cover-${book.cover}" aria-hidden="true"><div class="cover-art"><svg viewBox="0 0 340 270" preserveAspectRatio="xMidYMid slice">${COVER_ART[book.cover]}</svg></div><span class="cover-title">${COVER_TITLES[book.cover]}</span><span class="cover-tag">${book.language === "日语" ? "JAPANESE" : "ENGLISH"}</span><span class="cover-caption">${COVER_CAPTIONS[book.cover]}</span></div>`;
}

function searchBox(id, label, value) {
  return `<label class="search">${icon("search")}<input type="search" id="${id}" aria-label="${label}" placeholder="${label}" value="${escapeHtml(value)}" autocomplete="off"></label>`;
}

function renderLibrary() {
  if (isMobile()) { renderMobileLibrary(); return; }
  main.innerHTML = `<section class="editorial-heading"><div><p class="eyebrow">THE PERSONAL LIBRARY</p><h1>我的书库<span class="heading-dot">。</span></h1><p class="heading-description">把喜欢的故事，读成自己的语言。</p></div><div class="heading-right"><p class="editorial-quote">Read what you love.<br>Love what you learn.</p><button class="primary" data-action="import">${icon("plus")}导入材料</button></div></section>
    <section aria-label="书库材料"><div class="library-toolbar"><div class="filter-tabs" aria-label="材料类型">${["全部材料", "小说", "教材", "试卷", "其他"].map((type) => `<button class="filter-tab ${state.filter === type ? "active" : ""}" data-action="filter" data-value="${type}" aria-pressed="${state.filter === type}">${type}${type === "全部材料" ? `<span class="tiny-count">${String(state.books.length).padStart(2, "0")}</span>` : ""}</button>`).join("")}</div>${searchBox("library-search", "搜索你的书库…", state.query)}</div>
    <div class="shelf-meta"><p id="material-count" role="status" aria-live="polite"></p><div class="shelf-tools"><select id="language-filter" aria-label="材料语言">${["全部语言", "日语", "英语"].map((value) => `<option ${value === state.language ? "selected" : ""}>${value}</option>`).join("")}</select><select id="sort-order" aria-label="材料排序"><option value="default" ${state.sort === "default" ? "selected" : ""}>默认排序</option><option value="title" ${state.sort === "title" ? "selected" : ""}>标题排序</option></select><div class="view-toggle" aria-label="书库布局"><button class="icon-button ${state.view === "grid" ? "active" : ""}" data-action="view" data-value="grid" aria-label="封面视图" aria-pressed="${state.view === "grid"}">${icon("grid")}</button><button class="icon-button ${state.view === "list" ? "active" : ""}" data-action="view" data-value="list" aria-label="列表视图" aria-pressed="${state.view === "list"}">${icon("list")}</button></div></div></div>
    <div id="book-list"></div><div class="library-end" aria-hidden="true">Your next little discovery awaits.</div></section>`;
  renderBookList();
}

function renderBookList() {
  let books = state.books.filter((book) => (state.filter === "全部材料" || state.filter === book.type) && (state.language === "全部语言" || state.language === book.language) && `${book.title} ${book.subtitle}`.toLowerCase().includes(state.query.trim().toLowerCase()));
  if (state.sort === "title") books = [...books].sort((a, b) => a.title.localeCompare(b.title, "zh"));
  if (isMobile()) { renderMobileBooks(books); return; }
  const list = document.querySelector("#book-list");
  list.className = state.view === "grid" ? "book-grid" : "book-list";
  list.innerHTML = books.length ? books.map((book) => {
    const tag = book.type === "试卷" ? "button" : "a";
    const action = book.type === "试卷" ? 'data-action="exam"' : `href="#reader/${book.id}/0"`;
    return `<article class="book-card"><${tag} class="book-open" ${action} aria-label="打开 ${escapeHtml(book.title)}">${cover(book)}<div class="book-info"><div class="book-kicker"><span>${book.type}<span class="small-dot">•</span>${book.language}</span><span>${book.format}</span></div><h2>${escapeHtml(book.title)}</h2><div class="book-detail-line"><p>${escapeHtml(book.subtitle)}</p>${icon("arrow")}</div></div></${tag}></article>`;
  }).join("") : `<div class="empty-state">${icon("search")}<h2>还没有找到这份材料</h2><p>换个关键词，或清除筛选再看看。</p><button class="secondary" data-action="reset-filters">清除筛选</button></div>`;
  document.querySelector("#material-count").innerHTML = `<span class="material-count">${String(books.length).padStart(2, "0")} 份材料</span> / 共 ${state.books.length} 份`;
}

function readingParagraph(text, paragraph) {
  let result = "";
  let cursor = 0;
  for (const match of text.matchAll(/木漏れ日|穏やか|\bwindow\b/g)) {
    result += escapeHtml(text.slice(cursor, match.index));
    const start = [...text.slice(0, match.index)].length;
    result += `<button class="word" data-action="word" data-word="${escapeHtml(match[0])}" data-paragraph="${paragraph}" data-start="${start}" aria-label="解释 ${escapeHtml(match[0])}">${escapeHtml(match[0])}</button>`;
    cursor = match.index + match[0].length;
  }
  return result + escapeHtml(text.slice(cursor));
}

function renderReader() {
  if (isMobile()) { renderMobileReader(); return; }
  const book = bookById(state.bookId);
  const chapter = book.chapters[state.chapter];
  main.innerHTML = `<div class="reader-toolbar"><a href="#library" class="text-button">${icon("back")}返回书库</a><div class="reader-controls"><button class="icon-button" data-action="font" aria-label="调整阅读字号" title="调整字号">${icon("type")}</button><button class="icon-button ${state.focus ? "active" : ""}" data-action="focus" aria-label="专注阅读" aria-pressed="${state.focus}" title="专注阅读">${icon("focus")}</button><button class="secondary" data-action="tts">${icon("sound")}朗读</button></div></div>
    <div class="reader-layout" id="reader-layout"><nav class="contents" aria-label="章节目录"><h2>CONTENTS</h2>${book.chapters.map((item, index) => `<a href="#reader/${book.id}/${index}" class="chapter-link ${index === state.chapter ? "active" : ""}" ${index === state.chapter ? 'aria-current="page"' : ""}><span>${String(index + 1).padStart(2, "0")}</span><span>${escapeHtml(item.title)}</span></a>`).join("")}</nav>
    <article class="reader-body"><p class="chapter-number">CHAPTER ${String(state.chapter + 1).padStart(2, "0")}</p><h1 lang="${book.language === "日语" ? "ja" : "en"}">${escapeHtml(chapter.title)}</h1><p class="reader-byline">${escapeHtml(book.title)} · Haruka 原创示例</p><div class="reading-text" lang="${book.language === "日语" ? "ja" : "en"}">${chapter.paragraphs.map((text, index) => `<p id="paragraph-${index}">${readingParagraph(text, index)}</p>`).join("")}</div><p class="reading-hint">点击浅蓝色词语，查看释义并收藏。当前仅提供预置词条。</p><div class="chapter-navigation"><button class="text-button" data-action="chapter" data-offset="-1" ${state.chapter === 0 ? "disabled" : ""}>${icon("back")}上一章</button><span>${state.chapter + 1} / ${book.chapters.length}</span><button class="text-button" data-action="chapter" data-offset="1" ${state.chapter === book.chapters.length - 1 ? "disabled" : ""}>下一章${icon("arrow")}</button></div></article><aside id="explanation" class="explanation" aria-label="词句解释" hidden></aside></div>`;
  document.body.style.setProperty("--reading-size", `${state.fontSize}px`);
  document.body.classList.toggle("focus-mode", state.focus);
}

function selectionStart(entry) {
  if (entry.start !== undefined) return entry.start;
  const text = bookById(entry.bookId).chapters[entry.chapter].paragraphs[entry.paragraph];
  return [...text.slice(0, text.indexOf(entry.text))].length;
}
function sourceSentence(entry) {
  const text = bookById(entry.bookId).chapters[entry.chapter].paragraphs[entry.paragraph];
  const offset = [...text].slice(0, selectionStart(entry)).join("").length;
  const sentence = [...text.matchAll(/[^。.!?！？]+[。.!?！？]?/gu)].find((match) => match.index <= offset && match.index + match[0].length > offset);
  return sentence ? sentence[0].trim() : text;
}
function isSaved(entry) {
  return state.collections.some((saved) => saved.bookId === entry.bookId && saved.chapter === entry.chapter && saved.paragraph === entry.paragraph && saved.text === entry.text && selectionStart(saved) === entry.start);
}
function renderExplanation() {
  if (isMobile()) { renderMobileExplanation(); return; }
  const entry = state.explanation;
  const info = DICTIONARY[entry.text];
  const panel = document.querySelector("#explanation");
  document.querySelector("#reader-layout").classList.add("with-explanation");
  panel.hidden = false;
  panel.innerHTML = `<div class="explanation-heading"><span>词句解释 · 预置示例</span><button class="icon-button" data-action="close-explanation" aria-label="关闭词句解释">${icon("close")}</button></div><h2>${escapeHtml(entry.text)}</h2><p class="pronunciation">${escapeHtml(info.reading)}</p><span class="word-type">${info.kind}</span><p class="meaning">${escapeHtml(info.meaning)}</p><p class="word-detail">${escapeHtml(info.detail)}</p><div class="word-example">${escapeHtml(info.example)}<small>${escapeHtml(info.translation)}</small></div><button class="primary" data-action="save-word" ${isSaved(entry) ? "disabled" : ""}>${icon(isSaved(entry) ? "check" : "bookmark")}${isSaved(entry) ? "已加入收藏" : "收藏这个词"}</button><span class="explanation-source">${escapeHtml(bookById(entry.bookId).title)} · 第 ${entry.chapter + 1} 章</span>`;
}
function closeExplanation() {
  state.explanation = null;
  if (isMobile()) { if (dialog.open) dialog.close(); return; }
  document.querySelector("#explanation").hidden = true;
  document.querySelector("#reader-layout").classList.remove("with-explanation");
  if (explanationTrigger?.isConnected) explanationTrigger.focus({ preventScroll: true });
}

function renderCollections() {
  if (isMobile()) { renderMobileCollections(); return; }
  main.innerHTML = `<section class="editorial-heading"><div><p class="eyebrow">WORDS WORTH KEEPING</p><h1>词句收藏<span class="heading-dot">。</span></h1><p class="heading-description">让偶然遇见的词，成为表达的一部分。</p></div><div class="heading-right"><p class="collection-count"><strong>${String(state.collections.length).padStart(2, "0")}</strong> 条收藏</p></div></section><section aria-label="收藏词句"><div class="library-toolbar"><div class="filter-tabs" aria-label="收藏筛选">${["全部词句", "未掌握", "已掌握"].map((type) => `<button class="filter-tab ${state.collectionFilter === type ? "active" : ""}" data-action="collection-filter" data-value="${type}" aria-pressed="${state.collectionFilter === type}">${type}</button>`).join("")}</div>${searchBox("collection-search", "搜索词句或释义…", state.collectionQuery)}</div><div id="collection-list" class="collection-grid"></div></section>`;
  renderCollectionList();
}
function renderCollectionList() {
  const entries = state.collections.filter((entry) => (state.collectionFilter === "全部词句" || (state.collectionFilter === "已掌握" ? entry.mastered : !entry.mastered)) && `${entry.text} ${DICTIONARY[entry.text].meaning}`.toLowerCase().includes(state.collectionQuery.trim().toLowerCase()));
  if (isMobile()) { renderMobileCollectionList(entries); return; }
  document.querySelector("#collection-list").innerHTML = entries.length ? entries.map((entry) => {
    const info = DICTIONARY[entry.text];
    const book = bookById(entry.bookId);
    return `<article class="vocab-card"><div class="vocab-top"><span>${book.language} / ${info.kind}</span>${icon("bookmark")}</div><h2>${escapeHtml(entry.text)}</h2><p class="pronunciation">${escapeHtml(info.reading)}</p><p class="meaning">${escapeHtml(info.meaning)}</p><a href="#source/${entry.id}" class="source-link" aria-label="回到 ${escapeHtml(entry.text)} 的原文">${icon("link")}${escapeHtml(book.title)} · 第 ${entry.chapter + 1} 章</a><div class="vocab-bottom"><button class="mastery ${entry.mastered ? "is-mastered" : ""}" data-action="mastery" data-id="${entry.id}" aria-pressed="${entry.mastered}">${icon("check")}${entry.mastered ? "已掌握" : "标记已掌握"}</button><button class="icon-button" data-action="remove" data-id="${entry.id}" aria-label="移除收藏 ${escapeHtml(entry.text)}">${icon("trash")}</button></div></article>`;
  }).join("") : `<div class="empty-state">${icon("bookmark")}<h2>这里还没有词句</h2><p>试试其他筛选，或去书里发现一个新词。</p><a class="secondary" href="#library">去书库看看 ${icon("arrow")}</a></div>`;
}

function openDialog(title, body, kind = "info") {
  if (!dialog.open) dialogTrigger = document.activeElement;
  dialog.dataset.kind = kind;
  dialog.classList.toggle("mobile-sheet", isMobile());
  dialog.innerHTML = `<div class="dialog-heading"><h2 id="dialog-title" tabindex="-1">${title}</h2><button class="icon-button" data-action="close-dialog" aria-label="关闭弹窗">${icon("close")}</button></div>${body}`;
  if (!dialog.open) dialog.showModal();
  document.body.classList.add("dialog-open");
  dialog.querySelector("#dialog-title").focus();
}
function infoDialog(title, text, note = "") {
  openDialog(title, `<p class="dialog-description">${text}</p>${note ? `<p class="info-note">${note}</p>` : ""}<div class="dialog-actions"><button class="primary" data-action="close-dialog">知道了</button></div>`);
}
function renderImport() {
  openDialog("把喜欢的内容，放进书库", `<p class="dialog-description">选择学习方式，体验材料进入书库的流程。</p><div class="mode-options"><button class="mode-option ${state.importMode === "material" ? "active" : ""}" data-action="import-mode" data-value="material" aria-pressed="${state.importMode === "material"}">${icon("book")}学习材料<small>阅读、解释与收藏</small></button><button class="mode-option ${state.importMode === "exam" ? "active" : ""}" data-action="import-mode" data-value="exam" aria-pressed="${state.importMode === "exam"}">${icon("practice")}试卷模式<small>整卷作答，交卷后复盘</small></button></div><div class="sample-upload">${icon(state.importMode === "material" ? "upload" : "practice")}<p>${state.importMode === "material" ? "旅のはじまり.md" : "试卷需要先校对题目"}</p><small>${state.importMode === "material" ? "本轮使用预置示例，无需上传文件" : "本轮展示流程说明，暂未实现答题与评分"}</small></div><div class="dialog-actions"><button class="secondary" data-action="close-dialog">取消</button><button class="primary" data-action="confirm-import">${state.importMode === "material" ? "添加示例材料" : "查看试卷流程"}${icon("arrow")}</button></div>`);
}

function setFilterButtons(action, value) {
  main.querySelectorAll(`[data-action="${action}"]`).forEach((button) => {
    button.classList.toggle("active", button.dataset.value === value);
    button.setAttribute("aria-pressed", String(button.dataset.value === value));
  });
}

document.addEventListener("click", (event) => {
  const skip = event.target.closest(".skip-link");
  if (skip) { event.preventDefault(); main.focus(); main.scrollIntoView(); return; }
  const button = event.target.closest("[data-action]");
  if (!button || button.disabled) return;
  const { action, value, id } = button.dataset;
  if (action.startsWith("mobile-") && handleMobileAction(action, button, event)) return;
  if (action === "filter") { state.filter = value; setFilterButtons(action, value); renderBookList(); }
  else if (action === "view") { state.view = value; setFilterButtons(action, value); renderBookList(); }
  else if (action === "reset-filters") { state.query = ""; state.filter = "全部材料"; state.language = "全部语言"; renderLibrary(); document.querySelector("#library-search").focus(); }
  else if (action === "collection-filter") { state.collectionFilter = value; setFilterButtons(action, value); renderCollectionList(); }
  else if (action === "import") { state.importMode = "material"; renderImport(); }
  else if (action === "import-mode") { state.importMode = value; renderImport(); dialog.querySelector(`[data-value="${value}"]`).focus(); }
  else if (action === "confirm-import") {
    if (state.importMode === "exam") { showExamInfo(); return; }
    if (bookById("journey")) { toast("这份示例已在书库中，可以直接打开。"); dialog.close(); return; }
    state.books.unshift({ id: "journey", title: "旅のはじまり", subtitle: "每段旅程，都从一步开始", language: "日语", type: "其他", format: "MD", cover: "notes", number: "07", chapters: [{ title: "小さな一歩", paragraphs: ["新しいノートを開いた。最初のページは、まだ何も書かれていない。何から始めようか、少しだけ迷った。", "窓の外では、木漏れ日が揺れている。私はペンを取って、今日覚えた言葉を一つ書いた。旅のはじまりは、こんなに小さくてもいい。"] }] });
    state.query = ""; state.filter = "全部材料"; state.language = "全部语言";
    dialog.close(); renderNavigation();
    if (state.page === "library") { renderLibrary(); main.querySelector('[href="#reader/journey/0"]').focus(); }
    toast("示例已加入书库 · 刷新后重置");
  }
  else if (action === "close-dialog") dialog.close();
  else if (action === "exam") showExamInfo();
  else if (action === "planned") infoDialog(value || (button.dataset.feature === "practice" ? "学习练习" : "AI 助手"), button.dataset.feature === "practice" ? "这里将把收藏的词句变成练习，保留每一道题的原文出处。本轮先确认书库、阅读和收藏的视觉与操作。" : "这里将支持围绕个人材料追问、解释和生成学习卡片。本轮尚未接入 AI 服务。", "这是规划入口，目前不会发起模型调用。");
  else if (action === "about") infoDialog("你好，这里是 Haruka。", "白色与浅灰底，搭配蓝色 Primary 和杂志式排版。这是一份独立 HTML 交互原型，可以浏览材料、阅读示例与收藏词语。", "所有材料均为原创示例；数据只在当前页面内存中保存，刷新后重置。尚未接入账号、真实文件解析、AI、TTS 或后端服务。");
  else if (action === "settings") openDialog("偏好设置", `<p class="dialog-description">找到适合自己的阅读节奏。</p><label class="setting-row">阅读字号<select id="font-setting" aria-label="阅读字号">${[16, 18, 20, 22].map((size) => `<option value="${size}" ${size === state.fontSize ? "selected" : ""}>${size} px</option>`).join("")}</select></label><div class="setting-row"><span>界面风格</span><span>白色 · 蓝色 Primary</span></div><p class="info-note">本轮不接收真实 API Key。阅读偏好仅保留在当前页面。</p><div class="dialog-actions"><button class="primary" data-action="close-dialog">完成</button></div>`);
  else if (action === "tts") infoDialog("让文字，有声音", "正式版本将使用你配置的 Gemini TTS 或 OpenRouter TTS 朗读材料。", "当前原型尚未连接云端朗读服务，不会播放音频或使用系统 TTS。");
  else if (action === "word") {
    explanationTrigger = button;
    state.explanation = { text: button.dataset.word, paragraph: Number(button.dataset.paragraph), start: Number(button.dataset.start), bookId: state.bookId, chapter: state.chapter };
    state.focus = false; document.body.classList.remove("focus-mode");
    const focusButton = main.querySelector('[data-action="focus"]');
    if (focusButton) { focusButton.setAttribute("aria-pressed", "false"); focusButton.classList.remove("active"); }
    renderExplanation();
    if (!isMobile()) { const panel = document.querySelector("#explanation"); panel.tabIndex = -1; panel.focus({ preventScroll: true }); }
  }
  else if (action === "close-explanation") closeExplanation();
  else if (action === "save-word") {
    if (!state.explanation || isSaved(state.explanation)) return;
    state.collections.unshift({ ...state.explanation, id: `saved-${state.nextId++}`, mastered: false });
    renderNavigation(); renderExplanation();
    (isMobile() ? dialog.querySelector('[data-action="close-dialog"]') : document.querySelector('[data-action="close-explanation"]')).focus({ preventScroll: true });
    toast("已收藏这个词，并保留原文出处。");
  }
  else if (action === "font") {
    state.fontSize = state.fontSize >= 22 ? 16 : state.fontSize + 2;
    document.body.style.setProperty("--reading-size", `${state.fontSize}px`); toast(`阅读字号：${state.fontSize} px`);
  }
  else if (action === "focus") {
    if (state.explanation) closeExplanation();
    state.focus = !state.focus; document.body.classList.toggle("focus-mode", state.focus);
    button.setAttribute("aria-pressed", String(state.focus)); button.classList.toggle("active", state.focus); button.focus();
  }
  else if (action === "chapter") {
    const next = state.chapter + Number(button.dataset.offset);
    if (next >= 0 && next < bookById(state.bookId).chapters.length) location.hash = `reader/${state.bookId}/${next}`;
  }
  else if (action === "mastery") {
    const entry = state.collections.find((item) => item.id === id); if (!entry) return;
    entry.mastered = !entry.mastered; renderCollectionList();
    const replacement = main.querySelector(`[data-action="mastery"][data-id="${id}"]`);
    (replacement || main.querySelector('[data-action="collection-filter"].active')).focus({ preventScroll: true });
    toast(entry.mastered ? "已标记为掌握。" : "已移回待学习词句。");
  }
  else if (action === "remove") {
    const entry = state.collections.find((item) => item.id === id); if (!entry) return;
    openDialog("移除这个词？", `<p class="dialog-description">将「${escapeHtml(entry.text)}」从本次示例收藏中移除。原文会保留，你可以再次收藏。</p><div class="dialog-actions"><button class="secondary" data-action="close-dialog">保留</button><button class="primary" data-action="confirm-remove" data-id="${id}">确认移除</button></div>`);
  }
  else if (action === "confirm-remove") {
    state.collections = state.collections.filter((entry) => entry.id !== id); dialog.close(); renderNavigation(); renderCollections();
    document.querySelector("#collection-search").focus(); toast("已从本次收藏中移除。");
  }
});

function showExamInfo() {
  infoDialog("试卷，按自己的节奏练习", "正式流程：导入试卷 → 校对题目与分值 → 整卷作答 → 确认交卷 → 评分与复盘。答题期间不提前展示答案，交卷后再看解析。", "本轮只展示试卷入口。真实文件格式范围仍待确认，考试保存、计时与 AI 评分尚未实现。");
}

document.addEventListener("input", (event) => {
  if (event.target.id === "library-search") { state.query = event.target.value; renderBookList(); }
  if (event.target.id === "collection-search") { state.collectionQuery = event.target.value; renderCollectionList(); }
});
document.addEventListener("change", (event) => {
  if (event.target.id === "language-filter") { state.language = event.target.value; renderBookList(); }
  if (event.target.id === "sort-order") { state.sort = event.target.value; renderBookList(); }
  if (event.target.id === "font-setting") { state.fontSize = Number(event.target.value); document.body.style.setProperty("--reading-size", `${state.fontSize}px`); }
});
dialog.addEventListener("close", () => {
  if (dialog.open) return;
  document.body.classList.remove("dialog-open");
  if (dialog.dataset.kind === "word") state.explanation = null;
  if (dialogTrigger?.isConnected) dialogTrigger.focus({ preventScroll: true });
});
document.addEventListener("keydown", (event) => { if (event.key === "Escape" && !dialog.open && state.explanation && state.page === "reader") closeExplanation(); });

function route() {
  const parts = location.hash.slice(1).split("/");
  const source = parts[0] === "source" ? state.collections.find((entry) => entry.id === parts[1]) : null;
  let book = parts[0] === "reader" ? bookById(parts[1]) : source ? bookById(source.bookId) : null;
  if (book && !book.chapters.length) book = null;
  state.page = book ? "reader" : parts[0] === "collections" ? "collections" : "library";
  document.body.dataset.page = state.page;
  state.explanation = null; state.focus = false; document.body.classList.remove("focus-mode");
  if (dialog.open) dialog.close();
  if (book) {
    state.bookId = book.id;
    const requested = source ? source.chapter : Number(parts[2]);
    state.chapter = Number.isInteger(requested) && requested >= 0 && requested < book.chapters.length ? requested : 0;
    renderReader();
  } else if (state.page === "collections") renderCollections();
  else renderLibrary();
  renderNavigation();
  const title = state.page === "reader" ? book.title : state.page === "collections" ? "词句收藏" : "书库";
  document.querySelector("#breadcrumb").textContent = title;
  document.title = `Haruka · ${title}`;
  main.focus({ preventScroll: true }); window.scrollTo(0, 0);
  if (source) {
    const paragraph = document.querySelector(`#paragraph-${source.paragraph}`);
    if (paragraph) {
      paragraph.classList.add("source-highlight"); paragraph.tabIndex = -1;
      paragraph.focus({ preventScroll: true }); paragraph.scrollIntoView({ block: "center" });
      toast("已回到这个词的原文出处。");
    }
  } else if (parts[0] === "source") toast("这条示例收藏已不存在，请重新选择。");
  renderedMobile = isMobile(); layoutWidth = window.innerWidth;
  rememberReadingAnchor();
}

// Keep a content position rather than a scroll offset: phone and desktop have different line lengths.
let renderedMobile = isMobile();
let layoutWidth = window.innerWidth;
let readingAnchor = null;
let restoringAnchor = false;
let reflowFrame = 0;
function readingTop() {
  return isMobile() ? (main.querySelector(".m-reader-header")?.getBoundingClientRect().bottom || 62) + 18 : 100;
}
function rememberReadingAnchor() {
  if (state.page !== "reader") { readingAnchor = null; return; }
  if (restoringAnchor || dialog.open || layoutWidth !== window.innerWidth || renderedMobile !== isMobile()) return;
  const top = readingTop();
  const paragraphs = [...main.querySelectorAll(".reading-text p")];
  const paragraph = paragraphs.find((item) => item.getBoundingClientRect().bottom > top) || paragraphs.at(-1);
  if (!paragraph) return;
  const rect = paragraph.getBoundingClientRect();
  readingAnchor = { bookId: state.bookId, chapter: state.chapter, id: paragraph.id, fraction: Math.max(0, Math.min(1, (top - rect.top) / rect.height)), atTop: window.scrollY < 5 };
}
function restoreReadingAnchor(anchor) {
  if (!anchor || anchor.bookId !== state.bookId || anchor.chapter !== state.chapter) return;
  const paragraph = document.getElementById(anchor.id);
  if (!paragraph) return;
  restoringAnchor = true;
  const rect = paragraph.getBoundingClientRect();
  window.scrollTo(0, anchor.atTop ? 0 : window.scrollY + rect.top + rect.height * anchor.fraction - readingTop());
  // Retain the requested paragraph if the shorter desktop page clamps the scroll position.
  readingAnchor = anchor;
  requestAnimationFrame(() => requestAnimationFrame(() => { restoringAnchor = false; }));
}
function reflowLayout() {
  cancelAnimationFrame(reflowFrame);
  reflowFrame = requestAnimationFrame(() => {
    const modeChanged = renderedMobile !== isMobile();
    if (!modeChanged && layoutWidth === window.innerWidth) return;
    const anchor = readingAnchor;
    if (modeChanged) {
      if (dialog.open) dialog.close();
      state.explanation = null; state.focus = false;
      document.body.classList.remove("focus-mode");
      if (state.page === "reader") renderReader();
      else if (state.page === "collections") renderCollections();
      else renderLibrary();
      renderNavigation();
      main.focus({ preventScroll: true });
    }
    renderedMobile = isMobile(); layoutWidth = window.innerWidth;
    if (state.page === "reader") restoreReadingAnchor(anchor);
  });
}

document.querySelectorAll("[data-icon]").forEach((element) => { element.innerHTML = icon(element.dataset.icon); });
window.addEventListener("hashchange", route);
window.addEventListener("scroll", rememberReadingAnchor, { passive: true });
window.addEventListener("resize", reflowLayout);
mobileMedia.addEventListener("change", reflowLayout);
route();
