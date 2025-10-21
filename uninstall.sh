#!/bin/sh

# sing-box Alpine Linux 安装脚本
# 用途：自动化安装 sing-box 到 Alpine Linux 系统

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印信息函数
print_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
    print_error "此脚本需要 root 权限运行，请使用 sudo 或以 root 用户执行"
    exit 1
fi

# 检查是否为 Alpine Linux
if [ ! -f /etc/alpine-release ]; then
    print_warning "检测到非 Alpine Linux 系统，脚本可能无法正常工作"
fi

# 配置变量（可通过环境变量覆盖）
TR_PORT=${TR_PORT:-65031}
VL_PORT=${VL_PORT:-65032}
VL_SNI=${VL_SNI:-www.cityofrc.us}

# 步骤1：配置环境变量
print_info "步骤 1/9: 配置环境变量"

# 默认版本号，可通过参数修改
SING_BOX_VERSION=${1:-1.11.15}

# 检测系统架构
ARCH=$(case "$(uname -m)" in 
    'x86_64') echo 'amd64';; 
    'x86' | 'i686' | 'i386') echo '386';; 
    'aarch64' | 'arm64') echo 'arm64';; 
    'armv7l') echo 'armv7';; 
    's390x') echo 's390x';; 
    *) echo 'unsupported';; 
esac)

if [ "$ARCH" = "unsupported" ]; then
    print_error "不支持的服务器架构: $(uname -m)"
    exit 1
fi

print_info "检测到的服务器架构: $ARCH"
print_info "sing-box 版本: $SING_BOX_VERSION"
print_info "Trojan 端口: $TR_PORT"
print_info "VLESS 端口: $VL_PORT"
print_info "VLESS SNI: $VL_SNI"

# 步骤2：下载文件
print_info "步骤 2/9: 下载 sing-box"

DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v$SING_BOX_VERSION/sing-box-$SING_BOX_VERSION-linux-$ARCH.tar.gz"
print_info "下载地址: $DOWNLOAD_URL"

if ! wget -q --show-progress "$DOWNLOAD_URL"; then
    print_error "下载失败，请检查网络连接或版本号是否正确"
    exit 1
fi

# 步骤3：解压并安装
print_info "步骤 3/9: 解压并安装可执行文件"

if ! tar -zxf "sing-box-$SING_BOX_VERSION-linux-$ARCH.tar.gz"; then
    print_error "解压失败"
    exit 1
fi

mv "sing-box-$SING_BOX_VERSION-linux-$ARCH/sing-box" /usr/bin/
chmod +x /usr/bin/sing-box

print_info "sing-box 已安装到 /usr/bin/sing-box"

# 步骤4：清理临时文件
print_info "步骤 4/9: 清理临时文件"

rm -rf "./sing-box-$SING_BOX_VERSION-linux-$ARCH"
rm -f "./sing-box-$SING_BOX_VERSION-linux-$ARCH.tar.gz"

# 步骤5：创建配置目录和服务文件
print_info "步骤 5/9: 创建配置目录和 OpenRC 服务文件"

# 创建配置目录
mkdir -p /etc/sing-box
mkdir -p /var/lib/sing-box

# 创建 OpenRC 服务文件
cat > /etc/init.d/sing-box << 'EOF'
#!/sbin/openrc-run

name=$RC_SVCNAME
description="sing-box service"
supervisor="supervise-daemon"
command="/usr/bin/sing-box"
extra_started_commands="reload checkconfig"

: ${SINGBOX_CONFIG="/etc/sing-box"}

if [ -d "$SINGBOX_CONFIG" ]; then
	_config_opt="-C $SINGBOX_CONFIG"
elif [ -z "$SINGBOX_CONFIG" ]; then
	_config_opt=""
else
	_config_opt="-c $SINGBOX_CONFIG"
fi

command_args="run --disable-color
	-D ${SINGBOX_WORKDIR:-"/var/lib/sing-box"}
	$_config_opt"

depend() {
	after net dns
}

