#!/bin/bash

# ====================================================================
# 项目名称: Debian 12/13 一键安装 XanMod BBRv3 优化脚本 (智能高亮推荐版)
# 支持系统: Debian 12 (bookworm) / Debian 13 (trixie)
# ====================================================================

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[1;33m' # 高亮黄
BLUE='\033[36m'
PLAIN='\033[0m'

# 1. 权限与系统检查
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[错误] 必须使用 root 权限运行此脚本！${PLAIN}"
    exit 1
fi

if [ ! -f /etc/os-release ]; then
    echo -e "${RED}[错误] 无法识别当前系统架构！${PLAIN}"
    exit 1
fi

. /etc/os-release

# 限制仅支持 Debian 12 和 13
if [ "$ID" != "debian" ] || { [ "$VERSION_ID" != "12" ] && [ "$VERSION_ID" != "13" ]; }; then
    echo -e "${RED}[错误] 本脚本仅支持 Debian 12 (bookworm) 和 Debian 13 (trixie)！${PLAIN}"
    echo -e "${YELLOW}当前系统为: ${ID} ${VERSION_ID:-未知版本}${PLAIN}"
    exit 1
fi

# 2. 预检并安装基础依赖
echo -e "${BLUE}[1/5] 正在检查并安装系统必要依赖程序...${PLAIN}"
if ! command -v gpg >/dev/null || ! command -v wget >/dev/null || ! command -v curl >/dev/null; then
    apt update && apt install wget curl gnupg lsb-release -y
fi

# 3. 多重冗余高精度地理位置识别算法
get_country_code() {
    local cc=""
    # 算法 1：Cloudflare 边缘路由追踪（最精准，反映实际物理出网路由）
    cc=$(curl -s --connect-timeout 3 https://www.cloudflare.com/cdn-cgi/trace | grep -E '^loc=' | cut -d= -f2)
    if [ -n "$cc" ] && [ "$cc" != "XX" ] && [ ${#cc} -eq 2 ]; then
        echo "$cc"
        return
    fi
    # 算法 2：ipinfo.io 备用查询
    cc=$(curl -s --connect-timeout 3 https://ipinfo.io/country)
    if [ -n "$cc" ] && [ ${#cc} -eq 2 ]; then
        echo "$cc"
        return
    fi
    # 算法 3：ip-api.com 兜底查询
    cc=$(curl -s --connect-timeout 3 http://ip-api.com/json | grep -o '"countryCode":"[^"]*' | cut -d'"' -f4)
    if [ -n "$cc" ] && [ ${#cc} -eq 2 ]; then
        echo "$cc"
        return
    fi
    echo "US" # 最终兜底默认
}

echo -e "${BLUE}[2/5] 正在高精度分析当前 VPS 出网路由与地理战区...${PLAIN}"
COUNTRY_CODE=$(get_country_code)
COUNTRY_CODE=$(echo "$COUNTRY_CODE" | tr '[:lower:]' '[:upper:]')

IS_ASIA_PACIFIC=false

case "$COUNTRY_CODE" in
    # 亚太低延迟战区
    HK) COUNTRY_NAME="中国香港"; IS_ASIA_PACIFIC=true ;;
    JP) COUNTRY_NAME="日本"; IS_ASIA_PACIFIC=true ;;
    KR) COUNTRY_NAME="韩国"; IS_ASIA_PACIFIC=true ;;
    SG) COUNTRY_NAME="新加坡"; IS_ASIA_PACIFIC=true ;;
    MY) COUNTRY_NAME="马来西亚"; IS_ASIA_PACIFIC=true ;;
    PH) COUNTRY_NAME="菲律宾"; IS_ASIA_PACIFIC=true ;;
    TW) COUNTRY_NAME="中国台湾"; IS_ASIA_PACIFIC=true ;;
    TH) COUNTRY_NAME="泰国"; IS_ASIA_PACIFIC=true ;;
    VN) COUNTRY_NAME="越南"; IS_ASIA_PACIFIC=true ;;
    ID) COUNTRY_NAME="印度尼西亚"; IS_ASIA_PACIFIC=true ;;
    
    # 美洲大带宽战区
    US) COUNTRY_NAME="美国" ;;
    CA) COUNTRY_NAME="加拿大" ;;
    
    # 欧洲及其他远距离战区
    GB|UK) COUNTRY_NAME="英国" ;;
    DE) COUNTRY_NAME="德国" ;;
    NL) COUNTRY_NAME="荷兰" ;;
    FR) COUNTRY_NAME="法国" ;;
    RU) COUNTRY_NAME="俄罗斯" ;;
    AU) COUNTRY_NAME="澳大利亚" ;;
    IN) COUNTRY_NAME="印度" ;;
    
    CN) COUNTRY_NAME="中国大陆" ;;
    *) COUNTRY_NAME="${COUNTRY_CODE}";;
