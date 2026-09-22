# 注册、登录与账号操作

状态：设计基线 v0.1，2026-09-22，未实现。身份边界以 [认证与隔离](../architecture/authentication.md)、授权以 [RBAC](../architecture/authorization.md) 为准。本篇负责页面、步骤、状态、会话算法和可验收结果。

## 1. 页面与共同规则

用户端 /login、/register、/account/security；管理 Web /admin/login、/admin/account/security。两端属于同一 User，分别建立 client/admin 会话，首版切换入口重新登录，不默认静默交换。登录表单只有邮箱、密码、显示密码开关和提交；支持系统密码管理器、粘贴、键盘提交和明确焦点/错误标签。

表单状态 idle → validating → submitting → authenticated / action_required / error。提交中防重复；网络失败保留邮箱，密码只短暂在内存，不写缓存、日志、埋点或状态恢复。输入修改清理对应字段错误，服务端错误通过稳定 code 映射中文文案，不直接显示堆栈。

邮箱去首尾空白、校验格式/长度后生成大小写不敏感的 email_normalized 唯一值，原显示邮箱另存；不删除加号别名或点。密码不 trim/截断/改变 Unicode，首版建议 15–128 Unicode 码点，最大 UTF-8 1024 字节，允许空格/粘贴；常见密码离线阻止清单版本化。哈希使用 pwdlib/Argon2id，参数经容量基准验证并允许登录时升级哈希。输入建议和安全原因参考 [OWASP Authentication](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)。

## 2. 注册与激活

注册开放、邮箱验证/找回与审批方式仍按 [决策清单](../decisions/README.md) 处理。共同实现保留策略字段；未启用的流程不展示空链接，不承诺邮件已经配置。

1. 页面读取公开 /auth/policy，仅返回 registration_enabled、approval_required、email_verification_required、recovery_mode 和输入约束，不公开角色 ID、密钥、名单。
2. 输入邮箱、密码和确认密码；确认只在前端比对，不是后端安全依据。邀请码仅在最终启用邀请策略时出现，服务端验证并原子消费。
3. POST /auth/register 检查策略、限流、输入、公开允许的默认角色。额外 role/status/permissions/owner 字段拒绝，而非绑定到 ORM。
4. 单个数据库事务创建 User、Library、StudyProfile、默认角色绑定和必要的通知 Outbox；唯一邮箱约束处理并发。失败全部回滚。账号注册成功不要求模型 Key。
5. 邮箱/审批要求按本次注册的策略快照分别保存。满足条件才从 pending 转为 active；验证邮件不能自动绕过管理员审批。后续改变注册策略不追溯激活既有 pending 账号，需明确管理操作。
6. 返回统一受理说明与后续可用入口；已有邮箱不创建第二个账号，也不公开其状态。若启用邮件，按相同响应处理，重发受限。页面不根据该响应宣称已经能登录。
7. 激活完成后回登录页；首版不在注册成功时自动创建登录会话。默认角色必须仍有效，若配置失效则注册事务失败并向管理员报告配置问题。

账号字段区分 status=pending/active/disabled、email_verified_at、approval_status、locked_until。审批/邮箱检查是激活前置条件，locked_until 是限时安全阻断，不覆盖管理员 disabled。审批拒绝保留 pending 与 rejected 原因类别，不能再被验证邮件激活。

### 验证与找回的条件流程

若选用邮件：挑战使用高熵随机一次性 Token，数据库只用摘要验证，绑定 user/purpose/expiry/security_epoch；验证建议 24 小时、重置建议 30 分钟、重发至少 60 秒，均为可调初始值。通知 Worker 只从受控短期加密载荷取收件地址/链接，Kafka/普通 Outbox 消息只放引用，链接、Token、邮箱不入日志。发送失败可重试，不回滚已创建账号；页面显示可重发路径。

重置请求对存在/不存在账号返回同一受理结果；完成重置在事务中消费挑战、更新密码哈希、推进两端会话 epoch 并审计，再提示重新登录，不自动登录、不启用 disabled 账号。邮件跳转域名由部署白名单固定，不能使用不可信 Host/return_to 生成。挑战页面禁止分析采集 Token，加载后从地址栏移除秘密；过期/已用提示重新申请。参考 [OWASP Forgot Password](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html)。

若选择人工恢复：只有受控管理员/运维流程在核验身份后创建一次性恢复挑战，不显示/设置用户永久明文密码，不代登录；目标范围、近期身份验证和审计同其他敏感管理操作。具体身份核验和安全交付方式必须在该模式上线前记录，不把“联系管理员”当成已实现的恢复能力。

