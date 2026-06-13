fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios verify_asc

```sh
[bundle exec] fastlane ios verify_asc
```

验证 App Store Connect API Key 是否可用

### ios show_review

```sh
[bundle exec] fastlane ios show_review
```

打印当前版本的审核联系人信息（诊断）

### ios builds

```sh
[bundle exec] fastlane ios builds
```

列出 App Store Connect 上 1.0 版本的所有构建号（诊断）

### ios diag

```sh
[bundle exec] fastlane ios diag
```

列出此 API Key 可见的 App 和 Bundle ID（诊断）

### ios enable_siwa

```sh
[bundle exec] fastlane ios enable_siwa
```

在 App ID 上开启 Sign in with Apple 能力（幂等）

### ios build

```sh
[bundle exec] fastlane ios build
```

仅打包出 App Store .ipa（不上传）

### ios beta

```sh
[bundle exec] fastlane ios beta
```

打包并上传到 TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

打包 + 上传 IPA 到 App Store Connect（不自动提交审核）

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

只上传截图（覆盖现有），不动二进制和文字元数据

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

只上传文字元数据（名称/副标题/关键词/描述/更新说明），不需要新 IPA

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
