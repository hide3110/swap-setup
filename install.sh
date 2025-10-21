#!/bin/sh

# Debian 和 Alpine 的 Swap 配置脚本
# 使用方法: SW_SIZE=2G SW_NESS=60 ./setup_swap.sh
# 或者: ./setup_swap.sh 2G 60

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 打印函数
print_info() {
    echo "${GREEN}[信息]${NC} $1"
}

print_warn() {
    echo "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo "${RED}[错误]${NC} $1"
}

# 从环境变量或命令行参数获取参数
SWAP_SIZE=${SW_SIZE:-${1:-1G}}
SWAPPINESS=${SW_NESS:-${2:-10}}

# 验证 swap 大小格式
if ! echo "$SWAP_SIZE" | grep -qE '^[0-9]+[MG]$'; then
    print_error "无效的 swap 大小格式。请使用如下格式: 1G, 2G, 512M"
    exit 1
fi

# 验证 swappiness 值
if ! echo "$SWAPPINESS" | grep -qE '^[0-9]+$' || [ "$SWAPPINESS" -lt 0 ] || [ "$SWAPPINESS" -gt 100 ]; then
    print_error "Swappiness 必须是 0 到 100 之间的数字"
    exit 1
fi

# 检查是否以 root 身份运行
if [ "$(id -u)" -ne 0 ]; then
    print_error "此脚本必须以 root 身份运行"
    exit 1
fi

# 检测操作系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    print_error "无法检测操作系统"
    exit 1
fi

print_info "检测到的操作系统: $OS"
print_info "Swap 大小: $SWAP_SIZE"
print_info "Swappiness: $SWAPPINESS"

# 定义 swap 文件路径
SWAP_FILE=/swapfile

# 检查 swap 是否已存在
if [ -f "$SWAP_FILE" ]; then
    print_warn "Swap 文件已存在于 $SWAP_FILE"
    printf "是否要删除并创建新的 swap 文件? (y/N): "
    read REPLY
    if echo "$REPLY" | grep -qE '^[Yy]$'; then
        print_info "正在删除现有 swap..."
        swapoff "$SWAP_FILE" 2>/dev/null || true
        rm -f "$SWAP_FILE"
    else
        print_info "退出，未做任何更改"
        exit 0
    fi
fi

# 检查现有的 swap
EXISTING_SWAP=$(swapon --show --noheadings 2>/dev/null || true)
if [ -n "$EXISTING_SWAP" ]; then
    print_warn "检测到现有 swap:"
    swapon --show
    echo
fi

# 创建 swap 文件
print_info "正在创建大小为 $SWAP_SIZE 的 swap 文件..."

# 将大小转换为 MB 供 dd 命令使用
SIZE_NUM=$(echo "$SWAP_SIZE" | sed 's/[MG]$//')
SIZE_UNIT=$(echo "$SWAP_SIZE" | sed 's/^[0-9]*//')

if [ "$SIZE_UNIT" = "G" ]; then
    SIZE_MB=$((SIZE_NUM * 1024))
else
    SIZE_MB=$SIZE_NUM
fi

# 使用 fallocate（更快）或 dd（备用方案）创建 swap 文件
if command -v fallocate >/dev/null 2>&1; then
    print_info "使用 fallocate 创建 swap 文件..."
    fallocate -l "${SIZE_MB}M" "$SWAP_FILE"
else
    print_info "使用 dd 创建 swap 文件（这可能需要一些时间）..."
    dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SIZE_MB" status=progress
fi

# 设置正确的权限
print_info "正在设置权限..."
chmod 600 "$SWAP_FILE"

# 设置 swap
print_info "正在设置 swap 区域..."
mkswap "$SWAP_FILE"

# 启用 swap
print_info "正在启用 swap..."
swapon "$SWAP_FILE"

# 配置 swappiness
print_info "正在将 swappiness 配置为 $SWAPPINESS..."
sysctl vm.swappiness="$SWAPPINESS"

# 使 swap 永久生效
print_info "正在使 swap 永久生效..."
if ! grep -q "$SWAP_FILE" /etc/fstab; then
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    print_info "已将 swap 条目添加到 /etc/fstab"
else
    print_warn "Swap 条目已存在于 /etc/fstab"
fi

# 使 swappiness 永久生效
SYSCTL_CONF="/etc/sysctl.conf"
if [ "$OS" = "alpine" ]; then
    SYSCTL_CONF="/etc/sysctl.d/99-swappiness.conf"
    mkdir -p /etc/sysctl.d
fi

if grep -q "^vm.swappiness" "$SYSCTL_CONF" 2>/dev/null; then
    sed -i "s/^vm.swappiness.*/vm.swappiness=$SWAPPINESS/" "$SYSCTL_CONF"
    print_info "已在 $SYSCTL_CONF 中更新 swappiness"
else
    echo "vm.swappiness=$SWAPPINESS" >> "$SYSCTL_CONF"
    print_info "已将 swappiness 添加到 $SYSCTL_CONF"
fi

# 显示当前 swap 状态
print_info "当前 swap 状态:"
swapon --show
echo
free -h

print_info "${GREEN}Swap 配置已成功完成!${NC}"
