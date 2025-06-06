#!/bin/bash

# 定义节点ID文件路径
PROVER_ID_FILE="/root/.nexus/node-id"

# 脚本保存路径
SCRIPT_PATH="$HOME/nexus.sh"

# 定义颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 启动节点函数
function start_node() {
    # 安装 Nexus CLI
    echo "正在下载并安装 Nexus CLI..."
    if ! curl -sSL https://cli.nexus.xyz/ | sh; then
        echo "Nexus CLI 安装失败，请检查网络连接或脚本源。"
        exit 1
    fi

    # 重新加载环境变量
    echo "正在加载 Rust 环境..."
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
        export PATH="$HOME/.cargo/bin:$PATH"
    else
        echo "警告：未找到 $HOME/.cargo/env 文件，Rust 环境可能未正确安装。"
    fi

    # 加载 .bashrc 文件
    echo "正在加载 .bashrc 文件..."
    if [ -f "/root/.bashrc" ]; then
        source "/root/.bashrc"
    elif [ -f "/home/ubuntu/.bashrc" ]; then
        source "/home/ubuntu/.bashrc"
    else
        echo "警告：未找到 /root/.bashrc 或 /home/ubuntu/.bashrc 文件，跳过加载。"
    fi

    # 提示用户输入 node-id
    echo "请输入您的 node-id："
    read -r NODE_ID

    # 验证 node-id 是否为空
    if [ -z "$NODE_ID" ]; then
        echo "错误：node-id 不能为空，请重新运行脚本并输入有效的 node-id。"
        exit 1
    fi

    # 保存 node-id 到文件
    echo "$NODE_ID" > "$PROVER_ID_FILE"
    echo "node-id 已保存到 $PROVER_ID_FILE"

    # 使用 screen 在后台启动 nexus-network
    echo "正在使用 screen 在后台启动 nexus-network..."
    if ! command -v screen >/dev/null 2>&1; then
        echo "错误：未找到 screen 命令，正在尝试安装..."
        apt-get update && apt-get install -y screen || {
            echo "安装 screen 失败，请手动安装 screen 后重试。"
            exit 1
        }
    fi

    # 终止已存在的 nexus screen 会话（防止重复）
    screen -S nexus -X quit >/dev/null 2>&1

    # 启动 screen 会话并运行 nexus-network
    screen -dmS nexus bash -c "nexus-network start --node-id $NODE_ID"
    if [ $? -eq 0 ]; then
        echo "nexus-network 已成功在 screen 会话 'nexus' 中后台启动。"
        echo "您可以使用 'screen -r nexus' 查看运行状态。"
    else
        echo "错误：无法启动 nexus-network，请检查 node-id 或 nexus-network 命令。"
        exit 1
    fi

    echo "节点已在后台成功启动！"
    echo "你可以使用 'screen -r nexus' 命令查看节点状态。"
    read -p "按任意键返回主菜单"
}

# 显示 ID 的函数
function show_id() {
    if [ -f "$PROVER_ID_FILE" ]; then
        echo "Prover ID 内容:"
        echo "$(<"$PROVER_ID_FILE")"
    else
        echo "文件 $PROVER_ID_FILE 不存在。"
    fi
    read -p "按任意键返回主菜单"
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
        echo "3. 退出"
        
        read -p "请输入选项 (1-3): " choice
        
        case $choice in
            1)
                start_node
                ;;
            2)
                show_id
                ;;
            3)
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效选项，请重新选择。"
                read -p "按任意键返回主菜单"
                ;;
        esac
    done
}

# 调用主菜单函数
main_menu
