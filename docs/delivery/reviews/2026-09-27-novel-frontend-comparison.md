# 小说阅读前端对照记录（UI-11/12）

日期：2026-09-27。范围：小说阅读页的选句查询与连续朗读交互；仅前端 mock 状态，不包含真实 TTS 或后端调用。

## 直接操作的原型

| 视口 | 操作与观察 | 截图 |
| --- | --- | --- |
| 手机 390×844 | 阅读态长按句子或选区后打开贴近正文的选句工具栏；词气泡可多选，可查询、朗读整句、调整起止范围并关闭。 | [初始](assets/frontend-preview/novel_phone_prototype_initial.png) · [选句](assets/frontend-preview/novel_phone_prototype_selection.png) |
| 手机词卡 | 在解析态长按第二句，选“窓”词泡并查询；原型显示“窓／まど／窗户”词卡和原文出处。 | [窓词卡](assets/frontend-preview/novel_phone_prototype_window_query.png) |
| 手机 390×844 | 连续朗读在底部导航上方出现控制卡，显示当前句、句序、进度、暂停/继续、语速和停止；当前句随进度高亮。 | [朗读](assets/frontend-preview/novel_phone_prototype_playing.png) |
| 桌面 1440×900 | 首次进入显示解析态；约 340px 的选句工具栏覆盖在正文附近，不推开后续句子。查询后右侧显示结果面板；点击句子解析时，朗读自动暂停但控制卡保留。 | [初始](assets/frontend-preview/novel_desktop_prototype_initial.png) · [选句](assets/frontend-preview/novel_desktop_prototype_selection.png) · [暂停与解析](assets/frontend-preview/novel_desktop_prototype_paused_analysis.png) |
| 桌面 1440×900 | 连续朗读卡在阅读卡下方；速度选项为 0.7×、1.0×、1.2×、1.5×，可暂停、继续和停止。 | [朗读](assets/frontend-preview/novel_desktop_prototype_playing.png) |

原型桌面端有“点击句子看解析，长按可选词查询。”操作引导；它对应真实可用的入口，Flutter 保留同类引导。原型的“无实际音频”等演示说明不进入正式界面文案。

## Flutter 实现与验证

修正前的桌面 Flutter 预览默认处于阅读态，且没有选句工具栏或连续朗读卡：[修正前截图](assets/frontend-preview/novel_desktop_flutter_before_ui11.png)。

本次实现把手机与桌面的选句工具栏、查询结果、连续朗读控制分别接入阅读页。朗读是可见的本地 mock 状态：逐句推进并高亮，长按/查询/打开句析会暂停，用户可手动继续；不调用系统 TTS 或后端。桌面默认解析、手机默认阅读，切换视口时保留已选择的模式与阅读状态。

桌面选句栏改为约 340px 的覆盖式浮层；长按后阅读卡高度和后续句子位置均不变。手机播放中长按句子会暂停并暂时隐藏底部朗读卡，选句操作完成后恢复暂停的控制卡，避免挡住查询按钮。

最终 8772 Web 构建在桌面 1440×900 实点：长按第一句后，选句栏覆盖正文、宽约 340px；第二句仍在原位置，阅读卡未被撑高。[最终初始](assets/frontend-preview/novel_desktop_flutter_overlay_final_initial.png) · [最终选句](assets/frontend-preview/novel_desktop_flutter_overlay_final_selection.png)。点击浮层“查询”后右侧结果面板正常打开：[最终查询](assets/frontend-preview/novel_desktop_flutter_overlay_final_query.png)。

8772 Web 构建在手机 390×844 实点：从[阅读](assets/frontend-preview/novel_phone_flutter_overlay_final_initial.png)启动[连续朗读](assets/frontend-preview/novel_phone_flutter_overlay_final_playing.png)，播放时长按第一句，朗读卡隐藏，选句栏全部按钮仍在底部导航上方：[播放中选句](assets/frontend-preview/novel_phone_flutter_overlay_final_selection_during_playback.png)。点击“查询”能打开[结果页](assets/frontend-preview/novel_phone_flutter_overlay_final_query.png)。随后在解析态实点第二句的“窓”词泡；初版[通用词卡](assets/frontend-preview/novel_phone_flutter_window_query_final.png)缺原型的类型栏、独立读音和蓝色释义区，已修正并复拍：[手机最终词卡](assets/frontend-preview/novel_phone_flutter_word_card_aligned.png) · [收藏反馈](assets/frontend-preview/novel_phone_flutter_word_card_saved.png)。桌面右侧面板也实点同一词泡，显示对应卡片与收藏状态：[桌面最终词卡](assets/frontend-preview/novel_desktop_flutter_word_card_aligned.png) · [收藏反馈](assets/frontend-preview/novel_desktop_flutter_word_card_saved.png)。

定点检查：`flutter analyze`（小说两个组件文件及 widget 测试）0 问题；小说 widget 测试 8/8 通过，包含桌面浮层几何、手机播放中选句按钮可见、暂停恢复及双端“窓”词卡断言。课本系统返回 widget 测试 1/1 通过。正式朗读仍为 mock 进度，不代表真实音频播放。
