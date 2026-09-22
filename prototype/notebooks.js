"use strict";

const notebookState = {
  books: structuredClone(NOTEBOOK_DEMO), scope: "all", query: "", filter: "all", language: "全部语言", tag: "", source: "", sort: "added",
  selecting: false, selected: new Set(), homeLanguage: "日语", nextId: 1, session: null, sessions: [], opportunities: new Map(), deletedHistory: [], readingEntry: null
};
const notebookPages = new Set(["notebooks", "words", "word", "review", "study-history"]);
const masteryLabels = { new: "新词", learning: "学习中", mastered: "已掌握", relearning: "需重学" };
const wordById = (id) => state.collections.find((word) => word.id === id);
const notebookById = (id) => notebookState.books.find((book) => book.id === id);
const readyWord = (word) => Boolean(word.meaning.trim());
const dueWord = (word) => word.studyControl === "active" && word.due !== null && word.due <= 0;
const dueLabel = (word) => word.studyControl === "suspended" ? "已暂停复习" : !readyWord(word) ? "资料待补全" : word.due === null ? "尚未学习" : word.due <= 0 ? "今天复习" : word.due === 1 ? "明天复习" : `${word.due} 天后复习`;
const statusBadge = (word) => `<span class="nb-status ${word.status}">${masteryLabels[word.status]}</span>`;
const nbButton = (action, label, symbol, className = "secondary", data = "") => `<button class="${className}" data-action="nb-${action}" ${data}>${symbol ? icon(symbol) : ""}${label}</button>`;
const nbEmpty = (title, text, action = "") => `<div class="nb-empty">${icon("book")}<h2>${title}</h2><p>${text}</p>${action}</div>`;
function nbHeader(title, subtitle = "", back = "", actions = "") {
  return `<header class="nb-header">${back ? `<a class="icon-button" href="${back}" aria-label="返回">${icon("back")}</a>` : '<span class="nb-brand-dot" aria-hidden="true"></span>'}<div class="nb-header-copy"><h1>${escapeHtml(title)}</h1>${subtitle ? `<p>${escapeHtml(subtitle)}</p>` : ""}</div><div class="nb-header-actions">${actions}</div></header>`;
}
function scopedWords(scope = notebookState.scope) {
  return state.collections.filter((word) => scope === "all" || (scope === "ungrouped" ? !word.notebookIds.length : scope === "weak" ? word.errorCount > 0 : scope === "paused" ? word.studyControl === "suspended" : word.notebookIds.includes(scope)));
}
function filteredWords() {
  const n = notebookState;
  let words = scopedWords().filter((word) => (n.language === "全部语言" || word.language === n.language) && (!n.tag || word.tags.includes(n.tag)) && (!n.source || word.origin === n.source) && `${word.text} ${word.reading} ${word.meaning} ${word.notes} ${word.tags.join(" ")} ${word.sourceTitle}`.toLocaleLowerCase().includes(n.query.trim().toLocaleLowerCase()));
  words = words.filter((word) => n.filter === "all" || (n.filter === "due" ? dueWord(word) : n.filter === "unmastered" ? word.status !== "mastered" : n.filter === "incomplete" ? !readyWord(word) : word.status === n.filter));
  if (n.sort === "word") words.sort((a, b) => a.text.localeCompare(b.text) || a.id.localeCompare(b.id));
  if (n.sort === "due") words.sort((a, b) => (a.due ?? 999) - (b.due ?? 999) || a.id.localeCompare(b.id));
  if (n.sort === "errors") words.sort((a, b) => b.errorCount - a.errorCount || a.id.localeCompare(b.id));
  if (n.sort === "recent") words.sort((a, b) => (b.records.at(-1)?.date || "").localeCompare(a.records.at(-1)?.date || "") || a.id.localeCompare(b.id));
  return words;
}
function scopeName() {
  return ({ all: "全部单词", ungrouped: "未分组", weak: "常错词", paused: "已暂停" })[notebookState.scope] || notebookById(notebookState.scope)?.name || "全部单词";
}
function renderNotebooksHome() {
  const words = state.collections.filter((word) => word.language === notebookState.homeLanguage);
  const due = words.filter((word) => dueWord(word) && readyWord(word)).length;
  const fresh = words.filter((word) => word.status === "new" && word.studyControl === "active" && readyWord(word)).length;
  main.innerHTML = `<div class="nb-page nb-home">${nbHeader("单词本", "把遇见的词，变成会用的表达。", "", nbButton("home-menu", "", "more", "icon-button", 'aria-label="单词本更多操作"') + nbButton("add-menu", "", "plus", "nb-add-button", 'aria-label="添加单词或单词本"'))}
    <section class="nb-today"><div class="nb-today-top"><span>每日复习</span><label class="nb-language"><span class="sr-only">今日目标语</span><select id="nb-home-language"><option ${notebookState.homeLanguage === "日语" ? "selected" : ""}>日语</option><option ${notebookState.homeLanguage === "英语" ? "selected" : ""}>英语</option></select></label></div><div class="nb-today-numbers"><div><strong>${due}</strong><span>待复习</span></div><i></i><div><strong>${fresh}</strong><span>可学新词</span></div><span class="nb-today-art" aria-hidden="true">${icon("book")}</span></div><div class="nb-today-actions">${nbButton("plan", notebookState.session && !notebookState.session.finished ? "继续本次复习" : "开始今日复习", "arrow", "primary") }<a href="#study-history">学习记录 ${icon("chevron")}</a></div></section>
    <nav class="nb-system-views" aria-label="单词快捷筛选">${[["all", "全部", state.collections.length], ["ungrouped", "未分组", scopedWords("ungrouped").length], ["weak", "常错", scopedWords("weak").length], ["paused", "暂停", scopedWords("paused").length]].map(([id, name, count]) => `<a href="#notebook/${id}"><strong>${count}</strong><span>${name}</span></a>`).join("")}</nav>
    <div class="nb-section-heading"><h2>我的单词本 <span>${notebookState.books.length}</span></h2>${nbButton("create-book", "新建", "plus", "text-button")}</div><div class="nb-books">${notebookState.books.map((book) => { const entries = scopedWords(book.id); const mastered = entries.filter((w) => w.status === "mastered").length; return `<a class="nb-book-card" href="#notebook/${book.id}"><div class="nb-notebook-cover ${book.color}">${icon("book")}<span>${book.language === "日语" ? "あ" : "Aa"}</span></div><div class="nb-book-copy"><div><h3>${escapeHtml(book.name)}</h3><span class="nb-language-tag">${book.language}</span></div><p>${entries.length} 个单词 <span>·</span> ${entries.filter((w) => dueWord(w) && readyWord(w)).length} 个待复习</p><div class="nb-progress" role="meter" aria-label="${escapeHtml(book.name)}已掌握比例" aria-valuenow="${mastered}" aria-valuemin="0" aria-valuemax="${Math.max(1, entries.length)}"><span style="width:${entries.length ? mastered / entries.length * 100 : 0}%"></span></div><small>已掌握 ${mastered} / ${entries.length}</small></div>${icon("chevron")}</a>`; }).join("") || nbEmpty("创建第一本单词本", "按目标或兴趣整理；同一个词可以加入多本。", nbButton("create-book", "新建单词本", "plus", "primary"))}</div>
    <p class="nb-demo-note">本次使用示例数据，操作仅在当前页面保留。<br>掌握状态来自练习证据，不能手动勾选。</p></div>`;
}
function notebookRail() {
  return `<aside class="nb-rail"><a href="#collections" class="text-button">${icon("back")}我的单词本</a><p>系统视图</p>${[["all", "全部单词"], ["ungrouped", "未分组"], ["weak", "常错词"], ["paused", "已暂停"]].map(([id, label]) => `<a class="${notebookState.scope === id ? "active" : ""}" href="#notebook/${id}">${label}<span>${scopedWords(id).length}</span></a>`).join("")}<p>我的单词本</p>${notebookState.books.map((book) => `<a class="${notebookState.scope === book.id ? "active" : ""}" href="#notebook/${book.id}">${escapeHtml(book.name)}<span>${scopedWords(book.id).length}</span></a>`).join("")}${nbButton("create-book", "新建单词本", "plus", "text-button")}</aside>`;
}
function renderNotebookList() {
  const book = notebookById(notebookState.scope);
  const words = scopedWords();
  const mastered = words.filter((word) => word.status === "mastered").length;
  main.innerHTML = `<div class="nb-workspace">${isMobile() ? "" : notebookRail()}<div class="nb-page nb-word-list">${nbHeader(scopeName(), `${words.length} 个单词 · 已掌握 ${mastered} · 未掌握 ${words.length - mastered}`, isMobile() ? "#collections" : "", nbButton("book-menu", "", "more", "icon-button", 'aria-label="词列表更多操作"'))}
    ${book?.description ? `<p class="nb-book-description">${escapeHtml(book.description)}</p>` : ""}<div class="nb-list-actions">${nbButton("plan", "复习这些词", "practice", "primary", 'data-scope="current"')}${nbButton("add-word", "添加单词", "plus")}</div>
    <div class="nb-list-tools"><div class="nb-search-row">${searchBox("nb-word-search", "搜索单词、释义或笔记", notebookState.query)}${nbButton("filters", "", "filter", "icon-button", 'aria-label="单词筛选与排序"')}</div><div class="nb-filter-tabs" aria-label="学习状态筛选">${[["all", "全部"], ["due", "待复习"], ["new", "新词"], ["unmastered", "未掌握"], ["mastered", "已掌握"]].map(([value, label]) => `<button data-action="nb-filter" data-value="${value}" aria-pressed="${notebookState.filter === value}" class="${notebookState.filter === value ? "active" : ""}">${label}</button>`).join("")}</div></div><div class="nb-list-meta"><span id="nb-result-count" role="status"></span>${nbButton("select-mode", notebookState.selecting ? "完成选择" : "批量整理", "check", "text-button")}</div><div id="nb-word-rows"></div><div id="nb-batch-bar"></div></div></div>`;
  renderNotebookRows();
}
function renderNotebookRows() {
  const words = filteredWords();
  const container = document.querySelector("#nb-word-rows");
  if (!container) return;
  container.innerHTML = words.length ? words.map((word) => `<article class="nb-word-row ${notebookState.selected.has(word.id) ? "selected" : ""}">${notebookState.selecting ? `<label class="nb-word-check"><input type="checkbox" data-nb-select="${word.id}" aria-label="选择 ${escapeHtml(word.text)}" ${notebookState.selected.has(word.id) ? "checked" : ""}></label>` : ""}<a href="#word/${word.id}" class="nb-word-open"><div class="nb-word-first"><h2>${escapeHtml(word.text)}</h2>${statusBadge(word)}</div><p class="nb-word-reading">${escapeHtml(word.reading || "读音待补全")}</p><p class="nb-word-meaning">${escapeHtml(word.meaning || "释义待补全，暂不加入测验")}</p><div class="nb-word-meta"><span class="${dueWord(word) ? "is-due" : ""}">${dueLabel(word)}</span>${word.errorCount ? `<span>错过 ${word.errorCount} 次</span>` : ""}<span>${word.notebookIds.length > 1 ? `${word.notebookIds.length} 本共用进度` : word.tags[0] ? `#${escapeHtml(word.tags[0])}` : word.language}</span></div></a>${notebookState.selecting ? "" : `<span class="nb-row-arrow" aria-hidden="true">${icon("chevron")}</span>`}</article>`).join("") : nbEmpty("没有符合条件的单词", "试试其他关键词，或清除筛选。", nbButton("clear-filters", "清除筛选", "search"));
  document.querySelector("#nb-result-count").textContent = `${words.length} 个结果${notebookState.language !== "全部语言" ? ` · ${notebookState.language}` : ""}${notebookState.tag ? ` · #${notebookState.tag}` : ""}`;
  document.querySelector("#nb-batch-bar").innerHTML = notebookState.selecting ? `<div class="nb-batch-bar"><div><strong>已选 ${notebookState.selected.size} 个</strong>${nbButton("select-results", "选择全部结果", "", "text-button")}</div><div>${nbButton("members", "归本", "book", "secondary", 'data-mode="add"')}${nbButton("batch-menu", "更多操作", "more", "primary")}</div></div>` : "";
  document.body.classList.toggle("nb-selecting", notebookState.selecting);
}
function wordSource(word) {
  const book = word.bookId && bookById(word.bookId);
  return book ? `<a class="nb-source-link" href="#source/${word.id}">${icon("link")} ${escapeHtml(book.title)} · 第 ${word.chapter + 1} 章 ${icon("chevron")}</a>` : `<p class="nb-source-unavailable">${escapeHtml(word.sourceTitle || "手动录入")} · 无可回跳的材料出处</p>`;
}
function learningReason(word) {
  if (!readyWord(word)) return "先补充目标释义，再开始可靠的词形测验。";
  if (word.status === "mastered") return "示例记录满足3个有效学习日、至少2次主动回忆及7天间隔。到期仍需复习。";
  if (word.status === "relearning") return "曾经达到标准，后续出现未独立回忆成功的记录，需要重新验证。";
  if (word.status === "new") return "尚无当前词形和义项的有效测验证据。查看释义和听发音不会改变状态。";
  return "已有练习记录，还需要不同学习日和足够间隔的无提示回忆。一次答对不会直接变为已掌握。";
}
function recordLabel(record) { return ({ correct: "无提示答对", assisted: "看过答案后练习", wrong: "未答对", unknown: "选择了不会", skipped: "跳过，不计错误" })[record.outcome] || record.outcome; }
function renderWordDetail() {
  const word = wordById(notebookState.wordId);
  if (!word) { location.hash = `notebook/${notebookState.scope}`; return; }
  main.innerHTML = `<div class="nb-page nb-detail">${nbHeader("单词详情", word.language, `#notebook/${notebookState.scope}`, nbButton("edit-word", "编辑", "", "text-button", `data-id="${word.id}"`) + nbButton("word-menu", "", "more", "icon-button", 'aria-label="单词更多操作"'))}
    <div class="nb-detail-columns"><div><section class="nb-word-hero"><div><h2>${escapeHtml(word.text)}</h2>${nbButton("audio", "", "sound", "icon-button", 'aria-label="播放单词标准发音"')}</div><p>${escapeHtml(word.reading || "读音待补全")} <span>${escapeHtml(word.pos || "词性待补全")}</span></p><p class="nb-detail-meaning">${escapeHtml(word.meaning || "还没有释义，编辑后即可加入学习。")}</p><div class="nb-detail-status">${statusBadge(word)}${word.studyControl === "suspended" ? '<span class="nb-muted-badge">已暂停复习</span>' : ""}</div></section>
    <section class="nb-detail-section"><h3>在语境里记住它</h3><blockquote>${escapeHtml(word.context || "还没有原句，可以在编辑时补充。")} </blockquote>${wordSource(word)}</section>
    <section class="nb-detail-section"><div class="nb-section-heading"><h3>笔记与标签</h3>${nbButton("edit-word", "编辑", "", "text-button", `data-id="${word.id}"`)}</div><p>${escapeHtml(word.notes || "写下自己的联想，下次更容易记住。")}</p><div class="nb-tags">${word.tags.map((tag) => `<span>#${escapeHtml(tag)}</span>`).join("") || '<span>暂无标签</span>'}</div></section>
    <section class="nb-detail-section"><div class="nb-section-heading"><h3>所属单词本</h3>${nbButton("members", "整理", "", "text-button", 'data-mode="set"')}</div><div class="nb-memberships">${word.notebookIds.map((id) => { const book = notebookById(id); return book ? `<a href="#notebook/${id}">${icon("book")}${escapeHtml(book.name)}${icon("chevron")}</a>` : ""; }).join("") || '<p>未分组 · 可以加入任意同语种单词本。</p>'}</div><p class="nb-caption">同一个词加入多本，共用学习进度。</p></section></div>
    <div><section class="nb-learning-panel"><div class="nb-section-heading"><h3>学习状态</h3><span>自动判定</span></div><p>${learningReason(word)}</p><dl><div><dt>下次复习</dt><dd>${dueLabel(word)}</dd></div><div><dt>累计错误</dt><dd>${word.errorCount} 次</dd></div><div><dt>听力 / 发音</dt><dd>未评估</dd></div></dl><p class="nb-caption">种子记录为示例；新作答仅保存在本次原型中。</p>${nbButton("toggle-pause", word.studyControl === "suspended" ? "恢复复习" : "暂停复习", "", "secondary", `data-id="${word.id}"`)}</section><section class="nb-detail-section"><h3>最近学习记录</h3><div class="nb-timeline">${[...word.records].reverse().map((record) => `<div><span>${escapeHtml(record.date)}</span><p><strong>${recordLabel(record)}</strong><small>${record.skill}${record.training ? " · 加练，不推进间隔" : ""}${record.sample ? " · 示例记录" : " · 本次演示"}${record.revision !== word.learningRevision ? " · 旧词条版本" : ""}</small></p></div>`).join("") || '<p class="nb-caption">还没有测验记录。</p>'}</div></section></div></div>
    <div class="nb-detail-bottom">${nbButton("preview-one", "学习预览", "book")}${nbButton("plan", "练习这个词", "practice", "primary", `data-word="${word.id}"`)}</div></div>`;
}

function showNotebookForm(book) {
  openDialog(book ? "编辑单词本" : "新建单词本", `<form id="nb-book-form" data-id="${book?.id || ""}" class="nb-form"><label>名称<input name="name" maxlength="40" required value="${escapeHtml(book?.name || "")}" placeholder="例如：旅行日语"></label><label>目标语<select name="language" ${book && scopedWords(book.id).length ? "disabled" : ""}><option ${book?.language !== "英语" ? "selected" : ""}>日语</option><option ${book?.language === "英语" ? "selected" : ""}>英语</option></select></label><label>简介（选填）<textarea name="description" maxlength="200" rows="3" placeholder="这本单词本想用来做什么？">${escapeHtml(book?.description || "")}</textarea></label><p class="nb-form-error" role="alert"></p><div class="dialog-actions"><button type="button" class="secondary" data-action="close-dialog">取消</button><button type="submit" class="primary">${book ? "保存" : "创建单词本"}</button></div></form>`, "nb-book-form");
}
function notebookChoices(language, selected = [], name = "notebooks") {
  const books = notebookState.books.filter((book) => book.language === language);
  return books.length ? books.map((book) => `<label class="nb-check-row"><input type="checkbox" name="${name}" value="${book.id}" ${selected.includes(book.id) ? "checked" : ""}><span>${escapeHtml(book.name)}<small>${book.language} · ${scopedWords(book.id).length} 个单词</small></span></label>`).join("") : '<p class="nb-caption">还没有该语言的词本，不选则进入未分组。</p>';
}
function showWordForm(word) {
  const language = word?.language || notebookById(notebookState.scope)?.language || notebookState.homeLanguage;
  const books = word?.notebookIds || (notebookById(notebookState.scope) ? [notebookState.scope] : []);
  openDialog(word ? "编辑单词" : "添加单词", `<form id="nb-word-form" data-id="${word?.id || ""}" class="nb-form"><div class="nb-form-pair"><label>单词<input name="text" required maxlength="100" value="${escapeHtml(word?.text || "")}" placeholder="输入词形"></label><label>目标语<select name="language"><option ${language === "日语" ? "selected" : ""}>日语</option><option ${language === "英语" ? "selected" : ""}>英语</option></select></label></div><div class="nb-form-pair"><label>读音<input name="reading" maxlength="150" value="${escapeHtml(word?.reading || "")}" placeholder="假名或音标"></label><label>词性<input name="pos" maxlength="40" value="${escapeHtml(word?.pos || "")}" placeholder="例如：名词"></label></div><label>目标释义<textarea name="meaning" maxlength="500" rows="2" placeholder="没有释义的词会标为待补全">${escapeHtml(word?.meaning || "")}</textarea></label><label>原句 / 语境<textarea name="context" maxlength="1000" rows="2" ${word?.bookId ? 'readonly aria-description="保留材料原句；请在笔记中添加补充说明。"' : ""}>${escapeHtml(word?.context || "")}</textarea></label><label>笔记<textarea name="notes" maxlength="1000" rows="2" placeholder="搭配、易混点、自己的联想…">${escapeHtml(word?.notes || "")}</textarea></label><label>标签<input name="tags" maxlength="150" value="${escapeHtml(word?.tags.join("，") || "")}" placeholder="用逗号分隔，例如：旅行，日常"></label><fieldset><legend>加入单词本（可多选）</legend><div id="nb-form-books">${notebookChoices(language, books)}</div></fieldset>${word ? '<p class="nb-caption">修改词形、语言、读音或目标释义会重新开始学习评估；笔记、标签和归本不会重置进度。</p>' : ""}<p class="nb-form-error" role="alert"></p><div class="dialog-actions"><button type="button" class="secondary" data-action="close-dialog">取消</button><button class="primary" type="submit">保存单词</button></div></form>`, "nb-word-form");
}
function selectedWords() {
  return state.page === "word" ? [wordById(notebookState.wordId)].filter(Boolean) : state.collections.filter((word) => notebookState.selected.has(word.id));
}
function showMembers(mode, fromReading = false) {
  if (!fromReading) notebookState.readingEntry = null;
  const words = notebookState.readingEntry ? [notebookState.readingEntry] : selectedWords();
  if (!words.length) { toast("先选择要整理的单词。"); return; }
  if (new Set(words.map((word) => word.language)).size > 1) { toast("请先筛选同一种语言，再批量归本。"); return; }
  const selected = mode === "set" ? words[0].notebookIds : [];
  openDialog(mode === "move" ? "移动到另一本" : mode === "set" ? "整理所属单词本" : "加入单词本", `<form id="nb-members-form" data-mode="${mode}" class="nb-form"><p class="dialog-description">${notebookState.readingEntry ? `收藏「${escapeHtml(words[0].text)}」` : `整理 ${words.length} 个${words[0].language}单词`}。${mode === "move" ? "只移出当前来源本，其他归属不变。" : "归本不复制单词，也不会改变学习进度。"}</p>${notebookChoices(words[0].language, selected)}<p class="nb-caption">${mode === "set" || notebookState.readingEntry ? "不选择任何本则进入未分组。" : "可选择多个同语种单词本。"}</p><p class="nb-form-error" role="alert"></p><div class="dialog-actions"><button type="button" class="secondary" data-action="close-dialog">取消</button><button type="submit" class="primary">${notebookState.readingEntry ? "确认收藏" : "确认归本"}</button></div></form>`, "nb-members");
}
function showNotebookFilters() {
  const n = notebookState;
  openDialog("筛选与排序", `<form id="nb-filter-form" class="nb-form"><label>目标语<select name="language">${["全部语言", "日语", "英语"].map((value) => `<option ${n.language === value ? "selected" : ""}>${value}</option>`).join("")}</select></label><div class="nb-form-pair"><label>标签<select name="tag"><option value="">全部标签</option>${[...new Set(state.collections.flatMap((word) => word.tags))].map((tag) => `<option value="${escapeHtml(tag)}" ${n.tag === tag ? "selected" : ""}>${escapeHtml(tag)}</option>`).join("")}</select></label><label>来源<select name="source">${[["", "全部来源"], ["material", "阅读收藏"], ["manual", "手动录入"], ["csv", "CSV 导入"], ["photo", "照片词表"]].map(([value, label]) => `<option value="${value}" ${n.source === value ? "selected" : ""}>${label}</option>`).join("")}</select></label></div><label>学习状态<select name="filter">${[["all", "全部状态"], ["due", "待复习"], ["new", "新词"], ["unmastered", "未掌握"], ["mastered", "已掌握"], ["relearning", "需重学"], ["incomplete", "待补全"]].map(([value, label]) => `<option value="${value}" ${n.filter === value ? "selected" : ""}>${label}</option>`).join("")}</select></label><label>排序<select name="sort">${[["added", "加入顺序"], ["word", "单词词形"], ["due", "下次复习"], ["recent", "最近练习"], ["errors", "错误次数最多"]].map(([value, label]) => `<option value="${value}" ${n.sort === value ? "selected" : ""}>${label}</option>`).join("")}</select></label><div class="dialog-actions"><button type="button" class="secondary" data-action="nb-clear-filters">重置</button><button type="submit" class="primary">显示结果</button></div></form>`, "nb-filters");
}
function refreshNotebookPage() {
  if (state.page === "notebooks") renderNotebooksHome();
  else if (state.page === "words") renderNotebookList();
  else if (state.page === "word") renderWordDetail();
  else if (state.page === "review") renderReviewSession();
  else if (state.page === "study-history") renderStudyHistory();
  renderNavigation();
}

function showNotebookMenu(title, rows, note = "") {
  openDialog(title, `${note ? `<p class="dialog-description">${note}</p>` : ""}<div class="nb-menu">${rows.map(([action, label, symbol, data = ""]) => nbButton(action, label, symbol, "nb-menu-item", data)).join("")}</div>`, "nb-menu");
}
function confirmNotebookOperation(title, text, action) {
  openDialog(title, `<p class="dialog-description">${text}</p><div class="dialog-actions"><button class="secondary" data-action="close-dialog">取消</button>${nbButton(action, "确认", "", "primary")}</div>`, "nb-confirm");
}
function beginNotebookSave() {
  const entry = state.explanation;
  if (!entry || isSaved(entry)) return;
  const info = DICTIONARY[entry.text];
  notebookState.readingEntry = demoWord(`saved-${state.nextId++}`, entry.text, info.reading, info.meaning, { ...entry, pos: info.kind, language: bookById(entry.bookId).language, origin: "material", sourceTitle: bookById(entry.bookId).title, context: sourceSentence(entry) });
  showMembers("add", true);
}
function showImportDemo(origin = "csv") {
  notebookState.importOrigin = origin;
  showNotebookMenu(origin === "photo" ? "拍照 / 选择词表图片" : "导入单词 CSV", [["import-preview", "体验示例预览与确认", "list"]], origin === "photo" ? "本原型未接入相机或视觉模型，不会上传图片。下面用预置候选展示：检查词形、修正释义、归本、确认写入。" : "本原型未接入真实文件解析。下面用2条示例行展示CSV v2的预览、去重与归本；导入不恢复可信掌握度。");
}
function showImportPreview() {
  const source = notebookState.importOrigin;
  const existing = wordById("seed-calm");
  notebookState.importRows = [
    { text: "木漏れ日", reading: "こもれび", meaning: "从树叶间隙洒落的阳光。", context: "木漏れ日がテーブルの上で揺れていた。" },
    { text: existing?.text || "穏やか", reading: "おだやか", meaning: "平静的；温和的。", context: existing?.context || "" }
  ];
  openDialog(source === "photo" ? "确认识别候选 · 示例" : "CSV 导入预览 · 示例", `<form id="nb-import-form" class="nb-form"><p class="dialog-description">2条日语单词。先核对，再确认添加；取消不会写入。</p>${notebookState.importRows.map((row, i) => `<fieldset class="nb-import-row"><legend>第 ${i + 1} 条${source === "photo" && i === 0 ? " · 低置信度，请核对" : ""}</legend><label class="nb-inline-check"><input name="include-${i}" type="checkbox" checked>导入此行</label><label>单词<input name="text-${i}" value="${escapeHtml(row.text)}" maxlength="100"></label><label>释义<input name="meaning-${i}" value="${escapeHtml(row.meaning)}" maxlength="500"></label></fieldset>`).join("")}<label>重复单词处理<select name="duplicate"><option value="skip">跳过重复（默认）</option><option value="merge">仅补空字段并合并词本归属</option><option value="new">创建独立新条目</option></select></label><fieldset><legend>加入同语种单词本（可多选）</legend>${notebookChoices("日语", notebookById(notebookState.scope)?.language === "日语" ? [notebookState.scope] : [])}</fieldset>${source === "photo" ? '<label class="nb-inline-check"><input type="checkbox" name="verified" required>我已核对选中行，包括低置信度词形。</label>' : '<p class="info-note">示例文件含“已掌握”快照。新增词仍为新词；既有词的学习状态不被覆盖。</p>'}<p class="nb-form-error" role="alert"></p><div class="dialog-actions"><button type="button" class="secondary" data-action="close-dialog">取消</button><button type="submit" class="primary">确认导入示例</button></div></form>`, "nb-import");
}
function showExportPreview() {
  const filtered = state.page === "words";
  const words = filtered ? filteredWords() : state.collections;
  openDialog("导出单词 CSV · 范围预览", `<p class="dialog-description">${filtered ? "当前全部筛选结果" : "全部单词"}，共 ${words.length} 个去重单词，包含词本名称归属。</p><div class="nb-export-preview">${words.slice(0, 5).map((word) => `<div><strong>${escapeHtml(word.text)}</strong><span>${escapeHtml(word.notebookIds.map((id) => notebookById(id)?.name).filter(Boolean).join("、") || "未分组")}</span></div>`).join("")}</div><p class="info-note">文件生成尚未接入。正式CSV包含词形、读音、释义、语境、笔记、标签及所属词本；不备份练习成绩、原书或音频，也不凭状态快照恢复掌握。</p><div class="dialog-actions"><button class="primary" data-action="close-dialog">知道了</button></div>`, "nb-export");
}
function handleNotebookAction(action, button) {
  const n = notebookState;
  const word = wordById(n.wordId);
  const act = action.slice(3);
  if (act === "add-menu") showNotebookMenu("添加到学习空间", [["add-word", "手动添加单词", "plus"], ["create-book", "新建单词本", "book"], ["import-csv", "导入单词 CSV", "upload"], ["import-photo", "拍照 / 选择词表图片", "grid"]]);
  else if (act === "home-menu") showNotebookMenu("单词本工具", [["import-csv", "导入单词 CSV", "upload"], ["export", "导出全部单词 CSV", "upload"], ["history", "学习记录", "practice"]]);
  else if (act === "create-book") showNotebookForm();
  else if (act === "edit-book") showNotebookForm(notebookById(n.scope));
  else if (act === "add-word") showWordForm();
  else if (act === "edit-word") showWordForm(wordById(button.dataset.id));
  else if (act === "book-menu") showNotebookMenu(scopeName(), [["import-csv", "导入单词 CSV", "upload"], ["export", "导出当前筛选单词", "upload"], ...(notebookById(n.scope) ? [["edit-book", "编辑名称和简介", "type"], ["delete-book", "删除这个单词本", "trash"]] : [])]);
  else if (act === "delete-book") { const book = notebookById(n.scope); if (book) confirmNotebookOperation("删除单词本？", `「${escapeHtml(book.name)}」有 ${scopedWords().length} 个单词。只删除词本和归属关系，单词、学习记录和其他词本均保留。`, "confirm-delete-book"); }
  else if (act === "confirm-delete-book") { const id = n.scope; n.books = n.books.filter((book) => book.id !== id); state.collections.forEach((w) => { w.notebookIds = w.notebookIds.filter((bookId) => bookId !== id); }); dialog.close(); location.hash = "collections"; toast("已删除词本，单词和学习记录已保留。"); }
  else if (act === "filters") showNotebookFilters();
  else if (act === "filter") { n.filter = button.dataset.value; renderNotebookList(); }
  else if (act === "clear-filters") { Object.assign(n, { query: "", filter: "all", language: "全部语言", tag: "", source: "", sort: "added" }); if (dialog.open) dialog.close(); renderNotebookList(); }
  else if (act === "select-mode") { n.selecting = !n.selecting; if (!n.selecting) n.selected.clear(); renderNotebookList(); }
  else if (act === "select-results") { filteredWords().forEach((w) => n.selected.add(w.id)); renderNotebookRows(); }
  else if (act === "members") showMembers(button.dataset.mode || "add");
  else if (act === "batch-menu") { if (!n.selected.size) { toast("先选择需要整理的单词。"); return true; } showNotebookMenu(`整理 ${n.selected.size} 个单词`, [...(notebookById(n.scope) ? [["members", "移动到另一本", "book", 'data-mode="move"'], ["remove-members", "只从当前本移出", "back"]] : []), ["pause-selected", "暂停复习（影响全部所属本）", "focus"], ["resume-selected", "恢复复习", "practice"], ["delete-words", "删除单词", "trash"]]); }
  else if (act === "remove-members") confirmNotebookOperation("只从当前本移出？", `移出 ${n.selected.size} 个已选单词，保留其他归属和学习进度。移出最后一本的词进入未分组。`, "confirm-remove-members");
  else if (act === "confirm-remove-members") { selectedWords().forEach((w) => { w.notebookIds = w.notebookIds.filter((id) => id !== n.scope); }); n.selected.clear(); dialog.close(); refreshNotebookPage(); toast("已移出，单词仍保留。"); }
  else if (act === "pause-selected" || act === "resume-selected") { n.pendingControl = act === "pause-selected" ? "suspended" : "active"; confirmNotebookOperation(n.pendingControl === "suspended" ? "暂停这些词的复习？" : "恢复这些词的复习？", `影响 ${n.selected.size} 个词在所有单词本中的计划。掌握度和历史不变，恢复不会推迟已到期的复习。`, "confirm-control"); }
  else if (act === "confirm-control") { selectedWords().forEach((w) => { w.studyControl = n.pendingControl; }); dialog.close(); refreshNotebookPage(); toast("已更新参与计划的状态，学习记录未改变。"); }
  else if (act === "toggle-pause") { n.pendingControl = word.studyControl === "suspended" ? "active" : "suspended"; confirmNotebookOperation(n.pendingControl === "active" ? "恢复复习？" : "暂停复习？", "此操作影响这个词在所有词本中的计划，不改变掌握结论和历史。", "confirm-control"); }
  else if (act === "word-menu") showNotebookMenu(word.text, [["members", "整理所属单词本", "book", 'data-mode="set"'], ["toggle-pause", word.studyControl === "active" ? "暂停复习" : "恢复复习", "focus"], ["delete-words", "删除这个单词", "trash"]]);
  else if (act === "delete-words") confirmNotebookOperation("删除单词？", `将删除 ${selectedWords().length} 个单词，并从全部词本移除。历史作答快照保留；已删除词不再进入未来测验。`, "confirm-delete-words");
  else if (act === "confirm-delete-words") { const ids = new Set(selectedWords().map((w) => w.id)); n.deletedHistory.push(...selectedWords().map((w) => structuredClone(w))); state.collections = state.collections.filter((w) => !ids.has(w.id)); n.selected.clear(); dialog.close(); if (state.page === "word") location.hash = `notebook/${n.scope}`; else refreshNotebookPage(); toast("已删除单词并移除全部词本归属。"); }
  else if (act === "audio") openDialog("标准单词发音", '<p class="dialog-description">正式版可复用同语种、词形和读音的标准词音。此原型未接入音频服务，不会自动生成、收费或调用系统TTS。</p><div class="dialog-actions"><button class="primary" data-action="close-dialog">知道了</button></div>', "nb-audio");
  else if (act === "plan") showStudyPlan(button);
  else if (act === "preview-one") showStudyPreview([word]);
  else if (act === "preview-plan") { const plan = getPlan(); showStudyPreview(plan.queue, true); }
  else if (act === "start-previewed") startReview(n.previewWords.map((w) => wordById(w.id)).filter(Boolean), n.previewWords[0].language);
  else if (act === "reveal") { const session = n.session; if (!session.current) { session.revealed = true; opportunityFor(session.items[session.index]).exposed = true; renderReviewSession(); } }
  else if (act === "unknown") submitReview("unknown");
  else if (act === "skip") submitReview("skipped");
  else if (act === "next-question") advanceReview();
  else if (act === "exit-review") confirmNotebookOperation("结束本轮复习？", "已作答的结果会保留，未作答的词不记为错误。", "confirm-exit-review");
  else if (act === "confirm-exit-review") { dialog.close(); finishReview(); }
  else if (act === "retry-wrong") { const words = n.session.results.filter((r) => ["wrong", "unknown"].includes(r.outcome)).map((r) => wordById(r.id)).filter((w) => w && w.studyControl === "active"); if (words.length) startReview(words, words[0].language); else toast("错词已暂停或删除，当前没有可加练的词。"); }
  else if (act === "history") { if (dialog.open) dialog.close(); location.hash = "study-history"; }
  else if (act === "history-detail") { const session = n.sessions.find((s) => s.id === button.dataset.id); openDialog("本次学习记录", `<div class="nb-result-words">${session.results.map((r) => `<div><strong>${escapeHtml(r.text)}</strong><span>${recordLabel(r)}</span></div>`).join("")}</div><div class="dialog-actions"><button class="primary" data-action="close-dialog">关闭</button></div>`, "nb-history"); }
  else if (act === "import-csv" || act === "import-photo") showImportDemo(act === "import-photo" ? "photo" : "csv");
  else if (act === "import-preview") showImportPreview();
  else if (act === "export") showExportPreview();
  else return false;
  return true;
}

document.addEventListener("submit", (event) => {
  const form = event.target;
  if (!form.id.startsWith("nb-")) return;
  event.preventDefault();
  const field = (name) => form.elements[name]?.value.trim() || "";
  const checked = (name) => [...form.querySelectorAll(`[name="${name}"]:checked`)].map((el) => el.value);
  const fail = (text) => { form.querySelector(".nb-form-error").textContent = text; };
  const normalize = (text) => text.normalize("NFKC").trim().replace(/\s+/g, " ").toLocaleLowerCase();
  if (form.id === "nb-book-form") {
    const old = notebookById(form.dataset.id); const name = field("name"); const language = field("language");
    if (!name) { fail("请输入单词本名称。"); return; }
    if (notebookState.books.some((book) => book.id !== old?.id && book.language === language && normalize(book.name) === normalize(name))) { fail("同一语言下已有这个名称，请换一个。"); return; }
    if (old) Object.assign(old, { name, language, description: field("description") });
    else notebookState.books.push({ id: `notebook-${notebookState.nextId++}`, name, language, description: field("description"), color: ["blue", "violet", "sand"][notebookState.books.length % 3] });
    dialog.close(); refreshNotebookPage(); toast(old ? "已更新单词本。" : "单词本已创建。");
  } else if (form.id === "nb-word-form") {
    const old = wordById(form.dataset.id); const language = field("language"); const text = field("text");
    if (!text) { fail("请输入单词，不能只含空白。"); return; }
    if (old && old.language !== language && old.notebookIds.length) { fail("请先从原语言的词本明确移出，再修改目标语。"); return; }
    const books = checked("notebooks");
    if (books.some((id) => notebookById(id)?.language !== language)) { fail("只能加入同语种单词本。"); return; }
    const values = { text, language, reading: field("reading"), pos: field("pos"), meaning: field("meaning"), context: field("context"), notes: field("notes"), tags: [...new Set(field("tags").split(/[,，]/).map((s) => s.trim()).filter(Boolean))], notebookIds: books };
    if (old) { const changed = ["text", "language", "reading", "meaning"].some((key) => old[key] !== values[key]); Object.assign(old, values); if (changed) { old.learningRevision++; old.status = "new"; old.due = null; old.errorCount = 0; } }
    else { const added = demoWord(`word-${notebookState.nextId++}`, text, values.reading, values.meaning, values); state.collections.unshift(added); }
    dialog.close(); refreshNotebookPage(); toast("单词已保存；学习状态由测验证据决定。");
  } else if (form.id === "nb-members-form") {
    const mode = form.dataset.mode; const books = checked("notebooks"); const reading = notebookState.readingEntry; const words = reading ? [reading] : selectedWords();
    if (!words.length || books.some((id) => words.some((word) => notebookById(id)?.language !== word.language))) { fail("归本目标必须存在且与所有单词同语种。"); return; }
    if (!books.length && ["add", "move"].includes(mode) && !reading) { fail("请至少选择一个目标单词本。"); return; }
    if (mode === "move" && books.includes(notebookState.scope)) { fail("移动时请选择当前本之外的目标。"); return; }
    words.forEach((word) => { word.notebookIds = mode === "set" ? books : [...new Set([...word.notebookIds.filter((id) => mode !== "move" || id !== notebookState.scope), ...books])]; });
    if (reading) { state.collections.unshift(reading); notebookState.readingEntry = null; dialog.close(); renderExplanation(); renderNavigation(); toast("已收藏，并保存语境和所属词本。"); }
    else { dialog.close(); refreshNotebookPage(); toast("已整理归属，学习进度未改变。"); }
  } else if (form.id === "nb-filter-form") { ["language", "tag", "source", "sort", "filter"].forEach((key) => { notebookState[key] = field(key); }); dialog.close(); renderNotebookList(); }
  else if (form.id === "nb-plan-form") { const plan = getPlan(); startReview(plan.queue, plan.language); }
  else if (form.id === "nb-answer-form") { notebookState.session.draft = field("answer"); if (!notebookState.session.draft) return; submitReview("answer"); }
  else if (form.id === "nb-import-form") {
    const rows = notebookState.importRows.map((row, i) => ({ ...row, text: field(`text-${i}`), meaning: field(`meaning-${i}`), include: form.elements[`include-${i}`].checked }));
    if (rows.some((row) => row.include && !row.text)) { fail("选中的行不能缺少单词，请补全或明确排除。"); return; }
    let added = 0, merged = 0, skipped = 0; const books = checked("notebooks");
    rows.filter((row) => row.include).forEach((row) => {
      const existing = state.collections.find((word) => word.language === "日语" && normalize(word.text) === normalize(row.text) && word.context === row.context);
      if (existing && field("duplicate") === "skip") skipped++;
      else if (existing && field("duplicate") === "merge") { const revised = (!existing.meaning && Boolean(row.meaning)) || (!existing.reading && Boolean(row.reading)); if (!existing.meaning) existing.meaning = row.meaning; if (!existing.reading) existing.reading = row.reading; if (revised) { existing.learningRevision++; existing.status = "new"; existing.due = null; existing.errorCount = 0; } existing.notebookIds = [...new Set([...existing.notebookIds, ...books])]; merged++; }
      else { state.collections.unshift(demoWord(`imported-${notebookState.nextId++}`, row.text, row.reading, row.meaning, { context: row.context, notebookIds: [...books], origin: notebookState.importOrigin, sourceTitle: notebookState.importOrigin === "photo" ? "照片词表示例" : "CSV 导入示例", importedStatus: "mastered" })); added++; }
    });
    dialog.close(); refreshNotebookPage(); toast(`新增 ${added} · 补全 ${merged} · 跳过 ${skipped} · 排除 ${rows.filter((row) => !row.include).length}。新增词均为新词。`);
  }
});
document.addEventListener("input", (event) => {
  if (event.target.id === "nb-word-search") { notebookState.query = event.target.value; renderNotebookRows(); }
  if (event.target.id === "nb-answer" && notebookState.session) notebookState.session.draft = event.target.value;
  if (event.target.closest("#nb-plan-form")) updatePlanSummary();
});
document.addEventListener("change", (event) => {
  const target = event.target;
  if (target.id === "nb-home-language") { notebookState.homeLanguage = target.value; renderNotebooksHome(); }
  if (target.dataset.nbSelect) { if (target.checked) notebookState.selected.add(target.dataset.nbSelect); else notebookState.selected.delete(target.dataset.nbSelect); renderNotebookRows(); }
  if (target.name === "language" && target.closest("#nb-word-form")) document.querySelector("#nb-form-books").innerHTML = notebookChoices(target.value);
  if (target.closest("#nb-plan-form")) { if (target.name === "language") document.querySelector("#nb-plan-books").innerHTML = notebookChoices(target.value, [], "plan-books"); updatePlanSummary(); }
});

function handleNotebookRoute(parts) {
  if (!["collections", "notebook", "word", "review", "study-history"].includes(parts[0])) return false;
  if (parts[0] === "notebook") {
    const scope = ["all", "ungrouped", "weak", "paused"].includes(parts[1]) || notebookById(parts[1]) ? parts[1] : "all";
    if (notebookState.scope !== scope) { Object.assign(notebookState, { scope, query: "", filter: "all", tag: "", source: "", language: "全部语言", selecting: false }); notebookState.selected.clear(); }
  }
  if (parts[0] === "word") notebookState.wordId = parts[1];
  state.page = ({ collections: "notebooks", notebook: "words", word: "word", review: "review", "study-history": "study-history" })[parts[0]];
  document.body.dataset.page = state.page;
  state.focus = false; state.explanation = null;
  document.body.classList.remove("focus-mode");
  document.body.classList.toggle("nb-selecting", state.page === "words" && notebookState.selecting);
  if (dialog.open) dialog.close();
  refreshNotebookPage();
  document.querySelector("#breadcrumb").textContent = state.page === "review" ? "每日复习" : "单词本";
  document.title = `Haruka · ${state.page === "review" ? "每日复习" : "单词本"}`;
  main.focus({ preventScroll: true }); window.scrollTo(0, 0);
  return true;
}
