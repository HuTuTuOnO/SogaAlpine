#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

version="v1.0.0"

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n"
    exit 1
fi

# Check if the OS is Alpine Linux
if [[ -f /etc/alpine-release ]]; then
    release="alpine"
else
    echo -e "${red}本脚本仅适用ALPINE，其他系统请使用官方脚本安装${plain}\n"
    exit 1
fi

confirm() {
    if [ $# -gt 1 ]; then
        echo && read -p "$1 [默认$2]: " temp
        [ -z "$temp" ] && temp=$2
    else
        read -p "$1 [y/n]: " temp
    fi
    [ "$temp" = "y" ] || [ "$temp" = "Y" ] && return 0 || return 1
}

confirm_restart() {
    confirm "是否重启soga" "y"
    if [ $? -eq 0 ]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

install() {
    sh <(curl -Ls https://raw.githubusercontent.com/HuTuTuOnO/SogaAlpine/main/install.sh)
    [ $? -eq 0 ] && ( [ $# -eq 0 ] && start || start 0 )
}

update() {
    if [ $# -eq 0 ]; then
        echo && echo -n -e "输入指定版本(默认最新版): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/HuTuTuOnO/SogaAlpine/main/install.sh) $version
    if [ $? -eq 0 ]; then
        echo -e "${green}更新完成，已自动重启 soga，请使用 soga log 查看运行日志${plain}"
        exit
    fi

    [ $# -eq 0 ] && before_show_menu
}

config() {
    soga-tool "$@"
}

uninstall() {
    confirm "确定要卸载 soga 吗?" "n"
    if [ $? -ne 0 ]; then
        [ $# -eq 0 ] && show_menu
        return 0
    fi
    rc-service soga stop >/dev/null 2>&1
    rc-update del soga
    rm /etc/init.d/soga -f
    rm /etc/soga/ -rf
    rm /usr/local/soga/ -rf

    echo ""
    echo -e "卸载成功，如果你想删除此脚本，则退出脚本后运行 ${green}rm /usr/bin/soga -f${plain} 进行删除"
    echo ""

    [ $# -eq 0 ] && before_show_menu
}

start() {
    check_status
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${green}soga已运行，无需再次启动，如需重启请选择重启${plain}"
    else
        rc-service soga start >/dev/null 2>&1
        sleep 2
        check_status
        if [ $? -eq 0 ]; then
            echo -e "${green}soga 启动成功，请使用 soga log 查看运行日志${plain}"
        else
            echo -e "${red}soga可能启动失败，请稍后使用 soga log 查看日志信息${plain}"
        fi
    fi

    [ $# -eq 0 ] && before_show_menu
}

stop() {
    rc-service soga stop >/dev/null 2>&1
    sleep 2
    check_status
    if [ $? -eq 1 ]; then
        echo -e "${green}soga 停止成功${plain}"
    else
        echo -e "${red}soga停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息${plain}"
    fi

    [ $# -eq 0 ] && before_show_menu
}

restart() {
    rc-service soga restart >/dev/null 2>&1
    sleep 2
    check_status
    if [ $? -eq 0 ]; then
        echo -e "${green}soga 重启成功，请使用 soga log 查看运行日志${plain}"
    else
        echo -e "${red}soga可能启动失败，请稍后使用 soga log 查看日志信息${plain}"
    fi
    [ $# -eq 0 ] && before_show_menu
}

enable() {
    rc-update add soga default
    if [ $? -eq 0 ]; then
        echo -e "${green}soga 设置开机自启成功${plain}"
    else
        echo -e "${red}soga 设置开机自启失败${plain}"
    fi

    [ $# -eq 0 ] && before_show_menu
}

disable() {
    rc-update del soga
    if [ $? -eq 0 ]; then
        echo -e "${green}soga 取消开机自启成功${plain}"
    else
        echo -e "${red}soga 取消开机自启失败${plain}"
    fi

    [ $# -eq 0 ] && before_show_menu
}

show_log() {
    tail -f /var/log/soga.log
    [ $# -eq 0 ] && before_show_menu
}

update_shell() {
    wget -O /usr/bin/soga -N --no-check-certificate https://raw.githubusercontent.com/HuTuTuOnO/SogaAlpine/main/soga.sh
    if [ $? -ne 0 ]; then
        echo ""
        echo -e "${red}下载脚本失败，请检查本机能否连接 Github${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/soga
        echo -e "${green}升级脚本成功，请重新运行脚本${plain}" && exit 0
    fi
}

# 0: started, 1: stopped, 2: not installed, 3: crashed
check_status() {
    [ ! -f /etc/init.d/soga ] && return 2
    status=$(rc-service soga status 2>&1)
	if echo "$status" | grep -q "started"; then
	    return 0
	else	
	    return 1
	fi
}

check_enabled() {
    rc-status | grep -q 'soga'
    [ $? -eq 0 ] && return 0 || return 1
}

check_uninstall() {
    check_status
    if [ $? -ne 2 ]; then
        echo ""
        echo -e "${red}soga已安装，请不要重复安装${plain}"
        [ $# -eq 0 ] && before_show_menu
        return 1
    else
        return 0
    fi
}


check_install() {
    check_status
    if [ $? -eq 2 ]; then
        echo ""
        echo -e "${red}请先安装soga${plain}"
        [ $# -eq 0 ] && before_show_menu
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "soga状态: ${green}已运行${plain}"
            show_enable_status
            ;;
        1)
            echo -e "soga状态: ${yellow}未运行${plain}"
            show_enable_status
            ;;
        2)
            echo -e "soga状态: ${red}未安装${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [ $? -eq 0 ]; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

enable_auto_restart(){
    if crontab -l | grep -q 'rc-service soga restart'; then
        echo -e "${yellow}soga 报错自动重启任务已存在${plain}"
    else
        (crontab -l; echo "* * * * * /bin/sh -c 'if rc-service soga status 2>&1 | grep -qE \"crashed|stopped\"; then rc-service soga restart; fi'") | crontab -
        if [ $? -eq 0 ]; then
            echo -e "${green}已开启 soga 报错自动重启${plain}"
        else
            echo -e "${red}soga 报错自动重启开启失败${plain}"
        fi
    fi
    [ $# -eq 0 ] && before_show_menu
}

disable_auto_restart(){
    crontab -l | grep -v 'rc-service soga restart' | crontab -
    if [ $? -eq 0 ]; then
        echo -e "${green}已取消 soga 报错自动重启${plain}"
    else
        echo -e "${red}soga 报错自动重启取消失败${plain}"
    fi
    [ $# -eq 0 ] && before_show_menu
}

show_usage() {
    echo "soga 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "soga                    - 显示管理菜单 (功能更多)"
    echo "soga start              - 启动 soga"
    echo "soga stop               - 停止 soga"
    echo "soga restart            - 重启 soga"
    echo "soga enable             - 设置 soga 开机自启"
    echo "soga disable            - 取消 soga 开机自启"
    echo "soga log                - 查看 soga 日志"
    echo "soga update             - 更新 soga 最新版"
    echo "soga update x.x.x       - 安装 soga 指定版本"
    echo "soga config             - 显示配置文件内容"
    echo "soga config xx=xx yy=yy - 自动设置配置文件"
    echo "soga install            - 安装 soga"
    echo "soga uninstall          - 卸载 soga"
    echo "soga status             - 查看 soga 状态"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}soga 后端管理脚本，${plain}${red}仅适用于ALPINE${plain}

  ${green}0.${plain} 退出脚本
————————————————
  ${green}1.${plain} 安装 soga
  ${green}2.${plain} 更新 soga
  ${green}3.${plain} 卸载 soga
————————————————
  ${green}4.${plain} 启动 soga
  ${green}5.${plain} 停止 soga
  ${green}6.${plain} 重启 soga
  ${green}7.${plain} 查看 soga 日志
————————————————
  ${green}8.${plain} 设置 soga 开机自启
  ${green}9.${plain} 取消 soga 开机自启
————————————————
 ${green}10.${plain} 查看 soga 状态
————————————————
 ${green}11.${plain} 开启 soga 报错自启
 ${green}12.${plain} 取消 soga 报错自启
 "
    show_status
    read -p "请输入选择 [0-12]: " num

    case "$num" in
        0) exit 0 ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && show_log ;;
        8) check_install && enable ;;
        9) check_install && disable ;;
        10) check_install && show_status ;;
        11) check_install && enable_auto_restart ;;
        12) check_install && disable_auto_restart ;;
        *) echo -e "${red}请输入正确的数字 [0-12]${plain}" ;;
    esac
}

if [[ $# -gt 0 ]]; then
    case "$1" in
        start)      check_install 0 && start 0 ;;
        stop)       check_install 0 && stop 0 ;;
        restart)    check_install 0 && restart 0 ;;
        enable)     check_install 0 && enable 0 ;;
        disable)    check_install 0 && disable 0 ;;
        log)        check_install 0 && show_log 0 "$2" ;;
        update)     check_install 0 && update 0 "$2" ;;
        config)     config "$@" ;;
        install)    check_uninstall 0 && install 0 ;;
        uninstall)  check_install 0 && uninstall 0 ;;
        version)    check_install 0 && show_status 0 ;;
        *)          show_menu ;;
    esac
else
    show_menu
fi
