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

### 下载构建版本

每次推送到 `main` 都会由 GitHub Actions 运行测试并生成 ad-hoc 签名的 `Selecta.app`，可在
[Actions](https://github.com/XGWYTWGDYU/Selecta/actions/workflows/build.yml) 对应运行的 Artifacts 中下载；
推送 `v*` 标签时还会发布到 [Releases](https://github.com/XGWYTWGDYU/Selecta/releases)。

ad-hoc 签名未经公证，首次打开会被 Gatekeeper 拦截。解压后可在「系统设置 → 隐私与安全性」中点击「仍要打开」，或运行：

```sh
xattr -dr com.apple.quarantine /Applications/Selecta.app
```

ad-hoc 签名每次构建都会变化，更新应用后可能需要重新授予辅助功能和屏幕录制权限。


## 离线 OCR

打开应用「设置 → 离线 OCR」，点击「下载并安装 OCR」，即可自动下载并配置安装工具、独立 Python 3.12、固定版本依赖和百度 PP-OCRv5 模型。无需预装 uv、Python，无需终端或源码目录。

安装时显示当前步骤，支持取消和失败后重试。新环境会在离线检查通过后才被启用，现有环境不会被覆盖。

安装完成后，OCR 在本机推理并禁用 Python 网络连接。采用 `PP-OCRv5_mobile_det` 和 `PP-OCRv5_mobile_rec`，不使用其他 OCR 引擎回退。

### OCR 加速

安装时将同一套 PP-OCRv5 权重用 `paddle2onnx` 导出为 ONNX（fp32，权重和识别参数不变），推理使用 ONNX Runtime：

- **文字检测**通过 Core ML 在 Apple GPU 上运行。输入按尺寸分档补齐为静态形状，编译结果缓存在 `~/Library/Caches/` 下应用目录的 `coreml/` 中。导出时将 `HardSwish`/`HardSigmoid` 展开为等价的 `Mul`/`Add`/`Clip`，使整张图都能在 GPU 上执行。
- **文字识别**留在 CPU，按行并行占满所有核心。每行单独推理，不与其他行补齐到同一宽度：PP-OCRv5 识别模型对右侧补零敏感，GPU 所需的固定宽度会明显提高错误率，而逐行推理与 PaddlePaddle 单行结果一致。
- 未使用神经网络引擎（ANE）：ANE 只接受 fp16，实测仍比 GPU 慢且会改变精度。
- Core ML 不可用时自动退回 ONNX Runtime CPU；旧版本安装的 OCR 环境继续使用 PaddlePaddle，设置页会提示重新安装以启用加速。重新安装成功后会删除不再使用的旧环境。

Apple M3 实测：67 行密集文本 30 秒 → 2.8 秒，40 行中英混排 18 秒 → 1.6 秒，字符错误率也略有下降。

- 截图翻译：识别出的文字发送至已启用的翻译服务。
- 只 OCR：识别结果复制到剪贴板，并发送「模型名 OCR结果」系统通知。

Python、依赖和模型存放在 `~/Library/Application Support/Selecta/OCR/`，与源码目录和应用包独立。首次安装需要联网，之后可离线识别。高级设置仍可手动指定 Python 和模型路径。

## 测试

```sh
xcodegen generate
xcodebuild -project Selecta.xcodeproj -scheme Selecta \
  -configuration Debug -derivedDataPath .build/TestDerivedData test
```

测试覆盖语言路由、请求与响应处理、设置持久化、快捷键、浮窗布局、服务排序、隐私配置、OCR 进程复用与取消、OCR 环境清理和加速检测。

## 许可证与来源

Selecta 使用 [GPL-3.0](LICENSE)。Google/DeepL 请求处理、取词流程和 Mini 翻译窗口参考并移植自 [Easydict](https://github.com/tisfeng/Easydict)，部分服务图标也来自该项目，保留上游版权声明。

本仓库提供修改后的完整应用源码和构建脚本；与上游相比，客户端使用 Swift 重写，精简翻译服务与设置，去除 TTS 和词典，使用本机 PaddleOCR。

第三方来源、参考版本与依赖许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。PaddleOCR、PaddlePaddle 及模型通过安装脚本单独获取，不包含在仓库中。
