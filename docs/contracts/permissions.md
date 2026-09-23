# 权限目录与接口/页面映射

状态：设计基线 v0.2，2026-09-23，待工程注册和测试。此文是具体权限代码、依赖与功能映射的唯一目录；[RBAC](../architecture/authorization.md) 定义求值、授予与撤权规则。下面斜线分隔的动作均须展开成独立代码，不能把整串当通配符授予。

## 1. 共同求值规则

所有client业务动作要求active账号、client受众登录资格、动作allow且无匹配deny、self范围和对象状态；admin业务要求admin受众与目标管理范围。角色名只作初始模板，不能出现在日常业务if判断里。派生动作依赖按AND计算，禁止用“有写权限就自动给读权限”补授。

下列“读取来源”指实际使用的对象：材料内容需material.read，收藏需collection.read，练习/成绩需相应read，当前输入的自由文本不要求虚构材料ID。后台/Agent执行同样复核每个动作，配置和权限快照不能当作永久凭证。复合请求受理前列出并验证所有用户明确请求的动作；缺权限返回具体安全错误和可选降级入口，由用户重新选择，不静默删步骤或发起供应商调用。

收藏合并要求collection.read/update/delete；涉及有效词本成员迁移时另需vocabulary_notebook.read/update，确认归属并集后在同事务去重，不能以collection.update绕过成员权限。删除词条仍是独立collection.delete用例，可清其关系但不转移到其他条目；历史学习事实按版本保留。

## 2. 用户端目录

