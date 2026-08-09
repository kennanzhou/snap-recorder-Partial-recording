<div align="center">
  <img src="assets/SnapRecorderIcon.svg" width="96" alt="Snap Recorder 图标">
  <h1>Snap Recorder</h1>
  <p><strong>极简录屏，高清保存。</strong></p>
  <h2>
    <a href="https://github.com/shuyan-5200/snap-recorder/releases/latest">⬇️ 下载最新版</a>
    &nbsp;&nbsp;&nbsp;
    <a href="https://shuyan-5200.github.io/snap-recorder/">🌐 产品主页</a>
  </h2>
  <p>面向 macOS 的轻量录屏工具：浏览器、整个屏幕或自定义区域，本地处理，录完选择画质并保存。</p>
  <p><sub>A tiny, local-first macOS recorder for browser windows, full displays, and selected regions.</sub></p>
  <p>
    <a href="https://github.com/shuyan-5200/snap-recorder/releases/latest"><img src="https://img.shields.io/github/v/release/shuyan-5200/snap-recorder?style=flat-square&amp;label=release" alt="最新版本"></a>
    <a href="https://github.com/shuyan-5200/snap-recorder/actions/workflows/ci.yml"><img src="https://github.com/shuyan-5200/snap-recorder/actions/workflows/ci.yml/badge.svg" alt="构建状态"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/shuyan-5200/snap-recorder?style=flat-square" alt="MIT License"></a>
    <img src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&amp;logo=apple" alt="macOS 14 或更高版本">
  </p>
</div>

<p align="center">
  <a href="https://shuyan-5200.github.io/snap-recorder/">
    <img src="docs/images/snap-recorder-main.png" width="840" alt="Snap Recorder 主界面：整个屏幕、电脑声音与人声均已开启">
  </a>
  <br>
  <sub>点击截图查看完整产品主页</sub>
</p>

Snap Recorder 把录屏缩短成一条短路径：**选择来源 → 3 秒倒计时 → 录制 → 选择画质 → 保存到“下载”**。没有账号，没有云同步，也不需要先学习一个编辑器。

| 录制模式 | 导出画质 | 网络请求 | Universal App |
| --- | --- | --- | --- |
| 浏览器窗口 / 整个屏幕 / 局部录像 | 最高画质 / 清晰小体积 | 0 | 约 2.2 MB |

## 为什么选择 Snap Recorder

- **三种录制模式**：浏览器、整个屏幕、可调范围的局部录像。
- **局部构图**：支持 16:9、9:16、4:3、3:4、21:9、1:1 和自定义比例；固定比例可加聚焦蒙版。
- **鼠标可选**：三个模式共用“录制鼠标”开关；开启后用带光晕的圆形光点代替系统箭头，点击时产生扩散波纹，关闭后成片完全不显示鼠标。
- **两档画质**：最高画质沿用现有质量；清晰小体积保持同分辨率，视频体积目标约为前者的 1/3。
- **声音选择**：电脑声音、人声分别控制。
- **三种导出方式**：完整视频、视频与人声分开、两种同时导出。
- **高清成片**：原生像素优先，最高 3840×2160；H.264 High Profile，合并人声时视频轨不二次编码。
- **干净录制**：主窗口、倒计时与录制控制条不会进入成片。
- **小而本地**：v0.3.0 Universal App 约 2.2 MB；无账号、无统计、无网络请求。

