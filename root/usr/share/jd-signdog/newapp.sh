#!/bin/sh
#
# Copyright (C) 2020 luci-app-jd-signdog <jerrykuku@qq.com>
#
# This is free software, licensed under the GNU General Public License v3.
# See /LICENSE for more information.
#
# 501 下载脚本出错
# 101 没有新版本无需更新
# 0   更新成功

NAME=jd-signdog
TEMP_SCRIPT=/tmp/JD_DailyBonus.js
JD_SCRIPT=/usr/share/jd-signdog/JD_DailyBonus.js
LOG_HTM=/www/JD_DailyBonus.htm
CRON_FILE=/etc/crontabs/root
usage() {
    cat <<-EOF
		Usage: app.sh [options]
		Valid options are:

		    -a                      Add Cron
		    -n                      Check 
		    -r                      Run Script
		    -u                      Update Script From Server
		    -s                      Save Cookie And Add Cron
		    -w                      Background Run With Wechat Message
		    -h                      Help
EOF
    exit $1
}

# Common functions

uci_get_by_name() {
    local ret=$(uci get $NAME.$1.$2 2>/dev/null)
    echo ${ret:=$3}
}

uci_get_by_type() {
    local ret=$(uci get $NAME.@$1[0].$2 2>/dev/null)
    echo ${ret:=$3}
}

