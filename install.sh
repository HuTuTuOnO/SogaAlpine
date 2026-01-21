#!/bin/sh
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n"
    exit 1
fi

# check os
if grep -Eqi "alpine" /etc/issue || grep -Eqi "alpine" /proc/version; then
    release="alpine"
else
    echo -e "${red}未检测到系统版本或系统不支持，请联系脚本作者！${plain}\n"
    exit 1
fi

arch=$(arch)

if [ "$arch" = "x86_64" ] || [ "$arch" = "x64" ] || [ "$arch" = "amd64" ]; then
    arch="amd64"
elif [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
    arch="arm64"
else
    arch="amd64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ]; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

is_cmd_exist() {
    local cmd="$1"
    if [ -z "$cmd" ]; then
        return 1
    fi

    command -v "$cmd" > /dev/null 2>&1
    return $?
}

install_base() {
    apk update
    # 增加 openssl 以支持 install_acme 
    apk add wget curl tar tzdata socat bash openrc openssl
}

check_status() {
    if [ ! -f /etc/init.d/soga ]; then
        return 2
    fi
    status=$(rc-service soga status | grep "status:" | awk '{print $3}')
    if [ "$status" = "started" ]; then
        return 0
    else
        return 1
    fi
}

install_acme() {
    curl https://get.acme.sh | sh
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
}

install_soga() {
    cd /usr/local/
    if [ -e /usr/local/soga/ ]; then
        rm /usr/local/soga/ -rf
    fi

    if [ $# -eq 0 ]; then
        echo -e "开始安装 soga 最新版"
        wget -N --no-check-certificate -O /usr/local/soga.tar.gz https://github.com/vaxilu/soga/releases/latest/download/soga-linux-${arch}.tar.gz
        if [ $? -ne 0 ]; then
            echo -e "${red}下载 soga 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/vaxilu/soga/releases/download/${last_version}/soga-linux-${arch}.tar.gz"
        echo -e "开始安装 soga v$1"
        wget -N --no-check-certificate -O /usr/local/soga.tar.gz ${url}
        if [ $? -ne 0 ]; then
            echo -e "${red}下载 soga v$1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    tar zxvf soga.tar.gz
    rm soga.tar.gz -f
    cd soga
    chmod +x soga
    # 先创建文件在 执行 ./soga -v
    mkdir -p /etc/soga/
    last_version="$(./soga -v)"

    # 创建适用于 OpenRC 的初始化脚本
    cat > /etc/init.d/soga <<'EOF'
#!/sbin/openrc-run
description="Soga Service"

command="/usr/local/soga/soga"
command_args=""

pidfile="/run/soga.pid"
command_background="yes"
output_log="/var/log/${RC_SVCNAME}.log"
error_log="/var/log/${RC_SVCNAME}.log"

depend() {
    need net
    after firewall
}

start_pre() {
    # Ensure /run directory exists
    [ -d /run ] || mkdir -p /run
    [ -d /var/log ] || mkdir -p /var/log
}

#start() {
#    supervise-daemon ${RC_SVCNAME} --start \
#        --respawn-delay 5 \
#        --pidfile "${pidfile}" \
#        --stdout "${output_log}" \
#        --stderr "${error_log}" \
#        ${command} ${command_args}
#}
#
#stop() {
#    start-stop-daemon --stop --pidfile "${pidfile}" --retry 5
#    rm -f "${pidfile}"
#}
#
#restart() {
#    svc_stop
#    svc_start
#}
EOF

    chmod +x /etc/init.d/soga
    rc-update add soga default

    echo -e "${green}soga v${last_version}${plain} 安装完成，已设置开机自启"
    if [ ! -f /etc/soga/soga.conf ]; then
        cp soga.conf /etc/soga/
        echo -e ""
        echo -e "全新安装，请先配置必要的内容"
    else
        rc-service soga restart
        sleep 2
        check_status
        echo -e ""
        if [ $? -eq 0 ]; then
            echo -e "${green}soga 启动成功${plain}"
        else
            echo -e "${red}soga 可能启动失败，请稍后使用 soga log 查看日志信息${plain}"
        fi
    fi

    if [ ! -f /etc/soga/blockList ]; then
        cp blockList /etc/soga/
    fi
    if [ ! -f /etc/soga/dns.yml ]; then
        cp dns.yml /etc/soga/
    fi
    if [ ! -f /etc/soga/routes.toml ]; then
        cp routes.toml /etc/soga/
    fi
    curl -o /usr/bin/soga -Ls https://raw.githubusercontent.com/HuTuTuOnO/SogaAlpine/main/soga.sh
    chmod +x /usr/bin/soga
    curl -o /usr/bin/soga-tool -Ls https://raw.githubusercontent.com/vaxilu/soga/master/soga-tool-${arch}
    chmod +x /usr/bin/soga-tool
    echo -e ""
    echo "soga 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "soga                    - 显示管理菜单 (功能更多)"
    echo "soga start              - 启动 soga"
    echo "soga stop               - 停止 soga"
    echo "soga restart            - 重启 soga"
    echo "soga status             - 查看 soga 状态"
    echo "soga enable             - 设置 soga 开机自启"
    echo "soga disable            - 取消 soga 开机自启"
    echo "soga update             - 更新 soga"
    echo "soga update x.x.x       - 更新 soga 指定版本"
    echo "soga config             - 显示配置文件内容"
    echo "soga config xx=xx yy=yy - 自动设置配置文件"
    echo "soga install            - 安装 soga"
    echo "soga uninstall          - 卸载 soga"
    echo "soga status             - 查看 soga 版本"
    echo "------------------------------------------"
}

echo -e "${green}开始安装${plain}"
install_base
install_acme
install_soga $1
