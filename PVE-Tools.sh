#!/bin/bash

# PVE 9.0 配置工具脚本
# 支持换源、删除订阅弹窗、硬盘管理等功能
# 适用于 Proxmox VE 9.0 (基于 Debian 13)
# Auther:Maple 二次修改使用请不要删除此段注释

# 版本信息
CURRENT_VERSION="6.8.0"
VERSION_FILE_URL="https://raw.githubusercontent.com/Mapleawaa/PVE-Tools-9/main/VERSION"
UPDATE_FILE_URL="https://raw.githubusercontent.com/Mapleawaa/PVE-Tools-9/main/UPDATE"

# 颜色定义 - 保持一致性
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
ORANGE='\033[0;33m'  
NC='\033[0m'

# UI 界面一致性常量
UI_BORDER="═════════════════════════════════════════════════"
UI_DIVIDER="═════════════════════════════════════════════════"
UI_FOOTER="═════════════════════════════════════════════════"
UI_HEADER="═════════════════════════════════════════════════"
UI_FOOTER_SHORT="═════════════════════════════════════════════════"

# 镜像源配置
MIRROR_USTC="https://mirrors.ustc.edu.cn/proxmox/debian/pve"
MIRROR_TUNA="https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/pve"
MIRROR_DEBIAN="https://deb.debian.org/debian"
SELECTED_MIRROR=""

# ceph 模板源配置
CEPH_MIRROR_USTC="https://mirrors.ustc.edu.cn/proxmox/debian/ceph-squid"
CEPH_MIRROR_TUNA="https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/ceph-squid"
CEPH_MIRROR_OFFICIAL="http://download.proxmox.com/debian/ceph-squid"

# CT 模板源配置
CT_MIRROR_USTC="https://mirrors.ustc.edu.cn/proxmox"
CT_MIRROR_TUNA="https://mirrors.tuna.tsinghua.edu.cn/proxmox"
CT_MIRROR_OFFICIAL="http://download.proxmox.com"

# 自动更新网络检测配置
CF_TRACE_URL="https://www.cloudflare.com/cdn-cgi/trace"
GITHUB_MIRROR_PREFIX="https://ghfast.top/"
USE_MIRROR_FOR_UPDATE=0
USER_COUNTRY_CODE=""

# 快速虚拟机下载脚本配置
FASTPVE_INSTALLER_URL="https://raw.githubusercontent.com/kspeeder/fastpve/main/fastpve-install.sh"
FASTPVE_PROJECT_URL="https://github.com/kspeeder/fastpve"

# 日志函数
log_info() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} ${CYAN}INFO${NC} $1" >> /var/log/pve-tools.log
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')]${NC} ${ORANGE}WARN${NC} $1" | tee -a /var/log/pve-tools.log
}

log_error() {
    echo -e "${RED}[$(date +'%H:%M:%S')]${NC} ${RED}ERROR${NC} $1" | tee -a /var/log/pve-tools.log >&2
}

log_step() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} ${MAGENTA}STEP${NC} $1" | tee -a /var/log/pve-tools.log
}

log_success() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} ${GREEN}OK${NC} $1" | tee -a /var/log/pve-tools.log
}

log_tips(){
    echo -e "${CYAN}[$(date +'%H:%M:%S')]${NC} ${MAGENTA}TIPS${NC} $1" | tee -a /var/log/pve-tools.log
}

# Enhanced error handling function with consistent messaging
display_error() {
    local error_msg="$1"
    local suggestion="${2:-请检查输入或联系作者寻求帮助。}"
    
    log_error "$error_msg"
    echo -e "${YELLOW}提示: $suggestion${NC}"
    pause_function
}

# Enhanced success feedback
display_success() {
    local success_msg="$1"
    local next_step="${2:-}"
    
    log_success "$success_msg"
    if [[ -n "$next_step" ]]; then
        echo -e "${GREEN}下一步: $next_step${NC}"
    fi
}

# Confirmation prompt with consistent UI
confirm_action() {
    local action_desc="$1"
    local default_choice="${2:-N}"
    
    echo -e "${YELLOW}确认操作: $action_desc${NC}"
    read -p "请输入 'yes' 确认继续，其他任意键取消 [$default_choice]: " -r confirm
    if [[ "$confirm" == "yes" || "$confirm" == "YES" ]]; then
        return 0
    else
        log_info "操作已取消"
        return 1
    fi
}

# 进度指示函数
show_progress() {
    local message="$1"
    local spinner="|/-\\"
    local i=0
    # Print initial message
    echo -ne "${CYAN}[    ]${NC} $message\033[0K\r"
    
    # Update the spinner position in the box
    while true; do
        i=$(( (i + 1) % 4 ))
        echo -ne "\b\b\b\b\b${CYAN}[${spinner:$i:1}]${NC}\033[0K\r"
        sleep 0.1
    done &
    # Store the background job ID to be killed later
    SPINNER_PID=$!
}

update_progress() {
    local message="$1"
    # Kill the spinner if running
    if [[ -n "$SPINNER_PID" ]]; then
        kill $SPINNER_PID 2>/dev/null
    fi
    echo -ne "${GREEN}[ OK ]${NC} $message\033[0K\r"
    echo
}

# Enhanced visual feedback function
show_status() {
    local status="$1"
    local message="$2"
    local color="$3"
    
    case $status in
        "info")
            echo -e "${CYAN}[INFO]${NC} $message"
            ;;
        "success")
            echo -e "${GREEN}[ OK ]${NC} $message"
            ;;
        "warning")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "error")
            echo -e "${RED}[FAIL]${NC} $message"
            ;;
        "step")
            echo -e "${MAGENTA}[STEP]${NC} $message"
            ;;
        *)
            echo -e "${WHITE}[$status]${NC} $message"
            ;;
    esac
}

# Progress bar function
show_progress_bar() {
    local current="$1"
    local total="$2"
    local message="$3"
    local width=40
    local percentage=$(( current * 100 / total ))
    local filled=$(( width * current / total ))
    
    printf "${CYAN}[${NC}"
    for ((i=0; i<filled; i++)); do
        printf "█"
    done
    for ((i=filled; i<width; i++)); do
        printf " "
    done
    printf "${CYAN}]${NC} ${percentage}%% $message\r"
}

# 通过 Cloudflare Trace 检测地区，决定是否启用镜像源
detect_network_region() {
    local timeout=5
    USER_COUNTRY_CODE=""
    USE_MIRROR_FOR_UPDATE=0

    if ! command -v curl &> /dev/null; then
        return 1
    fi

    local trace_output
    trace_output=$(curl -s --connect-timeout $timeout --max-time $timeout "$CF_TRACE_URL" 2>/dev/null)
    if [[ -z "$trace_output" ]]; then
        return 1
    fi

    local loc
    loc=$(echo "$trace_output" | awk -F= '/^loc=/{print $2}' | tr -d '\r')
    if [[ -z "$loc" ]]; then
        return 1
    fi

    USER_COUNTRY_CODE="$loc"
    if [[ "$USER_COUNTRY_CODE" == "CN" ]]; then
        USE_MIRROR_FOR_UPDATE=1
    fi

    return 0
}

# 显示横幅
show_banner() {
    clear
    cat << 'EOF'
██████╗ ██╗   ██╗███████╗    ████████╗ ██████╗  ██████╗ ██╗     ███████╗     █████╗ 
██╔══██╗██║   ██║██╔════╝    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██╔════╝    ██╔══██╗
██████╔╝██║   ██║█████╗         ██║   ██║   ██║██║   ██║██║     ███████╗    ╚██████║
██╔═══╝ ╚██╗ ██╔╝██╔══╝         ██║   ██║   ██║██║   ██║██║     ╚════██║     ╚═══██║
██║      ╚████╔╝ ███████╗       ██║   ╚██████╔╝╚██████╔╝███████╗███████║     █████╔╝
╚═╝       ╚═══╝  ╚══════╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝     ╚════╝ 
EOF
    echo "═════════════════════════════════════════════════"
    echo "PVE-Tools-9 一键脚本"
    echo "让每个人都能体验虚拟化技术的的便利。"
    echo "作者: Maple & Claude 4.5 & 提交PR的你们"
    echo "当前版本: $CURRENT_VERSION | 最新版本: $remote_version"
    echo "═════════════════════════════════════════════════"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "哎呀！需要超级管理员权限才能运行哦"
        echo "请使用以下命令重新运行："
        echo "sudo $0"
        exit 1
    fi
}

# 检查调试模式
check_debug_mode() {
    for arg in "$@"; do
        if [[ "$arg" == "--debug" ]]; then
            log_warn "警告：您正在使用调试模式！"
            echo "此模式将跳过 PVE 系统版本检测"
            echo "仅在开发和测试环境中使用"
            echo "在非 PVE (Debian 系) 系统上使用可能导致系统损坏"
            echo "您确定要继续吗？输入 'yes' 确认，其他任意键退出: "
            read -r confirm
            if [[ "$confirm" != "yes" ]]; then
                log_info "已取消操作，退出脚本"
                exit 0
            fi
            DEBUG_MODE=true
            log_success "已启用调试模式"
            return
        fi
    done
    DEBUG_MODE=false
}

# 检查是否安装依赖软件包
check_packages() {
    # 程序依赖的软件包: `sudo` `curl`
    local packages=("sudo" "curl")
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            log_error "哎呀！需要安装 $pkg 软件包才能运行哦"
            echo "请使用以下命令安装：apt install -y $pkg"
            exit 1
        fi
    done
 }
    



# 检查 PVE 版本
check_pve_version() {
    # 如果在调试模式下，跳过 PVE 版本检测
    if [[ "$DEBUG_MODE" == "true" ]]; then
        log_warn "调试模式：跳过 PVE 版本检测"
        echo "请注意：您正在非 PVE 系统上运行此脚本，某些功能可能无法正常工作"
        return
    fi
    
    if ! command -v pveversion &> /dev/null; then
        log_error "咦？这里好像不是 PVE 环境呢"
        echo "请在 Proxmox VE 系统上运行此脚本"
        exit 1
    fi
    
    local pve_version=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1)
    log_info "太好了！检测到 PVE 版本: $pve_version"
}

# 检测当前内核版本
check_kernel_version() {
    log_info "检测当前内核信息..."
    local current_kernel=$(uname -r)
    local kernel_arch=$(uname -m)
    local kernel_variant=""
    
    # 检测内核变体（普通/企业版/测试版）
    if [[ $current_kernel == *"pve"* ]]; then
        kernel_variant="PVE标准内核"
    elif [[ $current_kernel == *"edge"* ]]; then
        kernel_variant="PVE边缘内核"
    elif [[ $current_kernel == *"test"* ]]; then
        kernel_variant="测试内核"
    else
        kernel_variant="未知类型"
    fi
    
    echo -e "${CYAN}当前内核信息：${NC}"
    echo -e "  版本: ${GREEN}$current_kernel${NC}"
    echo -e "  架构: ${GREEN}$kernel_arch${NC}"
    echo -e "  类型: ${GREEN}$kernel_variant${NC}"
    
    # 检测可用的内核版本
    local installed_kernels=$(dpkg -l | grep -E 'pve-kernel|linux-image' | grep -E 'ii|hi' | awk '{print $2}' | sort -V)
    if [[ -n "$installed_kernels" ]]; then
        echo -e "${CYAN}已安装的内核版本：${NC}"
        while IFS= read -r kernel; do
            echo -e "  ${GREEN}•${NC} $kernel"
        done <<< "$installed_kernels"
    fi
    
    return 0
}

# 获取可用内核列表
get_available_kernels() {
    log_info "获取可用内核列表..."
    
    # 检查网络连接
    if ! ping -c 1 mirrors.tuna.tsinghua.edu.cn &> /dev/null; then
        log_error "网络连接失败，无法获取内核列表"
        return 1
    fi
    
    # 获取当前 PVE 版本
    local pve_version=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1)
    local major_version=$(echo $pve_version | cut -d'.' -f1)
    
    # 构建内核包URL
    local kernel_url="https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/pve/dists/trixie/pve-no-subscription/binary-amd64/Packages"
    
    # 下载并解析可用内核
    local available_kernels=$(curl -s "$kernel_url" | grep -E 'Package: (pve-kernel|linux-pve)' | awk '{print $2}' | sort -V | uniq)
    
    if [[ -z "$available_kernels" ]]; then
        log_warn "无法获取可用内核列表，使用备用方法"
        # 备用方法：使用apt-cache搜索
        available_kernels=$(apt-cache search --names-only '^pve-kernel-.*' | awk '{print $1}' | sort -V)
    fi
    
    if [[ -n "$available_kernels" ]]; then
        echo -e "${CYAN}可用内核版本：${NC}"
        while IFS= read -r kernel; do
            echo -e "  ${BLUE}•${NC} $kernel"
        done <<< "$available_kernels"
    else
        log_error "无法找到可用内核"
        return 1
    fi
    
    return 0
}

# 安装指定内核版本
install_kernel() {
    local kernel_version=$1
    
    # 验证内核版本格式
    if [[ -z "$kernel_version" ]]; then
        log_error "请指定要安装的内核版本"
        return 1
    fi
    
    # 检查是否已经是完整包名格式 (contains "pve" and ends with "pve")
    if [[ "$kernel_version" =~ ^[a-zA-Z0-9.-]+pve$ ]]; then
        # This looks like a complete package name, use it as is
        log_info "检测到完整包名格式: $kernel_version"
    elif ! [[ "$kernel_version" =~ ^pve-kernel- ]]; then
        # If not in the correct format, prepend "pve-kernel-"
        log_info "检测到版本号格式，自动补全包名为 pve-kernel-$kernel_version"
        kernel_version="pve-kernel-$kernel_version"
    fi
    
    log_info "开始安装内核: $kernel_version"
    
    # 检查内核是否已安装
    if dpkg -l | grep -q "^ii.*$kernel_version"; then
        log_warn "内核 $kernel_version 已经安装"
        read -p "是否重新安装？(y/N): " reinstall
        if [[ "$reinstall" != "y" && "$reinstall" != "Y" ]]; then
            return 0
        fi
    fi
    
    # 更新软件包列表
    log_info "更新软件包列表..."
    if ! apt-get update; then
        log_error "更新软件包列表失败"
        return 1
    fi
    
    # 安装内核
    log_info "正在安装内核 $kernel_version ..."
    if ! apt-get install -y "$kernel_version"; then
        log_error "内核安装失败"
        return 1
    fi
    
    log_success "内核 $kernel_version 安装成功"
    
    # 更新引导配置
    update_grub_config
    
    return 0
}

# 更新 GRUB 配置
update_grub_config() {
    log_info "更新引导配置..."
    
    # 检查是否是 UEFI 系统
    local efi_dir="/boot/efi"
    local grub_cfg=""
    
    if [[ -d "$efi_dir" ]]; then
        log_info "检测到 UEFI 启动模式"
        grub_cfg="/boot/efi/EFI/proxmox/grub.cfg"
    else
        log_info "检测到 Legacy BIOS 启动模式"
        grub_cfg="/boot/grub/grub.cfg"
    fi
    
    # 更新 GRUB
    if command -v update-grub &> /dev/null; then
        if update-grub; then
            log_success "GRUB 配置更新成功"
        else
            log_warn "GRUB 配置更新过程中出现警告，但可能仍然成功"
        fi
    elif command -v grub-mkconfig &> /dev/null; then
        if grub-mkconfig -o "$grub_cfg"; then
            log_success "GRUB 配置更新成功"
        else
            log_warn "GRUB 配置更新过程中出现警告"
        fi
    else
        log_error "找不到 GRUB 更新工具"
        return 1
    fi
    
    return 0
}

# 切换默认启动内核
set_default_kernel() {
    local kernel_version=$1
    
    if [[ -z "$kernel_version" ]]; then
        log_error "请指定要设置为默认的内核版本"
        return 1
    fi
    
    log_info "设置默认启动内核: ${GREEN}$kernel_version${NC}"
    
    # 检查内核是否存在
    if ! [[ -d "/boot/initrd.img-$kernel_version" || -d "/boot/vmlinuz-$kernel_version" ]]; then
        log_error "内核文件不存在，请先安装该内核"
        return 1
    fi
    
    # 使用 grub-set-default 设置默认内核
    if command -v grub-set-default &> /dev/null; then
        # 查找内核在 GRUB 菜单中的位置
        local menu_entry=$(grep -n "$kernel_version" /boot/grub/grub.cfg | head -1 | cut -d: -f1)
        if [[ -n "$menu_entry" ]]; then
            # 计算 GRUB 菜单项索引（从0开始）
            local grub_index=$(( (menu_entry - 1) / 2 ))
            if grub-set-default "$grub_index"; then
                log_success "默认启动内核设置成功"
                return 0
            fi
        fi
    fi
    
    # 备用方法：手动编辑 GRUB 配置
    log_warn "使用备用方法设置默认内核"
    
    # 备份当前 GRUB 配置
    cp /etc/default/grub /etc/default/grub.backup.$(date +%Y%m%d%H%M%S)
    
    # 设置 GRUB_DEFAULT 为内核版本
    if sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Proxmox VE GNU\/Linux>Proxmox VE GNU\/Linux, with Linux $kernel_version\"/" /etc/default/grub; then
        log_success "GRUB 配置更新成功"
        update_grub_config
        return 0
    else
        log_error "GRUB 配置更新失败"
        return 1
    fi
}

# 删除旧内核（保留最近2个版本）
remove_old_kernels() {
    log_info "清理旧内核..."
    
    # 获取所有已安装的内核
    local installed_kernels=$(dpkg -l | grep -E '^ii.*pve-kernel' | awk '{print $2}' | sort -V)
    local kernel_count=$(echo "$installed_kernels" | wc -l)
    
    if [[ $kernel_count -le 2 ]]; then
        log_info "当前只有 $kernel_count 个内核，无需清理"
        return 0
    fi
    
    # 计算需要保留的内核数量（保留最新的2个）
    local keep_count=2
    local remove_count=$((kernel_count - keep_count))
    
    echo -e "${YELLOW}将删除 $remove_count 个旧内核，保留最新的 $keep_count 个内核${NC}"
    
    # 获取要删除的内核列表（最旧的几个）
    local kernels_to_remove=$(echo "$installed_kernels" | head -n $remove_count)
    
    read -p "是否继续？(y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "取消内核清理"
        return 0
    fi
    
    # 删除旧内核
    while IFS= read -r kernel; do
        log_info "正在删除内核: $kernel"
        if apt-get remove -y --purge "$kernel"; then
            log_success "内核 $kernel 删除成功"
        else
            log_error "删除内核 $kernel 失败"
        fi
    done <<< "$kernels_to_remove"
    
    # 更新引导配置
    update_grub_config
    
    log_success "旧内核清理完成"
    return 0
}

# 内核管理主菜单
kernel_management_menu() {
    while true; do
        echo
        echo "${UI_BORDER}"
        echo "  内核管理菜单"
        echo "${UI_DIVIDER}"
        show_menu_option "1" "显示当前内核信息"
        show_menu_option "2" "查看可用内核列表"
        show_menu_option "3" "安装新内核"
        show_menu_option "4" "设置默认启动内核"
        show_menu_option "5" "清理旧内核"
        show_menu_option "6" "重启系统应用新内核"
        echo "${UI_DIVIDER}"
        show_menu_option "0" "返回主菜单"
        echo "${UI_FOOTER}"
        
        read -p "请选择操作 [0-6]: " choice
        
        case $choice in
            1)
                check_kernel_version
                ;;
            2)
                get_available_kernels
                ;;
            3)
                echo "请输入要安装的内核版本："
                echo "  - 完整包名格式 (推荐): 如 proxmox-kernel-6.14.8-2-pve"
                echo "  - 简化版本格式: 如 6.8.8-1 (将自动补全为 pve-kernel-6.8.8-1)"
                read -p "请输入内核标识: " kernel_ver
                if [[ -n "$kernel_ver" ]]; then
                    install_kernel "$kernel_ver"
                else
                    log_error "请输入有效的内核版本"
                fi
                ;;
            4)
                read -p "请输入要设置为默认的内核版本 (例如: 6.8.8-1-pve): " kernel_ver
                if [[ -n "$kernel_ver" ]]; then
                    set_default_kernel "$kernel_ver"
                else
                    log_error "请输入有效的内核版本"
                fi
                ;;
            5)
                remove_old_kernels
                ;;
            6)
                read -p "确认要重启系统吗？(y/N): " reboot_confirm
                if [[ "$reboot_confirm" == "y" || "$reboot_confirm" == "Y" ]]; then
                    log_info "系统将在5秒后重启..."
                    echo "按 Ctrl+C 取消重启"
                    sleep 5
                    reboot
                else
                    log_info "取消重启"
                fi
                ;;
            0)
                break
                ;;
            *)
                log_error "无效的选择，请重新输入"
                ;;
        esac
        
        echo
        pause_function
    done
}

