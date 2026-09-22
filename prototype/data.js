"use strict";

// Original, fictional passages for this visual prototype. No remote services.
const DEMO_BOOKS = [
  {
    id: "cafe", title: "雨あがりの喫茶店", subtitle: "雨后的咖啡馆", language: "日语", type: "小说", format: "EPUB", cover: "cafe", number: "01",
    chapters: [
      { title: "雨がやんだ午後", paragraphs: [
        "雨がやんだ午後、私はいつもと違う道を歩いていた。濡れた石畳が、空の色を静かに映している。どこかから、挽きたてのコーヒーの香りがした。",
        "角を曲がると、小さな喫茶店が見えた。窓辺には古い本が並び、白いカップから湯気が立ちのぼっている。扉には、手書きの文字で「どうぞ、ごゆっくり」と書かれていた。",
        "木漏れ日がテーブルの上で揺れていた。私は窓のそばの席に座り、鞄から読みかけの本を取り出した。忙しい毎日の中で、こんなふうに何もしない時間は、久しぶりだった。",
        "「今日は、いい天気になりましたね。」店主がカップを置きながら言った。私はうなずいて、窓の外を見た。水たまりの中に、小さな青空があった。",
        "ページをめくる音と、カップが触れ合う音。言葉にしなくても、ここには確かに、穏やかな時間が流れている。もう少しだけ、この場所にいようと思った。"
      ] },
      { title: "一冊の忘れもの", paragraphs: [
        "翌週、同じ席には一冊の青いノートが置かれていた。表紙には名前も日付もなく、小さな葉っぱの絵だけが描かれている。",
        "店主に尋ねると、誰かの忘れものだという。「最後のページを読んでみてください。」そう言って、静かに笑った。",
        "そこには一行だけあった。「また来たくなる場所がある。それだけで、今日は少しいい日だ。」私はその言葉を、心の中でもう一度読んだ。"
      ] },
      { title: "いつもの席で", paragraphs: [
        "季節が変わっても、窓辺の席から見える木はそこにあった。葉の色が変わり、光の角度が変わる。その小さな違いに気づくのが、楽しみになっていた。",
        "私は新しい本を開いた。まだ知らない言葉が、ページの向こうで待っている。わからないことがあるのは、悪いことではない。今日も少しずつ、読んでいこう。"
      ] }
    ]
  },
  { id: "morning", title: "The Art of Slow Mornings", subtitle: "给清晨，一点慢下来的时间", language: "英语", type: "其他", format: "MD", cover: "morning", number: "02", chapters: [{ title: "A little room for the day", paragraphs: [
    "Before the city gets loud, I open the kitchen window. The morning air smells of rain and the bread from the bakery downstairs. For a moment, there is nothing I need to hurry toward.",
    "I used to fill every quiet minute with something useful. Now I leave a little space. I make tea, read a page, and watch the light move across the wall.",
    "A slow morning does not have to be a perfect morning. Sometimes it is just five minutes at the table, with both hands around a warm cup. That is enough for today."
  ] }] },
  { id: "walk", title: "街角を歩けば", subtitle: "在街角，遇见日常", language: "日语", type: "小说", format: "EPUB", cover: "walk", number: "03", chapters: [{ title: "知らない道", paragraphs: [
    "駅を出て、いつもとは反対の方向へ歩いた。地図は見なかった。今日は、少しだけ迷ってみたかった。",
    "小さな花屋の前で足を止めた。店先には、名前のわからない黄色い花が並んでいる。風が吹くたびに、花びらが楽しそうに揺れていた。",
    "知らない道にも、誰かにとっての日常がある。そのことを考えると、この街が少し近くなった気がした。"
  ] }] },
  { id: "notes", title: "日常のことばノート", subtitle: "把想说的话，好好记下来", language: "日语", type: "其他", format: "MD", cover: "notes", number: "04", chapters: [{ title: "暮らしの中で", paragraphs: [
    "「おかえり」と言われると、家に帰ってきたことを実感する。短い言葉なのに、そこにはたくさんの気持ちが入っている。",
    "「お疲れさま」は、相手の一日をそっと受け止める言葉だと思う。何をしたかを全部知らなくても、その時間を大切にすることはできる。"
  ] }] },
  { id: "everyday", title: "Everyday, in English", subtitle: "从生活里的小事开始表达", language: "英语", type: "教材", format: "MD", cover: "everyday", number: "05", chapters: [{ title: "Small talk, real connections", paragraphs: [
    "A conversation can begin with something small. Ask about the book on the table, or the music playing in the café. You do not need a perfect opening sentence.",
    "Listen to the answer. A good question gives the other person room to share a story. When you are curious, everyday moments become chances to connect.",
    "Try this: describe a place you enjoy in three sentences. What can you see? What can you hear? How do you feel when you are there?"
  ] }] },
  { id: "exam", title: "日本語読解 · 練習問題", subtitle: "阅读理解 · 示例试卷", language: "日语", type: "试卷", format: "示例", cover: "exam", number: "06", chapters: [] }
];

const DICTIONARY = {
  "木漏れ日": { reading: "こもれび", kind: "名词", meaning: "从树叶间隙洒落的阳光。", detail: "木（树木）＋ 漏れ（漏出）＋ 日（阳光）。一个词，装下了光穿过树叶时的温柔。", example: "木漏れ日がテーブルの上で揺れていた。", translation: "树隙间的阳光，在桌面上轻轻摇曳。" },
  "穏やか": { reading: "おだやか", kind: "形容动词", meaning: "平静的；温和的。", detail: "可以形容天气、气氛或人的性情。文中的「穏やかな時間」指宁静而舒适的时光。", example: "穏やかな時間が流れている。", translation: "宁静的时光缓缓流淌。" },
  "window": { reading: "/ˈwɪndoʊ/", kind: "名词", meaning: "窗；窗户。", detail: "这里指厨房的窗户。open the window 表示「打开窗户」。", example: "I open the kitchen window.", translation: "我打开厨房的窗户。" }
};
