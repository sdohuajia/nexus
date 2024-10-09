#!/bin/bash

# 自定义状态显示函数
show_status() {
    local message="$1"
    local status="$2"
    case $status in
        "error")
            echo -e "${RED}${BOLD}🚫 出错: ${message}${NORMAL}"
            ;;
        "progress")
            echo -e "${YELLOW}${BOLD}🔄 进行中: ${message}${NORMAL}"
            ;;
        "success")
            echo -e "${GREEN}${BOLD}✅ 成功: ${message}${NORMAL}"
            ;;
        *)
            echo -e "${PINK}${BOLD}${message}${NORMAL}"
            ;;
    esac
}

# 定义服务名称和文件路径
SERVICE_NAME="nexus"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

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
        echo "2. 查看 Prover 状态"
        echo "3. 查看日志"
        echo "4. 删除节点"
        echo "5. 退出"
        
        read -p "请输入选项 (1-5): " choice
        
        case $choice in
            1)
                start_node  # 调用启动节点函数
                ;;
            2)
                check_prover_status  # 调用查看 Prover 状态函数
                ;;
            3)
                view_logs  # 调用查看日志函数
                ;;
            4)
                delete_node  # 调用删除节点函数
                ;;
            5)
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效选项，请重新选择。"
                ;;
        esac
    done
}

# 启动节点的函数
function start_node() {
    # 检查并安装 Git
    if ! command -v git &> /dev/null; then
        echo "Git 未安装。正在安装 Git..."
        if ! sudo apt install git -y; then
            echo "安装 Git 失败。"  # 错误信息
            exit 1
        fi
    else
        echo "Git 已安装。"  # 成功信息
    fi

    # 检查 Rust 是否已安装
    if command -v rustc &> /dev/null; then
        echo "Rust 已安装，版本为: $(rustc --version)"
    else
        echo "Rust 未安装，正在安装 Rust..."
        # 使用 rustup 安装 Rust
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
        echo "Rust 安装完成。"
        
        # 加载 Rust 环境
        source $HOME/.cargo/env
        echo "Rust 环境已加载。"
    fi

    # 克隆指定的 GitHub 仓库
    echo "正在克隆仓库..."
    git clone https://github.com/nexus-xyz/network-api.git

    # 安装依赖项
    cd $HOME/network-api/clients/cli
    show_status "安装所需的依赖项..." "progress"
    if ! sudo apt install pkg-config libssl-dev -y; then
        show_status "安装依赖项失败。" "error"
        exit 1
    fi

    # 创建 systemd 服务文件
    show_status "创建 systemd 服务..." "progress"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"  # 定义服务文件路径
    if ! sudo bash -c "cat > $SERVICE_FILE <<EOF
[Unit]
Description=Nexus XYZ Prover Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/network-api/clients/cli
Environment=NONINTERACTIVE=1
ExecStart=$HOME/.cargo/bin/cargo run --release --bin prover -- beta.orchestrator.nexus.xyz
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"; then
        show_status "创建 systemd 服务文件失败。" "error"
        exit 1
    fi

    # 重新加载 systemd 并启动服务
    show_status "重新加载 systemd 并启动服务..." "progress"
    if ! sudo systemctl daemon-reload; then
        show_status "重新加载 systemd 失败。" "error"
        exit 1
    fi

    if ! sudo systemctl start $SERVICE_NAME.service; then
        show_status "启动服务失败。" "error"
        exit 1
    fi

    if ! sudo systemctl enable $SERVICE_NAME.service; then
        show_status "启用服务失败。" "error"
        exit 1
    fi

    echo "节点启动成功！"
}

# 查看 Prover 状态的函数
function check_prover_status() {
    echo "查看 Prover 状态..."
    systemctl status $SERVICE_NAME.service
}

# 查看日志的函数
function view_logs() {
    echo "查看 Prover 日志..."
    journalctl -u $SERVICE_NAME.service -f -n 50
}

# 删除节点的函数
function delete_node() {
    echo "正在删除节点..."
    sudo systemctl stop $SERVICE_NAME.service
    sudo systemctl disable $SERVICE_NAME.service
    echo "成功删除节点，按任意键返回主菜单。"
    read -n 1 -s  # 等待用户按任意键
}

# 调用主菜单函数
main_menu