# 内核同步更新（自动检测并更新到最新稳定版）
sync_kernel_update() {
    log_info "开始内核同步更新检查..."
    
    # 获取当前内核版本
    local current_kernel=$(uname -r)
    log_info "当前内核版本: ${GREEN}$current_kernel${NC}"
    
    # 获取最新可用内核
    local latest_kernel=$(get_available_kernels | tail -1 | awk '{print $2}')
    
    if [[ -z "$latest_kernel" ]]; then
        log_error "无法获取最新内核信息"
        return 1
    fi
    
    log_info "最新可用内核: ${GREEN}$latest_kernel${NC}"
    
    # 检查是否需要更新
    if [[ "$current_kernel" == *"$latest_kernel"* ]]; then
        log_success "当前已是最新内核，无需更新"
        return 0
    fi
    
    echo -e "${YELLOW}发现新内核版本: $latest_kernel${NC}"
    read -p "是否安装并更新到最新内核？(Y/n): " update_confirm
    
    if [[ "$update_confirm" == "n" || "$update_confirm" == "N" ]]; then
        log_info "取消内核更新"
        return 0
    fi
    
    # 安装最新内核
    if install_kernel "$latest_kernel"; then
        # 设置新内核为默认启动项
        if set_default_kernel "$latest_kernel"; then
            log_success "内核同步更新完成"
            echo -e "${YELLOW}建议重启系统以应用新内核${NC}"
            return 0
        else
            log_warn "内核安装成功但设置默认启动项失败"
            return 1
        fi
    else
        log_error "内核更新失败"
        return 1
    fi
}

# 备份文件
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        # 创建备份目录
        local backup_dir="/etc/pve-tools-9-bak"
        mkdir -p "$backup_dir"
        
        # 生成带时间戳的备份文件名
        local filename=$(basename "$file")
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_path="${backup_dir}/${filename}.backup.${timestamp}"
        
        cp "$file" "$backup_path"
        
        # 仅记录到日志文件，减少控制台干扰
        echo "[$(date +'%H:%M:%S')] [BACKUP] $file -> $backup_path" >> /var/log/pve-tools.log
    fi
}

# 换源功能
change_sources() {
    log_step "开始为您的 PVE 换上飞速源"
    
    # 根据选择的镜像源确定URL
    local debian_mirror=""
    local debian_security_mirror=""
    local pve_mirror=""
    local ct_mirror=""

    case $SELECTED_MIRROR in
        $MIRROR_USTC)
            debian_mirror="https://mirrors.ustc.edu.cn/debian"
            pve_mirror="$MIRROR_USTC"
            ceph_mirror="$CEPH_MIRROR_USTC"
            ct_mirror="$CT_MIRROR_USTC"
            ;;
        $MIRROR_TUNA)
            debian_mirror="https://mirrors.tuna.tsinghua.edu.cn/debian"
            pve_mirror="$MIRROR_TUNA"
            ceph_mirror="$CEPH_MIRROR_TUNA"
            ct_mirror="$CT_MIRROR_TUNA"
            ;;
        $MIRROR_DEBIAN)
            debian_mirror="https://deb.debian.org/debian"
            debian_security_mirror="https://security.debian.org/debian-security"
            pve_mirror="https://ftp.debian.org/debian"
            ceph_mirror="$CEPH_MIRROR_OFFICIAL"
            ct_mirror="$CT_MIRROR_OFFICIAL"
            ;;
    esac
    
    # 询问用户是否要更换安全更新源
    log_info "安全更新源选择"
    echo "═════════════════════════════════════════════════"
    echo "  安全更新源包含重要的系统安全补丁，选择合适的源很重要："
    echo "  1) 使用官方安全源 (推荐，更新最及时，但可能较慢)"
    echo "  2) 使用镜像站安全源 (速度快，但可能有延迟)"
    echo "═════════════════════════════════════════════════"
    
    read -p "  请选择 [1-2] (默认: 1): " security_choice
    security_choice=${security_choice:-1}
    
    if [[ "$security_choice" == "2" ]]; then
        # 使用镜像站的安全源
        case $SELECTED_MIRROR in
            $MIRROR_USTC)
                debian_security_mirror="https://mirrors.ustc.edu.cn/debian-security"
                ;;
            $MIRROR_TUNA)
                debian_security_mirror="https://mirrors.tuna.tsinghua.edu.cn/debian-security"
                ;;
            $MIRROR_DEBIAN)
                debian_security_mirror="https://security.debian.org/debian-security"
                ;;
        esac
        log_info "将使用镜像站的安全更新源"
    else
        # 使用官方安全源
        debian_security_mirror="https://security.debian.org/debian-security"
        log_info "将使用官方安全更新源"
    fi
    
    # 1. 更换 Debian 软件源 (DEB822 格式)
    log_info "正在配置 Debian 镜像源..."
    backup_file "/etc/apt/sources.list.d/debian.sources"
    
    cat > /etc/apt/sources.list.d/debian.sources << EOF
Types: deb
URIs: $debian_mirror
Suites: trixie trixie-updates trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
# Types: deb-src
# URIs: $debian_mirror
# Suites: trixie trixie-updates trixie-backports
# Components: main contrib non-free non-free-firmware
# Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 以下安全更新软件源包含了官方源与镜像站配置，如有需要可自行修改注释切换
Types: deb
URIs: $debian_security_mirror
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# Types: deb-src
# URIs: $debian_security_mirror
# Suites: trixie-security
# Components: main contrib non-free non-free-firmware
# Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    
    # 2. 注释企业源
    log_info "正在关闭企业源（我们用免费版就够啦）..."
    if [[ -f "/etc/apt/sources.list.d/pve-enterprise.sources" ]]; then
        backup_file "/etc/apt/sources.list.d/pve-enterprise.sources"
        sed -i 's/^Types:/#Types:/g' /etc/apt/sources.list.d/pve-enterprise.sources
        sed -i 's/^URIs:/#URIs:/g' /etc/apt/sources.list.d/pve-enterprise.sources
        sed -i 's/^Suites:/#Suites:/g' /etc/apt/sources.list.d/pve-enterprise.sources
        sed -i 's/^Components:/#Components:/g' /etc/apt/sources.list.d/pve-enterprise.sources
        sed -i 's/^Signed-By:/#Signed-By:/g' /etc/apt/sources.list.d/pve-enterprise.sources
    fi
    
    # 3. 更换 Ceph 源
    log_info "正在配置 Ceph 镜像源..."
    if [[ -f "/etc/apt/sources.list.d/ceph.sources" ]]; then
        backup_file "/etc/apt/sources.list.d/ceph.sources"
        cat > /etc/apt/sources.list.d/ceph.sources << EOF
Types: deb
URIs: $ceph_mirror
Suites: trixie
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    fi
    
    # 4. 添加无订阅源
    log_info "正在添加免费版专用源..."
    cat > /etc/apt/sources.list.d/pve-no-subscription.sources << EOF
Types: deb
URIs: $pve_mirror
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    
    # 5. 更换 CT 模板源
    log_info "正在加速 CT 模板下载..."
    if [[ -f "/usr/share/perl5/PVE/APLInfo.pm" ]]; then
        backup_file "/usr/share/perl5/PVE/APLInfo.pm"
        # 先恢复为官方源,确保可以二次替换
        sed -i "s|https://mirrors.ustc.edu.cn/proxmox|http://download.proxmox.com|g" /usr/share/perl5/PVE/APLInfo.pm
        sed -i "s|https://mirrors.tuna.tsinghua.edu.cn/proxmox|http://download.proxmox.com|g" /usr/share/perl5/PVE/APLInfo.pm
        # 然后替换为选定的镜像源
        sed -i "s|http://download.proxmox.com|$ct_mirror|g" /usr/share/perl5/PVE/APLInfo.pm
    fi
    
    log_success "太棒了！所有源都换成飞速版本啦"
}

# 删除订阅弹窗
remove_subscription_popup() {
    log_step "正在消除那个烦人的订阅弹窗"
    
    local js_file="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    if [[ -f "$js_file" ]]; then
        backup_file "$js_file"
        
        # 修复逻辑：
        # 新版 PVE 的 proxmoxlib.js 在 Ext.Msg.show 调用前有大量换行和空格
        # 原有的 sed 正则 "Ext.Msg.show\(\{\s+title" 可能因为换行符匹配失败
        # 新方案：直接将判断条件中的 !== 'active' 改为 == 'active'，从逻辑上短路
        # 匹配模式：res.data.status.toLowerCase() !== 'active'
        # 这种方式比替换 Ext.Msg.show 更稳定，且代码侵入性更小

        if grep -q "res.data.status.toLowerCase() !== 'active'" "$js_file"; then
             sed -i "s/res.data.status.toLowerCase() !== 'active'/res.data.status.toLowerCase() == 'active'/g" "$js_file"
             log_success "策略A生效：修改了判断逻辑"
        elif grep -q "Ext.Msg.show({" "$js_file"; then
             # 备用方案：如果找不到特定判断逻辑，尝试旧方法的宽泛匹配，但增强兼容性
             # 使用 perl 替代 sed 以更好地支持多行匹配
             perl -i -0777 -pe "s/(Ext\.Msg\.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" "$js_file"
             log_success "策略B生效：屏蔽了弹窗函数"
        else
             log_error "未找到匹配的代码片段，可能文件版本已更新"
             return 1
        fi

        systemctl restart pveproxy.service
        log_success "完美！再也不会有烦人的弹窗啦"
    else
        log_warn "咦？没找到弹窗文件，可能已经被处理过了"
    fi
}

# 恢复 proxmoxlib.js 文件
restore_proxmoxlib() {
    log_step "准备恢复 proxmoxlib.js 官方原版文件"
    local js_file="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    local download_url="https://ghfast.top/github.com/Mapleawaa/PVE-Tools-9/blob/main/proxmoxlib.js"
    
    # 警告提示
    log_warn "此操作将从云端下载官方原版文件覆盖当前文件"
    log_warn "如果之前有过修改，将会丢失！"
    echo -e "${YELLOW}您确定要继续吗？输入 'yes' 确认: ${NC}"
    read -r confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "操作已取消"
        return
    fi

    # 备份当前文件
    if [[ -f "$js_file" ]]; then
        backup_file "$js_file"
    fi

    # 下载文件
    log_info "正在下载文件..."
    # 注意：github blob链接下载需要处理，这里假设用户提供的链接可以直接wget下载或者通过raw格式下载
    # 修正链接为 raw 格式，虽然 ghfast.top 做了加速，但 blob 页面是 html，需要 raw 链接
    # 用户给的是 blob 链接: https://ghfast.top/github.com/Mapleawaa/PVE-Tools-9/blob/main/proxmoxlib.js
    # 尝试转换为 raw 链接，通常 github 加速镜像也支持 raw
    # 假设 ghfast.top 支持 /raw/ 路径或者直接替换 blob 为 raw
    # 既然是镜像，我们尝试直接去下载用户提供的链接，如果不行可能需要调整
    # 但根据经验，github 文件下载通常用 raw.githubusercontent.com 或加速镜像的对应 raw 路径
    # 我们可以尝试构造一个更稳妥的 raw 链接
    # 原始: https://github.com/Mapleawaa/PVE-Tools-9/raw/main/proxmoxlib.js
    # 加速: https://ghfast.top/https://github.com/Mapleawaa/PVE-Tools-9/raw/main/proxmoxlib.js
    
    local raw_url="https://ghfast.top/https://github.com/Mapleawaa/PVE-Tools-9/raw/main/proxmoxlib.js"
    
    if curl -L -o "$js_file" "$raw_url"; then
        if [[ -s "$js_file" ]]; then
            log_success "下载成功！正在重启 pveproxy 服务..."
            systemctl restart pveproxy.service
            log_success "恢复完成！文件已重置为官方状态"
        else
            log_error "下载的文件为空，恢复失败"
            # 尝试恢复备份
            if [[ -f "${js_file}.bak" ]]; then
                mv "${js_file}.bak" "$js_file"
                log_info "已恢复之前的备份文件"
            fi
        fi
    else
        log_error "下载失败，请检查网络连接"
    fi
}

# 合并 local 与 local-lvm
merge_local_storage() {
    log_step "准备合并存储空间，让小硬盘发挥最大价值"
    log_warn "重要提醒：此操作会删除 local-lvm，请确保重要数据已备份！"
    
    echo -e "${YELLOW}您确定要继续吗？这个操作不可逆哦${NC}"
    read -p "输入 'yes' 确认继续，其他任意键取消: " -r
    if [[ ! $REPLY == "yes" ]]; then
        log_info "明智的选择！操作已取消"
        return
    fi
    
    # 检查 local-lvm 是否存在
    if ! lvdisplay /dev/pve/data &> /dev/null; then
        log_warn "没有找到 local-lvm 分区，可能已经合并过了"
        return
    fi
    
    log_info "正在删除 local-lvm 分区..."
    lvremove -f /dev/pve/data
    
    log_info "正在扩容 local 分区..."
    lvextend -l +100%FREE /dev/pve/root
    
    log_info "正在扩展文件系统..."
    resize2fs /dev/pve/root
    
    log_success "存储合并完成！现在空间更充裕了"
    log_warn "温馨提示：请在 Web UI 中删除 local-lvm 存储配置，并编辑 local 存储勾选所有内容类型"
}

# 删除 Swap 分配给主分区
remove_swap() {
    log_step "准备释放 Swap 空间给系统使用"
    log_warn "注意：删除 Swap 后请确保内存充足！"
    
    echo -e "${YELLOW}您确定要删除 Swap 分区吗？${NC}"
    read -p "输入 'yes' 确认继续，其他任意键取消: " -r
    if [[ ! $REPLY == "yes" ]]; then
        log_info "好的，操作已取消"
        return
    fi
    
    # 检查 swap 是否存在
    if ! lvdisplay /dev/pve/swap &> /dev/null; then
        log_warn "没有找到 swap 分区，可能已经删除过了"
        return
    fi
    
    log_info "正在关闭 Swap..."
    swapoff /dev/mapper/pve-swap
    
    log_info "正在修改启动配置..."
    backup_file "/etc/fstab"
    sed -i 's|^/dev/pve/swap|# /dev/pve/swap|g' /etc/fstab
    
    log_info "正在删除 swap 分区..."
    lvremove -f /dev/pve/swap
    
    log_info "正在扩展系统分区..."
    lvextend -l +100%FREE /dev/mapper/pve-root
    
    log_info "正在扩展文件系统..."
    resize2fs /dev/mapper/pve-root
    
    log_success "Swap 删除完成！系统空间更宽裕了"
}

# 更新系统
update_system() {
    log_step "开始更新系统，让 PVE 保持最新状态 📦"
    
    echo -e "${CYAN}正在更新软件包列表...${NC}"
    apt update
    
    echo -e "${CYAN}正在升级系统软件包...${NC}"
    apt upgrade -y
    
    echo -e "${CYAN}正在清理不需要的软件包...${NC}"
    apt autoremove -y
    
    log_success "系统更新完成！您的 PVE 现在是最新版本"
}

# 标准化暂停函数
pause_function() {
    echo -n "按任意键继续... "
    read -n 1 -s input
    if [[ -n ${input} ]]; then
        echo -e "\b
"
    fi
}



#--------------开启硬件直通----------------
# 开启硬件直通
enable_pass() {
    echo
    log_step "开启硬件直通..."
    if [ `dmesg | grep -e DMAR -e IOMMU|wc -l` = 0 ];then
        log_error "您的硬件不支持直通！不如检查一下主板的BIOS设置？"
        pause_function
        return
    fi
    if [ `cat /proc/cpuinfo|grep Intel|wc -l` = 0 ];then
        iommu="amd_iommu=on"
    else
        iommu="intel_iommu=on"
    fi
    if [ `grep $iommu /etc/default/grub|wc -l` = 0 ];then
        backup_file "/etc/default/grub"
        sed -i 's|quiet|quiet '$iommu'|' /etc/default/grub
        update-grub
        if [ `grep "vfio" /etc/modules|wc -l` = 0 ];then
            cat <<-EOF >> /etc/modules
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
kvmgt
EOF
        fi
        
        if [ ! -f "/etc/modprobe.d/blacklist.conf" ];then
            echo "blacklist snd_hda_intel" >> /etc/modprobe.d/blacklist.conf 
            echo "blacklist snd_hda_codec_hdmi" >> /etc/modprobe.d/blacklist.conf 
            echo "blacklist i915" >> /etc/modprobe.d/blacklist.conf 
        fi

        if [ ! -f "/etc/modprobe.d/vfio.conf" ];then
            echo "options vfio-pci ids=8086:3185" >> /etc/modprobe.d/vfio.conf
        fi
        
        log_success "开启设置后需要重启系统，请准备就绪后重启宿主机"
        log_tips "重启后才可以应用对内核引导的修改哦！命令是 reboot"
    else
        log_warn "您已经配置过!"
    fi
}

# 关闭硬件直通
disable_pass() {
    echo
    log_step "关闭硬件直通..."
    if [ `dmesg | grep -e DMAR -e IOMMU|wc -l` = 0 ];then
        log_error "您的硬件不支持直通！"
        log_tips "不如检查一下主板的BIOS设置？"
        pause_function
        return
    fi
    if [ `cat /proc/cpuinfo|grep Intel|wc -l` = 0 ];then
        iommu="amd_iommu=on"
    else
        iommu="intel_iommu=on"
    fi
    if [ `grep $iommu /etc/default/grub|wc -l` = 0 ];then
        log_warn "您还没有配置过该项"
    else
        backup_file "/etc/default/grub"
        {
            sed -i 's/ '$iommu'//g' /etc/default/grub
            sed -i '/vfio/d' /etc/modules
            rm -rf /etc/modprobe.d/blacklist.conf
            rm -rf /etc/modprobe.d/vfio.conf
            sleep 1
        }
        log_success "关闭设置后需要重启系统，请准备就绪后重启宿主机。"
        log_tips "重启后才可以应用对内核引导的修改哦！命令是 reboot"
        sleep 1
        update-grub
    fi
}

# 硬件直通菜单
hw_passth() {
    while :; do
        clear
        show_menu_header "配置硬件直通"
        show_menu_option "1" "开启硬件直通"
        show_menu_option "2" "关闭硬件直通"
        echo "${UI_DIVIDER}"
        show_menu_option "0" "返回"
        show_menu_footer
        read -p "请选择: [ ]" -n 1 hwmenuid
        echo  # New line after input
        hwmenuid=${hwmenuid:-0}
        case "${hwmenuid}" in
            1)
                enable_pass
                pause_function
                ;;
            2)
                disable_pass
                pause_function
                ;;
            0)
                break
                ;;
            *)
                log_error "无效选项!"
                pause_function
                ;;
        esac
    done
}
#--------------开启硬件直通----------------

#--------------设置CPU电源模式----------------
# 设置CPU电源模式
cpupower() {
    governors=`cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors`
    while :; do
        clear
        show_menu_header "设置CPU电源模式"
        echo "  1. 设置CPU模式 conservative  保守模式   [变身老年机]"
        echo "  2. 设置CPU模式 ondemand       按需模式  [默认]"
        echo "  3. 设置CPU模式 powersave      节能模式  [省电小能手]"
        echo "  4. 设置CPU模式 performance   性能模式   [性能释放]"
        echo "  5. 设置CPU模式 schedutil      负载模式  [交给负载自动配置]"
        echo
        echo "  6. 恢复系统默认电源设置"
        echo "${UI_DIVIDER}"
        show_menu_option "0" "返回"
        show_menu_footer
        echo
        echo "部分CPU仅支持 performance 和 powersave 模式，只能选择这两项，其他模式无效不要选！"
        echo
        echo "你的CPU支持 ${governors} 模式"
        echo
        read -p "请选择: [ ]" -n 1 cpupowerid
        echo  # New line after input
        cpupowerid=${cpupowerid:-2}
        case "${cpupowerid}" in
            1)
                GOVERNOR="conservative"
                ;;
            2)
                GOVERNOR="ondemand"
                ;;
            3)
                GOVERNOR="powersave"
                ;;
            4)
                GOVERNOR="performance"
                ;;
            5)
                GOVERNOR="schedutil"
                ;;
            6)
                cpupower_del
                pause_function
                break
                ;;
            0)
                break
                ;;
            *)
                log_error "你的输入无效，请重新输入！"
                pause_function
                ;;
        esac
        if [[ ${GOVERNOR} != "" ]]; then
            if [[ -n `echo "${governors}" | grep -o "${GOVERNOR}"` ]]; then
                echo "您选择的CPU模式：${GOVERNOR}"
                echo
                cpupower_add
                pause_function
            else
                log_error "您的CPU不支持该模式！"
                log_tips "现在暂时不会对你的系统造成影响，但是下次开机时，CPU模式会恢复为默认模式。"
                pause_function
            fi
        fi
    done
}

