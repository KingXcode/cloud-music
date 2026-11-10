# 弦泊 · Xianbo

“弦泊”（xián bó）取音乐与停泊之意，表达收藏自己的音乐、安静聆听。0.7.4 起统一用于应用名称、安装包内的应用、媒体默认标题及网页入口。

## 名称检索与使用边界

2026-11-10 对“弦泊”“弦泊 音乐 播放器”“Xianbo music player”等做了初步公开网页检索，未发现明显的同名音乐软件。这只是当日网页筛查，不是商标登记数据库或各地区类别的正式清查，不能据此保证没有在先权利，也不表示已经注册商标。

候选“拾声”已有音频领域使用；“听岚 / Tinglan”接近现有[听澜音乐客户端](https://github.com/talongao/tinglan)，因此没有采用。

## 图标设计与来源

原创构图以象牙色缎带形成不对称声波，琥珀色圆点停泊在弯折处；深青色背景呼应安静聆听。没有使用现成品牌标志、第三方图片、字体轮廓或图库素材。

图像使用内置 `image_gen` 工具生成。首张母版不使用参考图片；macOS 版仅引用本项目首张母版，生成透明外边距和圆角图标。AI 生成记录和独立构图不等同于商标清查、排他著作权或不侵权保证。

- 通用母版：`assets/branding/xianbo-icon-source.png`。
- macOS 透明母版：`assets/branding/xianbo-macos-source.png`。
- 应用内资源：`assets/branding/xianbo-icon.png`。
- 派生资源：macOS/iOS 的 `AppIcon.appiconset`、Android 的 `mipmap-*/ic_launcher.png`，以及 Web favicon、主屏幕图标。

所有尺寸资源通过下列命令从母版生成，仅缩放和转换像素格式，不重新绘制图案：

```sh
uv run --with pillow python scripts/generate_app_icons.py
```

iOS 图标和 Web 图标使用不带透明通道的 PNG；macOS 保留透明边距。`pubspec.yaml` 只打包应用内 256 像素资源，不把两张母版放入 Flutter 资源包。

Web 应用清单的 `id`、`start_url` 和 `scope` 固定为现有站点入口 `/cloud-music/`，避免安装到主屏幕后被绑定到一次发布的不可变资源目录。

## 原始生成提示词

### 通用母版

```text
Use case: logo-brand. Asset type: original app icon master for an independent personal local-music player, for macOS, iOS, Android and web. Create one distinctive original icon, not a mockup or contact sheet. Full-bleed square 1024x1024 with an opaque deep petrol-teal background (#163E46), subtle smooth tonal depth, no outer margin or device frame. Center a bold sculptural continuous ivory ribbon folded into a flowing asymmetric sound-wave: two softly rounded upright folds of unequal height joined by a low sweeping curve, with a small amber circular accent nestled at the inner bend. The shape should evoke listening and collecting sound, not an alphabet letter and not a musical-note glyph. Refined, calm, tactile satin ceramic lighting, very restrained soft shading, crisp silhouette that is recognizable at 32 pixels. Keep all important mark geometry within central 65% of the canvas for launcher masks. No text, no letters, no watermark, no stock symbols, no headphones, no record disc, no play triangle, no three parallel arcs. Do not copy, reference or resemble existing app logos or commercial brand identities; develop original geometry.
```

### macOS 母版

```text
Create the macOS application-icon variant of this exact original image. Preserve the deep petrol teal background, ivory folded sound-wave ribbon and amber dot, and all their relative geometry/colors. Present the same artwork as one generously rounded square app-icon tile, straight-on and centered, occupying about 84% of the square canvas with equal transparent margins on all sides. The outer tile corners are smooth superellipse-like rounded corners, matching a polished macOS Dock icon, with a restrained soft drop shadow only outside the tile. The inside artwork should remain visually identical and fill its tile; do not redesign the ribbon. The canvas outside the rounded tile must be genuinely transparent. No additional background, words, border, watermark, devices or mockup.
```

## 兼容旧版

包标识、资料存储目录、Flutter 通道、Web 数据库和缓存命名保留，以继续读取原曲库、授权和偏好设置。仓库地址及 `cloud-music-*` 下载文件名是既有更新协议的一部分，本次沿用；界面与原生应用展示新品牌。macOS 应用文件名改为 `Xianbo.app`，升级方式见 [macOS 安装说明](MACOS_INSTALL.md)。
