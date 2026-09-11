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
DEVICE=lyt-t68m bash buildfnos.sh
```

## 说明

- 基镜像分区布局：BOOT (ext4) @ 32MiB / 360MiB；rootfs (btrfs) @ 408MiB
- 构建产物带 SHA256SUMS 校验
- ⚠️ 仅用于备份与研究，刷写前请备份数据