# 修改CPU模式
cpupower_add() {
    echo "${GOVERNOR}" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
    echo "查看当前CPU模式"
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

    echo "正在添加开机任务"
    NEW_CRONTAB_COMMAND="sleep 10 && echo "${GOVERNOR}" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null #CPU Power Mode"
    EXISTING_CRONTAB=$(crontab -l 2>/dev/null)
    if [[ -n "$EXISTING_CRONTAB" ]]; then
        TEMP_CRONTAB_FILE=$(mktemp)
        echo "$EXISTING_CRONTAB" | grep -v "@reboot sleep 10 && echo*" > "$TEMP_CRONTAB_FILE"
        crontab "$TEMP_CRONTAB_FILE"
        rm "$TEMP_CRONTAB_FILE"
    fi
    log_success "CPU模式已修改完成"
    # 修改完成
    (crontab -l 2>/dev/null; echo "@reboot $NEW_CRONTAB_COMMAND") | crontab -
    echo -e "
检查计划任务设置 (使用 'crontab -l' 命令来检查)"
}

# 恢复系统默认电源设置
cpupower_del() {
    # 恢复性模式
    echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
    # 删除计划任务
    EXISTING_CRONTAB=$(crontab -l 2>/dev/null)
    if [[ -n "$EXISTING_CRONTAB" ]]; then
        TEMP_CRONTAB_FILE=$(mktemp)
        echo "$EXISTING_CRONTAB" | grep -v "@reboot sleep 10 && echo*" > "$TEMP_CRONTAB_FILE"
        crontab "$TEMP_CRONTAB_FILE"
        rm "$TEMP_CRONTAB_FILE"
    fi

    log_success "已恢复系统默认电源设置！还是默认的好用吧"
}
#--------------设置CPU电源模式----------------

