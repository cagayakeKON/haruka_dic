"use strict";

// This session-only demo illustrates answer semantics. It does not implement server scheduling or FSRS.
function opportunityFor(word) {
  const key = `${word.id}:${word.learningRevision}`;
  if (!notebookState.opportunities.has(key)) notebookState.opportunities.set(key, { exposed: false, answered: false });
  return notebookState.opportunities.get(key);
}
function showStudyPlan(button) {
  if (notebookState.session && !notebookState.session.finished) { location.hash = "review"; toast("继续尚未结束的本次复习。"); return; }
  const single = button?.dataset.word && wordById(button.dataset.word);
  notebookState.planSingle = single?.id || null;
  notebookState.planPool = single ? [single.id] : button?.dataset.scope === "current" ? filteredWords().map((word) => word.id) : state.collections.map((word) => word.id);
  const language = single?.language || (button?.dataset.scope === "current" ? notebookById(notebookState.scope)?.language : null) || notebookState.homeLanguage;
  openDialog("准备这一轮复习", `<form id="nb-plan-form" class="nb-form"><p class="dialog-description">${single ? `练习「${escapeHtml(single.text)}」` : `从 ${notebookState.planPool.length} 个去重单词中安排这一轮`}，先复习到期词，再学习新词。</p><label>目标语<select name="language" ${single ? "disabled" : ""}><option ${language === "日语" ? "selected" : ""}>日语</option><option ${language === "英语" ? "selected" : ""}>英语</option></select></label>${single ? "" : `<details class="nb-plan-books"><summary>选择单词本 · 不勾选表示当前范围全部</summary><div id="nb-plan-books">${notebookChoices(language, [], "plan-books")}</div></details>`}<div class="nb-form-pair"><label>本轮新词上限<input type="number" name="newLimit" min="0" max="20" value="20" required></label><label>本轮复习上限<input type="number" name="reviewLimit" min="0" max="100" value="100" required></label></div><div id="nb-plan-summary" class="nb-plan-summary" role="status"></div><p class="nb-caption">使用现成释义做词形回忆，无需模型 Key。示例题按本词形匹配；未接入跨设备日额度或长期调度。</p><div class="dialog-actions"><button type="button" class="secondary" data-action="nb-preview-plan">学习预览</button><button class="primary" type="submit">开始测验</button></div></form>`, "nb-plan");
  updatePlanSummary();
}
function getPlan() {
  const form = document.querySelector("#nb-plan-form");
  const language = form.elements.language.value;
  const selectedBooks = [...form.querySelectorAll('[name="plan-books"]:checked')].map((el) => el.value);
  const words = state.collections.filter((word) => notebookState.planPool.includes(word.id) && word.language === language && (!selectedBooks.length || selectedBooks.some((id) => word.notebookIds.includes(id))));
  const eligible = words.filter((word) => word.studyControl === "active" && readyWord(word));
  const due = eligible.filter(dueWord).sort((a, b) => Number(b.status === "relearning") - Number(a.status === "relearning") || a.id.localeCompare(b.id));
  const fresh = eligible.filter((word) => word.status === "new" && !dueWord(word));
  const count = (name, max) => Math.max(0, Math.min(max, Number(form.elements[name].value) || 0));
  const chosenDue = due.slice(0, count("reviewLimit", 100));
  const chosenNew = fresh.slice(0, count("newLimit", 20));
  const queue = notebookState.planSingle ? eligible : [...chosenDue, ...chosenNew];
  return { queue, language, due: due.length, newCount: fresh.length, remaining: due.length - chosenDue.length, suspended: words.filter((w) => w.studyControl === "suspended").length, incomplete: words.filter((w) => !readyWord(w)).length };
}
function updatePlanSummary() {
  const target = document.querySelector("#nb-plan-summary"); if (!target) return;
  const plan = getPlan();
  target.innerHTML = `<strong>本轮 ${plan.queue.length} 个单词</strong><p>${plan.due} 个到期 · ${plan.newCount} 个新词<br>排除 ${plan.suspended} 个暂停词 / ${plan.incomplete} 个待补全词</p>${plan.remaining > 0 ? `<p>本轮之后仍有 ${plan.remaining} 个到期词。</p>` : ""}`;
  document.querySelector('#nb-plan-form [type="submit"]').disabled = !plan.queue.length;
  document.querySelector('[data-action="nb-preview-plan"]').disabled = !plan.queue.length;
}
function showStudyPreview(words, fromPlan = false) {
  const snapshots = words.map((word) => ({ ...word }));
  snapshots.forEach((word) => { opportunityFor(word).exposed = true; });
  notebookState.previewWords = snapshots;
  openDialog("学习预览", `<p class="dialog-description">先熟悉词义和语境。预览不会增加掌握度；紧接着的同轮作答按有辅助练习记录。</p><div class="nb-preview-cards">${snapshots.map((word) => `<article><div><h3>${escapeHtml(word.text)}</h3><span>${escapeHtml(word.reading)}</span></div><p>${escapeHtml(word.meaning || "释义待补全")}</p><small>${escapeHtml(word.context)}</small></article>`).join("")}</div><div class="dialog-actions"><button class="secondary" data-action="close-dialog">关闭预览</button>${fromPlan ? nbButton("start-previewed", "进入测验", "arrow", "primary") : ""}</div>`, "nb-preview");
}
function startReview(words, language) {
  if (!words.length) return;
  notebookState.session = { id: `session-${notebookState.nextId++}`, language, ids: words.map((word) => word.id), items: structuredClone(words), index: 0, results: [], draft: "", current: null, revealed: false, finished: false, started: new Date().toISOString() };
  dialog.close(); location.hash = "review";
  if (state.page === "review") renderReviewSession();
}
function renderReviewSession() {
  const session = notebookState.session;
  if (!session) { main.innerHTML = `<div class="nb-page">${nbHeader("每日复习", "", "#collections")}${nbEmpty("准备开始学习", "选择单词范围，先复习到期词。", nbButton("plan", "安排本轮复习", "practice", "primary"))}</div>`; return; }
  if (session.finished) { renderReviewResult(session); return; }
  const word = session.items[session.index];
  const live = wordById(word.id);
  const available = live && live.learningRevision === word.learningRevision && live.studyControl === "active" && readyWord(live);
  const result = session.current;
  const revealed = session.revealed || Boolean(result);
  main.innerHTML = `<div class="nb-page nb-quiz"><header class="nb-quiz-header">${nbButton("exit-review", "", "close", "icon-button", 'aria-label="结束本次复习"')}<div><strong>${session.language} · 词形回忆</strong><span>${session.index + 1} / ${session.ids.length}</span></div><span class="nb-quiz-mode">示例测验</span></header><div class="nb-quiz-progress"><span style="width:${session.index / session.ids.length * 100}%"></span></div>
    ${available || result ? `<div class="nb-question"><p class="nb-question-label">根据释义，回忆单词</p><h1>${escapeHtml(word.meaning)}</h1><p>请输入单词本中对应的${word.language}词形。</p>${revealed ? `<div class="nb-revealed"><small>${result ? "参考答案" : "已查看答案 · 本轮不计无提示成功"}</small><strong>${escapeHtml(word.text)}</strong><span>${escapeHtml(word.reading)}</span></div>` : ""}<form id="nb-answer-form"><label for="nb-answer">你的答案</label><input id="nb-answer" name="answer" autocomplete="off" autocapitalize="off" spellcheck="false" value="${escapeHtml(session.draft)}" ${result ? "disabled" : ""} placeholder="输入单词…" ${result ? "" : "required"}>${result ? `<div class="nb-answer-feedback ${result.outcome === "correct" ? "correct" : "neutral"}" role="status"><strong>${recordLabel(result)}</strong><p>${result.training ? "这是重复或尚未到期的加练，保留作答记录，不增加掌握成功次数或延长间隔。" : result.outcome === "correct" ? "本次已记录；还需要间隔复习验证，单次答对不直接判为掌握。" : "本次记录已保留，可以继续下一词；技术问题不会计为单词错误。"}</p></div>${nbButton("next-question", session.index === session.ids.length - 1 ? "查看本轮结果" : "下一个单词", "arrow", "primary")}` : `<button class="primary nb-submit-answer" type="submit">提交答案 ${icon("arrow")}</button>`}</form>${result ? "" : `<div class="nb-quiz-secondary">${nbButton("unknown", "不会", "", "text-button")}${nbButton("reveal", "查看答案", "", "text-button")}${nbButton("skip", "跳过", "", "text-button")}</div>`}</div>` : `<div class="nb-question">${nbEmpty("这个词已不可用", "词条已修改、暂停或删除。本题不计错误，请跳过后重新安排。", nbButton("skip", "跳过这个词", "arrow", "primary"))}</div>`}</div>`;
}
function submitReview(kind) {
  const session = notebookState.session;
  if (!session || session.finished || session.current) return;
  const snapshot = session.items[session.index];
  const word = wordById(snapshot.id);
  if (kind !== "skipped" && (!word || word.learningRevision !== snapshot.learningRevision || word.studyControl !== "active" || !readyWord(word))) { renderReviewSession(); return; }
  const opportunity = word ? opportunityFor(word) : null;
  const normalized = (text) => text.normalize("NFKC").trim().toLocaleLowerCase();
  const correct = word && normalized(session.draft) === normalized(snapshot.text);
  const outcome = kind === "skipped" ? "skipped" : kind === "unknown" ? "unknown" : correct ? (opportunity.exposed ? "assisted" : "correct") : "wrong";
  const result = { id: word?.id || session.ids[session.index], text: snapshot.text, outcome, training: Boolean(opportunity?.answered) || (outcome === "correct" && snapshot.status !== "new" && snapshot.due > 0), answer: session.draft, before: word?.status };
  if (word && outcome !== "skipped") {
    word.records.push({ date: new Date().toISOString().slice(5, 10), skill: "主动回忆", outcome, revision: word.learningRevision, training: result.training, sample: false });
    if (!result.training) {
      if (outcome === "correct") { if (word.status === "new") word.status = "learning"; word.due = 1; }
      else { word.status = word.status === "mastered" || word.status === "relearning" ? "relearning" : "learning"; word.due = 0; if (outcome !== "assisted") word.errorCount++; }
      opportunity.answered = true;
    }
  }
  session.results.push(result); session.current = result;
  if (kind === "skipped") advanceReview(); else renderReviewSession();
}
function advanceReview() {
  const session = notebookState.session;
  if (!session?.current) return;
  session.index++; session.current = null; session.draft = ""; session.revealed = false;
  if (session.index >= session.ids.length) finishReview(); else renderReviewSession();
}
function finishReview() {
  const session = notebookState.session;
  if (!session || session.finished) return;
  session.finished = true;
  notebookState.sessions.unshift(session);
  renderReviewResult(session);
}
function renderReviewResult(session) {
  const answered = session.results.filter((result) => result.outcome !== "skipped");
  const correct = answered.filter((result) => result.outcome === "correct").length;
  const wrong = answered.filter((result) => ["wrong", "unknown"].includes(result.outcome));
  const remaining = state.collections.filter((word) => word.language === session.language && dueWord(word) && readyWord(word)).length;
  main.innerHTML = `<div class="nb-page nb-results">${nbHeader("本轮学习小结", "", "#collections")}<div class="nb-result-mark">${icon("check")}</div><h2>每一次回忆，都算一步。</h2><p>本轮已作答 ${answered.length} / ${session.ids.length} 个单词</p><div class="nb-result-stats"><div><strong>${correct}</strong><span>无提示答对</span></div><div><strong>${wrong.length}</strong><span>需再练习</span></div><div><strong>${session.results.filter((r) => r.outcome === "assisted").length}</strong><span>有辅助</span></div></div><div class="nb-result-note"><strong>本轮新增已掌握：0</strong><p>掌握需要跨学习日与间隔验证。本原型不模拟长期达标；本次作答和状态变化可在详情查看。</p><p>仍有 ${remaining} 个${session.language}词到期；跳过或未作答不计错误。</p></div><div class="nb-result-words">${session.results.map((result) => `<div><span>${escapeHtml(result.text)}</span><small>${recordLabel(result)}${result.training ? " · 加练" : ""}</small></div>`).join("")}</div><div class="nb-result-actions">${wrong.length ? nbButton("retry-wrong", "错词再练", "practice", "primary") : ""}<a class="secondary" href="#collections">返回单词本</a></div></div>`;
}
function renderStudyHistory() {
  const grouped = new Map();
  state.collections.forEach((word) => word.records.filter((record) => record.sample).forEach((record) => { grouped.set(record.date, (grouped.get(record.date) || 0) + 1); }));
  main.innerHTML = `<div class="nb-page nb-history">${nbHeader("学习记录", "了解练习发生了什么。", "#collections")}<h2>本次原型中的练习</h2>${notebookState.sessions.map((session) => `<button class="nb-history-row" data-action="nb-history-detail" data-id="${session.id}"><span class="nb-history-icon">${icon("practice")}</span><span><strong>${session.language} · 词形回忆</strong><small>${session.results.filter((r) => r.outcome !== "skipped").length} 个已作答 · ${session.results.filter((r) => r.outcome === "correct").length} 个无提示答对</small></span>${icon("chevron")}</button>`).join("") || '<p class="nb-caption">还没有结束的练习。完成一轮后会显示实际结果。</p>'}<h2>示例学习日</h2><p class="nb-caption">以下记录来自预置词条，用于展示历史结构。</p>${[...grouped].sort((a, b) => b[0].localeCompare(a[0])).map(([date, count]) => `<div class="nb-history-row"><span class="nb-history-date">${date}</span><span><strong>${count} 个词的学习记录</strong><small>可从对应单词详情查看题型与结果</small></span></div>`).join("")}</div>`;
}
