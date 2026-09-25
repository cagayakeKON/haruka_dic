/* Typed language-learning samples. No OCR, model calls or assessment evidence. */
window.HarukaLearningCards = (() => {
  const { escape: e, icon: I } = window.HarukaCore;
  const kinds = {
    word: '单词',
    phrase: '短语',
    sentence: '句子',
    grammar: '语法',
    exercise: '习题',
    excerpt: '摘录',
  };
  const icons = {
    word: 'book',
    phrase: 'book',
    sentence: 'message',
    grammar: 'layers',
    exercise: 'edit',
    excerpt: 'bookmark',
  };
  const prompts = [
    'そっと 是什么意思？',
    '翻译：夏の風がそっと頬に触れた。',
    'に 和 へ 有什么区别？',
    '批改：昨日、図書館に行きます。',
  ];
  function sample(question) {
    const q = question.trim();
    if (['そっと', 'そっと 是什么意思？'].includes(q))
      return {
        kind: 'word',
        word: 'そっと',
        reading: 'sotto',
        partOfSpeech: '副词',
        meaning: '轻轻地；悄悄地',
        detail: '用于动作轻柔，或不希望打扰别人的场景。',
        language: '日语',
        examples: [
          { text: 'ドアをそっと閉めた。', translation: '轻轻地关上了门。' },
          { text: 'そっと手を握った。', translation: '轻轻握住了手。' },
        ],
      };
    if (
      [
        '夏の風がそっと頬に触れた。',
        '翻译：夏の風がそっと頬に触れた。',
      ].includes(q)
    )
      return {
        kind: 'sentence',
        word: '夏の風がそっと頬に触れた。',
        meaning: '夏风轻轻拂过脸颊。',
        language: '日语',
        detail: '「そっと」表达轻柔的动作。「頬」读作「ほお」，意思是脸颊。',
        segments: ['夏の風が', 'そっと', '頬に触れた。'],
        rule: '名词 + に + 触れる：触碰到某物。',
      };
    if (q === '窓を開けると、夏の風がそっと頬に触れた。')
      return {
        kind: 'sentence',
        word: q,
        language: '日语',
        meaning: '打开窗户，夏风轻轻拂过脸颊。',
        detail:
          '「窓を開けると」表示打开窗户后发生的情景；「そっと」描写轻柔的触感。',
        segments: ['窓を開けると、', '夏の風が', 'そっと頬に触れた。'],
      };
    if (['に 和 へ 有什么区别？', 'に / へ', 'に和へ的区别'].includes(q))
      return {
        kind: 'grammar',
        word: 'に / へ',
        meaning: '目的地与移动方向',
        language: '日语',
        detail:
          '「に」强调到达的地点；「へ」强调移动的方向。表示移动的句子中常可互换。',
        comparisons: [
          {
            label: 'に · 到达点',
            text: '駅に行きます。',
            translation: '去车站，强调目的地。',
          },
          {
            label: 'へ · 方向',
            text: '駅へ行きます。',
            translation: '往车站去，强调方向。',
          },
        ],
      };
    if (
      ['批改：昨日、図書館に行きます。', '昨日、図書館に行きます。'].includes(q)
    )
      return {
        kind: 'exercise',
        word: '昨日、図書館に行きます。',
        meaning: '过去时间需要搭配过去式',
        language: '日语',
        originalAnswer: '行きます',
        correction: '行きました',
        correctedSentence: '昨日、図書館に行きました。',
        detail:
          '「昨日」表示昨天。这里叙述已经发生的动作，应将「行きます」改为过去式「行きました」。',
        verdict: '时态需要调整',
      };
    return null;
  }
  function content(card) {
    const examples =
      card.examples || (card.sentence ? [{ text: card.sentence }] : []);
    return `<div class="learning-card-content"><h2 class="learning-title">${e(card.word)}</h2>${card.reading || card.partOfSpeech ? `<div class="learning-pronunciation">${card.reading ? `<span>${e(card.reading)}</span>` : ''}${card.partOfSpeech ? `<span class="learning-pos">${e(card.partOfSpeech)}</span>` : ''}</div>` : ''}<div class="learning-definition"><span class="learning-label">${card.kind === 'sentence' ? '译文' : card.kind === 'exercise' ? '订正重点' : card.kind === 'grammar' ? '核心用法' : '释义'}</span><p>${e(card.meaning)}</p></div>${card.segments?.length ? `<div class="learning-segments">${card.segments.map((part) => `<span>${e(part)}</span>`).join('')}</div>` : ''}${card.kind === 'exercise' && card.correction ? `<div class="learning-correction"><div><span class="learning-label">原作答</span><p>${e(card.originalAnswer)}</p></div><div><span class="learning-label">建议订正</span><p>${e(card.correction)}</p></div></div><p class="learning-corrected">${e(card.correctedSentence)}</p>` : ''}${card.detail ? `<p class="learning-explanation">${e(card.detail)}</p>` : ''}${card.rule ? `<div class="learning-rule">${I('layers')}<span>${e(card.rule)}</span></div>` : ''}${card.comparisons?.length ? `<div class="learning-comparison">${card.comparisons.map((item) => `<section><h3>${e(item.label)}</h3><p>${e(item.text)}</p><small>${e(item.translation)}</small></section>`).join('')}</div>` : ''}${examples.length ? `<section class="learning-examples"><h3>语境例句</h3>${examples.map((example, index) => `<div><span class="example-number">${String(index + 1).padStart(2, '0')}</span><p>${e(example.text)}${example.translation ? `<small>${e(example.translation)}</small>` : ''}</p></div>`).join('')}</section>` : ''}</div>`;
  }
  function render(card, action = '', showAgain = true) {
    return `<article class="learning-card kind-${e(card.kind)}" data-card-kind="${e(card.kind)}" data-card-id="${e(card.id)}"><header class="learning-card-header"><span class="learning-type">${I(icons[card.kind])}${e(kinds[card.kind])}</span><span class="learning-language">${e(card.language)} · 示例</span></header>${content(card)}<footer class="learning-card-footer"><span>${card.kind === 'exercise' ? '批改示例 · 不计入成绩' : '查询 · 内置示例'}</span><div>${showAgain ? '<button class="text-btn" type="button" data-x="queryAgain">再查一个</button>' : ''}${action}</div></footer></article>`;
  }
  return { kinds, icons, prompts, sample, content, render };
})();
