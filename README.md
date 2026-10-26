# fnnas-base-images

飞牛 NAS 通用基镜像（rockchip arm64），供各设备仓 CI 自动打包固件。
**全自动链路**：上传官方源镜像 → CI 自动去设备绑定 → 自动发新版本 → 各设备仓下次构建自动选用。

## 什么是"通用基镜像"

飞牛各设备固件本质上共用同一套系统：

- **内核通用**：所有 arm 设备共用同一内核（v1.1.0 起为 `vmlinuz-6.18.18.c1145-trim`）
- **dtb 全量**：`dtb/rockchip/` 内含 232 个设备树（rk3308/3328/3399/3528/3562/3566/3568/3576/3582/3588 全系列）
- **引导通用**：`boot.cmd/boot.scr` 现场取分区 UUID，通过 `fnEnv.txt` 指定机型
- **rootfs 通用**：btrfs，不绑定任何设备（hostname=trim、board.json=generic,rockchip、
  boot_board=generic、fstab 用 UUID、machine-id 清空、设备名残留全扫）

设备差异仅体现在 `fnEnv.txt`（fdtfile 指向）和 `board.json`（设备描述）——各板构建时注入。

## 版本

| tag | 内核 | 前导区(0~32MiB) | 状态 |
|---|---|---|---|
| `v1.0.0` | 6.18.18.c951-trim | 内嵌 RK3568 U-Boot (ddr-v1.23) | **已冻结**（历史锚点，永不改动） |
| `src-1.2.0701` | — | — | 源镜像存档（fnOS 1.2.0701 NanoPC-T6 官方原版，md5 402788b6 与官网一致） |
| `v1.1.0` | 6.18.18.c1145-trim | **清零**（U-Boot 由各板构建注入） | 当前通用版 |

- v1.1.0 起前导区清零（只清载荷区 `[17408, 32MiB)`，**GPT 前 17408 字节保留**）：
  3568/3588 无法共用一份 U-Boot（实测：v1.0.0 内嵌 RK3568 版，整盘刷到 3588 板会砖），
  飞牛官方也是每板一份；业界同款做法见 ophub/u-boot（按板存库、构建时注入）。
- 每个正式 release 附 `SHA256SUMS`（raw + gz 两行，均用正式文件名，消费端 `sha256sum -c` 直接可用）。

## 更新新基镜像（全自动，网页两步）

1. **上传官方原版**：[Draft a new release](https://github.com/linyueweia/fnnas-base-images/releases/new)
   - tag 必须以 `src-` 开头（如 `src-20261101`，`src-*` 永不被 latest 选中）
   - 把官网下载的 `.img.gz` **原样**（不解压不改名）拖进 Assets
   - Release notes 写一行 `md5: <官网公布的md5>`（可选；写了 CI 会核对防下载损坏）
   - Publish
2. **发布即触发**：`release published` 事件自动启动 *Make fnOS Universal Base Image*：
   md5 断言 → 去设备绑定 → 独立硬门禁自证（载荷区全零+GPT 完好+分区挂载核对+内核+dtb≥200+boot.scr）
   → 版本号自动 minor+1 → 发布新 `vN.N.N`（.img.gz + SHA256SUMS）

验收：Actions 全绿 + releases 出现新 tag（恰好两个资产）。

## 消费端（各设备仓）如何使用

各仓 workflow 统一逻辑（无需随基镜像更新而改仓库）：

```bash
TAG="${base_image_tag:-latest}"          # latest = 自适应最新正式 release
# jq 排除 draft / prerelease / src-* → 取最新 vX.Y.Z
curl -fL -o base/fnnas-official-arm64-image_rockchip.img.gz "$URL"
# 完整性：release 随附 SHA256SUMS 双校验（gz + 解压后 raw 各一道）
grep " <asset>$" SHA256SUMS | (cd base && sha256sum -c -)
gunzip -c <asset> > base/fnnas-official-arm64-image_rockchip.img   # 正式名对齐 SHA256SUMS
grep " fnnas-official-arm64-image_rockchip.img$" SHA256SUMS | (cd base && sha256sum -c -)
mv base/fnnas-official-arm64-image_rockchip.img base/fnnas-base.img
```

- **回滚/钉版**：三仓手动 Run workflow 时 `base_image_tag` 填具体值（如 `v1.1.0`）。
- **显式钉死内容**：可选输入 `base_image_sha256`（留空 = 只用 SHA256SUMS 校验）。

### U-Boot 口径（2026-10-26 定）

基镜像不带 U-Boot；各板构建时注入本板 U-Boot：

| 仓 | 注入件 | 来源 |
|---|---|---|
| lyw-hk | `uboot/h88k-first32m.bin` | H88K 实机 eMMC 前 32MiB 只读提取 |
| lyw-kf | `uboot/k1-first32m.bin` | v1.0.0 基镜像前 32MiB（= K1 板上同款 ddr-v1.23） |
| xck-nas | `uboot/rk3568/lyt-t68m/`（idbloader.img + u-boot.itb 分件） | 仓内既有素材 |

注入规则：只写镜像 `[17408, 32MiB)` 载荷区，镜像自身 GPT 保留；产物整盘 dd 安全。
刷写不走注入的场景（分区刷 / dd skip）则保留板上现有 U-Boot。

## 手动制作（备用入口）

Actions → *Make fnOS Universal Base Image* → Run workflow，
`source_tag` / `source_asset` / `source_md5` / `target_tag` 四个输入均可手动指定
（target_tag 留空 = 自动 minor+1）。

## 说明

- 分区布局：v1.0.0 = BOOT 360MiB @32MiB / rootfs @408MiB；v1.1.0 = BOOT 380MiB / rootfs @428MiB
  （消费端如有分区尺寸断言须自适应，勿写死）
- ⚠️ 仅用于备份与研究，刷写前请备份数据
