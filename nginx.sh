#!/bin/bash

# ANSI 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印带颜色的日志
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 权限
if [[ $EUID -ne 0 ]]; then
   log_error "此脚本必须以 root 权限运行，请使用 sudo 或切换到 root 用户。"
   exit 1
fi

# 检测发行版并安装 NGINX
main() {
    log_info "开始检测操作系统环境..."

    # 检测 ID (如 ubuntu, debian, centos, rhel)
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID=$ID
        DISTRO_VERSION=$VERSION_ID
    else
        log_error "无法检测操作系统，请确保系统支持 /etc/os-release。"
        exit 1
    fi

    case $DISTRO_ID in
        ubuntu|debian)
            log_info "检测到系统: ${DISTRO_ID^} $DISTRO_VERSION"
            log_info "正在配置 NGINX 官方 Stable 仓库..."

            # 1. 安装依赖 (参考文档 Ubuntu/Debian 章节)
            apt update
            apt install -y curl gnupg2 ca-certificates lsb-release

            # 2. 导入官方签名密钥
            # 参考文档: Ubuntu/Debian Installation instructions
            curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

            # 3. 验证密钥指纹 (可选，脚本中通常省略交互，但为了安全建议检查)
            # 预期指纹: 573B FD6B 3D8F BC64 1079 A6AB ABF5 BD82 7BD9 BF62
            EXPECTED_FINGERPRINT="573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62"
            ACTUAL_FINGERPRINT=$(gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg 2>&1 | grep -o "573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62" || true)

            if [ "$ACTUAL_FINGERPRINT" != "$EXPECTED_FINGERPRINT" ]; then
                log_warn "警告: GPG 密钥指纹验证失败。"
                log_warn "预期: $EXPECTED_FINGERPRINT"
                log_warn "实际: $ACTUAL_FINGERPRINT"
                log_warn "建议手动检查密钥后继续。"
            else
                log_info "GPG 密钥指纹验证通过。"
            fi

            # 4. 添加仓库源 (Stable 版本)
            # 参考文档: echo "deb [signed-by=...] https://nginx.org/packages/..."
            echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/${DISTRO_ID} $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list

            # 5. 设置 Pinning (优先使用官方源)
            # 参考文档: /etc/apt/preferences.d/99nginx
            echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx

            # 6. 安装 NGINX
            apt update
            apt install -y nginx
            ;;

        centos|rhel|almalinux|rocky)
            log_info "检测到系统: ${DISTRO_ID^} $DISTRO_VERSION"
            log_info "正在配置 NGINX 官方 Stable 仓库..."

            # 1. 安装依赖 (参考文档 RHEL 章节)
            # 使用 yum-utils 提供 yum-config-manager
            yum install -y yum-utils

            # 2. 创建 repo 文件
            # 参考文档: /etc/yum.repos.d/nginx.repo
            cat > /etc/yum.repos.d/nginx.repo << EOF
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF

            # 3. 安装 NGINX
            # 参考文档: yum install nginx
            # 注意: 安装过程中会提示接受 GPG Key，脚本中 -y 会自动确认
            yum install -y nginx
            ;;

        *)
            log_error "不支持的操作系统: $DISTRO_ID"
            log_info "本脚本支持: Ubuntu, Debian, CentOS, RHEL, AlmaLinux, Rocky Linux"
            exit 1
            ;;
    esac

    # 启动服务
    if command -v systemctl &> /dev/null; then
        systemctl enable nginx
        systemctl start nginx
        log_info "NGINX 已安装并启动。"
        log_info "请访问 http://$(hostname -I | awk '{print $1}') 查看默认页面"
    else
        log_warn "无法使用 systemctl 管理服务，请手动启动 nginx。"
    fi
}

# 执行主函数
main "$@"