checkconfig() {
	ebegin "Checking $RC_SVCNAME configuration"
	sing-box check $_config_opt
	eend $?
}

start_pre() {
	checkconfig
}

reload() {
	ebegin "Reloading $RC_SVCNAME"
	checkconfig && $supervisor "$RC_SVCNAME" --signal HUP
	eend $?
}
EOF

# 步骤6：生成自签证书
print_info "步骤 6/9: 安装 OpenSSL 并生成自签证书"

# 安装 openssl（如果未安装）
if ! command -v openssl >/dev/null 2>&1; then
    print_info "正在安装 OpenSSL..."
    apk add openssl
else
    print_info "OpenSSL 已安装"
fi

# 创建证书存储目录
mkdir -p /etc/ssl/private

# 生成自签证书
print_info "正在生成自签证书 (域名: bing.com, 有效期: 36500天)..."
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout /etc/ssl/private/bing.com.key \
    -out /etc/ssl/private/bing.com.crt \
    -subj "/CN=bing.com" \
    -days 36500

# 设置证书文件权限
chmod 644 /etc/ssl/private/bing.com.key
chmod 644 /etc/ssl/private/bing.com.crt

print_info "自签证书已生成:"

# 步骤7：创建配置文件
print_info "步骤 7/9: 创建 sing-box 配置文件"

cat > /etc/sing-box/config.json << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "::",
      "listen_port": ${TR_PORT},
      "users": [
        {
          "password": "hBh1uKxMhYr6yTc40MDIcg=="
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.bing.com",
        "certificate_path": "/etc/ssl/private/bing.com.crt",
        "key_path": "/etc/ssl/private/bing.com.key"
      }
    },
    {
      "type": "vless",
      "tag": "real-in",
      "listen": "::",
      "listen_port": ${VL_PORT},
      "users": [
        {
          "uuid": "43a1f08a-d9ff-4aea-ac8a-cc622caf62a5",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${VL_SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${VL_SNI}",
            "server_port": 443
          },
          "private_key": "IJ7MvrtAgMGCJdLk4JHtaRci5uAIa2SD5aNO0hsNJ2U",
          "short_id": [
            "4eae9cfd38fb5a8d"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

print_info "配置文件已创建: /etc/sing-box/config.json"

# 验证配置文件
print_info "正在验证配置文件..."
if sing-box check -c /etc/sing-box/config.json; then
    print_info "配置文件验证通过"
else
    print_error "配置文件验证失败，请检查配置"
    exit 1
fi

# 步骤8：配置自启动
print_info "步骤 8/9: 配置 OpenRC 自启动"

chmod +x /etc/init.d/sing-box

if rc-update add sing-box default; then
    print_info "已添加到开机自启动"
else
    print_warning "添加自启动失败，请手动执行: rc-update add sing-box default"
fi

# 步骤9：启动服务
print_info "步骤 9/9: 启动 sing-box 服务"

if rc-service sing-box start; then
    print_info "sing-box 服务已成功启动"
    
    # 等待1秒后检查服务状态
    sleep 1
    
    if rc-service sing-box status > /dev/null 2>&1; then
        print_info "服务运行状态: 正常运行"
    else
        print_warning "服务可能未正常运行，请检查日志"
    fi
else
    print_error "服务启动失败，请检查配置和日志"
    print_info "可以使用以下命令查看日志:"
    print_info "  tail -f /var/log/messages"
    exit 1
fi

# 完成安装
print_info "=========================================="
print_info "sing-box 安装并启动完成！"
print_info "=========================================="
print_info "版本: $SING_BOX_VERSION"
print_info "架构: $ARCH"
print_info ""
print_info "文件位置:"
print_info "  配置文件: /etc/sing-box/config.json"
print_info "  工作目录: /var/lib/sing-box"
print_info "  证书文件: /etc/ssl/private/bing.com.crt"
print_info "  密钥文件: /etc/ssl/private/bing.com.key"
print_info ""
print_info "服务状态:"
print_info "  当前状态: 运行中"
print_info "  开机自启: 已启用"
print_info "=========================================="
