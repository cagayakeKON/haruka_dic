# UI-15 试卷场次前端核对

本记录仅覆盖本地 mock 场次页。没有后端场次、权威计时、听力播放或刷新后的服务端恢复；页面显示试卷时长，不显示会运行的倒计时。

## 原型与实装操作

| 视口 | 亲自点击的原型状态 | 8771 实装点击结果 |
| --- | --- | --- |
| 手机 390×844 | 从试卷准备完成脚本匹配、音频准备与开考；选 A、标记、保存、答题卡、跳题、离开确认、交卷确认 | 选 A 后已答 1/3，标记可见；答题卡显示星号/已答/未答并能跳第 2 题；保存后为已保存；离开后准备页出现继续作答，重进仍为第 2 题 |
| 电脑 1440×900 | 从试卷准备开考；选 A、标记、保存、答题卡跳题、试卷准备离开确认 | 独立并列题面和答题卡；选 A、标记、保存后右卡显示已答 1/3 与标记，跳题保留；侧栏离开先确认，取消留在场次；交卷二次确认可取消 |

手机题卡顶部原型约 y=285，实装约 y=285；答题卡 sheet 顶部原型约 y=543，实装约 y=544；离开 sheet 顶部原型约 y=611，实装约 y=610。电脑题卡原型约 x=272–1052、y=166–517，实装约 x=269–1031、y=169–517。实装依据当前仓库 Flutter 主题绘制，局部字体与图标细节仍有差异。

## 截图

- 手机场次：[原型](assets/frontend-preview/prototype_phone_exam_session.png)、[实装](assets/frontend-preview/mock_web_phone_exam_session_final.png)
- 手机答题卡：[原型](assets/frontend-preview/prototype_phone_exam_answer_card.png)、[实装](assets/frontend-preview/mock_web_phone_exam_answer_card_final.png)
- 手机离开确认：[实装](assets/frontend-preview/mock_web_phone_exam_leave_sheet_final.png)
- 电脑场次：[原型](assets/frontend-preview/prototype_desktop_exam_session.png)、[实装](assets/frontend-preview/mock_web_desktop_exam_session_final.png)
- 电脑离开确认：[原型](assets/frontend-preview/prototype_desktop_exam_leave_dialog.png)、[实装](assets/frontend-preview/mock_web_desktop_exam_leave_dialog_final.png)

## 验证与边界

视觉微调后，`flutter analyze` 对场次、支持页、store、shell 和场次 widget 测试定点通过（0 问题）；场次 widget 测试 3/3 通过，覆盖手机草稿恢复、桌面交卷二次确认与侧栏离开守卫。

MockStore 只在当前应用运行期间保留答案、标记、题号和保存状态。刷新浏览器不会恢复正式服务端 ExamSession，且本页没有真实听力播放与服务器时限。

## 支持页状态复核

亲自点击手机和电脑原型的“状态样例”：手机“查看任务”进入任务进度页，电脑“查看任务”展开任务抽屉。原型把离线、失权、任务失败和载入作为虚构样例，没有可在现有 mock 支持页或考试场次中触发的对应失败流程，因此未把样例说明复制进正式界面，也未伪造重试结果。

每日单词原型选择无加入记录的日期后，手机与电脑均显示日期、0 个单词和居中空卡。实装也通过日期选择显示相同内容；手机原型空卡约 y=474–653、实装约 y=474–655，电脑原型约 y=408–597、实装约 y=408–596。截图：[手机原型](assets/frontend-preview/prototype_phone_daily_words_empty.png)、[手机实装](assets/frontend-preview/mock_web_phone_daily_words_empty_final.png)、[电脑原型](assets/frontend-preview/prototype_desktop_daily_words_empty.png)、[电脑实装](assets/frontend-preview/mock_web_desktop_daily_words_empty_final.png)。每日单词相关 widget 测试 3/3 通过，支持页及其测试定点 `flutter analyze` 为 0 问题。