esac

# 4. 根据战区，动态计算菜单高亮及推荐标签
OPT1_COLOR="${GREEN}"
OPT2_COLOR="${GREEN}"
OPT3_COLOR="${GREEN}"
OPT4_COLOR="${GREEN}"

OPT1_TAG=""
OPT2_TAG=""
OPT3_TAG=""
OPT4_TAG=""

if [ "$IS_ASIA_PACIFIC" = "true" ]; then
    OPT1_COLOR="${YELLOW}"
    OPT3_COLOR="${YELLOW}"
    OPT1_TAG=" ${RED}[⭐ 亚太建站推荐]${PLAIN}"
    OPT3_TAG=" ${RED}[⭐ 亚太翻墙推荐]${PLAIN}"
    RECOMMENDED_TIP="检测到您的 VPS 位于【亚太低延迟战区】，已为您高亮推荐 1 和 3 方案。"
else
    OPT2_COLOR="${YELLOW}"
    OPT4_COLOR="${YELLOW}"
    OPT2_TAG=" ${RED}[⭐ 远距离建站推荐]${PLAIN}"
    OPT4_TAG=" ${RED}[⭐ 远距离翻墙推荐]${PLAIN}"
    RECOMMENDED_TIP="检测到您的 VPS 位于【美欧/远距离战区】，已为您高亮推荐 2 和 4 方案。"
fi

# 5. 自动匹配内核包名称
CODENAME=$VERSION_CODENAME
if [ "$VERSION_ID" = "12" ]; then
    KERNEL_PKG="linux-xanmod-lts-x64v3"
else
    KERNEL_PKG="linux-xanmod-x64v3"
fi

# 6. 定义重试函数
retry_command() {
    local max_attempts=5
    local timeout=3
    local attempt=1
    until "$@"; do
        if (( attempt == max_attempts )); then
            echo -e "${RED}[错误] 命令 \"$*\" 失败，已重试 $max_attempts 次。请检查网络后重试。${PLAIN}"
            return 1
        fi
        echo -e "${YELLOW}[警告] 执行失败，正在进行第 $attempt 次重试...${PLAIN}"
        sleep $timeout
        ((attempt++))
    done
    return 0
}

# 7. 清理旧的系统参数配置
clean_sysctl() {
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_notsent_lowat/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_rmem/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_wmem/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_adv_win_scale/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_collapse_max_bytes/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_frto/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_sack/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_dsack/d' /etc/sysctl.conf
}

# 8. 显示交互菜单并渲染高亮
clear
echo -e "${BLUE}==================================================${PLAIN}"
echo -e "       Debian 12/13 XanMod BBRv3 一体化部署脚本"
echo -e "${BLUE}==================================================${PLAIN}"
echo -e "当前系统：${GREEN}Debian ${VERSION_ID} (${CODENAME})${PLAIN}"
echo -e "VPS位置 ：${GREEN}${COUNTRY_NAME} (${COUNTRY_CODE})${PLAIN}"
echo -e "匹配内核：${GREEN}${KERNEL_PKG}${PLAIN}"
echo -e "智能提示：${YELLOW}${RECOMMENDED_TIP}${PLAIN}"
echo -e "${BLUE}==================================================${PLAIN}"
echo -e "请选择使用场景与更换方案："
echo -e "  ${OPT1_COLOR}1. [建站+翻墙] 亚太低延迟区优化 (BBRv3 + FQ_CODEL + 适度缓存)${OPT1_TAG}"
echo -e "  ${OPT2_COLOR}2. [建站+翻墙] 欧美/远距离区优化 (BBRv3 + FQ_CODEL + 标准缓存)${OPT2_TAG}"
echo -e "  ${OPT3_COLOR}3. [纯翻墙机] 亚太低延迟区极限优化 (BBRv3 + CAKE + 亚太TCP调优)${OPT3_TAG}"
echo -e "  ${OPT4_COLOR}4. [纯翻墙机] 欧美/远距离区吞吐优化 (BBRv3 + FQ + 远距离调优)${OPT4_TAG}"
echo -e "  ${RED}0. 退出脚本${PLAIN}"
echo -e "${BLUE}==================================================${PLAIN}"
read -p "请输入数字 [0-4]: " CHOICE