cancel() {
    if [ $# -gt 0 ]; then
        echo "$1"
    fi
    exit 1
}

fill_cookie() {
    cookie1=$(uci_get_by_type global cookie)
    if [ ! "$cookie1" = "" ]; then
        varb="var Key = '$cookie1';"
        a=$(sed -n '/var Key =/=' $JD_SCRIPT)
        b=$((a-1))
        sed -i "${a}d" $JD_SCRIPT
        sed -i "${b}a ${varb}" $JD_SCRIPT
    fi

    cookie2=$(uci_get_by_type global cookie2)
    if [ ! "$cookie2" = "" ]; then
        varb2="var DualKey = '$cookie2';"
        aa=$(sed -n '/var DualKey =/=' $JD_SCRIPT)
        bb=$((aa-1))
        sed -i "${aa}d" $JD_SCRIPT
        sed -i "${bb}a ${varb2}" $JD_SCRIPT
    fi

    stop=$(uci_get_by_type global stop)
    if [ ! "$stop" = "" ]; then
        varb3="var stop = $stop;"
        sed -i "s/^var stop =.*/$varb3/g" $JD_SCRIPT
    fi
}

add_cron() {
if [ $(uci_get_by_type global jd_enable 0) -eq 1 ]; then
    sed -i '/jd-signdog/d' $CRON_FILE
    [ $(uci_get_by_type global auto_run 0) -eq 1 ] && echo '5 '$(uci_get_by_type global auto_run_time)' * * * sleep '$(expr $(head -n 128 /dev/urandom | tr -dc "0123456789" | head -c4) % 180)'s; /usr/share/jd-signdog/newapp.sh -w' >>$CRON_FILE
    [ $(uci_get_by_type global auto_update 0) -eq 1 ] && echo '1 '$(uci_get_by_type global auto_update_time)' * * * /usr/share/jd-signdog/newapp.sh -u' >>$CRON_FILE
    crontab $CRON_FILE
else
    sed -i '/jd-signdog/d' $CRON_FILE
    crontab $CRON_FILE
fi
}

# Run Script

serverchan() {
    failed=$(uci_get_by_type global failed)

    if [ $1 -eq 0 ]; then
	desc="接口测试通过"
    else
	desc=$(cat /www/JD_DailyBonus.htm | grep -E '签到号|签到概览|签到奖励|其他奖励|账号总计|其他总计' | sed 's/$/&\n/g')
    fi	   
    serverurlflag=$(uci_get_by_type global serverurl)

    if [ "$serverurlflag" = "scu" ]; then
 	sckey=$(uci_get_by_type global serverchan)
        serverurl=https://sc.ftqq.com/
        if [ $failed -eq 1 ]; then
           grep "Cookie失效" /www/JD_DailyBonus.htm > /dev/null
           if [ $? -eq 0 ]; then
                title="$(date '+%Y年%m月%d日') 京东签到 Cookie 失效"
            	wget-ssl -q --output-document=/dev/null --post-data="text=$title~&desp=$desc" $serverurl$sckey.send

           fi
    	else
            title="$(date '+%Y年%m月%d日') 京东签到"
       	    wget-ssl -q --output-document=/dev/null --post-data="text=$title~&desp=$desc" $serverurl$sckey.send

    	fi
    else
	sckey=$(uci_get_by_type global dingding)
        if [ $failed -eq 1 ]; then
            grep "Cookie失效" /www/JD_DailyBonus.htm > /dev/null
      	    if [ $? -eq 0 ]; then
                 send_title="$(date '+%Y年%m月%d日') 京东签到 Cookie 失效"
	         wget-ssl -q --output-document=/dev/null --header="Content-Type:application/json" --post-data="{\"msgtype\":\"markdown\",\"markdown\":{\"title\":\"${send_title}\",\"text\":\"${nowtime}${desc}\"}}" https://oapi.dingtalk.com/robot/send?access_token=${sckey}
            fi
    	else
                 send_title="$(date '+%Y年%m月%d日') 京东签到"
  	         wget-ssl -q --output-document=/dev/null --header="Content-Type:application/json" --post-data="{\"msgtype\":\"markdown\",\"markdown\":{\"title\":\"${send_title}\",\"text\":\"${nowtime}${desc}\"}}" https://oapi.dingtalk.com/robot/send?access_token=${sckey}
    	fi
    fi
}

check_serverchan(){
	serverchan 0
}

run() {
    fill_cookie
    echo -e $(date '+%Y-%m-%d %H:%M:%S %A') >$LOG_HTM 2>/dev/null
    [ ! -f "/usr/bin/node" ] && echo -e "未安装node.js,请安装后再试!\nNode.js is not installed, please try again after installation!">>$LOG_HTM && exit 1
    node $JD_SCRIPT >>$LOG_HTM 2>/dev/null
}

back_run() {
    run
    sleep 1s
    serverchan 1
}

save() {
    fill_cookie
    add_cron
}

# Update Script From Server
download() {
    REMOTE_SCRIPT=$(uci_get_by_type global remote_url)
    wget-ssl --user-agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36" --no-check-certificate -t 3 -T 10 -q $REMOTE_SCRIPT -O $TEMP_SCRIPT
    return $?
}

get_ver() {
    echo $(cat $1 | sed -n '/更新时间/p' | awk '{for (i=1;i<=NF;i++){if ($i ~/v/) {print $i}}}' | sed 's/v//')
}

check_ver() {
    download
    if [ $? -ne 0 ]; then
        cancel "501"
    else
        echo $(get_ver $TEMP_SCRIPT)
    fi
}

update() {
    download
    if [ $? -ne 0 ]; then
        cancel "501"
    fi
    if [ -e $JD_SCRIPT ]; then
        local_ver=$(get_ver $JD_SCRIPT)
    else
        local_ver=0
    fi
    remote_ver=$(get_ver $TEMP_SCRIPT)
    cp -r $TEMP_SCRIPT $JD_SCRIPT
    fill_cookie
    uci set jd-signdog.@global[0].version=$remote_ver
    uci commit jd-signdog
    cancel "0"
}

while getopts ":alnruswhm" arg; do
    case "$arg" in
    a)
        add_cron
        exit 0
        ;;
    l)
        serverchan
        exit 0
        ;;
    n)
        check_ver
        exit 0
        ;;
    r)
        run
        exit 0
        ;;
    u)
        update
        exit 0
        ;;
    s)
        save
        exit 0
        ;;
    w)
        back_run
        exit 0
        ;;
    m)
        check_serverchan
	exit 0
	;;
    h)
        usage 0
        ;;
    esac
done