## 3. 登录顺序与失败语义

1. 用户端 POST /auth/login；管理端 POST /admin/auth/login。固定路由决定 audience；platform 仅决定允许的传输适配，不能获得更多权限。
2. 解析输入，检查来源/CSRF（Web）、账号/IP/全局频率，取得 User；不存在的账号也执行受控等价哈希验证，避免明显时序差。
3. 验证密码后检查 status、锁定/激活条件、当前 client.login/admin.login、功能安全策略。一般错误统一为 AUTH_LOGIN_FAILED，不通过文案/状态码泄露账号是否存在。
4. 正确密码但仍待邮箱/审批时可返回短期、仅能查询本人激活进度的 continuation challenge；不签发业务会话，不返回角色列表/其他个人数据。安全锁定/禁用等敏感失败仍按统一文案处理。
5. PostgreSQL 创建会话元数据并绑定当前安全 epoch；Redis 初始化会话摘要/刷新材料与 TTL。只有两步均成功才返回凭据；失败返回 503 并撤销/清理半成品，永不返回没有有效服务端会话的成功结果。
6. Web 使用高熵 opaque session Cookie，按受众分别命名、HttpOnly/Secure/SameSite，JSON 不含令牌；原生端收到短期 JWT Bearer 与轮换刷新凭据，刷新凭据进入系统安全存储。Web 不把原生令牌响应模式作为默认会话实现。
7. 读取access中的最小本人身份（user_id/instance_id/audience/session_ref）、权限/导航，再进入首个有权限页面。profile/settings仅在具备对应权限时可选加载，无权不阻塞启动；access失败停留可重试加载页。只有login权限的账号也能显示受控空状态、本人安全和退出入口。
8. 成功登录清理旧账号/受众内存与队列，再启动当前账号缓存/播放器/订阅。迟到响应携带账号代次校验，不准改变新会话。

推荐限流起点：IP 20 次/分钟、账号 10 次失败/15 分钟，逐步退避，临时锁定不超过 15 分钟；注册/重置更低的单独限额。账号限流键用服务器摘要，不记录邮箱；这些是待压测初值，不是抗攻击保证。密码哈希计算有并发上限，Redis/身份依赖不可用时失败关闭，返回可重试的服务错误。

## 4. 会话存储、刷新与撤销

### 数据职责

PostgreSQL AuthSession 保存 session_id、user_id、audience、transport、created_at、absolute_expires_at、revoked_at、创建时的用户/受众安全 epoch、近期重验时间和安全设备摘要；它是持久身份/撤销事实。User 保存 security_epoch 与各受众 epoch，区别于 RBAC authz_version。Redis 保存Web随机会话摘要/CSRF状态或原生刷新摘要/代次，以及idle TTL、短期重复请求回执和限流；Redis 丢失只能要求重新登录。

原生受保护访问验证JWT固定算法/issuer/audience/exp/sid；Web以Cookie摘要查服务端会话，不信任客户端自报sid。两者均读取PG用户、会话撤销/epoch/绝对期限、当前权限版本和Redis存续；transport与受众必须匹配，混合Cookie/Bearer身份拒绝。不能只依赖JWT、自报设备ID或异步缓存删除。会话元数据过期可按留存任务清理，账号管理页只返回必要设备摘要，不回传令牌。

推荐初值：原生用户访问JWT 15分钟；用户会话绝对7天、空闲24小时；管理Web会话绝对8小时、空闲30分钟，敏感操作要求5分钟内重验。Web续期/原生刷新均不延长绝对期限，客户端以服务器时间/响应期限判断，不能靠调整本地时间延寿。

### Web续期与原生并发刷新

Web正常业务访问或显式/auth/refresh只原子延长Redis idle TTL到不超过PG绝对期限，不轮换Cookie、不发送新的Set-Cookie。因此多标签常规续期无旧刷新Cookie迟到覆盖问题；失效会话必须重新登录。GET auth/csrf返回绑定当前会话的CSRF值，允许前端内存持有；Cookie写操作校验CSRF Header和Origin，登录/注册等尚无会话的写操作也要求可信Origin与JSON。带浏览器Origin的请求不能伪装native逃过来源验证。

