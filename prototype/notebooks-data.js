"use strict";

// Fictional fixtures for the HTML prototype, not real learning results.
const NOTEBOOK_DEMO = [
  { id: "daily-ja", name: "日语日常", language: "日语", description: "把每天用得上的表达，慢慢变成自己的。", color: "blue" },
  { id: "reading-ja", name: "阅读拾光", language: "日语", description: "读故事时遇见的词，连同语境一起留下。", color: "violet" },
  { id: "english", name: "Everyday English", language: "英语", description: "Small words. More ways to say it.", color: "sand" }
];
function demoWord(id, text, reading, meaning, options = {}) {
  return { id, text, reading, meaning, language: "日语", pos: "名词", context: "", origin: "manual", sourceTitle: "手动录入", notes: "", tags: [], notebookIds: [], status: "new", studyControl: "active", due: null, errorCount: 0, records: [], learningRevision: 1, ...options };
}
const demoSuccess = (date, skill) => ({ date, skill, outcome: "correct", revision: 1, sample: true });
const VOCABULARY_DEMO = [
  demoWord("seed-calm", "穏やか", "おだやか", "平静的；温和的。", { pos: "形容动词", notebookIds: ["daily-ja", "reading-ja"], bookId: "cafe", chapter: 0, paragraph: 4, origin: "material", sourceTitle: "雨あがりの喫茶店", context: "言葉にしなくても、ここには確かに、穏やかな時間が流れている。", notes: "也可以形容人的性格：穏やかな人。", tags: ["日常", "氛围"], status: "learning", due: 0, records: [demoSuccess("09-15", "词义识别")] }),
  demoWord("seed-detour", "寄り道", "よりみち", "顺路绕道；途中顺便去别处。", { notebookIds: ["daily-ja"], context: "帰りに本屋へ寄り道した。", tags: ["日常"], notes: "寄り道する：顺路去一下。" }),
  demoWord("seed-help", "助ける", "たすける", "帮助；救助。", { pos: "动词", notebookIds: ["daily-ja"], status: "learning", due: 0, context: "困っている友達を助ける。", tags: ["动作"], records: [demoSuccess("09-14", "主动回忆")] }),
  demoWord("seed-nostalgia", "懐かしい", "なつかしい", "令人怀念的。", { pos: "形容词", notebookIds: ["reading-ja"], status: "mastered", due: 0, context: "この歌を聞くと、学生時代が懐かしい。", tags: ["情绪"], records: [demoSuccess("09-01", "主动回忆"), demoSuccess("09-04", "词义识别"), demoSuccess("09-15", "主动回忆")] }),
  demoWord("seed-home", "故郷", "ふるさと", "故乡；家乡。", { notebookIds: ["reading-ja"], context: "久しぶりに故郷へ帰る。", tags: ["生活"] }),
  demoWord("seed-receive", "受け取る", "うけとる", "接收；领到。", { pos: "动词", notebookIds: ["daily-ja"], status: "learning", due: 2, context: "駅で荷物を受け取った。", tags: ["动作"] }),
  demoWord("seed-promise", "約束", "やくそく", "约定；承诺。", { notebookIds: ["daily-ja"], status: "relearning", due: 0, errorCount: 3, context: "友達との約束を守る。", tags: ["常用"], records: [{ date: "09-21", skill: "主动回忆", outcome: "wrong", revision: 1, sample: true }] }),
  demoWord("seed-heart", "心", "こころ", "心；内心。", { notebookIds: ["reading-ja"], status: "mastered", due: 6, context: "心に残る一冊だった。", records: [demoSuccess("09-01", "主动回忆"), demoSuccess("09-06", "词义识别"), demoSuccess("09-18", "主动回忆")] }),
  demoWord("seed-quiet", "静か", "しずか", "安静的。", { pos: "形容动词", notebookIds: ["reading-ja"], studyControl: "suspended", context: "静かな部屋で本を読む。", tags: ["氛围"] }),
  demoWord("seed-incomplete", "続く", "つづく", "", { pos: "动词", tags: ["待整理"] }),
  demoWord("seed-window", "window", "/ˈwɪndoʊ/", "窗；窗户。", { language: "英语", notebookIds: ["english"], bookId: "morning", chapter: 0, paragraph: 0, origin: "material", sourceTitle: "The Art of Slow Mornings", context: "Before the city gets loud, I open the kitchen window.", status: "mastered", due: 0, records: [demoSuccess("09-01", "主动回忆"), demoSuccess("09-05", "词义识别"), demoSuccess("09-16", "主动回忆")] }),
  demoWord("seed-wander", "wander", "/ˈwɑːndər/", "漫步；闲逛。", { language: "英语", pos: "动词", notebookIds: ["english"], context: "We wander through the quiet streets.", tags: ["旅行"] }),
  demoWord("seed-notice", "notice", "/ˈnoʊtɪs/", "注意到；察觉。", { language: "英语", pos: "动词", notebookIds: ["english"], status: "learning", due: 0, errorCount: 2, context: "I notice the light on the wall.", tags: ["动作"] }),
  demoWord("seed-space", "space", "/speɪs/", "空间；空隙。", { language: "英语", context: "Leave a little space for yourself.", tags: ["日常"] })
];
