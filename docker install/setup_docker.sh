#!/bin/bash

LOG_FILE="/var/log/setup_docker.log"

# 写日志函数
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOG_FILE"
}

# 检查是否是root用户
if [[ $EUID -ne 0 ]]; then
    log "ERROR: 请以 root 用户运行此脚本！"
    exit 1
fi

# 修改 Rocky Linux 的镜像源
configure_repos() {
    log "开始配置 Rocky Linux 镜像源..."
    sed -e 's|^mirrorlist=|#mirrorlist=|g' \
        -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.aliyun.com/rockylinux|g' \
        -i.bak /etc/yum.repos.d/rocky*.repo
    if [[ $? -ne 0 ]]; then
        log "ERROR: 修改镜像源失败！"
        exit 1
    fi
    log "镜像源配置完成。"
}

# 更新缓存和系统
update_system() {
    log "开始清理和更新缓存..."
    dnf clean all && dnf makecache && dnf update -y
    if [[ $? -ne 0 ]]; then
        log "ERROR: 系统更新失败！"
        exit 1
    fi
    log "系统更新完成。"
}

# 安装必要的软件包
install_dependencies() {
    log "开始安装必要的软件包..."
    dnf install -y yum-utils device-mapper-persistent-data lvm2 bash-completion.noarch
    if [[ $? -ne 0 ]]; then
        log "ERROR: 安装依赖失败！"
        exit 1
    fi
    log "依赖安装完成。"
}

# 配置 Docker 源并安装 Docker
install_docker() {
    if command -v docker &> /dev/null; then
        log "Docker 已安装，跳过安装步骤。"
        return
    fi

    log "添加 Docker 阿里云镜像源..."
    yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo 
    sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo 
    if [[ $? -ne 0 ]]; then
        log "ERROR: 配置 Docker 源失败！"
        exit 1
    fi
    log "Docker 源配置完成。"

    log "开始安装 Docker CE..."
    dnf makecache && dnf -y install docker-ce
    if [[ $? -ne 0 ]]; then
        log "ERROR: Docker 安装失败！"
        exit 1
    fi
    log "Docker 安装完成。"
}

# 配置 Docker 镜像加速
configure_docker() {
    log "配置 Docker 镜像加速器..."
    cat > /etc/docker/daemon.json <<EOF
{
    "registry-mirrors": ["https://docker.1ms.run"]
}
EOF
    systemctl daemon-reload
    systemctl restart docker
    systemctl enable docker
    if [[ $? -ne 0 ]]; then
        log "ERROR: Docker 服务配置失败！"
        exit 1
    fi
    log "Docker 镜像加速器配置完成。"
}

# 停止并禁用 firewalld 服务
disable_firewalld() {
    log "停止并禁用 firewalld 服务..."
    systemctl stop firewalld.service
    systemctl disable firewalld.service
    if [[ $? -ne 0 ]]; then
        log "ERROR: 停止或禁用 firewalld 服务失败！"
        exit 1
    fi
    log "firewalld 服务已停止并禁用。"
}

# 修改 SELinux 配置
disable_selinux() {
    log "禁用 SELinux..."
    # 修改配置文件确保重启后永久生效
    if grep -q '^SELINUX=' /etc/selinux/config; then
        sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    else
        echo "SELINUX=disabled" >> /etc/selinux/config
    fi
    
    # 尝试临时禁用SELinux（仅当当前为Enforcing模式时）
    current_mode=$(getenforce 2>/dev/null)
    if [[ "$current_mode" == "Enforcing" ]]; then
        if setenforce 0; then
            log "SELinux 已临时设置为 Permissive 模式。"
        else
            log "WARNING: 无法临时禁用 SELinux，请检查系统状态（重启后将永久生效）。"
        fi
    else
        log "当前 SELinux 模式为 $current_mode，无需临时调整。"
    fi
    
    log "SELinux 配置完成，重启后将永久禁用。"
}

# 主流程
main() {
    log "开始执行脚本..."
    configure_repos
    update_system
    install_dependencies
    disable_firewalld
    disable_selinux
    install_docker
    configure_docker
    log "所有任务完成！请重启系统以使 SELinux 配置生效。"
}

main