想先完整了解产品，可打开 [Snap Recorder 产品主页](https://shuyan-5200.github.io/snap-recorder/)；想直接使用，可前往 [Releases](https://github.com/shuyan-5200/snap-recorder/releases/latest)。

## 三种录制模式

| 模式 | 画面 |
| --- | --- |
| 浏览器 | 只录浏览器窗口，按窗口原始比例完整铺满成片，不添加桌面背景。 |
| 整个屏幕 | 录制当前主屏幕，保持原始比例和原生像素。 |
| 局部录像 | 在主屏幕上拖动圆角虚线框选择范围；固定比例等比缩放，自定义比例自由缩放。可选柔和圆角暗角，以及框内原色、框外单色并压暗 50% 的聚焦蒙版。按 `⌘E` 锁定为点击穿透浮层，再按 `⌘R` 开录。 |

浏览器不必最大化，只要没有最小化即可录制。

主窗口聚焦时，三种模式都可按 `⌘R` 开始录制。局部录像锁定浮层后，`⌘R` 会临时成为全局快捷键；任意模式录制中或暂停时，可在任何应用里按 `Esc` 结束录制。

### 局部录像的构图工具

- 大选区默认使用 macOS 风格圆角虚线框，也可切换为方角，并可以直接拖动位置；选择 16:9、9:16、4:3、3:4、21:9 或 1:1 时只按原比例缩放，选择“自定义”时可自由改变宽高。
- 固定比例下可再开启一个小型聚焦蒙版。蒙版内部保持原色与原亮度，外部转为单色并压暗 50%；小蒙版可选方角或圆角，默认圆角，并用一圈低对比灰色细框提示范围。
- 大选区与小蒙版都默认圆角、都允许切换为方角。“柔和圆角暗角”是大选区处于圆角时的独立开关，只在最终画面的四个角做轻微渐隐，不会把选区虚线框或蒙版灰框录进成片。
- 调整完成后按 `⌘E` 把大选区变成点击穿透浮层，此时仍能看见范围，但可直接操作框线下面的应用；再次按 `⌘E` 恢复调整。

### 三个模式共用的录制选项

| 选项 | 行为 |
| --- | --- |
| 电脑声音 | 录制应用与网页声音，不包含麦克风。 |
| 人声（麦克风） | 默认关闭；开启后录制系统默认麦克风，并可在结束时选择合并或分轨导出。 |
| 录制鼠标 | 默认开启；系统箭头不会进入成片，改为带紫色光晕的圆形光点，左键、右键或中键按下时从点击位置扩散一圈光芒。关闭后不绘制任何鼠标或点击效果。 |

## 画质、声音与导出

结束录制后可选择“最高画质”或“清晰小体积”。最高画质直接保留录制原片；小体积档保持相同分辨率，使用约 1/3 的视频目标码率重新压缩，并开启更高压缩效率，优先保住网页文字和界面细节。实际文件大小仍会随画面变化与声音内容浮动。

<p align="center">
  <img src="docs/images/snap-recorder-quality-options.png" width="840" alt="Snap Recorder 录制结束后的双画质导出选择：最高画质与清晰小体积">
  <br>
  <sub>同一段录屏，可选择保留原片质量，或保持分辨率并把目标体积压缩到约 1/3</sub>
</p>

| 导出方式 | 得到的文件 |
| --- | --- |
| 不录人声 | 选择画质后保存 1 个 MP4。 |
| 完整视频 | 画面 + 电脑声音（如有）+ 人声，合成 1 个 MP4。 |
| 视频和人声分开 | 视频 MP4 + 对齐时长的人声 M4A，方便继续剪辑。 |
| 两种都要 | 一次得到完整 MP4、视频 MP4 和人声 M4A，共 3 个文件。 |

人声文件使用 AAC-LC、48 kHz、192 kbps；完整视频的混合音频为 48 kHz、256 kbps。

## 安装

1. 从 [Releases](https://github.com/shuyan-5200/snap-recorder/releases/latest) 下载 ZIP 并解压。
2. 把 `Snap Recorder.app` 移入“应用程序”。
3. 首次启动时允许“屏幕与系统音频录制”；开启人声时再允许麦克风。

当前预编译 App 尚未经过 Apple 公证。首次启动如果被 macOS 拦截，请右键 `Snap Recorder.app` →“打开”；仍被拦截时，前往“系统设置”→“隐私与安全性”→“仍要打开”。

## 系统要求

- 基础录屏：macOS 14 或更高版本。
- 人声录制：macOS 15 或更高版本。
- 支持 Apple Silicon 与 Intel Mac；预编译 App 为 Universal 2。

## 从源码构建

Snap Recorder 使用 SwiftUI、AppKit、ScreenCaptureKit、Core Image 和 AVFoundation，不依赖第三方库。

```bash
git clone https://github.com/shuyan-5200/snap-recorder.git
cd snap-recorder
./scripts/build-app.sh
```

构建结果位于 `build/Snap Recorder.app`。运行自动自检：

```bash
.build/release/SnapRecorder --self-test
```

本地构建使用固定的 ad-hoc designated requirement，让 macOS 在代码变化后仍能识别同一份应用。若曾运行过旧版构建，请先在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”移除旧的 Snap Recorder 条目，再对固定安装位置中的新 App 授权一次。正式分发时可通过 `SNAPRECORDER_CODESIGN_IDENTITY` 指定 Developer ID 签名身份。

## 隐私与边界

所有录屏和声音都只在本机处理。Snap Recorder 不联网、不上传、不收集统计，也不包含第三方分析 SDK。详见 [隐私说明](PRIVACY.md)。

为了保持极简，当前不提供编辑器、剪辑、自动变焦、摄像头、多显示器选择或云分享。DRM 受保护内容仍可能被 macOS 显示为黑屏。

实现细节与验证记录见 [技术说明](docs/technical-notes.md) 和 [验证清单](docs/verification.md)。欢迎阅读 [贡献指南](CONTRIBUTING.md) 后提交 Issue 或 Pull Request。

## License

[MIT License](LICENSE)
