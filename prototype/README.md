# Haruka HTML 交互原型

状态：v0.3，2026-09-22。独立的视觉与交互验证，不是 Flutter/Python 应用交付，不计入 B0/B1/B2。

## 打开方式

直接在现代 Edge / Chrome 中打开 [index.html](index.html)。没有安装依赖、外部字体、CDN 或网络 API。也可在仓库根目录使用已有 Python 启动本机预览：

```powershell
python -m http.server 8765 --bind 127.0.0.1 --directory prototype
```

然后访问 <http://127.0.0.1:8765>。

## 本轮设计

- 用户要求年轻化、现代美观，保留杂志式标题、留白和封面排版。
- 按最新反馈移除奶油白/抹茶绿主题，改为白色页面、浅灰侧栏、深灰文字与 Primary 主色。当前按常见蓝色 `#2563EB` 实现；“Markdown Primary”没有统一色值，这一具体取值为暂定设计解释。
- 书库直接展示全部材料，不设置“继续阅读 / 最近在读”区域。
- 桌面保留侧栏与杂志式书封排版。手机采用独立页面结构：纵向材料列表、底部导航、筛选底部弹窗和词句卡片；不把桌面网格简单缩小。
- 手机阅读页采用通栏正文和独立的目录/字号/朗读工具栏，隐藏全局导航；解释从底部弹出，关闭后恢复原文焦点与位置。收藏卡片与释义显示实际来源句，只有原句匹配预置翻译时才显示该翻译。
- 页面宽度不超过680px，或紧凑横屏宽度不超过1000px且高度不超过500px时，使用手机结构。调整字号及横竖屏/桌面断点切换时按段落与段内比例恢复阅读位置。
- 封面采用本地 CSS/SVG 绘制，内容为原创示例，不依赖外部图片。

## 可体验范围

| 入口 | 当前能力 |
| --- | --- |
| 书库 | 标题/副标题搜索、类型与语言筛选、标题排序、无结果状态；桌面可切换封面/列表，手机使用纵向列表及筛选弹窗 |
| 导入 | 学习材料/试卷用途选择；添加一份预置材料；重复添加提示 |
| 阅读 | 章节切换、字号调整；桌面支持专注模式，手机使用专属阅读页及目录/字号底部弹窗；点击木漏れ日、穏やか、window 查看预置解释 |
| 收藏 | 保存预置词及来源、去重、搜索、掌握状态/筛选、移除确认、回到原文段落 |
| 偏好 | 调整阅读字号；手机从书库/收藏顶部头像按钮进入 |
| 规划说明 | 学习练习、AI 助手、试卷、朗读入口只展示范围说明 |

所有示例状态仅在当前页面内存中保存，刷新重置。没有真实账号、文件上传/解析、CSV、考试答题/评分、AI/TTS、后端授权、日志采集或离线缓存。不会接收真实 Key、调用系统 TTS 或连接 MyHome。试卷首版格式范围仍待确认。

只支持点击明确标记的预置词；不声称支持任意选区解释。收藏保留示例材料/章节/段落/词语起点，回跳标记对应段落；正式跨版本定位以 [材料与阅读](../docs/modules/materials-reading.md) 为准。

## 文件与移植约束

- [index.html](index.html)：应用外壳与入口。
- [styles.css](styles.css)：颜色变量、排版、书封、响应式及焦点状态。
- [mobile.css](mobile.css)：手机专属页面、触控区域、安全边距与底部弹窗。
- [data.js](data.js)：原创材料、词典和初始收藏。
- [app.js](app.js)：路由、内存状态和交互。
- [mobile.js](mobile.js)：手机专属视图与操作，共用数据和业务动作。

| 原型动作 | 正式权限 | 正式事件映射 |
| --- | --- | --- |
| 书库/阅读/来源回跳 | client.material.list/read | screen.viewed、reading.chapter.opened、source.navigation.result |
| 导入材料/试卷 | client.material.import；试卷另验 client.exam.import | material.import.requested/completed/failed |
| 新解释 | client.ai.explain、来源 read、本人 Key | explanation.requested/completed |
| 收藏新增/掌握/移除 | client.collection.create/update/delete、来源 read | collection.saved；正式成功以服务端提交为准 |
| 云端朗读 | client.speech.generate/play、来源 read；新合成需本人 Key | speech.requested/generated、playback.started/failed |

上述为后续映射，不是 HTML 中已存在的安全机制或埋点。具体 [权限](../docs/contracts/permissions.md)、[API](../docs/contracts/api.md)、[数据事务](../docs/architecture/data-jobs.md)、[日志](../docs/operations/observability.md) 仍以专题为准。当前通过可访问名称/原生 HTML 控件定位，不创建未来 Flutter Test ID 注册表或测试旁路。浏览器模拟窄屏不等于 Android/Windows 原生验收。

本轮实际验证与独立审查记录见 [移动端重设计记录](../docs/delivery/reviews/2026-09-22-mobile-prototype.md)；此前桌面与配色记录见 [v0.2审查记录](../docs/delivery/reviews/2026-09-22-prototype.md)。