case "$CHOICE" in
    1)
        SCENARIO="[建站+翻墙] 亚太低延迟平衡型"
        CONFIG_SUMMARY="BBRv3 + FQ_CODEL + 适度亚太网络优化"
        clean_sysctl
        echo "net.core.default_qdisc=fq_codel" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_rmem=4096 87380 6291456" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_wmem=4096 65536 6291456" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_sack=1" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_dsack=1" >> /etc/sysctl.conf
        ;;
    2)
        SCENARIO="[建站+翻墙] 远距离标准平衡型"
        CONFIG_SUMMARY="BBRv3 + FQ_CODEL + 标准TCP缓存配置"
        clean_sysctl
        echo "net.core.default_qdisc=fq_codel" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_sack=1" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_dsack=1" >> /etc/sysctl.conf
        ;;
    3)
        SCENARIO="[纯翻墙] 亚太低延迟极限型"
        CONFIG_SUMMARY="BBRv3 + CAKE + 亚太TCP窗口极限优化"
        clean_sysctl
        echo "net.core.default_qdisc=cake" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_notsent_lowat=16384" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_rmem=4096 87380 16777216" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_wmem=4096 65536 16777216" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_adv_win_scale=-2" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_collapse_max_bytes=6291456" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_frto=2" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_sack=1" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_dsack=1" >> /etc/sysctl.conf
        ;;
    4)
        SCENARIO="[纯翻墙] 远距离吞吐极限型"
        CONFIG_SUMMARY="BBRv3 + FQ + 远距离吞吐量优化"
        clean_sysctl
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_notsent_lowat=16384" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_sack=1" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_dsack=1" >> /etc/sysctl.conf
        ;;
    0)
        echo -e "${BLUE}已退出脚本。${PLAIN}"
        exit 0
        ;;
    *)
        echo -e "${RED}[错误] 输入无效，脚本退出！${PLAIN}"
        exit 1
        ;;
esac

# 9. 开始执行更换动作
echo -e "\n${BLUE}[3/5] 开始配置 XanMod 官方存储库...${PLAIN}"
rm -f /etc/apt/sources.list.d/xanmod-release.list

mkdir -p /etc/apt/keyrings
retry_command wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor --yes -o /etc/apt/keyrings/xanmod-archive-keyring.gpg
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] PGP 证书导入失败！请检查系统网络连接。${PLAIN}"
    exit 1
fi

echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org ${CODENAME} main" | tee /etc/apt/sources.list.d/xanmod-release.list

echo -e "\n${BLUE}[4/5] 正在安装 XanMod 内核包 [${KERNEL_PKG}]...${PLAIN}"
retry_command apt update
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] 软件源更新失败！${PLAIN}"
    exit 1
fi

retry_command apt install ${KERNEL_PKG} -y
if [ $? -ne 0 ]; then
    echo -e "${RED}[错误] 内核程序安装失败！${PLAIN}"
    exit 1
fi

# 10. 执行核心修复：更新 GRUB 引导
echo -e "\n${BLUE}[5/5] 正在强行更新 GRUB 系统引导配置...${PLAIN}"
retry_command update-grub
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}[警告] update-grub 执行异常，正在尝试备份方案生成 grub.cfg...${PLAIN}"
    grub-mkconfig -o /boot/grub/grub.cfg
fi

# 11. 应用系统优化配置
sysctl -p > /dev/null

# 12. 输出漂亮的执行结果
clear
echo -e "${GREEN}==================================================${PLAIN}"
echo -e "          🎉 内核更换与网络调优配置成功！"
echo -e "${GREEN}==================================================${PLAIN}"
echo -e "当前系统为：${BLUE}Debian ${VERSION_ID} ${CODENAME}${PLAIN}，vps国家为：${BLUE}${COUNTRY_NAME}${PLAIN}；"
echo -e "使用场景：${BLUE}${SCENARIO}${PLAIN}；"
echo -e "已经成功配置：${BLUE}${CONFIG_SUMMARY}${PLAIN}。"
echo -e "${GREEN}==================================================${PLAIN}"
echo -e "${YELLOW}⚠️ 注意：请现在输入 reboot 重启服务器，使新内核生效！${PLAIN}"
echo -e "${YELLOW}重启后运行 uname -r 和 tc qdisc show 检查是否成功生效。${PLAIN}"
echo -e "${GREEN}==================================================${PLAIN}"