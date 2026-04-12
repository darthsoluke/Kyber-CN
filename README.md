# Kyber-CN

`Kyber-CN` 是基于官方开源项目 `ArmchairDevelopers/Kyber` 的中文化与可用性增强分支，面向 `STAR WARS Battlefront II (2017)` 的私服、模组联机与局域网联机场景。

这个分支的目标不是改写整个项目架构，而是在尽量兼容上游的前提下，优先解决中文玩家真正会遇到的问题：启动器本地化、局域网大厅、离线开服、自定义端口、安装分发和模组下载可用性。

## 当前特性

- 启动器中文本地化，覆盖首页、开服、统计、模组、设置等主要页面
- 正式的局域网模式，支持 LAN 广播发现与手动直连
- `OFFLINE` 开服模式，可跳过在线注册，直接用于局域网或内网穿透测试
- 自定义服务器端口，便于配合 `SakuraFRP` 等端口映射工具
- 随包分发本地 `Module`，减少首次启动时下载旧模块的问题
- Windows 安装包构建与发布流程
- 官方模组服务器下载链路修复与安装状态修正

## 适用场景

- 在同一局域网内快速开服联机
- 使用内网穿透工具把本地服务器暴露给外网玩家
- 给中文玩家提供更直接的 Launcher 使用体验
- 在保留原项目结构的前提下继续开发和验证 Frostbite Dedicated / Headless 相关能力

## 仓库结构

| 目录 | 说明 |
| --- | --- |
| `Launcher` | Flutter 启动器，包含 UI、本地化、下载器、更新器与开服逻辑 |
| `Module` | 注入游戏进程的 C++ 模块，负责网络、RPC、Hook、LAN 广播等核心能力 |
| `CLI` | 命令行工具，适合自动化、调试和脚本调用 |
| `API` | 后端 API 服务 |
| `Proxy` | Rust 代理服务 |
| `Packages` | 共用 Dart 包 |
| `artifacts` | 仓库内跟踪的发布产物，例如 Windows 安装包 |

## 快速使用

### 普通用户

1. 从仓库的 GitHub Releases 页面下载 Windows 安装包。
2. 安装并启动 `KYBER Launcher`。
3. 首次运行时指定你的 `STAR WARS Battlefront II` 游戏目录。
4. 如果要局域网开服：
   - 进入 `HOST`
   - 将 `AUTH MODE` 切到 `OFFLINE`
   - 设置地图、人数、端口后启动
5. 其他玩家可在 `HOME -> LAN` 中发现服务器，或者使用 `Direct Connect` 手动输入 `IP:端口` 加入。

### 联网穿透

如果你使用 `SakuraFRP` 或其他 FRP 工具：

- 推荐在 `HOST` 页直接设置你要对外使用的服务器端口
- FRP 的本地端口与远程端口尽量保持一致
- 客户端使用 `你的地址:端口` 进行直连

## 当前分支重点改动

相对于上游仓库，这个分支目前重点维护以下方向：

- 中文界面与文本本地化
- LAN 浏览页、LAN 直连、OFFLINE 开服流程
- 自定义服务器端口链路打通
- Launcher 分发包内置 Module
- Windows 安装包构建与发布
- 模组下载、解压、安装状态判定修复

## 开发与构建

### 基本要求

- Windows 是当前最完整的开发与测试平台
- 构建前请使用 `--recurse-submodules` 克隆仓库，或执行：

```bash
git submodule update --init --recursive
```

- 详细构建说明见 [BUILDING.md](BUILDING.md)

### 常用开发入口

```bash
melos bootstrap
```

```bash
cd Launcher
flutter run -d windows
```

```bash
cd Module
bazel --output_user_root="C:\bz" build --config=release Kyber
```

### Windows 安装包

项目使用 Inno Setup 构建安装包，脚本在：

- [Launcher/installer/installer.iss](Launcher/installer/installer.iss)

构建示例：

```powershell
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" "G:\dev\Kyber\Launcher\installer\installer.iss"
```

默认产物：

- `Launcher/installer/KyberLauncherInstaller.exe`

## 发布

- 仓库代码：`git@github.com:darthsoluke/Kyber-CN.git`
- 当前建议下载方式：GitHub Release 中的安装包
- 如果你是开发者并直接拉仓库，请注意较大的安装包文件通过 `Git LFS` 跟踪

## 注意事项

- 本项目不是 EA / DICE 官方项目
- 在线模式仍可能依赖上游的账号、接口或服务端能力
- `OFFLINE` 模式更适合局域网、测试服和内网穿透场景
- 游戏本体文件仍然是必需的

## 致谢

- 上游项目：`ArmchairDevelopers/Kyber`
- 所有为 `KYBER` 模块、Launcher、CLI、API 与社区生态做出贡献的开发者与测试者

## 许可证

本项目沿用上游许可证，详见 [LICENSE](LICENSE)。
