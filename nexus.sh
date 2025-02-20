#!/bin/bash

# 定义服务名称和文件路径
SERVICE_NAME="nexus"
SERVICE_FILE="/etc/systemd/system/nexus.service"

# 定义节点ID文件路径
PROVER_ID_FILE="/root/.nexus/node-id"

# 脚本保存路径
SCRIPT_PATH="$HOME/nexus.sh"

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 检查是否安装了tmux命令
function check_tmux() {
    if ! command -v tmux &> /dev/null; then
        echo "未检测到 tmux 命令，正在安装..."
        sudo apt install -y tmux
        if ! command -v tmux &> /dev/null; then
            echo "安装 tmux 失败，请手动安装后再试。"
            exit 1
        else
            echo "tmux 安装成功。"
        fi
    else
        echo "检测到 tmux 已安装。"
    fi
}

# 主菜单函数
function main_menu() {
    while true; do
        clear
        echo "脚本由大赌社区哈哈哈哈编写，推特 @ferdie_jhovie，免费开源，请勿相信收费"
        echo "如有问题，可联系推特，仅此只有一个号"
        echo "新建了一个电报群，方便大家交流：t.me/Sdohua"
        echo "================================================================"
        echo "退出脚本，请按键盘 ctrl + C 退出即可"
        echo "请选择要执行的操作:"
        echo "1. 启动节点"
        echo "2. 显示 ID" 
        echo "3. 更改 ID"
        echo "4) 退出"
        
        read -p "请输入选项 (1-4): " choice
        
        case $choice in
            1)
                start_node
                ;;
            2)
                show_id
                ;;
            3)
                set_prover_id
                ;;
            4)
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效选项，请重新选择。"
                ;;
        esac
    done
}

# 显示 ID 的函数
function show_id() {
    if [ -f /root/.nexus/node-id ]; then
        echo "Prover ID 内容:"
        echo "$(</root/.nexus/node-id)"
    else
        echo "文件 /root/.nexus/node-id 不存在。"
    fi
    read -p "按任意键返回主菜单"
}

# 设置节点ID的函数
function set_prover_id() {
    read -p "请输入新的节点ID: " new_id
    if [ -n "$new_id" ]; then
        echo "$new_id" > "$PROVER_ID_FILE"
        echo -e "${GREEN}节点ID已成功更新为: $new_id${NC}"
    else
        echo -e "${RED}错误：节点ID不能为空${NC}"
    fi
}

# 启动节点的函数
function start_node() {
    # 检查是否有名为 nexus 的 tmux 会话，如果存在，则删除
    if tmux has-session -t nexus 2>/dev/null; then
        echo "检测到已存在的 'nexus' tmux 会话，正在删除..."
        tmux kill-session -t nexus
        echo "'nexus' tmux 会话已成功删除。"
    fi

    # 更新系统和安装必要组件
    echo "正在更新系统并安装必要组件..."
    if ! sudo apt update && sudo apt upgrade -y && sudo apt install -y build-essential pkg-config libssl-dev git-all protobuf-compiler curl unzip; then
        echo "安装基础组件失败"
        exit 1
    fi

    # 检查并安装tmux
    check_tmux

    # 安装 Rust
    echo "正在安装 Rust..."
    if ! curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
        echo "Rust 安装失败"
        exit 1
    fi

    # 重新加载环境变量
    echo "正在加载 Rust 环境..."
    source $HOME/.cargo/env
    export PATH="$HOME/.cargo/bin:$PATH"

    # 验证 Rust 安装
    if command -v rustc &> /dev/null; then
        echo "Rust 安装成功，当前版本: $(rustc --version)"
    else
        echo "Rust 环境加载失败"
        exit 1
    fi

    # 安装额外的依赖
    echo "正在安装额外的依赖..."
    if ! sudo apt install -y libudev-dev liblzma-dev unzip; then
        echo "安装额外依赖失败"
        exit 1
    fi

    # 下载并安装 protoc
    echo "正在下载并安装 protoc..."
    PROTOC_VERSION="3.15.0"  # 设置所需的版本
    curl -LO "https://github.com/protocolbuffers/protobuf/releases/download/v$PROTOC_VERSION/protoc-$PROTOC_VERSION-linux-x86_64.zip"
    
    # 检查下载是否成功
    if [ ! -f "protoc-$PROTOC_VERSION-linux-x86_64.zip" ]; then
        echo "protoc 下载失败"
        exit 1
    fi

    # 解压 protoc
    if ! unzip "protoc-$PROTOC_VERSION-linux-x86_64.zip" -d protoc3; then
        echo "解压 protoc 失败"
        exit 1
    fi

    # 安装 protoc
    if [ -d "protoc3/bin" ]; then
        sudo mv protoc3/bin/protoc /usr/local/bin/
    else
        echo "protoc 二进制文件不存在"
        exit 1
    fi

    if [ -d "protoc3/include" ]; then
        sudo mv protoc3/include/* /usr/local/include/
    else
        echo "protoc include 文件不存在"
        exit 1
    fi

    # 清理临时文件
    rm -rf protoc3 "protoc-$PROTOC_VERSION-linux-x86_64.zip"

    # 检查 protoc 是否安装成功
    if ! command -v protoc &> /dev/null; then
        echo "protoc 安装失败"
        exit 1
    else
        echo "protoc 安装成功，版本: $(protoc --version)"
    fi

    # 在 tmux 会话中运行安装和启动命令
    echo "正在创建 tmux 会话并运行节点..."
    tmux new-session -d -s nexus 'curl https://cli.nexus.xyz/ | sh'

    echo "节点启动成功！节点正在后台运行。"
    echo "使用 'tmux attach -t nexus' 命令可以查看节点运行状态"
    read -p "按任意键返回主菜单"
}

# 调用主菜单函数
main_menu
