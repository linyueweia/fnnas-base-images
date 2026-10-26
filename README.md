# fnnas-base-images

飞牛 NAS 官方基镜像存档（rockchip arm64 通用基镜像），用于 CI 自动打包各设备固件。

## 什么是"通用基镜像"

飞牛各设备固件本质上共用同一套系统：

- **内核通用**：所有 arm 设备共用同一 `vmlinuz-6.18.18.c951-trim`
- **dtb 全量**：`dtb/rockchip/` 内含 ~200 个设备树（覆盖 rk3308/3328/3399/3528/3562/3566/3568/3576/3582/3588 全系列）
- **引导通用**：`boot.cmd/boot.scr` 自动适配所有 SoC，通过 `fnEnv.txt` 指定机型
- **rootfs 通用**：btrfs 文件系统，不绑定任何设备（hostname=trim，fstab 使用 UUID）

设备差异仅体现在 `fnEnv.txt`（fdtfile 指向）和 `board.json`（设备描述）。
本仓库的基镜像已清除设备绑定，可注入任意设备的 u-boot + dtb + fnEnv 生成对应固件。

## 使用方法

```bash
# 下载基镜像（文件名以 Release 资产为准）
curl -L -o base.img.gz \
  https://github.com/linyueweia/fnnas-base-images/releases/download/v1.0.0/fnnas-official-arm64-image_rockchip.img.gz

# 解压
gunzip -c base.img.gz > fnnas-arm64/fnnas-arm64.img

# 交给 buildfnos.sh 注入设备 u-boot/dtb/fnEnv
# DEVICE 指定目标设备名（需与 uboot/<soc>/<device> 目录一致）
DEVICE=<device> bash buildfnos.sh
```

## 说明

- 基镜像分区布局：BOOT (ext4) @ 32MiB / 360MiB；rootfs (btrfs) @ 408MiB
- 构建产物带 SHA256SUMS 校验
- ⚠️ 仅用于备份与研究，刷写前请备份数据

## 版本

| tag | 内核 | 前导区(0~32MiB) | 说明 |
|---|---|---|---|
| `v1.0.0` | 6.18.18.c951-trim | 内嵌 RK3568 U-Boot (ddr-v1.23) | 旧版，**已发布即冻结**（lyw-kf / lyw-hk / xck-nas 锁定它，永不改动） |
| `src-1.2.0701` | — | — | 源镜像存档（fnOS 1.2.0701 NanoPC-T6 官方原版，md5 402788b6 与官网一致） |
| `v1.1.0` | 6.18.18.c1145-trim | **清零**（U-Boot 由各板构建注入） | 通用版，由 `make-base.yml` 从源镜像去设备绑定制成 |

### 制作与切换
- 制作：Actions → *Make fnOS Universal Base Image* → Run workflow（源 md5 / 产物自证双门禁）
- 各仓切换：workflow 的 `base_image_tag` 改为新 tag + 同步 `base_image_sha256` 断言（一次一仓，CI 绿 + 上板验再切下一个）
- **U-Boot 口径（2026-10-26 定）**：基镜像不带 U-Boot（3568/3588 无法共用一份，飞牛官方也是每板一份）；
  各板构建时注入本板 U-Boot（如 `lyw-hk/uboot/` 存 H88K 实机提取件），刷写时保留板上现有 U-Boot。
  业界同款做法：ophub/u-boot（按板分文件的 U-Boot 库，构建时按 DEVICE 注入）。
