#!/usr/bin/env bash
#==========================================================================
# fnOS 通用基镜像制作 —— 把设备官方镜像"去设备绑定"成通用底包
#
# 源：fnOS 1.2.0701 NanoPC-T6 (RK3588) 官方镜像
#     md5 402788b6dad39f2c7afe5c18f3fee893（fnnas.com 公布值）
# 改造清单（用户拍板：前导区清零，U-Boot 由各板构建注入）：
#   A. 0~32MiB 前导区整体清零（去 T6 的 RK3588 U-Boot/idbloader/trust 绑定；
#      各板构建时注入本板 U-Boot —— 恢复 lyw-kf 的 UBOOT_DIR 机制；
#      刷写时也不碰板上现有 U-Boot）
#   B. BOOT 分区(ext4)：
#      · fnEnv.txt 删设备绑定行（fdtfile=…），保留通用行
#      · board.json → generic（对照 v1.0.0 通用格式）
#      · 删 u-boot-rockchip-spi.bin（T6 SPI 烧录件，设备特定）
#   C. rootfs 分区(btrfs)：
#      · /etc/hostname → trim（v1.0.0 同款）
#      · 设备名残留清理（nanopc-t6 等 → 无）
#   D. 断言（不过就不出产物）：
#      · 前 32MiB 全零
#      · 无设备名残留（boot+rootfs 两分区）
#      · dtb/rockchip 全量（≥200）、内核 vmlinuz-6.18.18.c1145-trim
#      · boot.scr / fnEnv.txt / grub 在位；分区 p1=BOOT p2=rootfs
#
# 用法: sudo bash make-base.sh <源.img> <输出.img>
set -euo pipefail
fail() { echo "✗ $*" >&2; exit 1; }
ok()   { echo "  ✓ $*"; }

SRC="${1:?用法: make-base.sh <源.img> <输出.img>}"
DST="${2:?用法: make-base.sh <源.img> <输出.img>}"
[[ -f "$SRC" ]] || fail "源镜像不存在: $SRC"

umount_safe() {
    sync; for i in 1 2 3; do umount "$1" 2>/dev/null && return 0; sleep 2; done
    umount -l "$1" 2>/dev/null || true; return 0
}

echo "==== 0) 源镜像 ===="
echo "  $SRC  $(stat -c%s "$SRC") B"

cp -f "$SRC" "$DST"
echo "  副本 → $DST"

LOOP=""; M1="$(mktemp -d)"; M2="$(mktemp -d)"
cleanup() {
    umount_safe "$M1"; umount_safe "$M2"
    [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null || true
    rmdir "$M1" "$M2" 2>/dev/null || true
}
trap cleanup EXIT

echo
echo "==== A) U-Boot 载荷区 [17408, 32MiB) 清零（去绑定；GPT 前17408字节保留）===="
# 注意：GPT（LBA0 MBR + LBA1 header + LBA2~33 entries）就住在前 17408 字节里，
# 整段 32MiB 清零会抹掉分区表 → losetup 找不到分区（run #1 实翻车，别再犯）。
dd if=/dev/zero of="$DST" bs=512 skip=34 seek=34 count=$((32*1024*1024/512-34)) conv=notrunc status=none
ok "载荷区 [17408,32MiB) 已清零，GPT 保留"

echo
echo "==== B) 挂载分区 ===="
LOOP="$(losetup -fP --show "$DST")"
sleep 1
P1="${LOOP}p1"; P2="${LOOP}p2"
[[ -e "$P1" && -e "$P2" ]] || fail "分区异常（需要 p1=BOOT p2=rootfs）"
mount "$P1" "$M1" || fail "挂载 BOOT 失败"
mount "$P2" "$M2" || fail "挂载 rootfs 失败"
echo "  p1=$(lsblk -no FSTYPE "$P1") p2=$(lsblk -no FSTYPE "$P2")"

echo
echo "==== B1) fnEnv.txt 去设备绑定 ===="
FN="$M1/fnEnv.txt"
if [[ -f "$FN" ]]; then
    sed 's/^/     原: /' "$FN"
    # 删设备绑定行（fdtfile=…），其余保留
    grep -v '^fdtfile=' "$FN" > /tmp/_mb_fnenv || true
    mv /tmp/_mb_fnenv "$FN"
    ok "已删 fdtfile= 行（fdtfile 由各板构建注入）"
else
    fail "BOOT 缺 fnEnv.txt"
fi
# 任何残留设备名（fnEnv/board/grub 配置里）
if grep -rqiE 'nanopc-t6|nanopi-t6' "$M1"/*.txt "$M1"/grub/grub.cfg 2>/dev/null; then
    grep -rniE 'nanopc-t6|nanopi-t6' "$M1"/*.txt "$M1"/grub/grub.cfg || true
    fail "fnEnv/grub 仍有设备名残留"
fi
ok "引导配置无设备名残留"

echo
echo "==== B2) board.json → generic ===="
BJ="$M1/board.json"
if [[ -f "$BJ" ]]; then
    sed 's/^/     原: /' "$BJ"
    cat > "$BJ" <<'EOF'
{
  "model": {
    "id": "generic,rockchip",
    "name": "FnNAS Official Base Image (Rockchip)"
  },
  "led": []
}
EOF
    python3 -c "import json;json.load(open('$BJ'))" || fail "board.json 非法"
    ok "board.json → generic,rockchip"
fi

echo
echo "==== B3) 删设备特定引导件 ===="
for f in u-boot-rockchip-spi.bin; do
    if [[ -e "$M1/$f" ]]; then rm -f "$M1/$f"; ok "删 $f"; fi
done

echo
echo "==== C1) rootfs: hostname → trim ===="
HN="$M2/etc/hostname"
if [[ -f "$HN" ]]; then
    echo "     原 hostname: $(cat "$HN")"
    echo "trim" > "$HN"
    ok "hostname → trim"
fi
# hosts 里的设备名
if [[ -f "$M2/etc/hosts" ]] && grep -qi 'nanopc-t6' "$M2/etc/hosts"; then
    sed -i 's/nanopc-t6/trim/gi' "$M2/etc/hosts"
    ok "hosts 设备名 → trim"
fi

echo
echo "==== C2) rootfs 设备名残留全扫 ===="
RES="$(grep -rlI --exclude-dir=usr --exclude-dir=lib --exclude-dir=var --exclude-dir=.snapshots \
      -iE 'nanopc-t6' "$M2/etc" "$M2/root" "$M2/opt" "$M2/boot" 2>/dev/null || true)"
if [[ -n "$RES" ]]; then
    echo "     命中（逐个处理）:"
    echo "$RES" | sed 's/^/       /'
    # machine-id / 首启标记类：清空即可；配置类文件名列表打印出来人工确认
    for f in $RES; do
        case "$f" in
            */machine-id) : > "$f"; ok "清空 $f";;
            *) echo "     ⚠ 需人工确认: $f";;
        esac
    done
    # 仍残留的非已知文件 → 判红（宁可红了看日志，不静默放过）
    RES2="$(grep -rlI --exclude-dir=usr --exclude-dir=lib --exclude-dir=var --exclude-dir=.snapshots \
            -iE 'nanopc-t6' "$M2/etc" "$M2/root" "$M2/opt" "$M2/boot" 2>/dev/null || true)"
    if [[ -n "$RES2" ]]; then
        echo "$RES2" | sed 's/^/       残留: /'
        fail "rootfs 仍有设备名残留（上列文件）"
    fi
