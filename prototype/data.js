/* Shared fictional content only. The phone and desktop views are independent. */
window.HarukaData = Object.freeze({
  materials: [
    { id: 'summer', type: 'novel', title: '夏の手紙', subtitle: '小说 · 日语 · 12 章', status: '可阅读', cover: '夏', tone: 'blue', detail: '一封从夏日海边寄来的信，慢慢连接起两个人的故事。', updated: '今天 09:42' },
    { id: 'daily', type: 'textbook', title: '日语的日常表达', subtitle: '课本 · 日语 · 8 单元', status: '可学习', cover: 'あ', tone: 'lime', detail: '用熟悉的生活场景学习表达、语法和课后练习。', updated: '昨天 18:10' },
    { id: 'n2', type: 'exam', title: 'N2 模拟试卷', subtitle: '试卷 · 日语 · 38 题', status: '待校对', cover: 'N2', tone: 'peach', detail: '结构已提取，听力文字稿与题目关联等待校对。', updated: '9 月 21 日' }
  ],
  novel: {
    chapters: ['海边的邮筒', '雨停之后', '窓の向こう', '写给未来的你'],
    paragraphs: [
      '朝の光が、白いカーテンを通して部屋に広がった。窓を開けると、夏の風がそっと頬に触れた。',
      '机の上には、一通の手紙が置かれていた。見覚えのある文字を見て、私は思わず微笑んだ。',
      'まだ知らない言葉にも、どこか懐かしい響きがある。'
    ],
    terms: {
      soft: { word: 'そっと', reading: 'sotto · 副词', meaning: '轻轻地，悄悄地。这里描写夏风轻触脸颊，带着温柔、不打扰的感觉。', sentence: '夏の風がそっと頬に触れた。', translation: '夏风轻轻拂过脸颊。', source: '第 03 章 · 第 1 段' },
      smile: { word: '微笑んだ', reading: 'ほほえんだ · 动词', meaning: '微笑了。这里的「思わず微笑んだ」表示认出熟悉的字迹后，不由自主地笑了。', sentence: '私は思わず微笑んだ。', translation: '我不由得微笑起来。', source: '第 03 章 · 第 2 段' }
    }
  },
  textbook: {
    units: [
      { id: 'unit1', title: 'Unit 01 · 初次见面', items: ['会话：よろしくお願いします', '词汇：姓名与职业', '语法：は 与 です', '课后练习：3 题'] },
      { id: 'unit2', title: 'Unit 02 · 一起去车站', items: ['课文：駅までの道', '词汇：方向与交通', '语法：に / へ', '课后练习：4 题'] },
      { id: 'unit3', title: 'Unit 03 · 在咖啡馆', items: ['会话：注文をお願いします', '例句与译文', '语法：ください', '课后练习：3 题'] }
    ],
    question: { prompt: '「駅へ行きます」中的「へ」主要表示什么？', options: ['移动方向', '动作对象', '动作原因', '所属关系'], correct: 0 }
  },
  exam: {
    title: 'N2 模拟试卷', duration: '60 分钟', sections: ['语言知识', '阅读', '听力'],
    questions: [
      { id: 'q1', group: '语言知识', text: '「穏やか」に最接近的意思是？', options: ['平静温和', '迅速猛烈', '十分复杂', '令人惊讶'], correct: 0 },
      { id: 'q2', group: '阅读', text: '文中主人公为什么停下脚步？', options: ['忘记了约定', '想起了旧友', '听到了广播', '遇见了老师'], correct: 1 },
      { id: 'q3', group: '听力', text: '听力题组 1：两人最后决定在哪里见面？', options: ['图书馆门口', '车站南口', '公园入口', '学校大厅'], correct: 1 }
    ]
  },
  notebooks: [
    { id: 'dailywords', title: '日常的细节', language: '日语', count: 24, tone: 'lime', description: '从小说和日常会话里收集的表达。' },
    { id: 'readingwords', title: '阅读时遇见', language: '日语', count: 18, tone: 'blue', description: '读故事时想记住的词与短语。' },
    { id: 'englishwords', title: 'English sparks', language: '英语', count: 12, tone: 'peach', description: '英语材料里的高频表达。' }
  ],
  words: [
    { id: 'soft', word: 'そっと', reading: 'sotto', meaning: '轻轻地；悄悄地', source: '夏の手紙 · 第 03 章', book: 'dailywords', mastery: '学习中', sentence: '夏の風がそっと頬に触れた。' },
    { id: 'smile', word: '微笑む', reading: 'ほほえむ', meaning: '微笑', source: '夏の手紙 · 第 03 章', book: 'readingwords', mastery: '学习中', sentence: '私は思わず微笑んだ。' },
    { id: 'gentle', word: '穏やか', reading: 'おだやか', meaning: '平静的；温和的', source: 'N2 模拟试卷 · 语言知识', book: 'dailywords', mastery: '尚无有效证据', sentence: '穏やかな一日を過ごした。' },
    { id: 'glimmer', word: 'glimmer', reading: '/ˈɡlɪmər/', meaning: '微光；一丝希望', source: 'English sparks · 阅读片段', book: 'englishwords', mastery: '尚无有效证据', sentence: 'A glimmer of light appeared beyond the hill.' }
  ],
  mistakes: [
    { id: 'm1', title: '移动方向与目的地', source: '日语的日常表达 · Unit 02', state: '当前待纠正', favorite: false, answer: '把「へ」解释为动作对象' },
    { id: 'm2', title: '阅读中的指代关系', source: 'N2 模拟试卷 · 阅读', state: '已经改进', favorite: true, answer: '遗漏上一段的指代' },
    { id: 'm3', title: '语境词义：穏やか', source: 'AI 习题 · 日常的细节', state: '当前待纠正', favorite: false, answer: '误选了「迅速猛烈」' }
  ],
  notifications: [
    { id: 'n1', title: '「夏の手紙」已可阅读', detail: '章节与正文已准备好。', time: '今天 09:42', route: 'novel', unread: true },
    { id: 'n2', title: '试卷结构需要校对', detail: '听力文字稿与题组匹配仍待确认。', time: '昨天 16:18', route: 'examPrep', unread: true },
    { id: 'n3', title: '「日语的日常表达」已完成解析', detail: '3 个单元可以学习。', time: '9 月 20 日', route: 'textbook', unread: false }
  ],
  practice: { prompt: '猫を起こさないように、ドアを（　）閉めた。', translation: '为了不把猫吵醒，轻轻关上门。', options: ['そっと', 'きっと', 'ずっと', 'もっと'], correct: 0, explanation: '「そっと」强调动作轻柔、避免打扰。' },
  practiceEnglish: { prompt: 'A (　) of light appeared beyond the hill.', translation: '山的那边出现了一丝微光。', options: ['glimmer', 'thunder', 'silence', 'weight'], correct: 0, explanation: 'glimmer 是微弱的光，也可表示一丝希望。' },
  conversations: [
    { from: 'user', text: '这句话里的「そっと」有什么语气？' },
    { from: 'agent', text: '它强调动作轻柔、不打扰。结合“夏风碰到脸颊”的场景，读起来很温和。可以回到原文，再看它与前一句的节奏。', source: '夏の手紙 · 第 03 章 · 第 1 段' }
  ]
});
