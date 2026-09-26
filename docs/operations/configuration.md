# 运行配置与健康契约

状态：设计基线 v0.3，2026-09-23；本地dev/test基础设施配置已在 [B0切片](../delivery/reviews/2026-09-22-scaffold-infrastructure.md) 部分实现，生产及完整业务健康尚未实现。本篇维护配置来源、隔离、限额、健康与留存参数；有序发布、迁移、故障和恢复步骤统一在 [部署与恢复](deployment-recovery.md)，证据门禁见 [交付验收](../delivery/acceptance.md)。开发步骤见 [开发指南](../engineering/development.md)，MyHome 已调查事实见 [复用方案](myhome-integration.md)。不包含真实连接信息或秘密。

工程包/正式CLI、开发profile、客户端安装身份与环境构建矩阵由 [脚手架蓝图](../engineering/scaffold.md) 维护；这里的INSTANCE_ID始终指部署实例，不用客户端包名或release替代。

## 1. 配置来源与隔离

推荐使用pydantic-settings解析后端类型化配置；部署Secret高于普通环境配置，测试只使用明确测试配置。来源/优先级在初始化时固定，不允许本地.env悄悄覆盖生产Secret。能力依据见 [Pydantic Settings](https://pydantic.dev/docs/validation/latest/concepts/pydantic_settings/)。

配置分成部署基础项、受审计管理策略、个人模型配置和客户端本地偏好，不能互相回退：

| 类别 | 示例设计键/内容 | 来源与失败策略 |
| --- | --- | --- |
| 应用识别 | APP_ENV、INSTANCE_ID、PUBLIC_BASE_URL、RELEASE、允许Origin | 部署配置；INSTANCE_ID稳定区分缓存，不随重启随机变化；生产域名缺失不启动公开服务 |
| 数据库 | DATABASE_URL、独立维护凭据、连接池/超时、DB_APPLICATION_NAME | Haruka专用数据库；运行DML与迁移/维护身份分离，UTC/search_path和最小权限按[数据库规范](../engineering/database.md)，API/Worker不取得维护凭据；连接失败readiness不通过 |
| 会话/权限 | REDIS_URL、HARUKA_NAMESPACE、session TTL、issuer、原生JWT算法/签名key版本 | 签名秘密独立；Cookie名/受众固定；Redis/PG失败关闭认证 |
| 加密 | CREDENTIAL_KEYRING、ACTIVE_ENCRYPTION_KEY_VERSION、挑战/回执用途隔离密钥 | 独立Secret，版本对应encryption_key_version而非用户credential_version；未知版本不当明文读取或换公共Key |
| 队列 | KAFKA_BOOTSTRAP、topics/groups、ack/retry/lease参数 | Haruka namespace；不可达保留Outbox，不丢已受理Job |
| 对象存储 | S3_ENDPOINT、PUBLIC_S3_ENDPOINT、bucket、应用凭据、签名TTL | 私有Haruka Bucket；地址需三端可达；不能使用MyHome root凭据 |
| 邮件（条件） | MAIL_ENABLED、发件身份、服务认证、challenge URL允许域 | 只有完整配置/投递演练通过才启用邮件模式；缺失时不能显示“已发送” |
| 工作限额 | upload/解压/文本/图片大小、用户/全局并发、模型请求/Token、任务重试与HTTP超时 | 部署硬上限；管理界面不能调高至超过硬上限，不作为商业套餐 |
| 观测 | project/environment/service、日志级别、接收/队列上限 | 生产启用正常埋点，脱敏；客户端无Loki写密钥 |
| 管理策略 | 注册开放/审批/默认角色、feature flags、配额、模型目录 | PG带revision/审计，不随容器重启恢复旧环境默认值 |
| 个人AI | 用户provider/model/voice/credential引用 | 用户库密文/设置；缺Key就暂停，不回退到环境全局模型调用Key |
| Flutter | API同源或明确实例地址、发布版本、非秘密功能协议版本 | 编译/公开运行配置；禁止数据库、签名、加密、供应商秘密进入包 |

日志只输出配置是否齐备、Secret版本标识和安全的组件状态，不输出整份settings对象或完整连接串。生产/测试数据库、Bucket、Topic、Redis前缀和加密材料分别设置，测试启动时拒绝生产目标。

## 2. 初始边界与验证

下面是原型起点，必须经MyHome资源余量与实际样本验证后写入发布清单，不是已确认容量承诺：

- 业务文件限额沿用PRD的MD/TXT 20MB、EPUB 50MB、获准PDF 80MB，按1MB=1,000,000字节配置；网关可以设更高传输硬上限但不能放宽业务限额。单张识词图推荐10MiB；头像初值为5MiB/4096×4096且只允许静态JPEG/PNG/WebP，必须真实解码并重编码，最终值经三端样本锁定。EPUB解压总量250MiB、条目10,000、深度/压缩比设限，拒绝路径穿越、符号链接、外部脚本/主动网络引用。扫描试卷规模依最终格式决策再定。
- 试卷文字听力稿使用独立purpose、允许MIME/扩展名、字节数、字符数和段落数上限，P0只允许经真实解码的UTF-8纯文本/Markdown；具体上限用英/日、多说话人及超长样本锁定，不沿用整本TXT材料上限。P0不注册原始音频上传purpose、音频MIME或自动绑定开关；通用网关/对象存储允许较大文件也不能使该业务入口接受音频。P1实现前须先完成OPEN-12及新的容量/隐私/版权配置。
- API请求体按用途限长；普通JSON不能沿用文件上传上限。字段长度、批量ID数、分页上限、SSE连接数分别控制。
- [多单词本](../modules/vocabulary-notebooks.md)配置本人本数/成员/批量硬上限，界面显示容量，不能退化成只能一本。[AI习题](../modules/ai-exercises.md)配置每次候选/题量、生成并发、模型调用和错题聚合上限；没有每日复习目标、日账本、due或FSRS配置。掌握策略版本按[学习证据](../architecture/vocabulary-learning.md)固定/重放，客户端不得上传派生状态或任意权重；结果阈值在OPEN-11样本验证后锁定。
- Worker分解析/AI/TTS配额，即时解释保留容量；试卷听力候选使用AI配额，确认稿的批量预生成使用TTS配额并与即时朗读隔离优先级/并发，开考只读取冻结成品而不现场抢占合成容量。每用户初始一个批量任务并发，全局数按压测收敛，不能凭共享Kafka存在就无限消费。
- [视觉OCR](../architecture/vision-recognition.md)复用AI任务配额，另按已验证模型约束页图像素/边长、单批页/区域数、总输入量、并发、输出与调用上限；具体值随获准格式和样本定版，不臆造供应商硬限制。不配置传统OCR回退开关；缺个人视觉配置只暂停受影响任务，不使无关文本读取的readiness失败。
- 模型用量适配按供应商与版本登记`provider_usage_schema`，只允许安全数字/枚举字段；input/output/cache read/cache write及可选推理、音频、图片、字符指标写入权威attempt记录。配置不含单价、币种或金额换算，完整口径见[模型用量统计](../contracts/model-usage.md)。
- [学习结果缓存](../architecture/learning-cache.md)分别配置本机文本/音频容量、Redis热点TTL/体积、批量resolve上限及服务端产物配额/调用前容量预留。具体键、字段、TTL/容量推荐初值与故障处理见[Redis设计](../architecture/redis-design.md)，不是已启用配置。有效引用的PG/MinIO成功解释/音频不设LRU或短TTL淘汰；满额阻止新的模型生成并保留已有结果。容量数字经平台/样本验证，不为Haruka修改MyHome共享Redis全局策略。
- global_word另外登记受控公共词条/读音与标准声音profile版本、实例目录容量和生成并发，使用独立对象前缀/全局唯一键。共享存储与个人调用上限分别预留，首次模型用量归实际发起人；不配置从其他用户Key池自动补缺的入口。目录修复只允许固定且不触发模型调用的动作，不能把平台模型目录管理权限当任意用户内容/凭据权限。
- Cookie/Token、离线租约、刷新回执初值以账号/RBAC专题为准，不在配置文档复制第二套数字。签名URL建议数分钟内，敏感即时撤权下载走代理。
- 外部网络出口只允许已配置供应商和必要服务，不接受用户任意base_url或解析文档中的内网URL，避免导入与模型测试成为SSRF入口。

解析文件在有资源上限的临时目录/隔离进程执行，下载和解码有时间/内存限制；生成路径由应用分配，不能拼接上传文件名形成宿主路径。

## 3. 运行与健康配置

API、Worker、Outbox 必须使用兼容的应用/schema/协议版本；进程入口与关闭协议见 [脚手架](../engineering/scaffold.md)，部署与启停顺序见 [运行步骤](deployment-recovery.md)。Haruka 重启或卸载不能停止共享 PG/Redis/Kafka/MinIO/日志服务。

| 检查 | 配置合同 |
| --- | --- |
| liveness | 进程事件循环/主循环存活，不访问数据库、缓存或外部供应商 |
| readiness | 必需配置有效，PG连接、迁移版本与当前profile的必需依赖可用；具体B0检查见下节。未来按能力降级时另行定义契约，不能谎报全功能健康 |
| Worker 心跳 | 类型、版本、最后领取/租约进度、可用容量；不是每条任务成功保证 |
| 端到端探针 | 无秘密小事件从 API 到 Grafana 可查询；任务演练使用隔离测试环境中不触发模型调用的路径，不能给生产增加 Fake、测试 seed 或公开调试入口 |
| 用户体验 | 只读、导入、AI、TTS、日志链路分别显示状态；日志宕机不停止学习，审计 DB 故障阻止管理写 |

反向代理配置 TLS、上传上限、SSE 缓冲/超时、Range、私有缓存头与请求 ID。CORS 只允许部署白名单；Web 静态缓存区分版本化 assets 与入口 HTML，避免旧壳请求不兼容 API。移动端/Windows 必须识别最低客户端版本并引导升级。生产实际探针及恢复演练不能对真实用户制造供应商请求。

### 3.1 B0健康检查的执行边界

本节约束当前dev/test基础设施入口，实施与局部验证见[readiness调整记录](../delivery/reviews/2026-09-26-b0-readiness.md)。生产探针配置、业务能力降级及Worker任务心跳仍需后续阶段交付。

| 时机 | 检查内容 | 失败行为 |
| --- | --- | --- |
| API、Worker、Outbox启动 | 实际连接身份/运行权限、完整schema及该profile必需依赖；结构检查包含迁移版本、字段/类型/默认值、索引/约束和注释 | 释放已取得资源并拒绝启动；不自动执行DDL或修复结构 |
| 受控迁移完成、当前版本的维护检查与结构验收 | 完整校验模型、迁移和实际反射结构一致 | 维护操作报告失败，不能把仅版本一致标记为结构验收通过 |
| 每次`GET /health/ready` | PG连接及运行身份/权限、精确匹配应用预期的单一Alembic revision、Redis；jobs另检查Kafka与私有Bucket | 任一必需依赖失败或版本缺失/为空/多行/不匹配均返回统一503；下一次请求重新检查，可恢复200 |
| 每次`GET /health/live` | 已进入且仍活动的应用生命周期 | 未启动或已停止返回503；运行中依赖故障不改变进程存活判断 |

readiness沿用5秒总探测预算和各客户端I/O时限，各依赖并行检查；取消及清理不以无上限后台重试代替。版本查询读取受控schema中的版本表，不调用全表反射，不检查每张表的列、约束和注释，也不扫描业务行。结果不跨请求缓存，不启动周期性结构扫描；错误响应和日志不包含连接字符串、SQL参数或原始驱动异常。离线壳模式始终不报告ready。

结构一致性由启动与受控维护保证：运行中若人为修改结构却保留原revision，readiness不保证发现该漂移，必须通过完整检查确认。应用运行账号不得执行DDL，正式结构变化必须走受控迁移入口，不能以轻量探针替代这条约束。

## 4. 留存与恢复参数

部署方登记数据库、私有对象、加密密钥的保护范围，明确负责人、备份保留、RPO/RTO 目标和实际恢复演练记录；参数依据容量与验证结果固定，不能填入未验证的“零丢失/分钟恢复”。用户侧备份仍只有单词 CSV，运维保护不扩大用户导出范围。

会话/挑战过期清理、幂等回执、无引用对象 GC、日志窗口和数据库管理审计留存分别配置。各时限以 [认证](../architecture/authentication.md)、[API](../contracts/api.md)、[数据与任务](../architecture/data-jobs.md)、[观测](observability.md) 为权威，不在此维护第二套默认值。管理审计首版建议至少 180 天并受控归档，最终按部署空间/要求确定；不得沿用 Loki 过期策略删除授权历史。

CREDENTIAL_KEYRING 的在线版本和归档恢复版本分别登记，备份记录必须能匹配密文所需的 encryption_key_version。在线重加密完成不等于旧备份不再依赖旧密钥；轮换、恢复和销毁条件统一见 [部署与恢复](deployment-recovery.md)。

## 5. 配置验收

OPS-01：生产配置缺 Secret、跨项目连接、错误 Origin、开发旁路或不完整能力配置时不能启动危险默认；实际配置校验和安全错误输出有证据。字段齐备不等于依赖真实可用，readiness 与平台探针须分别验证。

OPS-02～OPS-06 的部署、故障、回滚、恢复及 MyHome 共存验收统一在 [部署与恢复](deployment-recovery.md) 定义。当前仅为未来配置合同，没有执行部署或故障测试。
