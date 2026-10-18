# tv-emulator-verify

用 GitHub Actions 的 Android 模拟器对 TV 应用的预览包做 UI 验证，产出截图胶卷（本仓库不含应用源码，主仓库不受影响）。

- 触发：`workflow_dispatch`，默认下载本仓库 release 资产里的 preview APK。
- 输入：`apk_url` 可换成其它构建；`bridge_sk_mode` 支持 `off` 与 `invalid`（假密钥），用于验证云桥失败时的静默回退。
- 产物：`screenshots-<run_id>`，含首页逐行下移胶卷、发现页胶卷、prefs、logcat 摘要；所有文本产物上传前已做 `sk_` 脱敏。
- 说明：APK 为 arm64-v8a，依赖 API 30+ `google_apis` x86_64 镜像的 ARM 转译运行。