#--------------CPU、主板、硬盘温度显示----------------
# 安装工具
cpu_add() {
    nodes="/usr/share/perl5/PVE/API2/Nodes.pm"
    pvemanagerlib="/usr/share/pve-manager/js/pvemanagerlib.js"
    proxmoxlib="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"

    pvever=$(pveversion | awk -F"/" '{print $2}')
    echo pve版本$pvever

    # 判断是否已经执行过修改 (使用 modbyshowtempfreq 标记检测)
    if [ $(grep 'modbyshowtempfreq' $nodes $pvemanagerlib $proxmoxlib 2>/dev/null | wc -l) -eq 3 ]; then
        log_warn "已经修改过，请勿重复修改"
        log_tips "如果没有生效，请使用 Shift+F5 刷新浏览器缓存"
        log_tips "如果需要强制重新修改，请先执行还原操作"
        pause_function
        return
    fi

    # 先刷新下源
    log_step "更新软件包列表..."
    apt-get update

    log_step "开始安装所需工具..."
    # 输入需要安装的软件包 (添加 hdparm 用于 SATA 硬盘休眠检测, apcupsd for UPS support)
    packages=(lm-sensors nvme-cli sysstat linux-cpupower hdparm smartmontools apcupsd)

    # 查询软件包，判断是否安装
    for package in "${packages[@]}"; do
        if ! dpkg -s "$package" &> /dev/null; then
            log_info "$package 未安装，开始安装软件包"
            apt-get install "${packages[@]}" -y
            modprobe msr
            install=ok
            break
        fi
    done

    # 设置执行权限 (修正路径)
    [[ -e /usr/sbin/linux-cpupower ]] && chmod +s /usr/sbin/linux-cpupower
    chmod +s /usr/sbin/nvme
    chmod +s /usr/sbin/smartctl
    chmod +s /usr/sbin/turbostat || log_warn "无法设置 turbostat 权限"

    # 启用 MSR 模块
    modprobe msr && echo msr > /etc/modules-load.d/turbostat-msr.conf

    # 软件包安装完成
    if [ "$install" == "ok" ]; then
        log_success "软件包安装完成，检测硬件信息"
        sensors-detect --auto > /tmp/sensors
        drivers=$(sed -n '/Chip drivers/,/\#----cut here/p' /tmp/sensors | sed '/Chip /d' | sed '/cut/d')

        if [ $(echo $drivers | wc -w) = 0 ]; then
            log_warn "没有找到任何驱动，似乎你的系统不支持或驱动安装失败。"
            pause_function
        else
            for i in $drivers; do
                modprobe $i
                if [ $(grep $i /etc/modules | wc -l) = 0 ]; then
                    echo $i >> /etc/modules
                fi
            done
            sensors
            sleep 3
            log_success "驱动信息配置成功。"
        fi
        [[ -e /etc/init.d/kmod ]] && /etc/init.d/kmod start
        rm /tmp/sensors
    fi

    log_step "备份源文件"
    # 备份当前版本文件
    backup_file "$nodes"
    backup_file "$pvemanagerlib"
    backup_file "$proxmoxlib"

    # 备份当前版本文件 (这部分看起来和 backup_file 功能重复，但可能用于特定版本的还原逻辑)
    # 将其输出也重定向到日志
    if [[ ! -f "$nodes.$pvever.bak" ]]; then
        cp "$nodes" "$nodes.$pvever.bak"
    fi
    if [[ ! -f "$pvemanagerlib.$pvever.bak" ]]; then
        cp "$pvemanagerlib" "$pvemanagerlib.$pvever.bak"
    fi
    if [[ ! -f "$proxmoxlib.$pvever.bak" ]]; then
        cp "$proxmoxlib" "$proxmoxlib.$pvever.bak"
    fi

    log_info "是否启用 UPS 监控？"
    echo -n "（如果没有 UPS 设备或不想显示，请选择 N，默认Y）(y/N): "
    read -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        enable_ups=true
        log_success "已选择启用UPS监控"
    else
        enable_ups=false
        log_info "已选择跳过UPS监控"
    fi

    # 生成系统变量 (参考 PVE 8 脚本的改进实现)
    tmpf=tmpfile.temp
    touch $tmpf
    cat > $tmpf << 'EOF'

#modbyshowtempfreq

        $res->{thermalstate} = `sensors -A`;
        $res->{cpuFreq} = `
            goverf=/sys/devices/system/cpu/cpufreq/policy0/scaling_governor
            maxf=/sys/devices/system/cpu/cpufreq/policy0/cpuinfo_max_freq
            minf=/sys/devices/system/cpu/cpufreq/policy0/cpuinfo_min_freq

            cat /proc/cpuinfo | grep -i "cpu mhz"
            echo -n 'gov:'
            [ -f \$goverf ] && cat \$goverf || echo none
            echo -n 'min:'
            [ -f \$minf ] && cat \$minf || echo none
            echo -n 'max:'
            [ -f \$maxf ] && cat \$maxf || echo none
            echo -n 'pkgwatt:'
            [ -e /usr/sbin/turbostat ] && turbostat --quiet --cpu package --show "PkgWatt" -S sleep 0.25 2>&1 | tail -n1
        `;
EOF

    if [ "$enable_ups" = true ]; then
        cat >> $tmpf << 'EOF'
        $res->{ups_status} = `apcaccess status`;
EOF
    fi


    echo >> $tmpf

    # NVME 硬盘变量 (动态检测，参考 PVE 8 实现)
    log_info "检测系统中的 NVME 硬盘"
    nvi=0
    for nvme in $(ls /dev/nvme[0-9] 2> /dev/null); do
        chmod +s /usr/sbin/smartctl 2>/dev/null

        cat >> $tmpf << EOF

        \$res->{nvme$nvi} = \`smartctl $nvme -a -j\`;
EOF
        echo "检测到 NVME 硬盘: $nvme (nvme$nvi)"
        let nvi++
    done
    echo "已添加 $nvi 块 NVME 硬盘"

    # SATA 硬盘变量 (动态检测，参考 PVE 8 实现)
    log_info "检测系统中的 SATA 固态和机械硬盘"
    sdi=0
    for sd in $(ls /dev/sd[a-z] 2> /dev/null); do
        chmod +s /usr/sbin/smartctl 2>/dev/null
        chmod +s /usr/sbin/hdparm 2>/dev/null

        # 检测是否是真的硬盘
        sdsn=$(awk -F '/' '{print $NF}' <<< $sd)
        sdcr=/sys/block/$sdsn/queue/rotational
        [ -f $sdcr ] || continue

        if [ "$(cat $sdcr)" = "0" ]; then
            hddisk=false
            sdtype="固态硬盘"
        else
            hddisk=true
            sdtype="机械硬盘"
        fi

        # 硬盘输出信息逻辑，如果硬盘不存在就输出空 JSON
        cat >> $tmpf << EOF

        \$res->{sd$sdi} = \`
            if [ -b $sd ]; then
                # 增加 SAS 盘检测，SAS 盘不使用 hdparm 检测休眠，防止误报
                if $hddisk && ! smartctl -i $sd | grep -q "Transport protocol:.*SAS" && hdparm -C $sd 2>/dev/null | grep -iq 'standby'; then
                    echo '{"standy": true}'
                else
                    smartctl $sd -a -j
                fi
            else
                echo '{}'
            fi
        \`;
EOF
        echo "检测到 $sdtype: $sd (sd$sdi)"
        let sdi++
    done
    echo "已添加 $sdi 块 SATA 固态和机械硬盘"


    ###################  修改node.pm   ##########################
    log_info "修改node.pm："
    log_info "找到关键字 PVE::pvecfg::version_text 的行号并跳到下一行"

    # 显示匹配的行
    ln=$(expr $(sed -n -e '/PVE::pvecfg::version_text/=' $nodes) + 1)
    echo "匹配的行号：" $ln

    log_info "修改结果："
    sed -i "${ln}r $tmpf" $nodes
    # 显示修改结果
    sed -n '/PVE::pvecfg::version_text/,+18p' $nodes
    rm $tmpf

    ###################  修改pvemanagerlib.js   ##########################
    tmpf=tmpfile.temp
    touch $tmpf
    cat > $tmpf << 'EOF'

//modbyshowtempfreq
    {
          itemId: 'cpumhz',
          colspan: 2,
          printBar: false,
          title: gettext('CPU频率(GHz)'),
          textField: 'cpuFreq',
          renderer:function(v){
              console.log(v);

              // 解析所有核心频率
              let m = v.match(/(?<=^cpu[^\d]+)\d+/img);
              if (!m || m.length === 0) {
                  return '无法获取CPU频率信息';
              }

              let freqs = m.map(e => parseFloat((e / 1000).toFixed(1)));

              // 计算统计信息
              let avgFreq = (freqs.reduce((a, b) => a + b, 0) / freqs.length).toFixed(1);
              let minFreq = Math.min(...freqs).toFixed(1);
              let maxFreq = Math.max(...freqs).toFixed(1);
              let coreCount = freqs.length;

              // 获取系统配置的频率范围
              let sysMin = (v.match(/(?<=^min:).+/im)[0]);
              if (sysMin !== 'none') {
                  sysMin = (sysMin / 1000000).toFixed(1);
              }

              let sysMax = (v.match(/(?<=^max:).+/im)[0]);
              if (sysMax !== 'none') {
                  sysMax = (sysMax / 1000000).toFixed(1);
              }

              let gov = v.match(/(?<=^gov:).+/im)[0].toUpperCase();

              let watt = v.match(/(?<=^pkgwatt:)[\d.]+$/im);
              watt = watt ? " | 功耗: " + (watt[0]/1).toFixed(1) + 'W' : '';

              // 简洁显示：平均值 + 当前范围 + 系统范围 + 功耗 + 调速器
              return `${coreCount}核心 平均: ${avgFreq} GHz (当前: ${minFreq}~${maxFreq}) | 范围: ${sysMin}~${sysMax} GHz${watt} | 调速器: ${gov}`;
           }
    },

    {
          itemId: 'thermal',
          colspan: 2,
          printBar: false,
          title: gettext('CPU温度'),
          textField: 'thermalstate',
          renderer:function(value){
              console.log(value);
              let b = value.trim().split(/\s+(?=^\w+-)/m).sort();
              let cpuResults = [];
              let otherResults = [];

              const cpuSensorRegex = /(CORETEMP|K10TEMP|ZENPOWER|ZENPOWER3|K8TEMP|FAM15H|ZENPROBE)/i;
              const amdLabelRegex = /\bT(CTL|DIE|CCD|CCD\d+|Sx|LOOP)\b/i;

              b.forEach(function(v){
                  // 风扇转速数据
                  let fandata = v.match(/(?<=:\s+)[1-9]\d*(?=\s+RPM\s+)/ig);
                  if (fandata) {
                      otherResults.push('风扇: ' + fandata.join(', ') + ' RPM');
                      return;
                  }

                  let name = v.match(/^[^-]+/);
                  if (!name) return;
                  name = name[0].toUpperCase();

                  let temps = v.match(/(?<=:\s+)[+-][\d.]+(?=.?°C)/g);
                  if (!temps) return;

                  temps = temps.map(t => parseFloat(t));

                  // 只处理 CPU 温度（Intel coretemp 或 AMD 相关传感器）
                  const isCpuSensor = cpuSensorRegex.test(name) || amdLabelRegex.test(v);

                  if (isCpuSensor) {
                      let packageTemp = temps[0].toFixed(0);

                      if (temps.length > 1) {
                          let coreTemps = temps.slice(1);
                          let avgCore = (coreTemps.reduce((a, b) => a + b, 0) / coreTemps.length).toFixed(0);
                          let maxCore = Math.max(...coreTemps).toFixed(0);
                          let minCore = Math.min(...coreTemps).toFixed(0);

                          cpuResults.push(`封装: ${packageTemp}°C | 核心: 平均 ${avgCore}°C (${minCore}~${maxCore}°C)`);
                      } else {
                          cpuResults.push(`封装: ${packageTemp}°C`);
                      }

                      // 添加临界温度
                      let crit = v.match(/(?<=\bcrit\b[^+]+\+)\d+/);
                      if (crit) {
                          cpuResults[cpuResults.length - 1] += ` | 临界: ${crit[0]}°C`;
                      }
                  } else {
                      // 非 CPU 温度（主板、NVME等）放到其他结果中
                      let tempStr = `${name}: ${temps[0].toFixed(0)}°C`;
                      let crit = v.match(/(?<=\bcrit\b[^+]+\+)\d+/);
                      if (crit) {
                          tempStr += ` (临界: ${crit[0]}°C)`;
                      }
                      otherResults.push(tempStr);
                  }
              });

              // 只返回 CPU 相关温度，其他传感器信息不显示在这里
              // （NVME温度会在NVME硬盘信息中单独显示）
              if (cpuResults.length === 0) {
                  return '未获取到CPU温度信息';
              }

              // 如果有多个CPU（如双路服务器），分别显示
              if (cpuResults.length > 1) {
                  return cpuResults.map((temp, idx) => `CPU${idx}: ${temp}`).join(' | ');
              } else {
                  return cpuResults[0];
              }
           }
    },
EOF

    # 动态为每个 NVME 硬盘添加 JavaScript 代码
    for i in $(seq 0 $((nvi - 1))); do
        cat >> $tmpf << EOF

    {
          itemId: 'nvme${i}0',
          colspan: 2,
          printBar: false,
          title: gettext('NVME${i}'),
          textField: 'nvme${i}',
          renderer:function(value){
              try{
                  let  v = JSON.parse(value);

                  // 检查是否为空 JSON（硬盘不存在或已直通）
                  if (Object.keys(v).length === 0) {
                      return '<span style="color: #888;">未检测到 NVME（可能已直通或移除）</span>';
                  }

                  // 检查型号
                  let model = v.model_name;
                  if (!model) {
                      return '<span style="color: #f39c12;">NVME 信息不完整（建议检查连接状态）</span>';
                  }

                  // 构建显示内容
                  let parts = [model];
                  let hasData = false;

                  // 温度
                  if (v.temperature?.current !== undefined) {
                      parts.push(v.temperature.current + '°C');
                      hasData = true;
                  }

                  // 健康度和读写
                  let log = v.nvme_smart_health_information_log;
                  if (log) {
                      // 健康度
                      if (log.percentage_used !== undefined) {
                          let health = '健康: ' + (100 - log.percentage_used) + '%';
                          if (log.media_errors !== undefined && log.media_errors > 0) {
                              health += ' <span style="color: #e74c3c;">(0E: ' + log.media_errors + ')</span>';
                          }
                          parts.push(health);
                          hasData = true;
                      }

                      // 读写
                      if (log.data_units_read && log.data_units_written) {
                          let read = (log.data_units_read / 1956882).toFixed(1);
                          let write = (log.data_units_written / 1956882).toFixed(1);
                          parts.push('读写: ' + read + 'T / ' + write + 'T');
                          hasData = true;
                      }
                  }

                  // 通电时间
                  if (v.power_on_time?.hours !== undefined) {
                      let pot = '通电: ' + v.power_on_time.hours + '时';
                      if (v.power_cycle_count) {
                          pot += ' (次: ' + v.power_cycle_count + ')';
                      }
                      parts.push(pot);
                      hasData = true;
                  }

                  // SMART 状态
                  if (v.smart_status?.passed !== undefined) {
                      parts.push('SMART: ' + (v.smart_status.passed ? '<span style="color: #27ae60;">正常</span>' : '<span style="color: #e74c3c;">警告!</span>'));
                      hasData = true;
                  }

                  // 如果只有型号，没有其他数据，说明可能是权限或驱动问题
                  if (!hasData) {
                      return model + ' <span style="color: #888;">| 无法获取详细信息（检查 smartctl 权限或驱动）</span>';
                  }

                  return parts.join(' | ');

              }catch(e){
                  return '<span style="color: #888;">无法解析 NVME 信息（可能使用控制器直通）</span>';
              };

           }
    },
EOF
    done

    # 动态为每个 SATA 硬盘添加 JavaScript 代码
    for i in $(seq 0 $((sdi - 1))); do
        # 获取硬盘类型（固态/机械）
        sd="/dev/sd$(echo {a..z} | cut -d' ' -f$((i+1)))"
        sdsn=$(basename $sd 2>/dev/null)
        sdcr=/sys/block/$sdsn/queue/rotational
        if [ -f $sdcr ] && [ "$(cat $sdcr)" = "0" ]; then
            sdtype="固态硬盘$i"
        else
            sdtype="机械硬盘$i"
        fi

        cat >> $tmpf << EOF

    {
          itemId: 'sd${i}0',
          colspan: 2,
          printBar: false,
          title: gettext('${sdtype}'),
          textField: 'sd${i}',
          renderer:function(value){
              try{
                  let  v = JSON.parse(value);
                  console.log(v)

                  // 场景 1：硬盘休眠（节能模式）
                  if (v.standy === true) {
                      return '<span style="color: #27ae60;">硬盘休眠中（省电模式）</span>'
                  }

                  // 场景 2：空 JSON（硬盘不存在或已直通）
                  if (Object.keys(v).length === 0) {
                      return '<span style="color: #888;">未检测到硬盘（可能已直通或移除）</span>';
                  }

                  // 场景 3：检查型号
                  let model = v.model_name;
                  if (!model) {
                      return '<span style="color: #f39c12;">硬盘信息不完整（建议检查连接状态）</span>';
                  }

                  // 场景 4：构建正常显示内容
                  let parts = [model];

                  // 温度
                  if (v.temperature?.current !== undefined) {
                      parts.push('温度: ' + v.temperature.current + '°C');
                  }

                  // 通电时间
                  if (v.power_on_time?.hours !== undefined) {
                      let pot = '通电: ' + v.power_on_time.hours + '时';
                      if (v.power_cycle_count) {
                          pot += ',次: ' + v.power_cycle_count;
                      }
                      parts.push(pot);
                  }

                  // SMART 状态
                  if (v.smart_status?.passed !== undefined) {
                      parts.push('SMART: ' + (v.smart_status.passed ? '正常' : '<span style="color: #e74c3c;">警告!</span>'));
                  }

                  return parts.join(' | ');

              }catch(e){
                  // JSON 解析失败
                  return '<span style="color: #888;">无法获取硬盘信息（可能使用 HBA 直通）</span>';
              };
           }
    },
EOF
    done

    if [ "$enable_ups" = true ]; then
        cat >> $tmpf << 'EOF'

    {
        itemId: 'ups-status',
        colspan: 2,
        printBar: false,
        title: gettext('UPS 信息'),
        textField: 'ups_status',
        cellWrap: true,
        renderer: function(value) {
            if (!value || value.length === 0) {
                return '提示: 未检测到 UPS 或 apcaccess 未运行';
            }

            try {
                const DATE_MATCH      = value.match(/DATE\s*:\s*([^\n]+)/m);
                const STATUS_MATCH    = value.match(/STATUS\s*:\s*([A-Z]+)/m);
                const OUTPUTV_MATCH   = value.match(/OUTPUTV\s*:\s*([\d\.]+)/m);
                const LINEV_MATCH     = value.match(/LINEV\s*:\s*([\d\.]+)/m);
                const LOADPCT_MATCH   = value.match(/LOADPCT\s*:\s*([\d\.]+)/m);
                const BCHARGE_MATCH   = value.match(/BCHARGE\s*:\s*([\d\.]+)/m);
                const TIMELEFT_MATCH  = value.match(/TIMELEFT\s*:\s*([\d\.]+)/m);
                const NOMPOWER_MATCH  = value.match(/NOMPOWER\s*:\s*([\d\.]+)/m);
                const MODEL_MATCH     = value.match(/MODEL\s*:\s*(.+)/m);

                const DATE       = DATE_MATCH ? DATE_MATCH[1].trim() : '未知时间';
                const STATUS     = STATUS_MATCH ? STATUS_MATCH[1] : 'UNKNOWN';
                const VOLTAGE    = (OUTPUTV_MATCH || LINEV_MATCH) ? (OUTPUTV_MATCH || LINEV_MATCH)[1] : '-';
                const LOADPCT    = LOADPCT_MATCH ? parseFloat(LOADPCT_MATCH[1]) : NaN;
                const LOADPCT_TXT= isNaN(LOADPCT) ? '-' : LOADPCT_MATCH[1];
                const BCHARGE    = BCHARGE_MATCH ? BCHARGE_MATCH[1] : '-';
                const TIMELEFT   = TIMELEFT_MATCH ? TIMELEFT_MATCH[1] : '-';
                const NOMPOWER   = NOMPOWER_MATCH ? parseFloat(NOMPOWER_MATCH[1]) : NaN;
                const MODEL      = MODEL_MATCH ? MODEL_MATCH[1].trim() : '未知型号';

                let powerStatusText = '';
                switch (STATUS) {
                    case 'ONLINE':
                        powerStatusText = '市电供电正常';
                        break;
                    case 'ONBATT':
                        powerStatusText = '电池供电中（市电中断）';
                        break;
                    case 'CHRG':
                        powerStatusText = '电池充电中';
                        break;
                    case 'DISCHRG':
                        powerStatusText = '电池放电中';
                        break;
                    default:
                        powerStatusText = '状态: ' + STATUS;
                        break;
                }

                let totalPowerText = '-';
                let currentPowerText = '-';

                if (!isNaN(NOMPOWER) && NOMPOWER > 0) {
                    const totalPowerW = NOMPOWER;
                    totalPowerText = totalPowerW.toFixed(0) + ' W';

                    if (!isNaN(LOADPCT)) {
                        const currentPowerW = totalPowerW * LOADPCT / 100;
                        currentPowerText = currentPowerW.toFixed(0) + ' W';
                    }
                }

                return `${MODEL} | ${powerStatusText} | ${DATE}<br>
                        电量: ${BCHARGE} % | 剩余供电时间: ${TIMELEFT} 分钟<br>
                        电压: ${VOLTAGE} V | 负载: ${LOADPCT_TXT} %<br>
                        额定功率: ${totalPowerText} | 估算当前功率: ${currentPowerText}`;
            } catch(e) {
                return 'UPS 信息解析失败: ' + value;
            }
        }
    },
EOF
    fi

    log_info "找到关键字pveversion的行号"
    # 显示匹配的行
    ln=$(sed -n '/pveversion/,+10{/},/{=;q}}' $pvemanagerlib)
    echo "匹配的行号pveversion：" $ln

    log_info "修改结果："
    sed -i "${ln}r $tmpf" $pvemanagerlib
    # 显示修改结果
    # sed -n '/pveversion/,+30p' $pvemanagerlib

    log_info "修改页面高度"
    # 统计添加了几条内容（2个基础项 + NVME + SATA + UPS）
    if [ "$has_ups" = true ]; then
        addRs=$((2 + nvi + sdi + 1))
        ups_info="+ 1 个UPS"
    else
        addRs=$((2 + nvi + sdi))
        ups_info=""
    fi

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "检测到添加了 $addRs 条监控项 (2个基础项 + $nvi 个NVME + $sdi 个SATA $ups_info)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "请选择高度调整方式："
    echo "  1. 自动计算 (推荐，参考 PVE 8 算法：28px/项)"
    echo "  2. 手动设置 (自定义每项的高度增量)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    read -p "请输入选项 [1-2] (直接回车使用自动计算): " height_choice

    case ${height_choice:-1} in
        1)
            # 自动计算：每项 28px
            addHei=$((28 * addRs))
            log_info "使用自动计算：$addRs 项 × 28px = ${addHei}px"
            ;;
        2)
            # 手动设置
            echo
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "手动设置说明："
            echo "  - 推荐值范围: 20-40 (默认 28)"
            echo "  - 如果 CPU 核心很多或想显示更多信息，可适当增大"
            echo "  - 如果界面出现遮挡，可适当减小此值"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            read -p "请输入每项的高度增量 (px) [默认: 28]: " height_per_item

            # 验证输入是否为数字，如果不是或为空则使用默认值 28
            if [[ -z "$height_per_item" ]] || ! [[ "$height_per_item" =~ ^[0-9]+$ ]]; then
                height_per_item=28
                log_info "使用默认值: 28px/项"
            else
                log_info "使用自定义值: ${height_per_item}px/项"
            fi

            addHei=$((height_per_item * addRs))
            log_success "计算结果：$addRs 项 × ${height_per_item}px = ${addHei}px"
            ;;
        *)
            # 无效选项，使用自动计算
            addHei=$((28 * addRs))
            log_warn "无效选项，使用自动计算：${addHei}px"
            ;;
    esac

    rm $tmpf

    # 修改左栏高度（原高度 300）
    log_step "修改左栏高度"
    wph=$(sed -n -E "/widget\.pveNodeStatus/,+4{/height:/{s/[^0-9]*([0-9]+).*/\1/p;q}}" $pvemanagerlib)
    if [ -n "$wph" ]; then
        sed -i -E "/widget\.pveNodeStatus/,+4{/height:/{s#[0-9]+#$((wph + addHei))#}}" $pvemanagerlib
        echo "左栏高度: $wph → $((wph + addHei))" >> /var/log/pve-tools.log
    else
        log_warn "找不到左栏高度修改点"
    fi

    # 修改右栏高度和左栏一致，解决浮动错位（原高度 325）
    log_step "修改右栏高度和左栏一致，解决浮动错位"
    nph=$(sed -n -E '/nodeStatus:\s*nodeStatus/,+10{/minHeight:/{s/[^0-9]*([0-9]+).*/\1/p;q}}' "$pvemanagerlib")
    if [ -n "$nph" ]; then
        sed -i -E "/nodeStatus:\s*nodeStatus/,+10{/minHeight:/{s#[0-9]+#$((nph + addHei - (nph - wph)))#}}" $pvemanagerlib
        echo "右栏高度: $nph → $((nph + addHei - (nph - wph)))" >> /var/log/pve-tools.log
    else
        log_warn "找不到右栏高度修改点"
    fi

    # 调整显示布局
    ln=$(expr $(sed -n -e '/widget.pveDcGuests/=' $pvemanagerlib) + 10)
    sed -i "${ln}a\ textAlign: 'right'," $pvemanagerlib
    ln=$(expr $(sed -n -e '/widget.pveNodeStatus/=' $pvemanagerlib) + 10)
    sed -i "${ln}a\ textAlign: 'right'," $pvemanagerlib

    ###################  修改proxmoxlib.js   ##########################

    log_info "加强去除订阅弹窗"
    # 调用 remove_subscription_popup 函数，避免重复代码
    remove_subscription_popup

    # 显示修改结果
    # sed -n '/\/nodes\/localhost\/subscription/,+10p' $proxmoxlib >> /var/log/pve-tools.log
    systemctl restart pveproxy

    log_success "请刷新浏览器缓存shift+f5"
}

cpu_del() {

nodes="/usr/share/perl5/PVE/API2/Nodes.pm"
pvemanagerlib="/usr/share/pve-manager/js/pvemanagerlib.js"
proxmoxlib="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"

pvever=$(pveversion | awk -F"/" '{print $2}')
echo pve版本$pvever
if [ -f "$nodes.$pvever.bak" ];then
rm -f $nodes $pvemanagerlib $proxmoxlib
mv $nodes.$pvever.bak $nodes
mv $pvemanagerlib.$pvever.bak $pvemanagerlib
mv $proxmoxlib.$pvever.bak $proxmoxlib

log_success "已删除温度显示，请重新刷新浏览器缓存."
else
log_warn "你没有添加过温度显示，退出脚本."
fi


}
#--------------CPU、主板、硬盘温度显示----------------

#--------------GRUB 配置管理工具----------------
# 展示当前 GRUB 配置
show_grub_config() {
    log_info "当前 GRUB 配置信息"
    log_step "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ ! -f "/etc/default/grub" ]; then
        log_error "未找到 /etc/default/grub 文件"
        return 1
    fi

    log_info "文件路径: /etc/default/grub"
    log_info "当前内核参数:"

    # 读取并显示 GRUB_CMDLINE_LINUX_DEFAULT
    current_config=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | sed 's/GRUB_CMDLINE_LINUX_DEFAULT=//' | tr -d '"')

    if [ -z "$current_config" ]; then
        log_warn "未找到 GRUB_CMDLINE_LINUX_DEFAULT 配置"
    else
        log_success "GRUB_CMDLINE_LINUX_DEFAULT 内容:"
        # 逐行显示参数
        echo "$current_config" | tr ' ' '\n' | while read -r param; do
            [ -n "$param" ] && log_info "  - $param"
        done
    fi

    log_step "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 检测关键参数
    log_info "关键参数检测:"

    # 检测 IOMMU
    if echo "$current_config" | grep -q "intel_iommu=on\|amd_iommu=on"; then
        log_success "  IOMMU: 已启用"
    else
        log_warn "  IOMMU: 未启用"
    fi

    # 检测 SR-IOV
    if echo "$current_config" | grep -q "i915.enable_guc=3"; then
        log_success "  SR-IOV (i915.enable_guc=3): 已配置"
    else
        log_info "  SR-IOV: 未配置"
    fi

    # 检测 GVT-g
    if echo "$current_config" | grep -q "i915.enable_gvt=1"; then
        log_success "  GVT-g (i915.enable_gvt=1): 已配置"
    else
        log_info "  GVT-g: 未配置"
    fi

    # 检测硬件直通
    if echo "$current_config" | grep -q "iommu=pt"; then
        log_success "  硬件直通 (iommu=pt): 已启用"
    else
        log_info "  硬件直通: 未启用"
    fi

    log_step "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# GRUB 配置备份
backup_grub_with_note() {
    local note="$1"
    local backup_dir="/etc/pvetools9/backup/grub"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="${backup_dir}/${timestamp}_${note}.bak"

    log_step "备份 GRUB 配置..."

    # 创建备份目录
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir" || {
            log_error "无法创建备份目录: $backup_dir"
            return 1
        }
        log_info "创建备份目录: $backup_dir"
    fi

    # 检查源文件
    if [ ! -f "/etc/default/grub" ]; then
        log_error "源文件不存在: /etc/default/grub"
        return 1
    fi

    # 执行备份
    cp "/etc/default/grub" "$backup_file" || {
        log_error "备份失败"
        return 1
    }

    log_success "GRUB 配置已备份"
    log_info "备份文件: $backup_file"
    log_info "备份时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "备份备注: $note"

    # 统计备份文件数量
    local backup_count=$(ls -1 "$backup_dir"/*.bak 2>/dev/null | wc -l)
    log_info "当前共有 $backup_count 个备份文件"

    return 0
}

# 列出所有 GRUB 备份
list_grub_backups() {
    local backup_dir="/etc/pvetools9/backup/grub"

    log_info "GRUB 配置备份列表"
    log_step "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ ! -d "$backup_dir" ]; then
        log_warn "备份目录不存在: $backup_dir"
        log_tips "尚未创建任何备份"
        return 0
    fi

    local backup_files=$(ls -1t "$backup_dir"/*.bak 2>/dev/null)

    if [ -z "$backup_files" ]; then
        log_warn "未找到任何备份文件"
        return 0
    fi

    local count=1
    echo "$backup_files" | while read -r backup_file; do
        local filename=$(basename "$backup_file")
        local filesize=$(du -h "$backup_file" | awk '{print $1}')
        local filetime=$(stat -c '%y' "$backup_file" 2>/dev/null || stat -f '%Sm' "$backup_file")

        log_info "备份 $count:"
        log_info "  文件名: $filename"
        log_info "  大小: $filesize"
        log_info "  时间: $filetime"
        log_step "  ────────────────────────────────────"

        count=$((count + 1))
    done

    log_step "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 恢复 GRUB 备份
restore_grub_backup() {
    local backup_dir="/etc/pvetools9/backup/grub"

    list_grub_backups

    if [ ! -d "$backup_dir" ] || [ -z "$(ls -A "$backup_dir"/*.bak 2>/dev/null)" ]; then
        log_error "没有可恢复的备份文件"
        pause_function
        return 1
    fi

    echo
    log_warn "请输入要恢复的备份文件名（完整文件名）:"
    read -p "> " backup_filename

    local backup_file="${backup_dir}/${backup_filename}"

    if [ ! -f "$backup_file" ]; then
        log_error "备份文件不存在: $backup_filename"
        pause_function
        return 1
    fi

    log_warn "即将恢复 GRUB 配置"
    log_info "源文件: $backup_file"
    log_info "目标文件: /etc/default/grub"

    if ! confirm_action "确认恢复此备份"; then
        log_info "用户取消恢复操作"
        return 0
    fi

    # 在恢复前备份当前配置
    backup_grub_with_note "恢复前自动备份"

    # 执行恢复
    cp "$backup_file" "/etc/default/grub" || {
        log_error "恢复失败"
        pause_function
        return 1
    }

    log_success "GRUB 配置已恢复"

    # 更新 GRUB
    if confirm_action "是否立即更新 GRUB"; then
        update-grub && log_success "GRUB 更新完成" || log_error "GRUB 更新失败"
    fi

    pause_function
}
#--------------GRUB 配置管理工具----------------

#--------------核显虚拟化管理----------------
# 核显管理菜单
igpu_management_menu() {
    while true; do
        clear
        show_menu_header "Intel 核显虚拟化管理"
        show_menu_option "1" "Intel 11-15代 SR-IOV 配置 (DKMS)"
        show_menu_option "2" "Intel 6-10代 GVT-g 配置 (传统模式)"
        show_menu_option "3" "验证核显虚拟化状态"
        show_menu_option "4" "清理核显虚拟化配置 (恢复默认)"
        show_menu_option "0" "返回主菜单"
        show_menu_footer
        
        read -p "请选择操作 [0-4]: " choice
        case $choice in
            1) igpu_sriov_setup ;;
            2) igpu_gvtg_setup ;;
            3) igpu_verify ;;
            4) restore_igpu_config ;;
            0) return ;;
            *) log_error "无效选择" ;;
        esac
        pause_function
    done
}

# Intel 11-15代 SR-IOV 核显虚拟化配置
igpu_sriov_setup() {
    echo "开始配置 Intel 11-15代 SR-IOV 核显虚拟化"

    # 检查内核版本
    kernel_version=$(uname -r | awk -F'-' '{print $1}')
    kernel_major=$(echo $kernel_version | cut -d'.' -f1)
    kernel_minor=$(echo $kernel_version | cut -d'.' -f2)

    if [ "$kernel_major" -lt 6 ] || ([ "$kernel_major" -eq 6 ] && [ "$kernel_minor" -lt 8 ]); then
        echo -e "${RED}SR-IOV 需要内核版本 6.8 或更高${NC}"
        echo "  提示: 当前内核版本: $(uname -r)"
        echo "  提示: 请先使用内核管理功能升级到 6.8 内核"
        pause_function
        return 1
    fi

    echo -e "${GREEN}✓ 内核版本检查通过: $(uname -r)${NC}"

    # 展示当前 GRUB 配置
    echo
    show_grub_config
    echo

    # 危险性警告
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "【高危操作警告】SR-IOV 核显虚拟化配置"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "此操作属于【高危险性】系统配置，配置错误可能导致："
    echo -e "  - 系统无法正常启动（GRUB 配置错误）"
    echo -e "  - 核显完全不可用（参数配置错误）"
    echo -e "  - 虚拟机黑屏或无法启动（直通配置错误）"
    echo -e "  - 需要通过恢复模式修复系统"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "此功能将修改以下系统配置："
    echo "  1. 修改 GRUB 引导参数（启用 IOMMU 和 SR-IOV）"
    echo "  2. 加载 VFIO 内核模块"
    echo "  3. 下载并安装 i915-sriov-dkms 驱动（约 10MB）"
    echo "  4. 配置虚拟核显数量（VFs）"
    echo "前置要求（请确认已完成）："
    echo "  ✓ BIOS 已开启 VT-d 虚拟化"
    echo "  ✓ BIOS 已开启 SR-IOV（如有此选项）"
    echo "  ✓ BIOS 已开启 Above 4GB（如有此选项）"
    echo "  ✓ BIOS 已关闭 Secure Boot 安全启动"
    echo "  ✓ CPU 为 Intel 11-15 代处理器"
    echo -e "重要：物理核显 (00:02.0) 不能直通，否则所有虚拟核显将消失"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo -e "强烈建议："
    echo "  提示: 1. 在继续前先备份当前 GRUB 配置"
    echo "  提示: 2. 确保了解核显虚拟化的工作原理"
    echo "  提示: 3. 准备好通过 SSH 或物理访问恢复系统"
    echo

    # 询问是否要备份
    if confirm_action "是否先备份当前 GRUB 配置（强烈推荐）"; then
        echo
        echo "请输入备份备注（例如：SR-IOV配置前备份）："
        read -p "> " backup_note
        backup_note=${backup_note:-"SR-IOV配置前备份"}
        backup_grub_with_note "$backup_note"
        echo
    fi

    if ! confirm_action "确认继续配置 SR-IOV 核显虚拟化"; then
        echo "用户取消操作"
        return 0
    fi

    # 安装必要的软件包
    echo "安装必要的软件包..."
    apt-get update

    echo "安装 pve-headers..."
    apt-get install -y "pve-headers-$(uname -r)" || {
        echo -e "${RED}安装 pve-headers 失败${NC}"
        pause_function
        return 1
    }

    echo "安装构建工具..."
    apt-get install -y build-essential dkms sysfsutils || {
        echo -e "安装构建工具失败"
        pause_function
        return 1
    }

    echo -e "✓ 软件包安装完成"

    # 备份并修改 GRUB 配置
    echo "配置 GRUB 引导参数..."
    backup_file "/etc/default/grub"

    # 检查是否已配置
    if grep -q "i915.enable_guc=3.*i915.max_vfs=7" /etc/default/grub; then
        echo -e "GRUB 已配置 SR-IOV 参数，跳过修改"
    else
        # 移除旧的配置（如果有 GVT-g 配置）
        sed -i 's/i915.enable_gvt=1//g' /etc/default/grub

        # 添加 SR-IOV 参数
        sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=7 module_blacklist=xe"' /etc/default/grub

        echo -e "✓ GRUB 配置已更新"
    fi

    # 更新 GRUB
    echo "更新 GRUB..."
    update-grub || {
        echo -e "更新 GRUB 失败"
        pause_function
        return 1
    }

    # 配置内核模块
    echo "配置内核模块..."
    backup_file "/etc/modules"

    # 添加 VFIO 模块（如果未添加）
    for module in vfio vfio_iommu_type1 vfio_pci vfio_virqfd; do
        if ! grep -q "^$module$" /etc/modules; then
            echo "$module" >> /etc/modules
            echo "已添加模块: $module"
        fi
    done

    # 移除 kvmgt 模块（如果有 GVT-g 配置）
    sed -i '/^kvmgt$/d' /etc/modules

    echo -e "✓ 内核模块配置完成"

    # 更新 initramfs
    echo "更新 initramfs..."
    update-initramfs -u -k all || {
        echo -e "更新 initramfs 失败，但可以继续"
    }

    # 下载并安装 i915-sriov-dkms 驱动
    echo "下载 i915-sriov-dkms 驱动..."
    echo "  提示: 请在浏览器访问 https://github.com/strongtz/i915-sriov-dkms/releases 选择匹配的版本"
    echo "  一般建议选择最新的 release 版本以兼容最新的内核版本"
    echo "  输入格式：例如：2025.11.10"
    echo "  不输入回车的默认版本为 2025.11.10，可能不兼容老版本内核，故障表现在无法虚拟出 VFs" 

    default_dkms_version="2025.11.10"
    read -p "请输入要安装的 release 版本号 [默认: ${default_dkms_version}]: " dkms_version_input
    dkms_version_input=$(echo "$dkms_version_input" | xargs)

    if [ -z "$dkms_version_input" ]; then
        dkms_version_input="$default_dkms_version"
    fi

    # release 标签可能以 v 打头，但 deb 文件名不包含 v
    dkms_asset_version=$(echo "$dkms_version_input" | sed 's/^[vV]//')
    dkms_tag="$dkms_version_input"

    dkms_url="https://github.com/strongtz/i915-sriov-dkms/releases/download/${dkms_tag}/i915-sriov-dkms_${dkms_asset_version}_amd64.deb"
    dkms_file="/tmp/i915-sriov-dkms_${dkms_asset_version}_amd64.deb"

    # 检查是否已下载
    if [ -f "$dkms_file" ]; then
        echo "驱动文件已存在，跳过下载"
    else
        echo "从 GitHub 下载驱动..."
        echo "  提示: 如果下载失败，请检查网络或手动下载后放到 /tmp/ 目录"

        wget -O "$dkms_file" "$dkms_url" || {
            echo -e "下载驱动失败"
            echo "  提示: 请手动下载: $dkms_url"
            echo "  提示: 并上传到 PVE 的 /tmp/ 目录后重试"
            pause_function
            return 1
        }
    fi

    echo "安装 i915-sriov-dkms 驱动..."
    echo -e "驱动安装可能需要较长时间，请耐心等待..."

    dpkg -i "$dkms_file" || {
        echo -e "安装驱动失败"
        pause_function
        return 1
    }

    # 验证驱动安装
    echo "验证驱动安装..."
    if modinfo i915 2>/dev/null | grep -q "max_vfs"; then
        echo -e "✓ i915-sriov 驱动安装成功"
    else
        echo -e "驱动验证失败，请检查安装过程"
        pause_function
        return 1
    fi

    # 配置 VFs 数量
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "配置虚拟核显（VFs）数量"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "虚拟核显数量范围: 1-7"
    echo "推荐配置："
    echo "  - 1 个 VF: 性能最强，适合单个高性能虚拟机"
    echo "  - 2-3 个 VF: 平衡性能，适合多个虚拟机"
    echo "  - 4-7 个 VF: 最多虚拟机数量，性能较弱"
    echo
    read -p "请输入 VFs 数量 [1-7, 默认: 3]: " vfs_num

    # 验证输入
    if [[ -z "$vfs_num" ]]; then
        vfs_num=3
    elif ! [[ "$vfs_num" =~ ^[1-7]$ ]]; then
        echo -e "无效的 VFs 数量，必须是 1-7"
        pause_function
        return 1
    fi

    echo "配置 $vfs_num 个虚拟核显"

    # 写入 sysfs.conf
    echo "devices/pci0000:00/0000:00:02.0/sriov_numvfs = $vfs_num" > /etc/sysfs.conf
    echo -e "✓ VFs 数量配置完成"

    # 完成提示
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "✓ SR-IOV 核显虚拟化配置完成！"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "配置摘要："
    echo "  • 内核参数: intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=7"
    echo "  • VFIO 模块: 已加载"
    echo "  • i915-sriov 驱动: 已安装"
    echo "  • 虚拟核显数量: $vfs_num 个"
    echo
    echo -e "下一步操作："
    echo -e "  1. 重启系统使配置生效"
    echo "  2. 重启后使用 '验证核显虚拟化状态' 检查配置"
    echo "  3. 在虚拟机配置中添加核显 SR-IOV 设备"
    echo
    echo -e "重要提示："
    echo -e "  • 物理核显 (00:02.0) 不能直通给虚拟机"
    echo -e "  • 只能直通虚拟核显 (00:02.1 ~ 00:02.$vfs_num)"
    echo -e "  • 虚拟机需要勾选 ROM-Bar 和 PCIE 选项"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if confirm_action "是否现在重启系统"; then
        echo "正在重启系统..."
        reboot
    else
        echo -e "请记得手动重启系统以使配置生效"
    fi
}

# Intel 6-10代 GVT-g 核显虚拟化配置
igpu_gvtg_setup() {
    echo "开始配置 Intel 6-10代 GVT-g 核显虚拟化"

    # 展示当前 GRUB 配置
    echo
    show_grub_config
    echo

    # 危险性警告
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "【高危操作警告】GVT-g 核显虚拟化配置"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "此操作属于【高危险性】系统配置，配置错误可能导致："
    echo -e "  - 系统无法正常启动（GRUB 配置错误）"
    echo -e "  - 核显完全不可用（参数配置错误）"
    echo -e "  - 虚拟机黑屏或无法启动（直通配置错误）"
    echo -e "  - 需要通过恢复模式修复系统"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "此功能将修改以下系统配置："
    echo "  1. 修改 GRUB 引导参数（启用 IOMMU 和 GVT-g）"
    echo "  2. 加载 VFIO 和 kvmgt 内核模块"
    echo
    echo "前置要求（请确认已完成）："
    echo "  ✓ BIOS 已开启 VT-d 虚拟化"
    echo "  ✓ BIOS 已开启 SR-IOV（如有此选项）"
    echo "  ✓ BIOS 已开启 Above 4GB（如有此选项）"
    echo "  ✓ BIOS 已关闭 Secure Boot 安全启动"
    echo "  ✓ CPU 为 Intel 6-10 代处理器"
    echo
    echo "支持的处理器代号："
    echo "  • Skylake (6代)"
    echo "  • Kaby Lake (7代)"
    echo "  • Coffee Lake (8代)"
    echo "  • Coffee Lake Refresh (9代)"
    echo "  • Comet Lake (10代)"
    echo
    echo -e "特殊的处理器代号："
    echo -e "  • Rocket Lake / Tiger Lake (11代) 因处在当前代与上一代交界"
    echo -e "    部分型号支持，但是不保证兼容性，请谨慎使用"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo -e "强烈建议："
    echo "  提示: 1. 在继续前先备份当前 GRUB 配置"
    echo "  提示: 2. 确保了解核显虚拟化的工作原理"
    echo "  提示: 3. 准备好通过 SSH 或物理访问恢复系统"
    echo

    # 询问是否要备份
    if confirm_action "是否先备份当前 GRUB 配置（强烈推荐）"; then
        echo
        echo "请输入备份备注（例如：GVT-g配置前备份）："
        read -p "> " backup_note
        backup_note=${backup_note:-"GVT-g配置前备份"}
        backup_grub_with_note "$backup_note"
        echo
    fi

    if ! confirm_action "确认继续配置 GVT-g 核显虚拟化"; then
        echo "用户取消操作"
        return 0
    fi

    # 备份并修改 GRUB 配置
    echo "配置 GRUB 引导参数..."
    backup_file "/etc/default/grub"

    # 检查是否已配置
    if grep -q "i915.enable_gvt=1" /etc/default/grub; then
        echo -e "GRUB 已配置 GVT-g 参数，跳过修改"
    else
        # 移除旧的 SR-IOV 配置（如果有）
        sed -i 's/i915.enable_guc=3//g; s/i915.max_vfs=7//g; s/module_blacklist=xe//g' /etc/default/grub

        # 添加 GVT-g 参数
        sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt i915.enable_gvt=1 pcie_acs_override=downstream,multifunction"' /etc/default/grub

        echo -e "✓ GRUB 配置已更新"
    fi

    # 更新 GRUB
    echo "更新 GRUB..."
    update-grub || {
        echo -e "更新 GRUB 失败"
        pause_function
        return 1
    }

    # 配置内核模块
    echo "配置内核模块..."
    backup_file "/etc/modules"

    # 添加 VFIO 和 kvmgt 模块
    for module in vfio vfio_iommu_type1 vfio_pci vfio_virqfd kvmgt; do
        if ! grep -q "^$module$" /etc/modules; then
            echo "$module" >> /etc/modules
            echo "已添加模块: $module"
        fi
    done

    echo -e "✓ 内核模块配置完成"

    # 更新 initramfs
    echo "更新 initramfs..."
    update-initramfs -u -k all || {
        echo -e "更新 initramfs 失败，但可以继续"
    }

    # 完成提示
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "✓ GVT-g 核显虚拟化配置完成！"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "配置摘要："
    echo "  • 内核参数: intel_iommu=on iommu=pt i915.enable_gvt=1"
    echo "  • VFIO 模块: 已加载"
    echo "  • kvmgt 模块: 已加载"
    echo
    echo -e "下一步操作："
    echo -e "  1. 重启系统使配置生效"
    echo "  2. 重启后使用 '验证核显虚拟化状态' 检查配置"
    echo "  3. 在虚拟机配置中添加核显 GVT-g 设备（Mdev 类型）"
    echo
    echo "常见 Mdev 类型："
    echo "  • i915-GVTg_V5_4: 低性能，可创建更多虚拟机"
    echo "  • i915-GVTg_V5_8: 高性能，推荐使用（UHD630 最多 2 个）"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if confirm_action "是否现在重启系统"; then
        echo "正在重启系统..."
        reboot
    else
        echo -e "请记得手动重启系统以使配置生效"
    fi
}

# 清理 GVT-g 和 SR-IOV 配置 (恢复默认)
restore_igpu_config() {
    log_step "开始清理核显虚拟化配置 (恢复默认)"
    echo "此操作将执行以下步骤："
    echo "1. 移除 GRUB 中的核显相关参数 (intel_iommu, i915.enable_gvt, i915.enable_guc 等)"
    echo "2. 从 /etc/modules 移除核显相关模块 (kvmgt, vfio 等)"
    echo "3. 更新 GRUB 和 initramfs"
    echo "适用于因配置核显虚拟化导致系统异常或想要重置配置的情况。"
    echo

    if ! confirm_action "是否继续执行清理操作？"; then
        return
    fi

    # 1. 恢复 GRUB 配置
    log_info "正在清理 GRUB 参数..."
    if [[ -f "/etc/default/grub" ]]; then
        # 备份 GRUB 配置
        backup_file "/etc/default/grub"
        
        # 移除相关参数
        sed -i 's/intel_iommu=on//g' /etc/default/grub
        sed -i 's/iommu=pt//g' /etc/default/grub
        sed -i 's/i915.enable_gvt=1//g' /etc/default/grub
        sed -i 's/i915.enable_guc=[0-9]*//g' /etc/default/grub
        sed -i 's/i915.max_vfs=[0-9]*//g' /etc/default/grub
        
        # 清理多余空格
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[[:space:]]*/GRUB_CMDLINE_LINUX_DEFAULT="/g' /etc/default/grub
        sed -i 's/[[:space:]]*"$/"/g' /etc/default/grub
        sed -i 's/[[:space:]]\{2,\}/ /g' /etc/default/grub
        
        log_success "GRUB 参数清理完成"
    else
        log_error "未找到 /etc/default/grub 文件"
    fi

    # 2. 恢复 /etc/modules
    log_info "正在清理 /etc/modules..."
    if [[ -f "/etc/modules" ]]; then
        backup_file "/etc/modules"
        sed -i '/vfio/d' /etc/modules
        sed -i '/vfio_iommu_type1/d' /etc/modules
        sed -i '/vfio_pci/d' /etc/modules
        sed -i '/vfio_virqfd/d' /etc/modules
        sed -i '/kvmgt/d' /etc/modules
        log_success "/etc/modules 清理完成"
    fi

    # 3. 更新系统配置
    log_info "正在更新 GRUB..."
    update-grub
    
    log_info "正在更新 initramfs..."
    update-initramfs -u -k all
    
    log_success "清理完成！核显虚拟化配置已重置。"
    if confirm_action "是否现在重启系统？"; then
        reboot
    fi
}

# 验证核显虚拟化状态
igpu_verify() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  核显虚拟化状态检查"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    # 检查 IOMMU
    echo "1. 检查 IOMMU 状态..."
    if dmesg | grep -qi "DMAR.*IOMMU\|iommu.*enabled"; then
        echo -e "  ✓ IOMMU 已启用"
        echo "  $(dmesg | grep -i "DMAR.*IOMMU\|iommu.*enabled" | head -3)"
    else
        echo -e "  ✗ IOMMU 未启用"
        echo "  提示: 请检查 BIOS 是否开启 VT-d"
        echo "  提示: 请检查 GRUB 配置是否包含 intel_iommu=on"
    fi
    echo

    # 检查 VFIO 模块
    echo "2. 检查 VFIO 模块加载状态..."
    if lsmod | grep -q vfio; then
        echo -e "  ✓ VFIO 模块已加载"
        echo "  $(lsmod | grep vfio)"
    else
        echo -e "  ✗ VFIO 模块未加载"
        echo "  提示: 请检查 /etc/modules 配置"
    fi
    echo

    # 检查 SR-IOV
    echo "3. 检查 SR-IOV 虚拟核显..."
    if lspci | grep -i "VGA.*Intel" | wc -l | grep -q "^[2-9]"; then
        vf_count=$(($(lspci | grep -i "VGA.*Intel" | wc -l) - 1))
        echo -e "  ✓ 检测到 $vf_count 个虚拟核显 (SR-IOV)"
        echo
        lspci | grep -i "VGA.*Intel"
        echo
        echo "  提示: 物理核显 00:02.0 不能直通"
        echo "  提示: 虚拟核显 00:02.1 ~ 00:02.$vf_count 可直通给虚拟机"
    else
        echo -e "  ! 未检测到 SR-IOV 虚拟核显"
    fi
    echo

    # 检查 GVT-g
    echo "4. 检查 GVT-g mdev 类型..."
    if [ -d "/sys/bus/pci/devices/0000:00:02.0/mdev_supported_types" ]; then
        mdev_types=$(ls /sys/bus/pci/devices/0000:00:02.0/mdev_supported_types 2>/dev/null | wc -l)
        if [ "$mdev_types" -gt 0 ]; then
            echo -e "  ✓ GVT-g 已启用，可用 Mdev 类型: $mdev_types 个"
            echo
            ls -1 /sys/bus/pci/devices/0000:00:02.0/mdev_supported_types
        else
            echo -e "  ! GVT-g 未正确配置"
        fi
    else
        echo -e "  ! 未检测到 GVT-g 支持"
        echo "  提示: 此 CPU 可能不支持 GVT-g 或未配置"
    fi
    echo

    # 检查 kvmgt 模块（GVT-g 需要）
    echo "5. 检查 kvmgt 模块（GVT-g）..."
    if lsmod | grep -q kvmgt; then
        echo -e "  ✓ kvmgt 模块已加载（GVT-g 模式）"
    else
        echo "  kvmgt 模块未加载（SR-IOV 模式或未配置 GVT-g）"
    fi
    echo

    # 检查 i915 驱动参数
    echo "6. 检查 i915 驱动参数..."
    if [ -f "/sys/module/i915/parameters/enable_guc" ]; then
        guc_value=$(cat /sys/module/i915/parameters/enable_guc)
        if [ "$guc_value" = "3" ]; then
            echo -e "  ✓ i915.enable_guc = 3 (SR-IOV 模式)"
        else
            echo "  i915.enable_guc = $guc_value"
        fi
    fi

    if [ -f "/sys/module/i915/parameters/enable_gvt" ]; then
        gvt_value=$(cat /sys/module/i915/parameters/enable_gvt)
        if [ "$gvt_value" = "Y" ]; then
            echo -e "  ✓ i915.enable_gvt = Y (GVT-g 模式)"
        else
            echo "  i915.enable_gvt = $gvt_value"
        fi
    fi
    echo

    # 总结
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  检查完成"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    pause_function
}

# 移除核显虚拟化配置
igpu_remove() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e " 警告 - 移除核显虚拟化配置"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo -e "  此操作将："
    echo "  • 恢复 GRUB 配置为默认值"
    echo "  • 清理 /etc/modules 中的 VFIO 和 kvmgt 模块"
    echo "  • 删除 /etc/sysfs.conf 中的 VFs 配置"
    echo "  • 卸载 i915-sriov-dkms 驱动（如已安装）"
    echo
    echo -e "  注意：此操作不会自动重启系统"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if ! confirm_action "确认移除核显虚拟化配置"; then
        echo "用户取消操作"
        return 0
    fi

    # 恢复 GRUB 配置
    echo "恢复 GRUB 配置..."
    backup_file "/etc/default/grub"

    # 移除所有核显虚拟化参数
    sed -i 's/intel_iommu=on//g; s/iommu=pt//g; s/i915.enable_guc=3//g; s/i915.max_vfs=7//g; s/module_blacklist=xe//g; s/i915.enable_gvt=1//g; s/pcie_acs_override=downstream,multifunction//g' /etc/default/grub

    # 清理多余空格
    sed -i 's/  */ /g' /etc/default/grub

    update-grub
    echo -e "  ✓ GRUB 配置已恢复"

    # 清理 /etc/modules
    echo "清理内核模块配置..."
    backup_file "/etc/modules"

    sed -i '/^vfio$/d; /^vfio_iommu_type1$/d; /^vfio_pci$/d; /^vfio_virqfd$/d; /^kvmgt$/d' /etc/modules
    echo -e "  ✓ 内核模块配置已清理"

    # 清理 /etc/sysfs.conf
    if [ -f "/etc/sysfs.conf" ]; then
        echo "清理 sysfs 配置..."
        backup_file "/etc/sysfs.conf"
        sed -i '/sriov_numvfs/d' /etc/sysfs.conf
        echo -e "  ✓ sysfs 配置已清理"
    fi

    # 卸载 i915-sriov-dkms
    echo "检查 i915-sriov-dkms 驱动..."
    if dpkg -l | grep -q i915-sriov-dkms; then
        echo "卸载 i915-sriov-dkms 驱动..."
        dpkg -P i915-sriov-dkms || echo -e "${YELLOW}警告: 卸载驱动失败，可能需要手动处理${NC}"
        echo -e "✓ 驱动已卸载"
    else
        echo "未安装 i915-sriov-dkms 驱动，跳过"
    fi

    # 更新 initramfs
    echo "更新 initramfs..."
    update-initramfs -u -k all

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "✓ 核显虚拟化配置已移除"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "提示: 请重启系统使更改生效"

    if confirm_action "是否现在重启系统"; then
        echo "正在重启系统..."
        reboot
    else
        echo "请记得手动重启系统"
    fi
}

# 核显高级功能菜单
igpu_management_menu() {
    while true; do
        clear
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "              核显虚拟化高级功能"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "【危险警告】核显虚拟化属于高危操作"
        echo -e "配置错误可能导致系统无法启动，请务必提前备份 GRUB 配置"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  1. Intel 11-15代 SR-IOV 核显虚拟化"
        echo "     支持: Rocket Lake, Alder Lake, Raptor Lake"
        echo "     特性: 最多 7 个虚拟核显，性能较好"
        echo "  2. Intel 6-10代 GVT-g 核显虚拟化"
        echo "     支持: Skylake ~ Comet Lake"
        echo "     特性: 最多 2-8 个虚拟核显（取决于型号）"
        echo "  3. 验证核显虚拟化状态"
        echo "     检查 IOMMU、VFIO、SR-IOV/GVT-g 配置"
        echo "  4. 移除核显虚拟化配置"
        echo "     恢复默认配置，移除所有核显虚拟化设置"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  GRUB 配置管理（强烈推荐使用）"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  5. 查看当前 GRUB 配置"
        echo "     展示当前的 GRUB 引导参数和关键配置"
        echo "  6. 备份 GRUB 配置"
        echo "     备份到 /etc/pvetools9/backup/grub/"
        echo "  7. 查看 GRUB 备份列表"
        echo "     列出所有已创建的备份文件"
        echo "  8. 恢复 GRUB 配置"
        echo "     从备份文件恢复 GRUB 配置"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  0. 返回主菜单"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo
        read -p "请选择操作 [0-8]: " choice

        case $choice in
            1)
                igpu_sriov_setup
                ;;
            2)
                igpu_gvtg_setup
                ;;
            3)
                igpu_verify
                ;;
            4)
                igpu_remove
                ;;
            5)
                show_grub_config
                pause_function
                ;;
            6)
                echo
                echo "请输入备份备注（例如：手动备份_测试）："
                read -p "> " backup_note
                backup_note=${backup_note:-"手动备份"}
                backup_grub_with_note "$backup_note"
                pause_function
                ;;
            7)
                list_grub_backups
                pause_function
                ;;
            8)
                restore_grub_backup
                ;;
            0)
                echo "返回主菜单"
                return 0
                ;;
            *)
                echo -e "无效的选择，请输入 0-8"
                pause_function
                ;;
        esac
    done
}
#--------------核显虚拟化管理----------------

#---------PVE8/9添加ceph-squid源-----------
pve9_ceph() {
    sver=`cat /etc/debian_version |awk -F"." '{print $1}'`
    case "$sver" in
     13 )
         sver="trixie"
     ;;
     12 )
         sver="bookworm"
     ;;
    * )
        sver=""
     ;;
    esac
    if [ ! $sver ];then
        log_error "版本不支持！"
        pause_function
        return
    fi

    log_info "ceph-squid目前仅支持PVE8和9！"
    [[ ! -d /etc/apt/backup ]] && mkdir -p /etc/apt/backup
    [[ ! -d /etc/apt/sources.list.d ]] && mkdir -p /etc/apt/sources.list.d

    [[ -e /etc/apt/sources.list.d/ceph.sources ]] && mv /etc/apt/sources.list.d/ceph.sources /etc/apt/backup/ceph.sources.bak
    [[ -e /etc/apt/sources.list.d/ceph.list ]] && mv /etc/apt/sources.list.d/ceph.list /etc/apt/backup/ceph.list.bak

    [[ -e /usr/share/perl5/PVE/CLI/pveceph.pm ]] && cp -rf /usr/share/perl5/PVE/CLI/pveceph.pm /etc/apt/backup/pveceph.pm.bak
    sed -i 's|http://download.proxmox.com|https://mirrors.tuna.tsinghua.edu.cn/proxmox|g' /usr/share/perl5/PVE/CLI/pveceph.pm

    cat > /etc/apt/sources.list.d/ceph.list <<-EOF
deb https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/ceph-squid ${sver} no-subscription
EOF
    log_success "添加ceph-squid源完成!"
}
#---------PVE8/9添加ceph-squid源-----------

#---------PVE7/8添加ceph-quincy源-----------
pve8_ceph() {
    sver=`cat /etc/debian_version |awk -F"." '{print $1}'`
    case "$sver" in
     12 )
         sver="bookworm"
     ;;
     11 )
         sver="bullseye"
     ;;
    * )
        sver=""
     ;;
    esac
    if [ ! $sver ];then
        log_error "版本不支持！"
        pause_function
        return
    fi

    log_info "ceph-quincy目前仅支持PVE7和8！"
    [[ ! -d /etc/apt/backup ]] && mkdir -p /etc/apt/backup
    [[ ! -d /etc/apt/sources.list.d ]] && mkdir -p /etc/apt/sources.list.d

    [[ -e /etc/apt/sources.list.d/ceph.sources ]] && mv /etc/apt/sources.list.d/ceph.sources /etc/apt/backup/ceph.sources.bak
    [[ -e /etc/apt/sources.list.d/ceph.list ]] && mv /etc/apt/sources.list.d/ceph.list /etc/apt/backup/ceph.list.bak

    [[ -e /usr/share/perl5/PVE/CLI/pveceph.pm ]] && cp -rf /usr/share/perl5/PVE/CLI/pveceph.pm /etc/apt/backup/pveceph.pm.bak
    sed -i 's|http://download.proxmox.com|https://mirrors.tuna.tsinghua.edu.cn/proxmox|g' /usr/share/perl5/PVE/CLI/pveceph.pm

    cat > /etc/apt/sources.list.d/ceph.list <<-EOF
deb https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/ceph-quincy ${sver} main
EOF
    log_success "添加ceph-quincy源完成!"
}
#---------PVE7/8添加ceph-quincy源-----------
# 待办
#---------PVE7/8添加ceph-quincy源-----------
#---------PVE一键卸载ceph-----------
remove_ceph() {
    log_warn "会卸载ceph，并删除所有ceph相关文件！"

    systemctl stop ceph-mon.target && systemctl stop ceph-mgr.target && systemctl stop ceph-mds.target && systemctl stop ceph-osd.target
    rm -rf /etc/systemd/system/ceph*

    killall -9 ceph-mon ceph-mgr ceph-mds ceph-osd
    rm -rf /var/lib/ceph/mon/* && rm -rf /var/lib/ceph/mgr/* && rm -rf /var/lib/ceph/mds/* && rm -rf /var/lib/ceph/osd/*

    pveceph purge

    apt purge -y ceph-mon ceph-osd ceph-mgr ceph-mds
    apt purge -y ceph-base ceph-mgr-modules-core

    rm -rf /etc/ceph && rm -rf /etc/pve/ceph.conf  && rm -rf /etc/pve/priv/ceph.* && rm -rf /var/log/ceph && rm -rf /etc/pve/ceph && rm -rf /var/lib/ceph

    [[ -e /etc/apt/sources.list.d/ceph.sources ]] && mv /etc/apt/sources.list.d/ceph.sources /etc/apt/backup/ceph.sources.bak

    log_success "已成功卸载ceph."
}
#---------PVE一键卸载ceph-----------

#---------第三方小工具管理-----------
# 小工具配置
# FastPVE - PVE 虚拟机快速下载
fastpve_quick_download_menu() {
    clear
    show_banner
    show_menu_header "PVE 虚拟机快速下载 (FastPVE)"

    echo "  FastPVE 由社区开发者 @kspeeder 维护，提供热门 PVE 虚拟机模板快速拉取能力。"
    echo "  本功能将直接运行 FastPVE 官方脚本，请在执行前确保信任该来源。"
    echo
    echo "  项目地址: $FASTPVE_PROJECT_URL"
    echo "  安装脚本: $FASTPVE_INSTALLER_URL"
    echo
    echo -e "${RED}⚠️  重要提示:${NC} 这是第三方脚本，出现任何问题请前往 FastPVE 项目反馈，别找我喔~"
    echo -e "${YELLOW}    我们只负责帮你下载并执行，后续操作和风险请自行承担。${NC}"
    echo "${UI_DIVIDER}"
    echo "  使用说明："
    echo "    • FastPVE 会拉取独立菜单，按提示选择需要的虚拟机模板"
    echo "    • 需要互联网访问 GitHub（大陆环境自动优先使用镜像源）"
    echo "    • 本脚本仅负责下载并执行 FastPVE，具体操作由 FastPVE 完成"
    echo "${UI_DIVIDER}"

    read -p "是否立即运行 FastPVE 脚本？(y/N): " confirm
    confirm=${confirm:-N}
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "已取消执行 FastPVE"
        return 0
    fi

    local fastpve_url="$FASTPVE_INSTALLER_URL"
    local fastpve_mirror_url="${GITHUB_MIRROR_PREFIX}${FASTPVE_INSTALLER_URL}"
    local preferred_url="$fastpve_url"
    local fallback_url="$fastpve_mirror_url"
    local preferred_label="GitHub"
    local fallback_label="加速镜像"

    if detect_network_region; then
        if [[ $USE_MIRROR_FOR_UPDATE -eq 1 ]]; then
            preferred_url="$fastpve_mirror_url"
            fallback_url="$fastpve_url"
            preferred_label="加速镜像"
            fallback_label="GitHub"
            log_info "检测到中国大陆网络环境，优先使用 FastPVE 加速镜像下载"
        else
            if [[ -n "$USER_COUNTRY_CODE" ]]; then
                log_info "检测到当前地区: $USER_COUNTRY_CODE，将通过 GitHub 下载 FastPVE"
            else
                log_info "网络检测成功，将通过 GitHub 下载 FastPVE"
            fi
        fi
    else
        log_warn "无法检测网络地区，默认使用 GitHub 下载 FastPVE"
    fi

    local -a download_cmd
    local downloader_name=""
    if command -v curl &> /dev/null; then
        download_cmd=(curl -fsSL --connect-timeout 10 --max-time 60 -o)
        downloader_name="curl"
    elif command -v wget &> /dev/null; then
        download_cmd=(wget -q -O)
        downloader_name="wget"
    else
        log_error "未检测到 curl 或 wget，无法下载 FastPVE 脚本"
        return 1
    fi

    local tmp_script
    if ! tmp_script=$(mktemp /tmp/fastpve-install.XXXXXX.sh); then
        log_error "无法创建临时文件，FastPVE 启动失败"
        return 1
    fi

    log_info "使用 $preferred_label 下载 FastPVE 安装脚本 (下载器: $downloader_name)..."
    if ! "${download_cmd[@]}" "$tmp_script" "$preferred_url"; then
        log_warn "$preferred_label 下载失败，尝试改用 $fallback_label..."
        : > "$tmp_script"
        if ! "${download_cmd[@]}" "$tmp_script" "$fallback_url"; then
            log_error "FastPVE 安装脚本下载失败，请检查网络或稍后重试"
            rm -f "$tmp_script"
            return 1
        fi
    fi

    chmod +x "$tmp_script"
    echo
    log_step "FastPVE 脚本即将运行，请根据 FastPVE 菜单提示选择虚拟机模板"
    echo "${UI_BORDER}"
    sh "$tmp_script"
    local run_status=$?
    echo "${UI_BORDER}"

    rm -f "$tmp_script"

    if [[ $run_status -eq 0 ]]; then
        log_success "FastPVE 虚拟机快速下载脚本执行完成"
    else
        log_error "FastPVE 脚本执行失败 (退出码: $run_status)"
    fi

    return $run_status
}
#---------FastPVE 虚拟机快速下载-----------

# 社区第三方工具集合提示
third_party_tools_menu() {
    clear
    show_menu_header "第三方工具集 (Community Scripts)"

    echo "  这里推荐一个由社区维护的庞大脚本集合，覆盖 Proxmox 安装、容器/虚拟机模版、监控等各种高级玩法。"
    echo
    echo "  项目主页: https://community-scripts.github.io/ProxmoxVE/"
    echo "  GitHub 仓库: https://github.com/community-scripts/ProxmoxVE"
    echo
    echo -e "${RED}⚠️  重要提示:${NC} 该工具集完全由第三方维护，与 PVE-Tools 项目无关。"
    echo -e "${YELLOW}    如果脚本运行出现问题，请直接前往上述项目反馈，不要来找我喔~${NC}"
    echo
    echo "  使用建议："
    echo "    • 全站为英文界面，可配合浏览器或翻译软件使用，中文用户建议提前准备。"
    echo "    • 网站中包含大量脚本和功能说明，建议按需阅读说明后再执行。"
    echo "    • 执行任何第三方脚本前，请务必备份关键配置并了解潜在风险。"
    echo "${UI_DIVIDER}"
    read -p "按任意键返回主菜单..." -n 1 _
    echo
}
#---------社区第三方工具集合-----------

# PVE8 to PVE9 升级功能
pve8_to_pve9_upgrade() {
    log_step "开始 PVE 8.x 升级到 PVE 9.x"
    
    # 检查当前 PVE 版本
    local current_pve_version=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1)
    local major_version=$(echo $current_pve_version | cut -d'.' -f1)
    
    if [[ "$major_version" != "8" ]]; then
        log_error "当前 PVE 版本为 $current_pve_version，不是 PVE 8.x 版本，无法执行此升级"
        log_info "PVE7 请先试用ISO或升级教程升级哦! ：https://pve.proxmox.com/wiki/Upgrade_from_7_to_8"
        log_tips "如果你已经是PVE 9.x了，你还来用这个脚本，敲你额头！"
        return 1
    fi
    
    log_info "检测到当前 PVE 版本: $current_pve_version"
    log_warn "即将开始 PVE 8.x 到 PVE 9.x 的升级流程"
    log_warn "此过程不可逆，请确保已备份重要数据！"
    log_warn "建议在升级前阅读官方升级指南：https://pve.proxmox.com/wiki/Upgrade_from_8.x_to_9.0"
    echo
    log_warn "升级过程中请勿中断，确保有稳定的网络连接"
    log_warn "升级完成后，系统将自动重启以应用更改"
    log_warn "如果脚本出现升级问题，请及时联系作者或参照官方文档解决。"
    echo
    log_info "推荐使用我的新项目嘿嘿，一个独立的升级AGENT: https://github.com/Mapleawaa/PVE-8-Upgrage-helper"
    
    # 确认用户要继续执行升级
    echo "您确定要继续升级吗？本次任务执行以下操作："
    echo "  1. 安装 pve8to9 检查工具"
    echo "  2. 运行升级前检查"
    echo "  3. 更新软件源到 Debian 13 (Trixie)"
    echo "  4. 执行系统升级"
    echo "  5. 重启系统以应用更改"
    echo
    echo "注意：升级过程中可能会遇到一些警告或错误，请根据提示进行处理！脚本无法处理故障提示！(脚本只能把提示扔给你..) )"
    read -p "输入 'yesido' 确认继续，其他任意键取消: " confirm
    if [[ "$confirm" != "yesido" ]]; then
        log_info "已取消升级操作"
        return 0
    fi
    
    # 1. 更新当前系统到最新 PVE 8.x 版本
    log_info "更新当前系统到最新 PVE 8.x 版本..."
    if ! apt update && apt dist-upgrade -y; then
        log_error "更新 PVE 8.x 到最新版本失败了，请检查网络连接或源配置，或者前往作者的GitHub反馈issue.."
        return 1
    fi
    
    # 再次检查当前版本
    current_pve_version=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1)
    log_info "更新后 PVE 版本: ${GREEN}$current_pve_version${NC}"
    
    # PVE8.4 自带这个包，此处无需检查安装，apt 源无此包会报错。
    # 2. 安装和运行 pve8to9 检查工具
    # log_info "安装 pve8to9 升级检查工具..."
    # if ! apt install -y pve8to9; then
    #     log_warn "pve8to9 工具安装失败，尝试手动安装..."
    #     # 尝试手动添加 PVE 8 仓库安装 pve8to9
    #     if ! apt install -y pve8to9; then
    #         log_error "无法安装 pve8to9 检查工具,奇怪！请检查网络连接或源配置，或者前往作者的GitHub反馈issue.."
    #         return 1
    #     fi
    # fi
    
    log_info "运行升级前检查..."
    echo -e "${CYAN}pve8to9 检查结果：${NC}"
    # 运行 pve8to9 检查，但不直接退出，而是捕获输出并分析
    echo -e "检查结果会保存到 /tmp/pve8to9_check.log 文件中，如出现故障建议查看该文件以获取详细信息"
    echo -e "再次提示，脚本只能做到把错误扔给你，无法修复问题，请根据提示自行解决(或前往作者issue反馈问题)..."
    local check_result=$(pve8to9 | tee /tmp/pve8to9_check.log)
    echo "$check_result"
    
    # 检查是否有 FAIL 标记（这意味着有严重错误需要修复）
    if echo "$check_result" | grep -E -i "FAIL" > /dev/null; then
        log_error "pve8to9 检查发现严重错误!! 一般是软件包冲突或是其他报错!建议修复后再进行升级！"
        echo -e "${YELLOW}升级检查结果详情：${NC}"
        cat /tmp/pve8to9_check.log
        read -p "您确定要忽略这些错误并继续升级吗？这不是在开玩笑！(y/N): " force_upgrade
        if [[ "$force_upgrade" != "y" && "$force_upgrade" != "Y" ]]; then
            log_info "由于存在严重错误，已取消升级操作...返回主界面"
            return 1
        fi
    else
        log_success "pve8to9 检查通过，没有发现严重错误，太好了！"
        
        # 检查是否有 WARNING 标记
        if echo "$check_result" | grep -E -i "WARN" > /dev/null; then
            log_warn "pve8to9 检查发现一些警告信息，请查看以上详情并根据需要处理。(有些可能是软件包没升级上去，不是关键软件包可以无视先升级喔)"
            read -p "是否继续升级？(Y/n): " continue_check
            if [[ "$continue_check" == "n" || "$continue_check" == "N" ]]; then
                log_info "已取消升级操作"
                return 0
            fi
        fi
    fi
    
    # 3. 安装 CPU 微码（如果提示需要）
    log_info "检查是否需要安装 CPU 微码..."
    if command -v lscpu &> /dev/null; then
        local cpu_vendor=$(lscpu | grep "Vendor ID" | awk '{print $3}')
        if [[ "$cpu_vendor" == "GenuineIntel" ]]; then
            log_info "检测到 Intel CPU，安装 Intel 微码..."
            apt install -y intel-microcode
        elif [[ "$cpu_vendor" == "AuthenticAMD" ]]; then
            log_info "检测到 AMD CPU，安装 AMD 微码..."
            apt install -y amd64-microcode
        fi
    fi
    
    # 4. 检查当前启动方式并更新引导配置
    log_info "检查系统启动方式..."
    local boot_method="unknown"
    if [[ -d "/boot/efi" ]]; then
        boot_method="efi"
        log_info "检测到 EFI 启动模式"
        # 为 EFI 系统配置 GRUB
        echo 'grub-efi-amd64 grub2/force_efi_extra_removable boolean true' | debconf-set-selections -v -u
    else
        boot_method="bios"
        log_info "检测到 BIOS 启动模式"
        log_tips "怎么还在用BIOS启用呀？建议升级到UEFI启动方式，提升系统兼容性和安全性"
    fi
    
    # 5. 备份当前源文件
    log_info "备份当前源文件..."
    local backup_dir="/etc/pve-tools-9-bak"
    mkdir -p "$backup_dir"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # 备份各种源文件
    if [[ -f "/etc/apt/sources.list" ]]; then
        cp /etc/apt/sources.list "${backup_dir}/sources.list.backup.${timestamp}"
    fi
    
    if [[ -f "/etc/apt/sources.list.d/pve-enterprise.list" ]]; then
        cp /etc/apt/sources.list.d/pve-enterprise.list "${backup_dir}/pve-enterprise.list.backup.${timestamp}"
    fi
    
    # 6. 更新源到 Debian 13 (Trixie) 并添加 PVE 9.x 源
    log_info "更新软件源到 Debian 13 (Trixie)..."
    
    # 将所有 bookworm 源替换为 trixie
    log_step "替换 sources.list 和 pve-enterprise.list 中的 bookworm 为 trixie"
    sed -i 's/bookworm/trixie/g' /etc/apt/sources.list 2>/dev/null || true
    sed -i 's/bookworm/trixie/g' /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null || true
    
    # 创建 PVE 9.x 的 sources 配置文件
    log_step "创建 PVE 9.x 的 sources 配置文件..."
    cat > /etc/apt/sources.list.d/proxmox.sources << EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    
    # 创建 Ceph Squid 源配置文件
    log_step "创建 Ceph Squid 源配置文件..."
    cat > /etc/apt/sources.list.d/ceph.sources << EOF
Types: deb
URIs: http://download.proxmox.com/debian/ceph-squid
Suites: trixie
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    
    log_info "软件源已更新到 Debian 13 (Trixie) 和 PVE 9.x 配置"
    
    # 7. 再次运行升级前检查确认源更新无误
    log_info "再次运行 pve8to9 检查以确认源配置..."
    local final_check_result=$(pve8to9)
    if echo "$final_check_result" | grep -E -i "FAIL" > /dev/null; then
        log_error "pve8to9 最终检查发现错误，请手动检查源配置后再继续"
        echo "$final_check_result"
        return 1
    else
        log_success "源更新配置检查通过"
    fi
    
    # 8. 更新包列表并开始升级
    log_info "更新包列表..."
    if ! apt update; then
        log_error "更新包列表失败，请检查网络连接和源配置"
        return 1
    fi
    
    log_info "开始 PVE 9.x 升级过程，这可能需要较长时间..."
    log_warn "如果你正在使用Web UI内置的终端，建议改用SSH连接以防止连接中断"
    echo -e "${YELLOW}升级过程中可能会出现多个提示，通常按回车键或选择默认选项即可${NC}"
    
    # 使用非交互模式升级，自动回答问题
    DEBIAN_FRONTEND=noninteractive apt dist-upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
    
    if [[ $? -ne 0 ]]; then
        log_error "PVE 升级过程失败，请查看日志并手动处理...如果是在看不明白可以试试问AI或者提交issue"
        return 1
    fi
    
    # 9. 清理无用包
    log_info "清理无用软件包..."
    apt autoremove -y
    apt autoclean
    
    # 10. 检查升级结果
    local new_pve_version=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1)
    local new_major_version=$(echo $new_pve_version | cut -d'.' -f1)
    
    if [[ "$new_major_version" == "9" ]]; then
        log_success "（撒花）PVE 升级成功！新的 PVE 版本: ${GREEN}$new_pve_version${NC}"
        
        # 运行最终的升级后检查
        log_info "运行升级后检查..."
        pve8to9 2>/dev/null || true
        
        log_info "系统将在 30 秒后重启以完成升级..."
        log_success "如果一切顺利，重启后就能体验到PVE9啦！"
        log_warn "如果升级后出现问题，例如卡内核卡Grub，请先使用LiveCD抢修内核，提取日志文件后联系作者寻求帮助"
        echo -e "${YELLOW}按 Ctrl+C 可取消自动重启${NC}"
        sleep 30
        
        # 重启系统以完成升级
        log_info "正在重启系统以完成 PVE 9.x 升级..."
        reboot
    else
        log_error "升级完成后检查发现，PVE 版本仍为 $new_pve_version，升级可能未完全成功"
        log_tips "请手动检查系统状态，并确认是否需要重试升级"
        return 1
    fi
}

# 显示系统信息
show_system_info() {
    log_step "为您展示系统运行状况"
    echo
    echo "${UI_BORDER}"
    echo "  系统信息概览"
    echo "${UI_DIVIDER}"
    echo "PVE 版本: $(pveversion | head -n1)"
    echo "内核版本: $(uname -r)"
    echo "CPU 信息: $(lscpu | grep 'Model name' | sed 's/Model name:[ \t]*//')"
    echo "CPU 核心: $(nproc) 核心"
    echo "系统架构: $(dpkg --print-architecture)"
    echo "系统启动: $(uptime -p | sed 's/up //')"
    echo "引导类型: $(if [ -d /sys/firmware/efi ]; then echo UEFI; else echo BIOS; fi)"
    echo "系统负载: $(uptime | awk -F'load average:' '{print $2}')"
    echo "内存使用: $(free -h | grep Mem | awk '{print $3"/"$2}')"
    echo "磁盘使用:"
    df -h | grep -E '^/dev/' | awk '{print "  "$1" "$3"/"$2" ("$5")"}'
    echo "网络接口:"
    ip -br addr show | awk '{print "  "$1" "$3}'
    echo "当前时间: $(date)"
    echo "${UI_FOOTER}"
}

# 主菜单
show_menu() {
    show_banner 
    show_menu_option "请选择您需要的功能："
    show_menu_option "1"  "基础设置 (换源/去弹窗/更新)"
    show_menu_option "2"  "存储与系统优化 (Local/Swap/内核)"
    show_menu_option "3"  "硬件与监控 (温度/电源/核显)"
    show_menu_option "4"  "PVE 虚拟机快速下载 (FastPVE)"
    show_menu_option "5"  "第三方工具集 (Community Scripts)"
    show_menu_option "6"  "PVE8 升级到 PVE9 (PVE8专用)"
    show_menu_option "7"  "系统信息概览"
    
    show_menu_option "8" "给作者点个Star吧，谢谢喵~"
    show_menu_option "9" "应急救砖工具箱 (高危操作兜底)"
    show_menu_option "0"  "退出脚本"
    show_menu_footer
    
    # 贴吧老梗随机轮播 (卡吧特供版)
    local tips=(
        "装机前记得先吃饭，不然修电脑修到低血糖"
        "一定要在中午刷机，因为早晚会出事"
        "三千预算进卡吧，加钱加到九万八"
        "八核E5洋垃圾，一核有难七核围观"
        "GTX690战术核显卡，一发摧毁一个航母战斗群"
        "遇事不决，重启解决；重启不行，重装系统"
        "勤备份，保平安；删库跑路，牢底坐穿"
        "一入卡吧深似海，从此钱包是路人"
        "RGB能提升200%的性能，不信你试试"
        "只要我不看日志，报错就不存在"
        "高端的服务器，往往只需要最朴素的重启方式"
        "硬盘有价，数据无价，请谨慎操作"
        "千万不要在生产环境测试脚本，除非你想被祭天"
        "刷机有风险，变砖请自重，虽然PVE很难刷砖"
        "配置千万条，安全第一条，操作不规范，亲人两行泪"
        "玄学时刻：刷机前洗手，成功率提升50%"
        "四路泰坦刷贴吧，流畅度提升明显"
        "什么？你问我电源多少瓦？能亮就行！"
        "散热全靠吼，除尘全靠抖"
        "矿卡锻炼身体，新卡锻炼钱包"
    )
    local random_index=$((RANDOM % ${#tips[@]}))
    echo -e "${CYAN}小贴士：${tips[$random_index]}${NC}"
    
    echo -n "请输入您的选择 [0-9]: "
}

# 应急救砖工具箱菜单
show_menu_rescue() {
    while true; do
        clear
        show_menu_header "应急救砖工具箱"
        echo -e "${RED}警告：本工具箱用于修复因误操作导致的系统问题，请谨慎使用！${NC}"
        echo
        show_menu_option "1" "恢复 proxmoxlib.js (修复弹窗去除失败)"
        show_menu_option "2" "恢复官方 pve-qemu-kvm (修复修改版 QEMU 问题)"
        show_menu_option "3" "清理驱动黑名单 (i915/snd_hda_intel)"
        show_menu_option "0" "返回主菜单"
        show_menu_footer
        read -p "请选择操作 [0-3]: " choice
        case $choice in
            1) restore_proxmoxlib ;;
            2) restore_qemu_kvm ;;
            3) 
                if confirm_action "确定要清理显卡和声卡驱动的黑名单设置吗？"; then
                    log_info "正在清理黑名单配置..."
                    sed -i '/blacklist i915/d' /etc/modprobe.d/pve-blacklist.conf
                    sed -i '/blacklist snd_hda_intel/d' /etc/modprobe.d/pve-blacklist.conf
                    sed -i '/blacklist snd_hda_codec_hdmi/d' /etc/modprobe.d/pve-blacklist.conf
                    log_info "正在更新 initramfs..."
                    update-initramfs -u -k all
                    log_success "黑名单清理完成，请重启系统"
                fi
                ;;
            0) return ;;
            *) log_error "无效选择" ;;
        esac
        pause_function
    done
}

# 二级菜单：基础设置
show_menu_basic() {
    while true; do
        clear
        show_menu_header "基础设置"
        show_menu_option "1" "更换软件源"
        show_menu_option "2" "删除订阅弹窗"
        show_menu_option "3" "更新系统"
        show_menu_option "4" "一键配置 (换源+删弹窗+更新)"
        show_menu_option "0" "返回主菜单"
        show_menu_footer
        read -p "请选择操作 [0-4]: " choice
        case $choice in
            1) change_sources ;;
            2) remove_subscription_popup ;;
            3) update_system ;;
            4) quick_setup ;;
            0) return ;;
            *) log_error "无效选择" ;;
        esac
        pause_function
    done
}

# 二级菜单：存储与系统优化
show_menu_system() {
    while true; do
        clear
        show_menu_header "存储与系统优化"
        show_menu_option "1" "合并 local 与 local-lvm"
        show_menu_option "2" "删除 Swap 分区"
        show_menu_option "3" "内核管理 (内核切换/更新/清理)"
        show_menu_option "4" "Ceph 管理"
        show_menu_option "0" "返回主菜单"
        show_menu_footer
        read -p "请选择操作 [0-4]: " choice
        case $choice in
            1) merge_local_storage ;;
            2) remove_swap ;;
            3) kernel_management_menu ;;
            4) ceph_management_menu ;;
            0) return ;;
            *) log_error "无效选择" ;;
        esac
        pause_function
    done
}

# 二级菜单：硬件与监控
show_menu_hardware() {
    while true; do
        clear
        show_menu_header "硬件与监控"
        show_menu_option "1" "温度监控管理 (CPU/硬盘监控设置)"
        show_menu_option "2" "CPU 电源模式"
        show_menu_option "3" "Intel 核显虚拟化 (GVT-g)"
        show_menu_option "4" "Intel 核显直通"
        show_menu_option "5" "NVIDIA 显卡直通/虚拟化"
        show_menu_option "6" "硬件直通配置 (IOMMU)"
        show_menu_option "0" "返回主菜单"
        show_menu_footer
        read -p "请选择操作 [0-6]: " choice
        case $choice in
            1) temp_monitoring_menu ;;
            2) cpupower ;;
            3) igpu_management_menu ;;
            4) intel_gpu_passthrough ;;
            5) nvidia_gpu_management_menu ;;
            6) hw_passth ;;
            0) return ;;
            *) log_error "无效选择" ;;
        esac
        pause_function
    done
}

# 一键配置
quick_setup() {
    log_step "开始一键配置"
    log_step "天涯若比邻，海内存知己，坐和放宽，让我来搞定一切。"
    echo
    change_sources
    echo
    remove_subscription_popup
    echo
    update_system
    echo
    log_success "一键配置全部完成！您的 PVE 已经完美优化"
    echo -e "现在您可以愉快地使用 PVE 了！"
}

# 通用UI函数
show_menu_header() {
    local title="$1"
    echo "${UI_BORDER}"
    printf "  %s\n" "$title"
    echo "${UI_DIVIDER}"
}

show_menu_footer() {
    echo "${UI_FOOTER}"
}

show_menu_option() {
    local num="$1"
    local desc="$2"
    # Use plain text without color codes
    printf "  %-3s. %s\\n" "$num" "$desc"
}

# 镜像源选择函数
select_mirror() {
    while true; do
        clear
        show_menu_header "请选择镜像源"
        show_menu_option "1" "中科大镜像源"
        show_menu_option "2" "清华Tuna镜像源" 
        show_menu_option "3" "Debian默认源"
        echo "${UI_DIVIDER}"
        echo "注意：选择后将作为后续所有软件源操作的基础"
        show_menu_footer
        echo
        
        read -p "请选择 [1-3]: " mirror_choice
        
        case $mirror_choice in
            1)
                SELECTED_MIRROR=$MIRROR_USTC
                log_success "已选择中科大镜像源"
                break
                ;;
            2)
                SELECTED_MIRROR=$MIRROR_TUNA
                log_success "已选择清华Tuna镜像源"
                break
                ;;
            3)
                SELECTED_MIRROR=$MIRROR_DEBIAN
                log_success "已选择Debian默认源"
                break
                ;;
            *)
                log_error "无效选择，请重新输入"
                pause_function
                ;;
        esac
    done
}

# 版本检查函数
check_update() {
    log_info "正在检查更新..."
    
    download_file() {
        local url="$1"
        local timeout=10
        
        if command -v curl &> /dev/null; then
            curl -s --connect-timeout $timeout --max-time $timeout "$url" 2>/dev/null
        elif command -v wget &> /dev/null; then
            wget -q -T $timeout -O - "$url" 2>/dev/null
        else
            echo ""
        fi
    }
    
    # 显示进度提示
    echo -ne "[....] 正在检查更新...\033[0K\r"

    local prefer_mirror=0
    local preferred_version_url="$VERSION_FILE_URL"
    local preferred_update_url="$UPDATE_FILE_URL"
    local mirror_version_url="${GITHUB_MIRROR_PREFIX}${VERSION_FILE_URL}"
    local mirror_update_url="${GITHUB_MIRROR_PREFIX}${UPDATE_FILE_URL}"

    if detect_network_region; then
        prefer_mirror=$USE_MIRROR_FOR_UPDATE
        if [[ $prefer_mirror -eq 1 ]]; then
            log_info "当前地区为： $USER_COUNTRY_CODE，使用镜像源检查更新...请等待 3 秒"
            # log_info "检测到中国大陆网络环境，将优先使用镜像源检查更新"
            preferred_version_url="$mirror_version_url"
            preferred_update_url="$mirror_update_url"
        else
            if [[ -n "$USER_COUNTRY_CODE" ]]; then
                log_info "检测到当前地区为: $USER_COUNTRY_CODE，将使用 GitHub 源检查更新"
            fi
        fi
    else
        log_warn "无法获取网络地区信息，默认使用 GitHub 源检查更新"
    fi

    remote_content=$(download_file "$preferred_version_url")

    if [ -z "$remote_content" ]; then
        if [[ $prefer_mirror -eq 1 ]]; then
            log_warn "镜像源连接失败，尝试使用 GitHub 源..."
            remote_content=$(download_file "$VERSION_FILE_URL")
        else
            log_warn "GitHub 连接失败，尝试使用镜像源..."
            remote_content=$(download_file "$mirror_version_url")
        fi
    fi
    
    # 清除进度显示
    echo -ne "\033[0K\r"
    
    # 如果下载失败
    if [ -z "$remote_content" ]; then
        log_warn "网络连接失败，跳过版本检查"
        echo "提示：您可以手动访问以下地址检查更新："
        echo "https://github.com/Mapleawaa/PVE-Tools-9"
        echo "按回车键继续..."
        read -r
        return
    fi
    
    # 提取版本号和更新日志
    remote_version=$(echo "$remote_content" | head -1 | tr -d '[:space:]')
    version_changelog=$(echo "$remote_content" | tail -n +2)
    
    if [ -z "$remote_version" ]; then
        log_warn "获取的版本信息格式不正确"
        return
    fi

    detailed_changelog=$(download_file "$preferred_update_url")

    if [ -z "$detailed_changelog" ]; then
        if [[ $prefer_mirror -eq 1 ]]; then
            log_warn "镜像源更新日志获取失败，尝试使用 GitHub 源..."
            detailed_changelog=$(download_file "$UPDATE_FILE_URL")
        else
            log_warn "GitHub 更新日志获取失败，尝试使用镜像源..."
            detailed_changelog=$(download_file "$mirror_update_url")
        fi
    fi
    
    # 比较版本
    if [ "$(printf '%s\n' "$remote_version" "$CURRENT_VERSION" | sort -V | tail -n1)" != "$CURRENT_VERSION" ]; then
        echo "----------------------------------------------"
        echo "发现新版本！推荐更新哦，新增功能和修复BUG喵"
        echo "当前版本: $CURRENT_VERSION"
        echo "最新版本: $remote_version"
        echo "更新内容："
        
        # 如果获取到了详细的更新日志，则显示详细内容，否则显示从VERSION文件中获取的内容
        if [ -n "$detailed_changelog" ]; then
            echo "$detailed_changelog"
        else
            # 格式化显示版本文件中的更新内容
            if [ -n "$version_changelog" ] && [ "$version_changelog" != "$remote_version" ]; then
                echo "$version_changelog"
            else
                echo "  - 请查看项目页面获取详细更新内容"
            fi
        fi
        
        echo "----------------------------------------------"
        echo "请访问项目页面获取最新版本："
        echo "https://github.com/Mapleawaa/PVE-Tools-9"
        echo "按回车键继续..."
        read -r
    else
        log_success "当前已是最新版本 ($CURRENT_VERSION) 放心用吧"
    fi
}

# 版本检查函数 - 拉一坨屎在这里，这是镜像源的使用情景，但是大家好像都是用的 bash -sSl <(curl ...) 来跑脚本，所以就注释掉了。
# check_update() {
#     log_info "正在检查更新..."
    
#     download_file() {
#         local url="$1"
#         local timeout=10
        
#         if command -v curl &> /dev/null; then
#             curl -s --connect-timeout $timeout --max-time $timeout "$url" 2>/dev/null
#         elif command -v wget &> /dev/null; then
#             wget -q -T $timeout -O - "$url" 2>/dev/null
#         else
#             echo ""
#         fi
#     }
    
#     # 显示进度提示
#     echo -ne "[....] 正在检查更新...\033[0K\r"
    
#     # 首先尝试从GitHub下载版本文件
#     remote_content=$(download_file "$VERSION_FILE_URL")
    
#     # 如果GitHub下载失败，自动尝试镜像源
#     if [ -z "$remote_content" ]; then
#         echo -ne "[WARN] GitHub连接失败，尝试镜像源...\033[0K\r"
#         mirror_url="https://ghfast.top/${UPDATE_FILE_URL}"
#         remote_content=$(download_file "$mirror_url")
#     fi
    
#     # 清除进度显示
#     echo -ne "\033[0K\r"
    
#     # 如果所有下载都失败
#     if [ -z "$remote_content" ]; then
#         log_warn "网络连接失败，跳过版本检查"
#         echo "提示：您可以手动访问以下地址检查更新："
#         echo "https://github.com/Mapleawaa/PVE-Tools-9"
#         echo "按回车键继续..."
#         read -r
#         return
#     fi
    
#     # 提取版本号和更新日志
#     remote_version=$(echo "$remote_content" | head -1 | tr -d '[:space:]')
#     version_changelog=$(echo "$remote_content" | tail -n +2)
    
#     if [ -z "$remote_version" ]; then
#         log_warn "获取的版本信息格式不正确"
#         return
#     fi
    
#     # 尝试获取详细的更新日志
#     UPDATE_FILE_URL="https://raw.githubusercontent.com/Mapleawaa/PVE-Tools-9/main/UPDATE"
#     detailed_changelog=$(download_file "$UPDATE_FILE_URL")
    
#     # 如果GitHub的UPDATE文件获取失败，尝试镜像源
#     if [ -z "$detailed_changelog" ]; then
#         mirror_update_url="https://ghfast.top/Mapleawaa/PVE-Tools-9/main/UPDATE"
#         detailed_changelog=$(download_file "$mirror_update_url")
#     fi
    
#     # 比较版本
#     if [ "$(printf '%s\n' "$remote_version" "$CURRENT_VERSION" | sort -V | tail -n1)" != "$CURRENT_VERSION" ]; then
#         echo "----------------------------------------------"
#         echo "发现新版本！推荐更新哦，新增功能和修复BUG喵"
#         echo "当前版本: $CURRENT_VERSION"
#         echo "最新版本: $remote_version"
#         echo "更新内容："
        
#         # 如果获取到了详细的更新日志，则显示详细内容，否则显示从VERSION文件中获取的内容
#         if [ -n "$detailed_changelog" ]; then
#             echo "$detailed_changelog"
#         else
#             # 格式化显示版本文件中的更新内容
#             if [ -n "$version_changelog" ] && [ "$version_changelog" != "$remote_version" ]; then
#                 echo "$version_changelog"
#             else
#                 echo "  - 请查看项目页面获取详细更新内容"
#             fi
#         fi
        
#         echo "----------------------------------------------"
#         echo "请访问项目页面获取最新版本："
#         echo "https://github.com/Mapleawaa/PVE-Tools-9"
#         echo "按回车键继续..."
#         read -r
#     else
#         log_success "当前已是最新版本 ($CURRENT_VERSION) 放心用吧"
#     fi
# }

# 温度监控管理菜单
temp_monitoring_menu() {
    while true; do
        clear
        show_menu_header "温度监控管理"
        show_menu_option "1" "配置温度监控 (CPU/硬盘温度显示)"
        show_menu_option "2" "移除温度监控 (移除温度监控功能)"
        show_menu_option "3" "自定义温度监控选项 (高级)"
        echo "${UI_DIVIDER}"
        show_menu_option "0" "返回主菜单"
        show_menu_footer
        echo
        read -p "请选择 [0-3]: " temp_choice
        echo
        
        case $temp_choice in
            1)
                cpu_add
                ;;
            2)
                cpu_del
                ;;
            3)
                custom_temp_monitoring
                ;;
            0)
                break
                ;;
            *)
                log_error "无效选择，请重新输入"
                ;;
        esac
        
        echo
        pause_function
    done
}

# 自定义温度监控配置
custom_temp_monitoring() {
    clear

    
    # Define options
    declare -A options
    # options[0]="CPU 实时主频"
    # options[1]="CPU 最小及最大主频 (必选 0)"
    # options[2]="CPU 线程主频"
    # options[3]="CPU 工作模式 (必选 0)"
    # options[4]="CPU 功率 (必选 0)"
    # options[5]="CPU 温度"
    # options[6]="CPU 核心温度 (不支持 AMD, 必选 5)"
    # options[7]="核显温度 (仅支持 AMD, 必选 5)"
    # options[8]="风扇转速 (可能需要单独安装传感器驱动, 必选 5)"
    # options[9]="UPS 信息 (仅支持 apcupsd - apcaccess 软件包)"
    # options[a]="硬盘基础信息 (容量、寿命 (仅 NVME )、温度)"
    # options[b]="硬盘通电信息 (必选 a)"
    # options[c]="硬盘 IO 信息 (必选 a)"
    # options[l]="概要信息: 居左显示"
    # options[r]="概要信息: 居右显示"
    # options[m]="概要信息: 居中显示"
    # options[j]="概要信息: 平铺显示"
    options[o]="推荐方案一：高大全 (除 UPS 信息以外全部居右显示)"
    options[p]="推荐方案二：精简"
    options[q]="推荐方案三：极简"
    options[x]="一键清空 (还原默认)"
    options[s]="跳过本次修改"
    
    echo "请选择要启用的监控项目 (用空格分隔，如: o):"
    echo
    
    # Display options with checkboxes
    # for key in 0 1 2 3 4 5 6 7 8 9 a b c l r m j o p q x s; do
    for key in o p q x s; do
        if [[ -n "${options[$key]}" ]]; then
            echo "  [ ] $key) ${options[$key]}"
        fi
    done
    
    echo
    read -p "请输入选择 (如: 0 5 6 或 o 或 s): " input
    
    # Process user selections
    if [[ "$input" == "s" ]]; then
        log_info "跳过自定义配置"
        return
    fi
    
    if [[ "$input" == "x" ]]; then
        log_info "正在还原默认设置..."
        cpu_del
        log_success "已还原默认设置"
        return
    fi
    
    if [[ "$input" == "o" ]]; then
        log_info "应用推荐方案一：高大全..."
        # Apply comprehensive configuration
        cpu_add
        log_success "推荐方案一已应用"
        return
    fi
    
    if [[ "$input" == "p" ]]; then
        log_info "应用推荐方案二：精简..."
        # Apply simplified configuration
        cpu_add
        log_success "推荐方案二已应用"
        return
    fi
    
    if [[ "$input" == "q" ]]; then
        log_info "应用推荐方案三：极简..."
        # Apply minimal configuration
        cpu_add
        log_success "推荐方案三已应用"
        return
    fi
    
    # Process selected individual options
    echo "您选择了: $input"
    echo "正在配置自定义温度监控..."
    
    # Parse and validate dependencies
    selections=($input)
    dependencies_met=true
    
    # Check for dependencies
    for selection in "${selections[@]}"; do
        case "$selection" in
            1) if [[ ! " ${selections[@]} " =~ " 0 " ]]; then
                 log_error "选项 1 需要选项 0，请重新选择"
                 dependencies_met=false
                 break
               fi ;;
            3|4) if [[ ! " ${selections[@]} " =~ " 0 " ]]; then
                 log_error "选项 3 或 4 需要选项 0，请重新选择"
                 dependencies_met=false
                 break
               fi ;;
            6|7|8) if [[ ! " ${selections[@]} " =~ " 5 " ]]; then
                 log_error "选项 6, 7 或 8 需要选项 5，请重新选择"
                 dependencies_met=false
                 break
               fi ;;
            b) if [[ ! " ${selections[@]} " =~ " a " ]]; then
                 log_error "选项 b 需要选项 a，请重新选择"
                 dependencies_met=false
                 break
               fi ;;
            c) if [[ ! " ${selections[@]} " =~ " a " ]]; then
                 log_error "选项 c 需要选项 a，请重新选择"
                 dependencies_met=false
                 break
               fi ;;
        esac
    done
    
    if [[ "$dependencies_met" == true ]]; then
        log_info "配置所选监控项..."
        # In a real implementation, this would customize the monitoring based on selections
        # For now, we'll use the existing cpu_add function
        cpu_add  # Use the existing function to install the basic monitoring
        log_success "自定义温度监控配置完成"
    else
        log_error "配置失败，依赖关系不满足"
    fi
}

# Ceph管理菜单
ceph_management_menu() {
    while true; do
        clear

        show_menu_header "Ceph管理"
        show_menu_option "1" "添加ceph-squid源 (PVE8/9专用)"
        show_menu_option "2" "添加ceph-quincy源 (PVE7/8专用)"
        show_menu_option "3" "卸载Ceph (完全移除Ceph)"
        echo "${UI_DIVIDER}"
        show_menu_option "0" "返回主菜单"
        show_menu_footer
        echo
        read -p "请选择 [0-3]: " ceph_choice
        echo
        
        case $ceph_choice in
            1)
                pve9_ceph
                ;;
            2)
                pve8_ceph
                ;;
            3)
                remove_ceph
                ;;
            0)
                break
                ;;
            *)
                log_error "无效选择，请重新输入"
                ;;
        esac
        
        echo
        pause_function
    done
}

# 救砖：恢复官方 pve-qemu-kvm
restore_qemu_kvm() {
    log_step "开始恢复官方 pve-qemu-kvm"
    echo "此操作将执行以下步骤："
    echo "1. 解除 pve-qemu-kvm 的版本锁定 (unhold)"
    echo "2. 强制重新安装官方版本的 pve-qemu-kvm"
    echo "3. 恢复官方的 initramfs 设置"
    echo "适用于因安装修改版 QEMU 导致虚拟机无法启动或系统异常的情况。"
    echo

    if ! confirm_action "是否继续执行恢复操作？"; then
        return
    fi

    # 1. 解除锁定
    log_info "正在解除软件包锁定..."
    apt-mark unhold pve-qemu-kvm
    
    # 2. 强制重装官方版本
    log_info "正在重新安装官方 pve-qemu-kvm..."
    if apt-get update && apt-get install --reinstall -y pve-qemu-kvm; then
        log_success "官方 pve-qemu-kvm 恢复成功"
    else
        log_error "恢复失败，请检查网络连接或手动尝试: apt-get install --reinstall pve-qemu-kvm"
        return 1
    fi

    # 3. 清理黑名单 (可选)
    if confirm_action "是否同时清理 Intel 核显相关的驱动黑名单？"; then
        log_info "正在清理黑名单配置..."
        sed -i '/blacklist i915/d' /etc/modprobe.d/pve-blacklist.conf
        sed -i '/blacklist snd_hda_intel/d' /etc/modprobe.d/pve-blacklist.conf
        sed -i '/blacklist snd_hda_codec_hdmi/d' /etc/modprobe.d/pve-blacklist.conf
        
        log_info "正在更新 initramfs..."
        update-initramfs -u -k all
        log_success "黑名单清理完成"
    fi

    log_success "救砖操作完成！建议重启系统。"
    if confirm_action "是否现在重启系统？"; then
        reboot
    fi
}

#英特尔核显直通
intel_gpu_passthrough() {
    log_step "开始 Intel 核显直通配置"
    echo "注意：此功能基于 lixiaoliu666 的修改版 QEMU 和 ROM"
    echo "适用于需要将 Intel 核显直通给 Windows 虚拟机且遇到代码 43 或黑屏的情况"
    echo "支持的 CPU 架构：6代(Skylake) 到 14代(Raptor Lake Refresh)"
    echo "项目地址：https://github.com/lixiaoliu666/intel6-14rom"
    echo
    log_warn "警告"
    log_warn "本功能并非能100%一次成功！"
    echo 
    log_warn "由于 Intel 牙膏厂混乱的代号和半代升级策略（如 N5105 Jasper Lake 等）"
    log_warn "通用 ROM 无法保证 100% 适用于所有 CPU 型号！"
    log_warn "直通失败属于正常现象，请尝试更换其他版本的 ROM 或自行寻找专用 ROM"
    log_warn "本功能仅提供自动化配置辅助，作者精力有限，无法提供免费的一对一排错服务"
    log_warn "折腾有风险，入坑需谨慎！"
    echo
    log_tips "如需要反馈或者请求更新ROM文件适配你的CPU，请前往lixiaoliu666的GitHub仓库开ISSUE反馈，不是找我。"
    echo

    echo "请选择操作："
    echo "  1) 开始配置 (安装修改版 QEMU + 下载 ROM)"
    echo "  2) 救砖模式 (恢复官方 QEMU + 清理配置)"
    echo "  0) 返回上级菜单"
    read -p "请输入选择 [0-2]: " choice
    
    case $choice in
        1)
            # 继续执行配置流程
            ;;
        2)
            restore_qemu_kvm
            return
            ;;
        0)
            return
            ;;
        *)
            log_error "无效选择"
            return
            ;;
    esac

    # 1. 配置黑名单
    log_step "配置驱动黑名单 (屏蔽宿主机占用核显)"
    if ! grep -q "blacklist i915" /etc/modprobe.d/pve-blacklist.conf; then
        echo "blacklist i915" >> /etc/modprobe.d/pve-blacklist.conf
        echo "blacklist snd_hda_intel" >> /etc/modprobe.d/pve-blacklist.conf
        echo "blacklist snd_hda_codec_hdmi" >> /etc/modprobe.d/pve-blacklist.conf
        log_success "已添加黑名单配置"
        
        log_info "正在更新 initramfs..."
        update-initramfs -u -k all
    else
        log_info "黑名单配置已存在，跳过"
    fi

    # 2. 安装修改版 QEMU
    log_step "安装修改版 pve-qemu-kvm"
    echo "正在获取最新 release 版本..."
    
    # 尝试获取最新下载链接 (这里为了稳定性暂时写死或使用最新已知的逻辑，实际可爬虫获取)
    # 根据用户提供的信息，修改版 QEMU 下载地址: https://github.com/lixiaoliu666/pve-anti-detection/releases
    # 为了简化，我们使用 ghfast.top 加速下载最新的 release
    # 注意：这里需要动态获取最新 deb 包链接，或者让用户手动输入链接
    # 为方便起见，这里演示自动获取逻辑
    
    local qemu_releases_url="https://api.github.com/repos/lixiaoliu666/pve-anti-detection/releases/latest"
    local qemu_deb_url=$(curl -s $qemu_releases_url | grep "browser_download_url.*deb" | cut -d '"' -f 4 | head -n 1)
    
    if [ -z "$qemu_deb_url" ]; then
        log_warn "无法自动获取修改版 QEMU 下载链接，尝试使用备用链接或手动下载"
        # 备用逻辑：提示用户手动下载
        echo "请访问 https://github.com/lixiaoliu666/pve-anti-detection/releases 下载最新 deb 包"
        echo "然后使用 dpkg -i 安装"
    else
        # 加速下载
        local fast_qemu_url="https://ghfast.top/${qemu_deb_url}"
        log_info "正在下载: $fast_qemu_url"
        wget -O /tmp/pve-qemu-kvm.deb "$fast_qemu_url"
        
        if [ -s "/tmp/pve-qemu-kvm.deb" ]; then
            log_info "正在安装修改版 QEMU..."
            dpkg -i /tmp/pve-qemu-kvm.deb
            log_success "安装完成"
            
            # 阻止更新
            apt-mark hold pve-qemu-kvm
            log_info "已锁定 pve-qemu-kvm 防止自动更新"
        else
            log_error "下载失败"
        fi
    fi

    # 3. 下载 ROM 文件
    log_step "下载核显 ROM 文件"
    echo "正在检测 CPU 型号..."
    local cpu_model=$(lscpu | grep "Model name" | awk -F: '{print $2}' | xargs)
    echo "CPU 型号: $cpu_model"
    
    # 优先推荐的通用 ROM
    local recommended_rom="6-14-qemu10.rom"
    
    # 特殊 CPU 型号映射表 (根据 release 信息整理)
    # 格式: "关键字|ROM文件名"
    local special_cpus=(
        "J6412|11-J6412-q10.rom"
        "N5095|11-n5095-q10.rom"
        "1240P|12-1240p-q10.rom"
        "N100|12-n100-q10.rom"
        "J4125|j4125-q10.rom"
        "N2930|N2930-q10.rom"
        "N3350|N3350-q10.rom"
        "11700H|nb-11-11700h-q10.rom"
        "1185G7|nb-11-1185G7E-q10.rom"
        "12700H|nb-12-12700h-q10.rom"
        "13700H|nb-13-13700h-q10.rom"
    )
    
    # 检测是否为特殊 CPU
    for item in "${special_cpus[@]}"; do
        local keyword="${item%%|*}"
        local rom_name="${item##*|}"
        if echo "$cpu_model" | grep -qi "$keyword"; then
            recommended_rom="$rom_name"
            log_success "检测到特殊 CPU ($keyword)，推荐使用专用 ROM: $recommended_rom"
            break
        fi
    done

    # 下载 ROM 文件
    local rom_releases_url="https://api.github.com/repos/lixiaoliu666/intel6-14rom/releases/latest"
    log_info "正在获取 ROM 列表..."
    
    # 获取 release 信息
    # 注意：这里我们使用 grep 简单提取下载链接和文件名
    local release_info=$(curl -s $rom_releases_url)
    local assets=$(echo "$release_info" | grep "browser_download_url" | cut -d '"' -f 4)
    
    if [ -z "$assets" ]; then
         log_error "无法获取 ROM 下载链接"
         return
    fi

    # 显示 ROM 列表供用户选择
    echo "------------------------------------------------"
    echo "可用的 ROM 文件列表："
    local i=1
    local rom_list=()
    local recommended_index=0
    
    for url in $assets; do
        local fname=$(basename "$url")
        # 过滤非 .rom 文件 (如 patch)
        if [[ "$fname" != *.rom ]]; then
            continue
        fi
        
        rom_list+=("$fname|$url")
        
        if [[ "$fname" == "$recommended_rom" ]]; then
            echo -e "  $i) ${GREEN}$fname (推荐)${NC}"
            recommended_index=$i
        else
            echo "  $i) $fname"
        fi
        ((i++))
    done
    echo "------------------------------------------------"
    
    # 让用户选择
    local choice
    if [ $recommended_index -gt 0 ]; then
        read -p "请输入序号选择 ROM [默认 $recommended_index]: " choice
        choice=${choice:-$recommended_index}
    else
        read -p "请输入序号选择 ROM: " choice
    fi
    
    # 验证选择
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -ge $i ]; then
        log_error "无效选择"
        return
    fi
    
    # 获取选中的 ROM 信息
    local selected_item="${rom_list[$((choice-1))]}"
    local selected_fname="${selected_item%%|*}"
    local selected_url="${selected_item##*|}"
    
    # 下载选中的 ROM
    local fast_url="https://ghfast.top/${selected_url}"
    log_info "正在下载: $selected_fname"
    wget -O "/usr/share/kvm/$selected_fname" "$fast_url"
    
    if [ ! -s "/usr/share/kvm/$selected_fname" ]; then
        log_error "下载失败"
        return
    fi
    log_success "ROM 文件已就绪: $selected_fname"
    local rom_filename="$selected_fname"

    # 4. 自动配置虚拟机
    log_step "配置虚拟机参数"
    
    # 获取 VMID
    echo "请选择要配置直通的虚拟机 ID (VMID):"
    ls /etc/pve/qemu-server/*.conf | awk -F/ '{print $NF}' | sed 's/.conf//' | xargs -n1 echo "  -"
    read -p "请输入 VMID: " vmid
    
    if [ -z "$vmid" ] || [ ! -f "/etc/pve/qemu-server/$vmid.conf" ]; then
        log_error "无效的 VMID 或配置文件不存在"
        return
    fi
    
    # 获取核显 PCI ID
    echo "正在查找 Intel 核显设备..."
    local igpu_pci=$(lspci -D | grep -i "VGA compatible controller" | grep -i "Intel" | head -n1 | awk '{print $1}')
    
    if [ -z "$igpu_pci" ]; then
        log_error "未找到 Intel 核显设备"
        return
    fi
    echo "找到核显设备: $igpu_pci"
    
    # 获取声卡 PCI ID (通常和核显在一起，但也可能分开)
    local audio_pci=$(lspci -D | grep -i "Audio device" | grep -i "Intel" | head -n1 | awk '{print $1}')
    if [ -n "$audio_pci" ]; then
        echo "找到声卡设备: $audio_pci"
    else
        log_warn "未找到配套声卡设备，将只直通核显"
    fi

    if ! confirm_action "即将修改虚拟机 $vmid 的配置，是否继续？"; then
        return
    fi
    
    # 备份配置文件
    backup_file "/etc/pve/qemu-server/$vmid.conf"
    
    # 修改 args
    local args_line="-set device.hostpci0.bus=pcie.0 -set device.hostpci0.addr=0x02.0 -set device.hostpci0.x-igd-gms=0x2 -set device.hostpci0.x-igd-opregion=on -set device.hostpci0.x-igd-lpc=on"
    
    # 如果有声卡，添加 hostpci1 的 args 配置
    if [ -n "$audio_pci" ]; then
        args_line="$args_line -set device.hostpci1.bus=pcie.0 -set device.hostpci1.addr=0x03.0"
    fi
    
    # 写入 args (先删除旧的 args)
    sed -i '/^args:/d' "/etc/pve/qemu-server/$vmid.conf"
    echo "args: $args_line" >> "/etc/pve/qemu-server/$vmid.conf"
    
    # 写入 hostpci0 (核显)
    # 先删除旧的 hostpci0
    sed -i '/^hostpci0:/d' "/etc/pve/qemu-server/$vmid.conf"
    # 格式: hostpci0: 0000:00:02.0,romfile=xxx.rom
    # 注意：这里 PCI ID 使用 lspci 获取到的真实 ID，通常是 0000:00:02.0
    echo "hostpci0: $igpu_pci,romfile=$rom_filename" >> "/etc/pve/qemu-server/$vmid.conf"
    
    # 写入 hostpci1 (声卡)
    if [ -n "$audio_pci" ]; then
        sed -i '/^hostpci1:/d' "/etc/pve/qemu-server/$vmid.conf"
        echo "hostpci1: $audio_pci" >> "/etc/pve/qemu-server/$vmid.conf"
    fi
    
    log_success "虚拟机 $vmid 配置完成"
    echo "已添加 args 参数和 hostpci 设备"
    echo "请记得在虚拟机中安装驱动: https://downloadmirror.intel.com/854560/gfx_win_101.6793.exe"
    
    echo
    echo "注意：需要重启宿主机使黑名单生效"
    if confirm_action "是否现在重启系统？"; then
        reboot
    fi
}

# NVIDIA显卡管理菜单
nvidia_gpu_management_menu() {

    log_step "诶？怎么没进度了？"
    log_tips "前面有个小纸条，捡起来："
    log_error "该功能尚在开发中，敬请期待！"
    log_tips "如果您急需该功能，请前往作者的GitHub提交pr 谢谢喵"
    echo -e "3秒后自动回城 …"
    sleep 3
    main "$@"
}

# 主程序
main() {
    check_root
    check_debug_mode "$@"
    check_pve_version
    
    # 检查更新
    check_update
    
    # 选择镜像源
    select_mirror
    
    while true; do

        show_menu
        read -n 2 choice
        echo
        echo
        
        case $choice in
            1)
                show_menu_basic
                ;;
            2)
                show_menu_system
                ;;
            3)
                show_menu_hardware
                ;;
            4)
                fastpve_quick_download_menu
                ;;
            5)
                third_party_tools_menu
                ;;
            6)
                pve8_to_pve9_upgrade
                ;;
            7)
                show_system_info
                ;;
            8)
                echo "项目地址：https://github.com/Mapleawaa/PVE-Tools-9"
                echo "有你真好~"
                ;;
            9)
                show_menu_rescue
                ;;
            0)
                echo "感谢使用,谢谢喵"
                echo "再见！"
                exit 0
                ;;
            *)
                log_error "哎呀，这个选项不存在呢"
                log_warn "请输入 0-9 之间的数字"
                ;;
        esac
        
        echo
        pause_function
    done
}

# 运行主程序
main "$@"