| 权限代码 | 页面/接口动作 | 附加依赖和模型调用含义 |
| --- | --- | --- |
| client.login | 学习端登录、身份续期、access快照/已登录遥测 | 不授予其他业务动作 |
| client.material.list/read | 书库列表/搜索；材料元数据、小说/课本版本内容与出处读取 | read校验类型/文件用途与来源；list无原文，试卷正文/题面/答案另走exam权限与专用DTO |
| client.material.import | 上传或复用本人原文件建立所选类型的新材料 | 确定性提取；复用源需material.read，exam源另需exam.read+exam.edit完整原件资格；目标exam另需exam.import，视觉OCR/进一步AI分析另验analyze |
| client.material.update | 改标题等允许的元数据字段，不接受类型修改 | read、expected_revision；另类型重新处理使用import动作，不由update授权 |
| client.material.reparse | 重解析/重识别并生成新内容版本 | read；新版本不覆盖旧引用；视觉OCR另验analyze，试卷完整原件按exam校对范围检查 |
| client.material.analyze | 所选类型的视觉OCR、AI结构建议、语义补充与抽取；试卷听力题标记和脚本/题目候选匹配 | read、本人相应能力Key、上限、分别明确阶段意图；允许发起供应商调用，不能改变material_type；试卷同时要求exam.read+exam.edit，模型只写候选，人工确认仍由exam.edit控制 |
| client.material.delete | 从书库移除材料 | read；tombstone/引用保留，不删除成绩/收藏 |
| client.reading.progress.update | 小说当前位置/最远进度、课本最近单元位置 | material.read；仅novel/textbook，无该权限仍能只读；考试进度使用场次动作 |
| client.bookmark.read/create/delete | 阅读书签列表/创建/删除 | material.read；本人记录 |
| client.collection.read/create/update/delete | 收藏列表、笔记、标签和exercise_control；自动mastery摘要只读 | create引用来源需read；update/delete需collection.read；学习证据/历史明细另需practice.read及来源read，所属本需notebook.read；不授予改掌握/历史证据权限，不存在调度写入 |
| client.vocabulary_notebook.read/create/update/delete | 多单词本、成员关系和本内计数 | read需collection.read；create/update/delete需notebook.read，成员变更需update+collection.read；删本不删词，删除词另需collection.delete |
| client.vocabulary.csv.export | 导出本人单词CSV | collection.read；含wordbooks列或按本筛选另需vocabulary_notebook.read，缺时可明确选择仅单词内容；无需Key |
| client.vocabulary.csv.import | 预览/确认/分批导入 | collection.create；比较/匹配/跳过已有记录需collection.read，合并另需collection.update；选择v2词本列需notebook.read/update，建新本另需create；无read只能明确直接新增且不比较/恢复既有词本；不从status导入掌握，无需Key |
| client.vocabulary.photo.import | 照片识词及预览 | 新视觉调用要求Key/上限；确认新增需collection.create，读取/补空合并既有记录另需collection.read/update，按所选动作组合检查 |
| client.practice.read | 题目/会话/本人历史成绩、本人AI习题条件预览 | 预览需实际来源read，按本另需notebook.read，按错题另需mistake.read；不要求Key/generate、不调用模型或写学习事实；提交前DTO不返回答案 |
| client.practice.start | 用已有教材题或AI习题集开始会话 | practice.read及题目/来源read；不建立复习计划，不自动出新题或发起供应商调用 |
| client.practice.answer | 保存/提交回答、规则判分、受控提示/揭示、结束已有练习 | practice.read、本人活动场次；服务端记录辅助/不会/跳过，新AI判分另验grade.request；不授予直接改掌握权限 |
| client.practice.generate | 从收藏/词本/教材/错题/诊断等显式生成AI习题 | practice.read、对应来源read；按本另需notebook.read，按错题另需mistake.read；确认本人未过期/未冲突快照、Key/上限；不由start隐含授予，Worker各供应商调用阶段及发布重验 |
| client.practice.mistake.read/favorite | 本人全部错题历史/投影/详情；收藏或取消收藏历史错题 | read需practice.read并按题面/成绩来源裁剪；favorite需read，只写独立本人关系，不改评分、掌握或错误状态；管理员无私有正文旁路 |
| client.practice.grade.request | 主观AI判分/显式重评 | practice.read、已提交答案、Key/上限；规则判分不要求该模型评分权限 |
| client.practice.review.request | 个人成绩标记待审/异议 | practice.read；不直接改分，人工覆盖P1另行注册权限 |
| client.diagnosis.read/generate | 查看/生成薄弱点报告 | generate还需practice.read等实际数据权限、Key/上限；数据不足要说明 |
| client.ai.explain | 词句解释、只读resolve、本人完整缓存结果与书内已查索引 | 实际来源read，批量索引逐项按业务状态裁剪；仅新外部调用要求Key/上限，缓存命中不发起供应商调用；不能作为任意工具操作许可 |
| client.ai.feedback | 对本人解释结果提交反馈 | 该结果当前可读，不授权读取他人内容 |
| client.agent.read/use/delete | 历史对话；创建空会话/新一轮；删除对话 | use需read；空会话不发起供应商调用，新run需Key/上限；工具再验具体业务权限；delete不删除已收藏的独立结果 |
| client.speech.generate | 创建TTS合成请求 | 实际来源read，仅新调用要求本人Key/上限；试卷听力还需exam.read+exam.edit且只能使用已人工确认的脚本版本/题目绑定，成品保持private；标准收藏词音全局合并不授予读/取消他人Job或借Key权限，已有结果只读复用不发起供应商调用 |
| client.speech.play | 读取音频清单、播放/缓存下载，含受控global_word | 实际来源可读且音频有效；试卷场次还需exam_session.read并匹配冻结资产/播放策略，领取新播放另需exam_session.save且由服务端账本计次，ExamListeningAudioBinding不能经通用speech媒体/离线缓存绕过PlayAttempt；开考时由start组合检查；标准词音需本人collection.read、词条/读音/profile匹配，无需生成权限或Key；非匿名全局媒体接口 |
| client.exam.list/read | 试卷列表/版本题面 | read控制专用题面与状态，答案有独立DTO |
| client.exam.import/edit | 创建试卷/题目校对/版本确认；上传文字听力稿、确认听力题/脚本/题目绑定与冻结版本 | import复用上传需material.import；AI结构化/听力候选另验material.analyze；edit需exam.read；文字稿专用上传只接受UTF-8文本/Markdown，P0拒绝原始音频；在本人校对范围使用完整原件另需material.read，普通题面read不授予含答案原件、隐藏听力稿或候选证据的复用/下载 |
| client.exam_session.start/read/save/submit | 开考、恢复/答题卡、存草稿与领取有限次数听力播放、交卷 | start需exam.read，存在必需听力题时还需speech.play且冻结音频/播放策略ready；save/submit需session.read与活动状态/edit_epoch；新听力play attempt需save+speech.play并锁定场次账本，同attempt续播只需read+speech.play且仍校验状态；submit不隐含发起供应商调用批改 |
| client.exam_grade.request/read/regrade | 请求批改、成绩、显式重评 | request/regrade需session.read及已提交答案；需要AI时Key/上限，交卷并批改需同时submit+request |
| client.profile.read/update | 本人资料、学习语言档案、模型/阅读/显示等服务器设置 | update需read、字段白名单、field mask和expected_revision；不允许改角色/状态/登录邮箱/权限/配额/掌握，出生年份/性别为可选本人数据 |
| client.profile.avatar.update | 申请/完成本人头像上传、替换或删除当前头像 | 需profile.read；仅avatar用途临时对象及本人资料revision，不能复用材料/题图FileObject或提交外链；读取当前头像仍需profile.read |
| client.credential.read/manage/test | 掩码/配置与本人模型用量；新增轮换删除Key；供应商测试 | read的用量投影仅限本人且不返回Key/Prompt/回复；manage不返回明文；test需read、本人Key/上限并明确提示会发起一次最小供应商调用 |
| client.job.read/cancel/retry | 本人任务状态/取消/重试 | read校验结果本身所需read；retry重查原业务所有权限/意图/上限，不能绕过unknown确认 |

