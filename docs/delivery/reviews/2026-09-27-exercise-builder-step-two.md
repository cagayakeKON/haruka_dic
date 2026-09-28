# 出题构建器第二步原型对照

2026-09-27；在 Chrome Computer Use 中实点手机、电脑原型与 8772 Web 构建。屏幕分别设为 390×844、1440×900。截图是调整卡片尺寸前的实装状态。

| 画面 | 题目设置卡约略边界 | 出题范围卡约略边界 | 截图 |
| --- | --- | --- | --- |
| 手机原型 | x20–355，y170–398 | x20–355，y414–916 | [原型](assets/frontend-preview/prototype_phone_exercise_builder_step2.png) |
| 手机实装（首次复拍） | x20–370，y163–340 | x20–370，y358–772 | [实装](assets/frontend-preview/mock_web_phone_exercise_builder_step2.png) |
| 电脑原型 | x324–715，y202–425 | x738–1323，y202–659 | [原型](assets/frontend-preview/prototype_desktop_exercise_builder_step2.png) |
| 电脑实装（首次复拍） | x269–707，y207–383 | x727–1383，y207–599 | [实装](assets/frontend-preview/mock_web_desktop_exercise_builder_step2.png) |

原型手机页的浏览器滚动条占约 15px，造成卡片宽度与 Flutter 内部滚动容器约 15px 的差值。电脑实装的卡片区比原型宽约 110px，设置卡少约 47px 高，范围卡少约 60px 高。已调整电脑内容最大宽度和两卡纵向留白；调整后的构建与截图待复核。

交互实点：从单词本来源进入第二步；题型切换为词义选择、题量改为 1 后确认可用，并进入 1 道可作答示例，选择并提交后出现反馈。5 题时需勾选候选复用方可确认；更改题型会清除该勾选并再次禁用确认。“修改来源”返回第一步且保留已选单词本。原型中的演示实现说明按用户要求未置入正式界面。
