# Selecta

ChatGPT修改的轻量版easydict，去除了无用功能并实现swift化

## 功能

- 继续保持Google和DeepL翻译的免费使用
- AI支持仅保留Gemini、DeepSeek、OpenAI
- 更好的OCR，使用百度本地模型，解决了原版识别不准和识别失败的问题
- 支持只OCR不翻译
- 重构了设置UI
- 应用内一键下载并配置 OCR 环境和模型

## 环境与构建

仅支持 Apple Silicon（arm64）Mac，需要 macOS 13 或更新版本，不支持 Intel/x64。构建需要完整 Xcode 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)，无第三方 Swift 包依赖。运行测试需要 macOS 14 或更新版本。

```sh
git clone https://github.com/XGWYTWGDYU/Selecta.git
cd Selecta
bash Scripts/build.sh
open build/Selecta.app
```

脚本从 `project.yml` 生成 Xcode 工程并构建 Release。也可以先运行 `xcodegen generate`，再用 Xcode 打开 `Selecta.xcodeproj`。

公开版本默认使用 ad-hoc 签名，不包含开发者证书、开发团队或分发公证配置。


## 离线 OCR

打开应用「设置 → 离线 OCR」，点击「下载并安装 OCR」，即可自动下载并配置安装工具、独立 Python 3.12、固定版本依赖和百度 PP-OCRv5 模型。无需预装 uv、Python，无需终端或源码目录。

安装时显示当前步骤，支持取消和失败后重试。新环境会在离线检查通过后才被启用，现有环境不会被覆盖。

安装完成后，OCR 使用本机 PaddleOCR 推理并禁用 Python 网络连接。采用 `PP-OCRv5_mobile_det` 和 `PP-OCRv5_mobile_rec`，不使用其他 OCR 引擎回退。

- 截图翻译：识别出的文字发送至已启用的翻译服务。
- 只 OCR：识别结果复制到剪贴板，并发送「模型名 OCR结果」系统通知。

Python、依赖和模型存放在 `~/Library/Application Support/Selecta/OCR/`，与源码目录和应用包独立。首次安装需要联网，之后可离线识别。高级设置仍可手动指定 Python 和模型路径。

## 测试

```sh
xcodegen generate
xcodebuild -project Selecta.xcodeproj -scheme Selecta \
  -configuration Debug -derivedDataPath .build/TestDerivedData test
```

测试覆盖语言路由、请求与响应处理、设置持久化、快捷键、浮窗布局、服务排序、隐私配置和 OCR 进程复用与取消。

## 许可证与来源

Selecta 使用 [GPL-3.0](LICENSE)。Google/DeepL 请求处理、取词流程和 Mini 翻译窗口参考并移植自 [Easydict](https://github.com/tisfeng/Easydict)，部分服务图标也来自该项目，保留上游版权声明。

本仓库提供修改后的完整应用源码和构建脚本；与上游相比，客户端使用 Swift 重写，精简翻译服务与设置，去除 TTS 和词典，使用本机 PaddleOCR。

第三方来源、参考版本与依赖许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。PaddleOCR、PaddlePaddle 及模型通过安装脚本单独获取，不包含在仓库中。