Web登录/退出/换账号/近期重验属于身份变更，跨标签协调并广播“身份可能变化”，其他标签暂停私有写入，重新取当前Cookie的me/access最小身份后再绑定缓存；不广播秘密，不要求额外profile.read。重验成功创建新会话标识并撤销旧会话，不能把认证提升绑定到不变的旧标识。异常并发/迟到身份响应一律重新查询服务端当前身份；无法确认则清空私有UI并重新登录，不仅凭返回的邮箱切换缓存。改密/重置撤销全部会话。

原生ApiClient使用single-flight；刷新携带稳定refresh_request_id，同次网络重试不变，以会话/当前摘要/代次CAS原子轮换。成功后保留旧摘要和绑定原request_id的短期加密回执最多10秒，支持同次丢响应重试；只有最新代次可回放，不返回已被更后代次替换的凭据。窗口内不同request_id的旧摘要返回409 REFRESH_SUPERSEDED，不立即全家撤销；协调读取最新安全存储后最多再试一次。窗口外旧凭据重放撤销会话家族。

原生响应含session_generation，安全存储按会话/代次CAS更新，旧响应不得覆盖新值。窗口外无法恢复则重新登录，不永久保存旧凭据。仅ACCESS_EXPIRED触发一次原生刷新；权限不足、禁用、撤销或CSRF失败不循环刷新。自动重放业务请求受 [API幂等规则](../contracts/api.md) 限制。

### 退出、改密与强制下线

本人退出先在 PostgreSQL 标记当前会话撤销并记录安全事件/Outbox，再清 Redis 和客户端 Cookie/凭据；重复退出幂等。客户端网络失败也先本地清理并明确“本机已退出，远端撤销未确认”，不能宣称远端成功。失效凭据也允许本地清 Cookie，不得以失败阻止退出。

改密验证当前密码、活跃会话与 CSRF，事务更新哈希并增加 security_epoch，撤销两端既有会话；响应后重新登录。管理员撤销某会话以 PG revoked_at 为准，撤销所有/某端会话则增加对应 epoch；审计和撤销在同一 PG 事务生效，Redis 删除经 Outbox 重试。移除 login 权限会在授权事务推进受影响端 epoch，之后重新授予也不复活旧 Token。

普通退出/设备强制下线不自动取消已受理 Job；禁用、撤销动作权限或取消 Job 才停止其后续受限执行。相关语义见 [数据与任务](../architecture/data-jobs.md)。

## 5. 账号设置与管理联动

个人可修改显示名与学习偏好；首版不提供随意修改登录邮箱或自助销号界面，后续加入需验证新邮箱/撤销会话/数据留存完整流程。本人设备会话列表、退出其他会话属于经过认证的本人安全操作，不依赖学习菜单权限；其他用户的会话必须走 admin.session 权限。

管理员创建账号不产生可公开复制的永久默认密码，使用受控邀请/一次性设置流程；审批/启停/角色变更/撤销是独立按钮与权限。详见 [后台操作](admin.md)。用户 API Key 不参与登录校验，也不作为密码恢复证据。

## 6. 验收用例

| ID | 操作与期望 |
| --- | --- |
| ACC-01 | 并发注册同邮箱仅产生一个 User/Library；角色越权字段拒绝，失败事务无孤立记录 |
| ACC-02 | 正确密码但无对应 login 权限无法建立该端业务会话；用户端 Token 不进管理 API |
| ACC-03 | pending 的验证/审批任一未满足不能激活，策略变更不静默激活旧账号 |
| ACC-04 | 两端三平台登录恢复、到期/空闲、退出/换账号和迟到响应正确，密码/Key/Token 无持久日志 |
| ACC-05 | Web多标签续期不轮换Cookie，身份变更后按当前Cookie重新绑定；原生丢响应/迟到代次/窗口内外重放有确定结果，无刷新风暴 |
| ACC-06 | 禁用/指定会话撤销/撤销端登录权限提交后，新请求被拒；Redis 删除失败仍不能通过；重新授权不复活旧会话 |
| ACC-07 | 改密/重置挑战单次消费并撤销两端会话，失效/禁用账号不会被恢复流程激活 |
| ACC-08 | 无 Key 可完成已授权的注册登录和基础操作；密码管理器/键盘/屏幕阅读错误提示可用 |
| ACC-09 | 邮件模式测发送失败/重发/过期/重复；人工模式必须有可演练的安全交付步骤，未选模式不伪造完成 |
| ACC-10 | client.login-only/admin.login-only账号登录与刷新恢复仅依赖access最小身份；无profile/settings权限仍能显示空状态和本人安全/退出 |

原生安全存储插件、跨标签协调与刷新回执实现需工程验证后锁定版本；本篇是明确的待实现协议。
