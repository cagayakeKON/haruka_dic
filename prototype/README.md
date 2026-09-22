# Haruka HTML 交互原型

状态：v0.5，2026-09-22。独立的视觉与交互验证，不是 Flutter/Python 应用交付，不计入 B0/B1/B2 或正式 VB1 验收。

## 打开方式

从 [phone.html](phone.html) 直接体验手机单词本首页。桌面窗口展示390px手机视口，手机浏览器使用可用宽度；内嵌同一份交互页面，没有业务状态副本。[完整页面](index.html#collections)支持桌面与手机。无外部字体、CDN或网络API，可直接打开，也可在仓库根目录启动本机预览：

```powershell
python -m http.server 8765 --bind 127.0.0.1 --directory prototype
```

访问 <http://127.0.0.1:8765/phone.html?v=0.5>；旧标签页需刷新。示例状态只保存在当前页面内存，刷新重置。

## 本轮设计与依据

按最新[多单词本规格](../docs/modules/vocabulary-notebooks.md)、[词汇学习架构](../docs/architecture/vocabulary-learning.md)、[练习模块](../docs/modules/vocabulary-practice.md)和[CSV v2契约](../docs/contracts/vocabulary-csv.md)重做单词本。保留中性白灰底、蓝色Primary `#2563EB`和清晰排版；不设“继续阅读”。

- 单词本首页展示按目标语计算的到期词、新词、系统视图及个人词本。多本共用词条和学习进度；首页汇总去重，本内各自计数。
- 手机为“首页→本内词表→单词详情→复习”独立页面层级，使用专属顶栏、返回和底部导航。表单、归本、筛选使用底部面板，批量整理和详情主操作放在底部。
- 桌面使用侧栏和本内导航；小于1024px使用紧凑结构。切换结构保留筛选、表单、作答草稿与本次会话。
- 移除旧手动“已掌握”按钮。学习状态只读，暂停/恢复是独立操作；修改笔记、标签、归属不重置学习，实质词条修改创建新学习版本并保留旧记录。

## 可体验范围

| 入口 | 当前页面内存中的交互 |
| --- | --- |
| 单词本 | 新建、重命名、简介、同语言名称去重；删本保留词条和学习历史 |
| 本内词表 | 搜索单词/释义/笔记/标签/来源；目标语、标签、来源、状态筛选及词形/到期/错误次数排序 |
| 系统视图 | 全部、未分组、常错、暂停；词表内筛选新词、未掌握、已掌握、待复习及待补全 |
| 批量整理 | 多选归本、移动、只从当前本移出、暂停/恢复、确认删除；跨语言归本阻止，重复归本不复制词条 |
| 单词详情 | 词形/读音/词性/义项、原句及出处、笔记、标签、多个所属本、学习理由/状态/历史 |
| 添加与编辑 | 手动录入；阅读预置词收藏时选本、去重、保留原句及出处；有材料出处的原句只读 |
| 每日复习 | 按语言及单本/多本/全部范围去重，排除暂停和缺释义词，到期/重学优先、新词随后；选择本轮数量 |
| 学习与测验 | 学习预览；按现成释义回忆词形，精确规范化匹配；不会、揭示答案、跳过、结束、错词加练、结果与会话记录 |
| CSV / 照片词表 | 明确标注的两行示例预览；编辑/排除候选、重复跳过/补空/另建、选择目标本、确认后写入内存；照片示例须勾选已核对 |
| CSV导出 | 展示全部或当前完整筛选结果的去重范围和词本归属；尚不生成文件 |
| 书库与阅读 | 保留材料搜索/筛选、示例材料导入、章节/字号/专注模式；手机专属目录、字号、释义面板和来源回跳 |
| 规划说明 | AI助手、试卷及标准词音/朗读仅说明范围 |

练习反馈遵守关键边界：查看/听读不生成掌握成功；曝光后的回答按有辅助记录；一次答对最多由新词进入学习中；跳过/退出不算错误；同一学习机会的反馈后订正只作训练；未到期正向加练不增加间隔，首次可靠负面仍可触发重学。会话冻结题目、答案和学习版本；词条修改、暂停或删除后，尚未作答的旧题提示不可用，不写入新版本；已作答题保留冻结反馈，可继续下一题。

**这仍是有限的交互原型。** 示例“已掌握”来自标注的种子历史，新作答不模拟跨日达标。到期以相对天数演示，并未实现FSRS、服务端机会归并/配额/并发、多设备、跨日与时区调度。只演示词形回忆，不声称完成全部题型或正式掌握算法。

没有真实账号、文件上传/CSV解析与导出、相机/OCR、考试、AI/TTS、后端授权、日志或离线缓存。CSV状态快照不恢复可信掌握；补空若实质改变词条则重新评估。不会接收真实Key、调用系统TTS或连接MyHome。书库等其他模块保留既有示例，未宣称完成最新文档中的全部页面和业务。

阅读只支持明确标记的预置词，不支持任意选区解释。来源回跳保留材料、章节、段落及可用选区位置；正式跨版本定位以[出处契约](../docs/contracts/content-locator.md)为准。

## 文件与移植约束

- [index.html](index.html)、[phone.html](phone.html)：应用外壳及手机预览。
- [styles.css](styles.css)、[mobile.css](mobile.css)：公共样式及既有手机书库/阅读样式。
- [notebooks.css](notebooks.css)：单词本、词表、详情、表单、复习与结果的桌面/手机样式。
- [data.js](data.js)：原创材料与预置解释；[notebooks-data.js](notebooks-data.js)：14个虚构词条、3本及标注的示例历史。
- [app.js](app.js)、[mobile.js](mobile.js)：公共路由、弹窗、导航及书库/阅读。
- [notebooks.js](notebooks.js)：词本、词条、筛选、批量、归本和示例导入。
- [notebooks-study.js](notebooks-study.js)：冻结本轮题目、局部作答规则和会话记录；不是正式调度器。

| 原型动作 | 正式权限边界 |
| --- | --- |
| 单词内容、笔记、标签、暂停/恢复 | client.collection.read/create/update/delete；掌握和调度只读 |
| 词本和成员关系 | client.vocabulary_notebook.read/create/update/delete及collection.read |
| CSV预览/导入/导出、照片识词 | 对应client.vocabulary.csv.import/export、client.vocabulary.photo.import，按比较/归本/新本动作追加权限 |
| 复习、提交、学习历史 | client.practice.read/start/answer及实际来源/词本读取权限 |
| 阅读、新解释、朗读 | 材料read；新解释需client.ai.explain；朗读需speech权限；新模型调用检查本人Key |

上述是移植边界，不是HTML中已实现的鉴权或埋点。[权限](../docs/contracts/permissions.md)、[API](../docs/contracts/api.md)、[词汇学习](../docs/architecture/vocabulary-learning.md)和[观测](../docs/operations/observability.md)以专题为准。HTML用原生控件和可访问名称，不建立未来Flutter测试ID注册表。

## 验证记录

本轮验证与两轮独立审查见[单词本v0.5](../docs/delivery/reviews/2026-09-22-notebooks-prototype.md)。此前记录：[手机主页与导航v0.4](../docs/delivery/reviews/2026-09-22-mobile-home.md)、[手机重设计v0.3](../docs/delivery/reviews/2026-09-22-mobile-prototype.md)、[桌面与配色v0.2](../docs/delivery/reviews/2026-09-22-prototype.md)。

浏览器模拟手机尺寸不等于Android真机、软键盘或Flutter平台验收。