fi
ok "rootfs 无设备名残留"

echo
echo "==== D) 断言 ===="
[[ -f "$M1/boot.scr" ]] || fail "缺 boot.scr"
[[ -f "$M1/fnEnv.txt" ]] || fail "缺 fnEnv.txt"
NV="$(ls "$M1"/vmlinuz-* 2>/dev/null | head -1 || true)"
[[ -n "$NV" ]] || fail "缺内核"
ok "内核: $(basename "$NV")"
NDTB="$(ls "$M1/dtb/rockchip/"*.dtb 2>/dev/null | wc -l)"
[[ "$NDTB" -ge 200 ]] || fail "dtb 只有 $NDTB 个（应 ≥200 全量）"
ok "dtb/rockchip 全量: $NDTB 个"
sync
umount_safe "$M1"; umount_safe "$M2"
losetup -d "$LOOP" 2>/dev/null || true
LOOP=""; trap - EXIT

# 终检：载荷区全零 + GPT 完好
python3 - "$DST" <<'PYEOF'
import sys, struct
p = sys.argv[1]
with open(p,'rb') as f:
    head = f.read(32*1024*1024)
nz = sum(1 for b in head[17408:] if b)
assert nz == 0, f"载荷区仍有 {nz} 非零字节"
assert head[512:520] == b'EFI PART', "GPT 头被抹了"
assert head[510:512] == b'\x55\xaa', "MBR 签名丢失"
pl, = struct.unpack('<Q', head[72+512:80+512])
e = head[pl*512:pl*512+128]
s, = struct.unpack('<Q', e[32:40])
assert s == 65536, f"p1 起始 LBA={s}（应 65536）"
print(f"  载荷区全零 ✓  GPT 完好 ✓  p1@LBA{s} ✓")
PYEOF
ok "载荷区全零 + GPT 完好终检通过"

echo
echo "==== 打包（gzip —— 各仓 workflow 用 gzip -t / gunzip -c 解，格式必须一致）===="
OUT_GZ="$DST.gz"
rm -f "$OUT_GZ"
gzip -c -9 "$DST" > "$OUT_GZ"
{
    sha256sum "$DST"
    sha256sum "$OUT_GZ"
} > "$(dirname "$DST")/SHA256SUMS.new"
echo "  raw : $(stat -c%s "$DST") B  $(sha256sum "$DST" | cut -c1-32)…"
echo "  gz  : $(stat -c%s "$OUT_GZ") B  $(sha256sum "$OUT_GZ" | cut -c1-32)…"
echo
echo "== 基镜像制作完成 =="
