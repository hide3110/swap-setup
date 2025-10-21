#!/bin/sh

# Debian 和 Alpine 的 Swap 删除脚本
# 使用方法: sudo ./remove.sh

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

print_success() {
    echo "${GREEN}[成功]${NC} $1"
}

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

# 定义 swap 文件路径
SWAP_FILE=/swapfile

# 显示当前 swap 状态
print_info "当前 swap 状态:"
if swapon --show 2>/dev/null | grep -q .; then
    swapon --show
    echo
    free -h
    echo
else
    print_warn "当前没有启用的 swap"
fi

# 检查 swap 文件是否存在
if [ ! -f "$SWAP_FILE" ]; then
    print_warn "未找到 swap 文件 $SWAP_FILE"
    
    # 检查是否有其他 swap 设备
    if swapon --show 2>/dev/null | grep -q .; then
        print_info "检测到其他 swap 设备，但不是 $SWAP_FILE"
        printf "是否要继续清理 swap 配置? (y/N): "
        read REPLY
        if ! echo "$REPLY" | grep -qE '^[Yy]$'; then
            print_info "已取消操作"
            exit 0
        fi
    else
        print_info "系统中没有需要删除的 swap"
        exit 0
    fi
else
    print_warn "找到 swap 文件: $SWAP_FILE"
    printf "确定要删除 swap 配置吗? 此操作不可恢复 (y/N): "
    read REPLY
    if ! echo "$REPLY" | grep -qE '^[Yy]$'; then
        print_info "已取消操作"
        exit 0
    fi
fi

echo

# 禁用 swap 文件
if [ -f "$SWAP_FILE" ]; then
    print_info "正在禁用 swap 文件..."
    if swapoff "$SWAP_FILE" 2>/dev/null; then
        print_success "Swap 文件已禁用"
    else
        print_warn "Swap 文件可能已经被禁用"
    fi
    
    # 删除 swap 文件
    print_info "正在删除 swap 文件..."
    if rm -f "$SWAP_FILE"; then
        print_success "Swap 文件已删除"
    else
        print_error "删除 swap 文件失败"
    fi
fi

# 从 /etc/fstab 中移除 swap 条目
print_info "正在从 /etc/fstab 中移除 swap 条目..."
if grep -q "$SWAP_FILE" /etc/fstab 2>/dev/null; then
    # 创建备份
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
    print_info "已创建 /etc/fstab 备份"
    
    # 删除包含 swapfile 的行
    sed -i "\#$SWAP_FILE#d" /etc/fstab
    print_success "已从 /etc/fstab 中移除 swap 条目"
else
    print_warn "/etc/fstab 中未找到 swap 条目"
fi

# 移除 swappiness 配置
print_info "正在移除 swappiness 配置..."

# 处理 /etc/sysctl.conf
if [ -f /etc/sysctl.conf ]; then
    if grep -q "^vm.swappiness" /etc/sysctl.conf; then
        cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S)
        print_info "已创建 /etc/sysctl.conf 备份"
        
        sed -i '/^vm.swappiness/d' /etc/sysctl.conf
        print_success "已从 /etc/sysctl.conf 中移除 swappiness 配置"
    fi
fi

# 处理 Alpine 的 sysctl.d 目录
if [ "$OS" = "alpine" ] && [ -f /etc/sysctl.d/99-swappiness.conf ]; then
    print_info "正在删除 Alpine swappiness 配置文件..."
    rm -f /etc/sysctl.d/99-swappiness.conf
    print_success "已删除 /etc/sysctl.d/99-swappiness.conf"
fi

# 重置 swappiness 为系统默认值
print_info "正在重置 swappiness 为系统默认值 (60)..."
sysctl vm.swappiness=60 2>/dev/null || true

# 显示最终状态
echo
print_info "最终系统状态:"
if swapon --show 2>/dev/null | grep -q .; then
    print_warn "仍有以下 swap 设备处于活动状态:"
    swapon --show
else
    print_success "所有 swap 已被禁用"
fi

echo
free -h

echo
print_success "${GREEN}Swap 删除操作已完成!${NC}"
print_info "提示: 配置文件的备份已保存，文件名包含时间戳"
