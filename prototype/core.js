window.HarukaCore = (() => {
  const data = window.HarukaData;
  const escape = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
  const icons = {
    library: '<rect x="3" y="3" width="6" height="18" rx="1"/><rect x="10" y="3" width="5" height="18" rx="1"/><path d="m17 4 4 16"/>',
    book: '<path d="M12 7v14M3 18V5a2 2 0 0 1 2-2h5a2 2 0 0 1 2 2v16a2 2 0 0 0-2-2H5a2 2 0 0 1-2-2Zm18 0V5a2 2 0 0 0-2-2h-5a2 2 0 0 0-2 2v16a2 2 0 0 1 2-2h5a2 2 0 0 0 2-2Z"/>',
    layers: '<rect x="3" y="3" width="15" height="15" rx="2"/><path d="M7 21h13a1 1 0 0 0 1-1V7"/>',
    spark: '<path d="m12 3 1.4 5.6L19 10l-5.6 1.4L12 17l-1.4-5.6L5 10l5.6-1.4L12 3Z"/><path d="m19 17 .5 1.5L21 19l-1.5.5L19 21l-.5-1.5L17 19l1.5-.5L19 17Z"/>',
    message: '<path d="M21 11.5a8.4 8.4 0 0 1-.9 3.8A9 9 0 0 1 12 20a8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.2A8.4 8.4 0 0 1 4 12a9 9 0 0 1 4.7-8.1A8.4 8.4 0 0 1 12.5 3h.5a9 9 0 0 1 8 8v.5Z"/>',
    bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>',
    settings: '<path d="M12 3v2m0 14v2M3 12h2m14 0h2M5.6 5.6 7 7m10 10 1.4 1.4M18.4 5.6 17 7M7 17l-1.4 1.4"/><circle cx="12" cy="12" r="5"/>',
    chevron: '<path d="m9 18 6-6-6-6"/>', arrow: '<path d="M5 12h14m-6-6 6 6-6 6"/>', back: '<path d="m15 18-6-6 6-6"/>',
    plus: '<path d="M12 5v14M5 12h14"/>', search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>',
    bookmark: '<path d="M5 4a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v18l-7-5-7 5V4Z"/>',
    headphones: '<path d="M3 14v-2a9 9 0 0 1 18 0v2M5 14h3v7H5a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2Zm11 0h3a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2h-3v-7Z"/>',
    check: '<path d="m4 12 5 5L20 6"/>', close: '<path d="M5 5 19 19M19 5 5 19"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    shield: '<path d="m12 2 8 4v6c0 5-3.5 8-8 10-4.5-2-8-5-8-10V6l8-4Z"/><path d="m9 12 2 2 4-4"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    image: '<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="8" cy="8" r="1.5"/><path d="m21 15-5-5L5 21"/>',
    camera: '<path d="M8 5 9.5 3h5L16 5h4a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1Z"/><circle cx="12" cy="12" r="4"/>',
    upload: '<path d="M12 16V3m-5 5 5-5 5 5M4 16v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4"/>',
    edit: '<path d="m16 4 4 4M4 20l4-.7L20 7a2.8 2.8 0 0 0-4-4L3.7 15.3 3 20Z"/>',
    grid: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    play: '<path d="m8 5 12 7-12 7V5Z"/>', pause: '<path d="M7 5v14M17 5v14"/>',
    more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    warning: '<path d="m12 2 10 19H2L12 2Z"/><path d="M12 9v5m0 3h.01"/>',
    globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a15 15 0 0 1 0 18M12 3a15 15 0 0 0 0 18"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l2 2m10 10 2 2M19 5l-2 2M7 17l-2 2"/>',
    database: '<rect x="3" y="4" width="18" height="5" rx="2"/><path d="M3 7v11c0 3 18 3 18 0V7M3 13c0 3 18 3 18 0"/>',
    lock: '<rect x="4" y="10" width="16" height="12" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
    filter: '<path d="M4 5h16M7 12h10m-7 7h4"/>',
    download: '<path d="M12 3v12m-5-5 5 5 5-5M4 17v4h16v-4"/>',
    trash: '<path d="M4 7h16M9 7V4h6v3m-9 0 1 14h10l1-14M10 11v6m4-6v6"/>'
  };
  const icon = (name, cls = '') => `<svg class="${cls}" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${icons[name] || icons.grid}</svg>`;
  function initialState() {
    return {
      route: 'library', previousRoute: 'library', filter: 'all', search: '', chosenMaterial: 'summer',
      importType: '', importFile: '', importStep: 0, importAnalyze: false, importComplete: false,
      selectedTerm: 'soft', collected: ['soft'], selectedBook: 'dailywords', selectedWord: 'soft',
      notebooks: data.notebooks.map(x => ({ ...x })), words: data.words.map(x => ({ ...x })),
      notifications: data.notifications.map(x => ({ ...x })), mistakes: data.mistakes.map(x => ({ ...x })),
      practiceSources: ['notebook'], practiceBookIds: ['dailywords'], practiceAllWords: false,
      practiceMistakeScope: 'current', practiceTextbookUnit: 'unit1', practiceQuestionType: '语境填空', practiceCount: '5 题',
      practiceGenerated: false, practiceAnswer: -1, practiceSubmitted: false,
      textbookUnit: 'unit1', textbookAnswer: -1, textbookSubmitted: false,
      examReady: false, examRunning: false, examFinished: false, examQuestion: 0, examAnswers: {}, examMarked: [], examDraft: '尚未保存',
      examScriptMatched: false, examAudioReady: false, playing: false,
      activeLanguage: '日语', targetLanguages: ['日语', '英语'],
      profile: { displayName: '小遥', birthYear: '', gender: '未填写', timezone: 'Asia/Tokyo' },
      nativeLanguages: ['简体中文'], explanationLanguage: '简体中文',
      learningGoals: ['阅读', '考试'], level: '中级', useDemographics: false,
      serviceAddress: 'https://haruka.example.test', serviceProbe: false,
      theme: 'light', readingTheme: 'light', readingFont: 'serif', readingSize: 18, lineHeight: 2,
      reduceMotion: false, highContrast: false, modelProvider: 'OpenRouter', modelStatus: '未配置',
      speechProvider: 'Gemini TTS', speechSpeed: 1, cacheCleared: false,
      toast: '', modal: '', authMode: 'login', signedIn: true, onboardStep: 0, registrationAccepted: false,
      adminSignedIn: false, adminRoute: 'overview', adminArea: false,
      csvFile: '', csvStep: 0, wordDraft: '', usageRange: '30 天'
    };
  }
  const typeLabel = { novel: '小说', textbook: '课本', exam: '试卷' };
  function visibleMaterials(state) {
    return data.materials.filter(m => (state.filter === 'all' || m.type === state.filter) && `${m.title} ${m.subtitle}`.toLowerCase().includes(state.search.toLowerCase()));
  }
  return { data, escape, icon, initialState, typeLabel, visibleMaterials };
})();
