#!/bin/bash

# ==================== 代理配置项（请自行修改）====================
HTTP_PROXY="http://127.0.0.1:10809"
SOCKS5_PROXY="socks5://127.0.0.1:10808"
NO_PROXY="localhost,127.0.0.1,::1,localaddress,.localdomain.com"
TEST_URL="https://www.google.com"
# =================================================================

# 颜色输出
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

info() { echo -e "${GREEN}[INFO] $*${RESET}"; }
warn() { echo -e "${YELLOW}[WARN] $*${RESET}"; }
error() { echo -e "${RED}[ERROR] $*${RESET}"; }

# 检查root权限
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    error "权限不足！请使用 sudo 运行此脚本。"
    exit 1
  fi
}

# 检测系统发行版
detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
  else
    error "无法识别系统发行版！"
    exit 1
  fi
}

# 安装全局快捷命令
setup() {
  check_root
  cp "$0" /usr/local/bin/proxy
  chmod +x /usr/local/bin/proxy
  info "✅ 全局命令安装完成！使用方式：proxy [start|stop|status|test]"
}

# 开启代理
start() {
  check_root
  detect_distro
  info "开始配置系统代理..."

  # 1. 配置系统全局环境变量
  cat > /etc/profile.d/proxy.sh << EOF
export http_proxy="$HTTP_PROXY"
export https_proxy="$HTTP_PROXY"
export all_proxy="$SOCKS5_PROXY"
export no_proxy="$NO_PROXY"
export HTTP_PROXY="$HTTP_PROXY"
export HTTPS_PROXY="$HTTP_PROXY"
export ALL_PROXY="$SOCKS5_PROXY"
export NO_PROXY="$NO_PROXY"
EOF

  # 2. 配置包管理器代理
  case "$DISTRO" in
    debian|ubuntu)
      cat > /etc/apt/apt.conf.d/95proxies << EOF
Acquire::http::Proxy "$HTTP_PROXY";
Acquire::https::Proxy "$HTTP_PROXY";
EOF
      info "✅ APT 代理已配置"
      ;;

    centos|rhel|fedora)
      if command -v dnf >/dev/null; then
        sed -i '/^proxy=/d' /etc/dnf/dnf.conf
        sed -i '/^proxy_username=/d' /etc/dnf/dnf.conf
        sed -i '/^proxy_password=/d' /etc/dnf/dnf.conf

        echo "proxy=$HTTP_PROXY" >> /etc/dnf/dnf.conf
        echo "proxy_username=" >> /etc/dnf/dnf.conf
        echo "proxy_password=" >> /etc/dnf/dnf.conf

        info "✅ DNF 代理已配置"

        warn "正在清理 DNF 缓存以确保代理生效..."
        dnf clean all >/dev/null 2>&1
        info "✅ DNF 缓存已清理"
      fi
      ;;
  esac

  # 3. 配置Docker代理
  mkdir -p /etc/systemd/system/docker.service.d
  cat > /etc/systemd/system/docker.service.d/http-proxy.conf << EOF
[Service]
Environment="HTTP_PROXY=$HTTP_PROXY"
Environment="HTTPS_PROXY=$HTTP_PROXY"
Environment="NO_PROXY=$NO_PROXY"
Environment="ALL_PROXY=$SOCKS5_PROXY"
EOF

  if systemctl daemon-reload 2>/dev/null; then
    if systemctl is-active --quiet docker; then
      systemctl restart docker
      info "✅ Docker 代理已配置并重启生效"
    else
      warn "ℹ️ Docker 未运行，仅生成配置文件"
    fi
  fi

  info "🎉 代理开启完成！请重新登录终端或执行：source /etc/profile"
}

# 关闭代理
stop() {
  check_root
  detect_distro
  info "正在关闭所有代理..."

  rm -f /etc/profile.d/proxy.sh
  rm -f /etc/apt/apt.conf.d/95proxies 2>/dev/null
  rm -rf /etc/systemd/system/docker.service.d 2>/dev/null

  if command -v dnf >/dev/null; then
    sed -i '/^proxy=/d' /etc/dnf/dnf.conf
    sed -i '/^proxy_username=/d' /etc/dnf/dnf.conf
    sed -i '/^proxy_password=/d' /etc/dnf/dnf.conf
  fi

  if systemctl daemon-reload 2>/dev/null; then
    if systemctl is-active --quiet docker; then
      systemctl restart docker
    fi
  fi

  unset http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
  info "🎉 代理已全部关闭！"
}

# 查看状态
status() {
  detect_distro
  info "=== 系统代理状态 ==="

  # 环境变量
  if [ -f /etc/profile.d/proxy.sh ]; then
    echo -e "系统环境变量: ${GREEN}🟢 已开启${RESET}"
  else
    echo -e "系统环境变量: ${RED}🔴 未开启${RESET}"
  fi

  # 包管理器
  case "$DISTRO" in
    debian|ubuntu)
      if [ -f /etc/apt/apt.conf.d/95proxies ]; then
        echo -e "APT 代理: ${GREEN}🟢 已开启${RESET}"
      else
        echo -e "APT 代理: ${RED}🔴 未开启${RESET}"
      fi
      ;;
    centos|rhel|fedora)
      if grep -q "^proxy=" /etc/dnf/dnf.conf 2>/dev/null; then
        echo -e "DNF 代理: ${GREEN}🟢 已开启${RESET}"
      else
        echo -e "DNF 代理: ${RED}🔴 未开启${RESET}"
      fi
      ;;
  esac

  # Docker
  if [ -f /etc/systemd/system/docker.service.d/http-proxy.conf ]; then
    echo -e "Docker 代理: ${GREEN}🟢 已开启${RESET}"
  else
    echo -e "Docker 代理: ${RED}🔴 未开启${RESET}"
  fi
}

test_proxy() {
  info "=== 代理连通性测试 ==="
  warn "测试地址：$TEST_URL"
  warn "使用代理：$HTTP_PROXY"

  if ! command -v curl &> /dev/null; then
    error "未安装 curl，正在自动安装..."
    detect_distro
    case "$DISTRO" in
      debian|ubuntu) apt update && apt install -y curl ;;
      centos|rhel|fedora) dnf install -y curl ;;
    esac
  fi

  curl -x "$HTTP_PROXY" -I --connect-timeout 5 --max-time 10 -s "$TEST_URL" | head -n 1

  if [ $? -eq 0 ]; then
    info "✅ 代理连通性测试：成功！"
  else
    error "❌ 代理连通性测试：失败！请检查代理地址是否可用。"
  fi
}

# 主入口
case "$1" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  setup) setup ;;
  test) test_proxy ;;
  *)
    echo "用法：$0 [start|stop|status|setup|test]"
    ;;
esac