收藏CSV、照片导入、试卷及音频即使属于同一个页面，也按实际执行路径检查组合权限。文件签名/上传完成/后台事件没有独立“万能文件权限”：继承其引用业务动作与用途的授权要求，无法用任意FileObject ID下载所有文件。

## 3. 管理端目录

| 权限代码 | 操作 | 目标约束 |
| --- | --- | --- |
| admin.login | 管理入口、access、身份续期、管理遥测 | 不隐含管理其他权限 |
| admin.dashboard.view | 运行概览 | 仅授权聚合，无个人成绩/正文 |
| admin.user.read/create/approve/update/enable/disable | 账号列表/详情、创建、审批、基本字段、启停 | 可管理目标范围；create带初始角色还需user.role.assign；无assign仅可建无业务角色pending账号；状态/角色敏感字段不得借update写入 |
| admin.user.role.assign | 绑定/移除角色 | grant boundary、影响闭包、受保护目标、禁止自升权 |
| admin.session.read/revoke | 查看/撤销目标会话 | 明确目标范围、近期重验、持久撤销审计 |
| admin.role.read/create/update/delete | 角色元数据、继承、启停/删除 | 空角色/纯标题描述与授权变化分开；初始allow/deny/继承以及改变有效权限的启停/删除都需role.permission.assign；移除deny同样是授权变化，解绑/迁移用户还需user.role.assign |
| admin.role.permission.assign | 角色allow/deny配置 | 在可授予上限内，不能向任意角色增加超范围权限 |
| admin.permission.read | 权限目录/依赖/有效结果 | 只读注册目录，不能前端新增可执行权限 |
| admin.grant_boundary.read/update | 委派授予上限 | 受保护规则、近期重验，不允许借上限提高自身权限 |
| admin.protected_role.manage | 受保护角色目标操作附加许可 | 仍需具体基础动作权限，不能代替其他校验 |
| admin.menu.read/update | 两端导航/附加显示条件 | 已发布组件白名单、不能降低页面最低权限 |
| admin.auth_policy.read/update | 注册开放/审批/默认角色等 | 默认角色必须可公开分配；不得通过新策略锁死最后管理员 |
| admin.quota.read/update | 账号/全局配额、功能开关 | 部署硬上限、对后续动作生效、版本/审计 |
| admin.model_catalog.read/update | 模型能力与启停 | 不含任何用户Key、不能假定能力已测试 |
| admin.resource_metadata.read | 材料/试卷运维元数据 | 所有者引用/容量/状态，非原文/答卷/文件下载 |
| admin.job.read/cancel/retry | 平台任务元数据与安全运维 | retry仅可重试不触发外部模型调用的阶段；无代用户确认或借Key调用模型的能力 |
| admin.audit.read | 管理审计查询 | 白名单字段；无删除/修改/批量导出 |
| admin.diagnostics.read | Haruka诊断摘要 | 固定模板/范围，不授予任意Loki查询或MyHome数据 |

