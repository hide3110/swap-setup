#!/bin/bash
# sing-box Debian/Ubuntu Linux 安装脚本
# 使用方法: SB_VERSION=1.11.4 AL_PORTS="8443-8445" RE_PORT=443 AL_DOMAIN=example.com RE_SNI=www.example.com API_TOKEN=your_token bash install.sh

set -e

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[信息]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    print_error "此脚本需要 root 权限运行"
    exit 1
fi

# 配置变量（支持环境变量和位置参数，优先使用环境变量）
SB_VERSION=${SB_VERSION:-${1:-1.11.15}}
AL_PORTS=${AL_PORTS:-"65031,65032,65033"}
RE_PORT=${RE_PORT:-443}
AL_DOMAIN=${AL_DOMAIN:-us.yyds.nyc.mn}
RE_SNI=${RE_SNI:-www.cityofrc.us}
API_TOKEN=${API_TOKEN:-K8Xo_z-Sayq0iyQ7icdio0t5lFSRoCFrgdYr7HFY}

# 显示配置信息
print_info "=========================================="
print_info "sing-box 安装脚本"
print_info "=========================================="
print_info "sing-box 版本: $SB_VERSION"
print_info "AL 端口配置: $AL_PORTS"
print_info "Reality 端口: $RE_PORT"
print_info "AL 域名: $AL_DOMAIN"
print_info "Reality SNI: $RE_SNI"
print_info "=========================================="

# 解析端口（支持范围表示法）
if [[ "$AL_PORTS" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    # 范围表示法: 8443-8445
    START_PORT=${BASH_REMATCH[1]}
    END_PORT=${BASH_REMATCH[2]}
    PORT_COUNT=$((END_PORT - START_PORT + 1))
    
    if [ $PORT_COUNT -ne 3 ]; then
        print_error "端口范围必须包含3个端口，当前为 $PORT_COUNT 个"
        exit 1
    fi
    
    SS_PORT=$START_PORT
    TR_PORT=$((START_PORT + 1))
    WS_PORT=$((START_PORT + 2))
    
    print_info "端口分配: SS=$SS_PORT, Trojan=$TR_PORT, VLESS-WS=$WS_PORT"
else
    # 逗号分隔表示法: 8443,9443,10443
    IFS=',' read -ra PORT_ARRAY <<< "$AL_PORTS"
    SS_PORT=${PORT_ARRAY[0]:-65031}
    TR_PORT=${PORT_ARRAY[1]:-65032}
    WS_PORT=${PORT_ARRAY[2]:-65033}
    
    print_info "端口分配: SS=$SS_PORT, Trojan=$TR_PORT, VLESS-WS=$WS_PORT"
fi

# 安装 sing-box
print_info "正在安装 sing-box $SB_VERSION ..."
if curl -fsSL https://sing-box.app/install.sh | bash -s -- --version "$SB_VERSION" > /dev/null 2>&1; then
    print_info "sing-box $SB_VERSION 安装成功"
else
    print_error "sing-box 安装失败"
    exit 1
fi

# 创建目录
CONFIG_DIR="/etc/sing-box"
WORK_DIR="/var/lib/sing-box"
mkdir -p "$CONFIG_DIR" "$WORK_DIR"

# 生成配置文件
print_info "正在生成配置文件..."
cat > "$CONFIG_DIR/config.json" << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": ${SS_PORT},
      "method": "aes-128-gcm",
      "password": "L3vCBgE7nSUlHQcV0D9qYA=="
    },
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
        "server_name": "${AL_DOMAIN}",
        "alpn": [
          "h2",
          "http/1.1"
        ],
        "acme": {
          "domain": "${AL_DOMAIN}",
          "data_directory": "acme",
          "email": "yyds88@gmail.com",
          "dns01_challenge": {
            "provider": "cloudflare",
            "api_token": "${API_TOKEN}"
          }
        }
      }
    },
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${WS_PORT},
      "users": [
        {
          "uuid": "43a1f08a-d9ff-4aea-ac8a-cc622caf62a5"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${AL_DOMAIN}",
        "alpn": [
          "h2",
          "http/1.1"
        ],
        "acme": {
          "domain": "${AL_DOMAIN}",
          "data_directory": "acme",
          "email": "yyds88@gmail.com",
          "dns01_challenge": {
            "provider": "cloudflare",
            "api_token": "${API_TOKEN}"
          }
        }
      }
    },
    {
      "type": "vless",
      "tag": "real-in",
      "listen": "::",
      "listen_port": ${RE_PORT},
      "users": [
        {
          "uuid": "43a1f08a-d9ff-4aea-ac8a-cc622caf62a5",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${RE_SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${RE_SNI}",
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

print_info "配置文件已创建: $CONFIG_DIR/config.json"

# 验证配置
print_info "正在验证配置文件..."
if sing-box check -c "$CONFIG_DIR/config.json" > /dev/null 2>&1; then
    print_info "配置文件验证通过"
else
    print_error "配置文件验证失败，请检查配置"
    exit 1
fi

# 启动服务
print_info "正在启动 sing-box 服务..."
systemctl daemon-reload
systemctl enable sing-box.service --now > /dev/null 2>&1

# 等待服务启动
sleep 2

# 检查服务状态
if systemctl is-active --quiet sing-box.service; then
    SERVICE_STATUS="运行中"
else
    SERVICE_STATUS="启动失败"
    print_error "服务启动失败，请检查日志: journalctl -u sing-box -n 50"
    exit 1
fi

# 输出结果
echo ""
print_info "=========================================="
print_info "sing-box 安装并启动完成！"
print_info "=========================================="
echo ""
print_info "版本信息:"
print_info "  sing-box 版本: $SB_VERSION"
echo ""
print_info "端口配置:"
print_info "  Shadowsocks: $SS_PORT"
print_info "  Trojan (TLS): $TR_PORT"
print_info "  VLESS-WS (TLS): $WS_PORT"
print_info "  VLESS-Reality: $RE_PORT"
echo ""
print_info "域名配置:"
print_info "  ACME 域名: $AL_DOMAIN"
print_info "  Reality SNI: $RE_SNI"
echo ""
print_info "文件位置:"
print_info "  配置文件: $CONFIG_DIR/config.json"
print_info "  工作目录: $WORK_DIR"
print_info "  证书目录: $WORK_DIR/acme (相对路径)"
echo ""
print_info "服务状态:"
print_info "  当前状态: $SERVICE_STATUS"
print_info "  开机自启: 已启用"
echo ""
print_info "常用命令:"
print_info "  查看状态: systemctl status sing-box"
print_info "  查看日志: journalctl -u sing-box -f"
print_info "  重启服务: systemctl restart sing-box"
print_info "=========================================="
