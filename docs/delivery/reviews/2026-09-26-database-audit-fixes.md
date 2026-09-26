# 数据库业务缺口修订

日期：2026-09-26；阶段1内文档小阶段DBDESIGN4，基线`0f031ae`。用户授权先修复[AUDIT1](2026-09-26-business-design-audit.md)的6项数据库问题；本轮修改设计书、直接相关契约、关系/收敛清单和实施追踪，不修改原型、正式代码、生成字典、ORM/迁移或运行数据库。

## 1. 修订映射

| 原问题 | 修订 | 主要正文 |
| --- | --- | --- |
| DB-01 根级教材Lesson | unit_id可空；根级与Unit下课程分别部分唯一；版本/父归属与混合根顺序由共同锁内发布服务校验，不伪造Unit | [材料表](../../architecture/database-materials.md#32-课本专用结构) |
| DB-02 直接题目收藏 | card/question互斥；物理题源/题版本/作答上下文列、规范摘要部分唯一；none与不同已提交Attempt分别保存，同Attempt重评不覆盖；源/归本/提交权限、锁序、GC及tombstone明确 | [收藏表](../../architecture/database-learning.md#21-collection_items--收藏条目)、[业务规则](../../modules/vocabulary-practice.md#题目直接收藏) |
| DB-03 共享请求身份 | 冻结词条/profile版本/strict、学习与选择代次、slot/执行代次；resolve不写请求；旧回调不能覆盖新选择或订阅新执行 | [请求字段](../../architecture/database-learning.md#66-收藏词音字段与-speech_requests)、[缓存](../../architecture/learning-cache.md#51-收藏库标准单词发音的全局缓存) |
| DB-04 格式派生 | global_word_audios同表synthesized/derived分支，根1:N派生、一对象一行；独立派生唯一、对象校验、受控转码容量预留/恢复/GC，无新供应商attempt | [共享成品](../../architecture/database-learning.md#65-global_word_audiosglobal_word_lookup_statesglobal_word_generation_slots)、[共享预留](../../architecture/database-identity.md#global_storage_reservations) |
| DB-05 实际合成出处 | 合成根保存冻结请求规格/适配器/API及实际路由/模型修订known/unknown，排除私人生产者/Key/Job/原始响应，派生引用根出处 | [共享成品](../../architecture/database-learning.md#65-global_word_audiosglobal_word_lookup_statesglobal_word_generation_slots)、[TTS](../../architecture/tts-adapters.md) |
| DB-06 听力问题代码 | 统一listening_type_review/listening_binding_review/listening_script_missing/listening_audio_missing，纳入language_confirmation_required，字典/服务/API/ready使用同一注册集合 | [试卷候选契约](../../contracts/material-structures.md#51-首版输入与候选结构)、[材料表](../../architecture/database-materials.md) |

不增加实体表：目标仍142张（含条件邮件表1张），B0仍12张，Redis仍R01～R19。共享格式成品是既有音频表的受控一层自关联；每种格式有独立记录/唯一键/对象/清理状态，不用一个不断增长的JSON数组，也不把转码计为新合成代次。共享容量沿既有表分支处理，合成继续绑定本人生产Job，确定性转码只用已发布公共根和冻结spec。

UI-01～03、DOC-01，以及后续讨论的空格/硬换行排版协议细化不在本轮范围；不借数据库修订宣称原型同步或完整业务已实现。

## 2. 独立审查

第1轮非作者审查分工：materials_design核对DB-01/02/06与题目来源/约束/锁；learning_design核对DB-03～05的成品、请求、缓存/API及生命周期；identity_design定点复核派生容量的受理/发布/恢复/GC。主审集中修订后最多进行一次直接影响的定点复核，不开展第三轮全仓审查。

首轮结果：materials_design确认根级Lesson、题目收藏和听力代码的修订闭合；learning_design确认共享请求、派生及实际出处已有对应修复，要求把waiting/ready执行身份CHECK明确限定为global_word，避免与private全空条件冲突，并建议说明broken成品恢复边界。identity_design发现新增P2（D4-R1）：转码不再使用私人Job/模型slot后，容量预留缺少执行租约/fence和可恢复对象定位，无法落实崩溃恢复及无在途写入证明。

集中修订：补齐transcode_fence、执行lease、受控Bucket/对象键协议和output_candidate；每个reservation/fence使用不可覆盖对象，领取/接管/候选/发布逐步比较当前lease/fence。恢复先核对已有成品/候选和完整对象，全部候选受预留容量上界约束，不能确认旧写入结束时保持unknown，不因TTL退容量；转码继续不依赖私人Job/Key/供应商attempt。私有语音分支约束已明确；broken派生只在确切既有对象版本/摘要恢复后重新ready，不能偷换不可变成品或自动重合成。

第2轮identity_design定点确认D4-R1关闭，执行与对象恢复、容量/unknown和共享成品发布衔接一致，无新增P1/P2；learning_design确认私有语音约束消除歧义、broken恢复边界正确，以及本记录六项问题映射和设计/实现边界准确。未修订的材料/题目范围保留首轮独立证据，不重复全仓审查。两轮必要修订均已关闭，没有开启第三轮。

## 3. 检查与后续工程验收

本轮仅执行必要文档检查：改动Markdown的本地链接/锚点/文件路径/代码围栏、markdownlint、git diff --check；核对142表/19类Redis计数、旧约束残留及需求/计划一致性。不运行应用、数据库、原型或真实供应商测试。

实际结果：17份Markdown本地链接/锚点/文件路径/围栏0错误、0未解析，markdownlint通过，git diff --check通过；关系清单142行/142个唯一目标名，Redis R01～R19共19类，未改生成字典仍12张B0表。旧强制Unit、exercise仅卡片来源、全局音频无分支唯一及旧听力别名不再作为现行规则；历史审查保留原证据，新契约中旧代码仅用于明确禁止别名。

AUDIT1的DB-01～DB-06在设计文档层修订完成；不将该结论扩展为已迁移、已运行或性能已验收。UI-01～03与DOC-01仍开放。

后续工程验收仍须证明根级/混合教材目录、跨版本拒绝、跨设备题目收藏唯一/提交可见性、声音与执行代次切换、共享成品出处、转码并发/中断/字节计量/GC、跨账号及Redis丢失。对应COL-005/006、LC-10和材料契约已经同步，迁移只按相关阶段切片实施；本轮不勾选这些用例。