## 4. 明确的入口例外

| 类型 | 入口 | 限制 |
| --- | --- | --- |
| 公开 | meta、auth/policy、register/login、恢复/邮箱挑战受理与消费、受限匿名遥测 | 对应速率/来源/用途校验；meta仅实例/兼容版本等安全信息，不返回业务资源或权限目录 |
| 身份基础 | 本人access/account摘要、model/language-capabilities、CSRF读取、续期、改密、列出/撤销本人会话、近期重验、退出 | 本人有效会话/必要旧密码或挑战；能力目录仅有效client登录者的已发布安全字段；active与受众登录资格按账号协议；退出可本地清理失效会话；不授权他人数据或邮箱修改 |
| 已登录遥测 | frontend-logs及admin对应入口 | 当前受众login权限；只写白名单遥测，无查询权 |
| 运行探针 | live/readiness | 公网仅最少状态，依赖细节仅内部；不返回配置/秘密 |
| 系统维护 | 截止锁卷、租约清理、Outbox发布、明确GC、已返回产物最低落盘、公共词音错误版本隔离/指针修复 | 固定代码注册的服务主体/动作白名单，不接受用户指定任意principal；目录维护只执行不触发模型调用的公共资产操作，不借个人Key生成 |

每条路由/Worker handler/工具都登记“具体权限集合+范围+状态”或以上具体例外及原因，CI检查未登记项。例外不是通过 path 包含auth/admin 等字符串自动放行。

## 5. 角色模板的可复现生成

learner由发布种子显式列出本期所有client业务权限，不使用运行时通配符；client_readonly包含client.login、material.list/read、bookmark.read、collection.read、vocabulary_notebook.read、practice.read、diagnosis.read、agent.read、speech.play、exam.list/read、exam_session.read、exam_grade.read、profile.read、credential.read、job.read及CSV导出，仍按来源/范围限制。照片、导入、AI、写入及管理权限均不含于只读模板。

operator包含admin.login/dashboard.view/resource_metadata.read/job.read/cancel/retry与diagnostics.read；account_admin只管理授予边界内账号/会话/角色绑定；security_admin只管理可委派角色/菜单/策略；auditor只读审计/诊断。每个模板的完整展开清单在工程种子和权限矩阵中版本化，权限目录新增时默认不给自定义角色。super_admin也受硬数据边界，不能获得未定义的私人内容旁路。

## 6. 验收

PERM-01覆盖每个注册权限的allow/deny/未知/受众错误/范围错误；PERM-02覆盖全部组合依赖及复合请求受理（包括照片只识别/新增/合并权限分离）；PERM-03覆盖页面/按钮/API/Worker/Agent同一动作；PERM-04覆盖新增目录默认拒绝、旧客户端未知权限不放行；PERM-05覆盖模板种子升级不覆盖人工角色授权及只读角色无隐含模型调用路径；PERM-06覆盖无assign的账号/角色创建、初始授权、启停/删除deny角色与用户迁移均不能绕过授予边界。
