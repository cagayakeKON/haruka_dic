# Haruka HTML 交互原型

状态：v0.6，2026-09-23。独立的视觉与交互验证，不是 Flutter/Python 应用交付，不计入 B0/B1/B2 或正式 VB1 验收。

## 打开方式

分别打开[手机端](phone.html#collections)与[电脑端](desktop.html#library)；[入口页](index.html)提供两个链接。手机端是真实的独立页面，没有 iframe：拥有自己的页面壳、触控导航、页面样式和手机阅读视图；电脑端拥有自己的侧栏与宽屏页面。两端只共享示例数据、词本业务规则和部分基础样式/脚本。窗口宽度不会把一端自动变成另一端。桌面窗口打开手机端时，手机画布保持390px；电脑端宽度不足980px时保留宽屏画布，可横向查看。无外部字体、CDN或网络API，可直接打开，也可在仓库根目录启动本机预览：

```powershell
python -m http.server 8765 --bind 127.0.0.1 --directory prototype
```

手机端访问 <http://127.0.0.1:8765/phone.html?v=0.6>，电脑端访问 <http://127.0.0.1:8765/desktop.html?v=0.6>。旧标签页需刷新；两个页面各有独立的内存示例状态，互不自动同步，刷新重置。

## 原型版本与现行依据

该HTML在2026-09-23产品决策前按当时的[多单词本规格](../docs/modules/vocabulary-notebooks.md)、词汇学习方案、练习模块和[CSV v2契约](../docs/contracts/vocabulary-csv.md)制作。视觉仍可用于中性白灰底、蓝色Primary `#2563EB`、清晰排版和手机/电脑独立布局参考；其中每日复习、到期状态、暂停和旧掌握算法已经失效。现行功能以[AI习题与错题库](../docs/modules/ai-exercises.md)、[学习证据](../docs/architecture/vocabulary-learning.md)和[公共作答](../docs/modules/vocabulary-practice.md)为准。

- 旧单词本首页仍展示到期词、新词、系统视图及个人词本；这些到期/每日数字不再是产品需求。多本共用词条的组织关系仍有效。
- 手机仍保留旧“首页→本内词表→单词详情→复习”页面层级；其中“复习”页不能作为未来AI习题页面的流程、状态或验收依据。
- 电脑端使用侧栏和本内导航，手机端使用触控导航与专属阅读页；在各自页面内调整窗口不切换另一端结构，当前筛选、表单、作答草稿与本次会话仍保留。
- 移除手动“已掌握”按钮的方向仍有效。正式产品的掌握状态只读，使用 `exercise_control=active/excluded` 控制是否进入AI习题候选；旧原型中的暂停/恢复命名已经失效。

## 可体验范围

| 入口 | 当前页面内存中的交互 |
| --- | --- |
| 单词本 | 新建、重命名、简介、同语言名称去重；删本保留词条和学习历史 |
| 本内词表（旧原型） | 搜索单词/释义/笔记/标签/来源；其中到期排序已失效，错误次数只可作为未来错题投影的视觉参考 |
| 系统视图（旧原型） | 全部、未分组和常错可参考；暂停、待复习及任何到期视图已失效 |
| 批量整理 | 多选归本、移动、只从当前本移出、确认删除仍可参考；正式候选控制为排除/恢复，旧暂停命名已失效 |
| 单词详情 | 词形/读音/词性/义项、原句及出处、笔记、标签、多个所属本、学习理由/状态/历史 |
| 添加与编辑 | 手动录入；阅读预置词收藏时选本、去重、保留原句及出处；有材料出处的原句只读 |
| 旧每日复习演示（已失效） | 2026-09-23产品已改为显式AI习题与全部错题库；当前HTML仍保留旧交互，仅供历史视觉参考，不能作为正式需求/验收 |
| 旧学习与测验演示 | 仅可参考逐题输入、揭示答案、跳过、结果和会话的局部交互；选题、状态、评分证据和针对性生成以AI习题专题为准 |
| CSV / 照片词表 | 明确标注的两行示例预览；编辑/排除候选、重复跳过/补空/另建、选择目标本、确认后写入内存；照片示例须勾选已核对 |
| CSV导出 | 展示全部或当前完整筛选结果的去重范围和词本归属；尚不生成文件 |
| 书库与阅读 | 保留材料搜索/筛选、示例材料导入、章节/字号/专注模式；手机专属目录、字号、释义面板和来源回跳 |
| 规划说明 | AI助手、试卷及标准词音/朗读仅说明范围 |

旧HTML的反馈和间隔算法已经失效。仍可沿用的边界只有：查看/听读不生成掌握成功；曝光后的回答记录辅助；跳过/退出不算错误；会话冻结题目、答案和学习版本；内容删除或失去资格后拒绝尚未提交的旧题写回。正式掌握只消费有效习题证据，可靠错误/部分正确由服务端自动形成错题账本；规则、重评和作废语义以现行专题为准。

**这仍是有限的交互原型。** 示例“已掌握”和旧到期/每日复习界面来自已被取代的设计；正式产品不实现FSRS、到期队列或日额度。当前原型尚未实现AI习题选择/生成、全部错题自动留档及错题收藏，不能据此反推现行产品范围或正式掌握算法。

没有真实账号、文件上传/CSV解析与导出、相机/OCR、考试、AI/TTS、后端授权、日志或离线缓存。CSV状态快照不恢复可信掌握；补空若实质改变词条则重新评估。不会接收真实Key、调用系统TTS或连接MyHome。书库等其他模块保留既有示例，未宣称完成最新文档中的全部页面和业务。

阅读只支持明确标记的预置词，不支持任意选区解释。来源回跳保留材料、章节、段落及可用选区位置；正式跨版本定位以[出处契约](../docs/contracts/content-locator.md)为准。

## 文件与移植约束

- [index.html](index.html)：选择手机端或电脑端的入口页；[phone.html](phone.html)、[desktop.html](desktop.html)：两个独立的交互页面和导航结构。
- [styles.css](styles.css)：共用基础样式；[phone.css](phone.css)和[desktop.css](desktop.css)：分别属于手机端与电脑端的布局。
- [notebooks.css](notebooks.css)：词本共用视觉；[notebooks-phone.css](notebooks-phone.css)：手机词本专属排版和触控操作。
- [data.js](data.js)：原创材料与预置解释；[notebooks-data.js](notebooks-data.js)：14个虚构词条、3本及标注的示例历史。
- [app.js](app.js)：共享路由/动作与电脑端书库/阅读；[phone.js](phone.js)：手机端书库、阅读、面板与页头。入口显式选择平台，不靠窗口宽度推断。
- [notebooks.js](notebooks.js)：词本、词条、筛选、批量、归本和示例导入。
- [notebooks-study.js](notebooks-study.js)：旧每日复习演示及局部会话记录；其选题、间隔和状态规则已经失效。

| 原型动作 | 正式权限边界 |
| --- | --- |
| 单词内容、笔记、标签、排除/恢复AI习题候选 | client.collection.read/create/update/delete；掌握及其证据只读 |
| 词本和成员关系 | client.vocabulary_notebook.read/create/update/delete及collection.read |
| CSV预览/导入/导出、照片识词 | 对应client.vocabulary.csv.import/export、client.vocabulary.photo.import，按比较/归本/新本动作追加权限 |
| AI习题、提交、学习历史、错题/收藏 | client.practice.read/start/answer/generate、client.practice.mistake.read/favorite及实际来源/词本读取权限 |
| 阅读、新解释、朗读 | 材料read；新解释需client.ai.explain；朗读需speech权限；新模型调用检查本人Key |

上述是移植边界，不是HTML中已实现的鉴权或埋点。[权限](../docs/contracts/permissions.md)、[API](../docs/contracts/api.md)、[词汇学习](../docs/architecture/vocabulary-learning.md)和[观测](../docs/operations/observability.md)以专题为准。HTML用原生控件和可访问名称，不建立未来Flutter测试ID注册表。

## 验证记录

本轮双入口拆分与审查见[手机/电脑端分离v0.6](../docs/delivery/reviews/2026-09-23-prototype-platform-split.md)。前一轮交互见[单词本v0.5](../docs/delivery/reviews/2026-09-22-notebooks-prototype.md)；更早记录见[手机主页与导航v0.4](../docs/delivery/reviews/2026-09-22-mobile-home.md)、[手机重设计v0.3](../docs/delivery/reviews/2026-09-22-mobile-prototype.md)及[桌面与配色v0.2](../docs/delivery/reviews/2026-09-22-prototype.md)。

浏览器模拟手机尺寸不等于Android真机、软键盘或Flutter平台验收。
