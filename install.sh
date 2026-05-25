#!/bin/bash

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

install_base() {
    apk update
    # 增加 openssl 以支持 install_acme 
    apk add wget curl tar tzdata socat bash openrc openssl
}

check_status() {
    if [ ! -f "/etc/init.d/${alias_name}" ]; then
        return 2
    fi
    status=$(rc-service "$alias_name" status | grep "status:" | awk '{print $3}')
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
    
    if [ -n "$2" ]; then
        alias_name="$2"
    else
        printf "请输入管理命令名称 [默认 soga]: "
        read -r alias_name
        [ -z "$alias_name" ] && alias_name="soga"
    fi

    case "$alias_name" in
        *[!a-zA-Z0-9_-]*|"")
            echo -e "${red}命令名称只能包含字母、数字、下划线和横杠${plain}"
            exit 1
            ;;
    esac

    cd /usr/local/
    if [ -e "/usr/local/${alias_name}" ]; then
        rm "/usr/local/${alias_name}" -rf
    fi

    if [ -z "$1" ]; then
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
    if [ "$alias_name" != "soga" ]; then
        mv soga "$alias_name"
        cd "/usr/local/${alias_name}"
        if [ -f soga ]; then
            mv soga "$alias_name"
        fi
        if [ -f soga.conf ]; then
            mv soga.conf "${alias_name}.conf"
        fi
    else
        cd "/usr/local/${alias_name}"
    fi
    chmod +x "$alias_name"
    # 先创建目录再执行版本检查
    mkdir -p "/etc/${alias_name}"
    last_version="$(./${alias_name} -v)"

    # 创建适用于 OpenRC 的初始化脚本
    cat > "/etc/init.d/${alias_name}" <<EOF
#!/sbin/openrc-run
description="${alias_name} Service"

command="/usr/local/${alias_name}/${alias_name}"
command_args="-c /etc/${alias_name}/${alias_name}.conf"

pidfile="/run/${alias_name}.pid"
command_background="yes"
output_log="/var/log/${alias_name}.log"
error_log="/var/log/${alias_name}.log"

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

    chmod +x "/etc/init.d/${alias_name}"
    rc-update add "$alias_name" default

    echo -e "${green}${alias_name} v${last_version}${plain} 安装完成，已设置开机自启"
    
    if [ ! -f "/etc/${alias_name}/${alias_name}.conf" ]; then
        cp "${alias_name}.conf" "/etc/${alias_name}/${alias_name}.conf"
        echo -e ""
        echo -e "全新安装，请先配置必要的内容"
    else
        rc-service "$alias_name" restart
        sleep 2
        check_status
        echo -e ""
        if [ $? -eq 0 ]; then
            echo -e "${green}${alias_name} 启动成功${plain}"
        else
            echo -e "${red}${alias_name} 可能启动失败，请稍后使用 ${alias_name} log 查看日志信息${plain}"
        fi
    fi

    if [ ! -f "/etc/${alias_name}/blockList" ]; then
        cp blockList "/etc/${alias_name}/"
    fi
    if [ ! -f "/etc/${alias_name}/dns.yml" ]; then
        cp dns.yml "/etc/${alias_name}/"
    fi
    if [ ! -f "/etc/${alias_name}/routes.toml" ]; then
        cp routes.toml "/etc/${alias_name}/"
    fi
    curl -o "/usr/bin/${alias_name}" -Ls https://raw.githubusercontent.com/HuTuTuOnO/SogaAlpine/main/soga.sh
    chmod +x "/usr/bin/${alias_name}"
    curl -o "/usr/bin/${alias_name}-tools" -Ls https://raw.githubusercontent.com/vaxilu/soga/master/soga-tool-${arch}
    chmod +x "/usr/bin/${alias_name}-tools"
    echo -e ""
    echo "${alias_name} 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "${alias_name}                    - 显示管理菜单 (功能更多)"
    echo "${alias_name} start              - 启动 ${alias_name}"
    echo "${alias_name} stop               - 停止 ${alias_name}"
    echo "${alias_name} restart            - 重启 ${alias_name}"
    echo "${alias_name} status             - 查看 ${alias_name} 状态"
    echo "${alias_name} enable             - 设置 ${alias_name} 开机自启"
    echo "${alias_name} disable            - 取消 ${alias_name} 开机自启"
    echo "${alias_name} update             - 更新 ${alias_name}"
    echo "${alias_name} update x.x.x       - 更新 ${alias_name} 指定版本"
    echo "${alias_name} config             - 显示配置文件内容"
    echo "${alias_name} config xx=xx yy=yy - 自动设置配置文件"
    echo "${alias_name} install            - 安装 ${alias_name}"
    echo "${alias_name} uninstall          - 卸载 ${alias_name}"
    echo "${alias_name} version            - 查看 ${alias_name} 版本"
    echo "------------------------------------------"
}

echo -e "${green}开始安装${plain}"

install_base
install_acme
install_soga "$1" "$2"
