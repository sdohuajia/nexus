# 启动节点的函数
function start_node() {
    # 检查是否有名为 nexus 的 screen 会话，如果存在，则删除
    if screen -list | grep -q "nexus"; then
        echo "检测到已存在的 'nexus' screen 会话，正在删除..."
        screen -S nexus -X quit
        echo "'nexus' screen 会话已成功删除。"
    fi

    # 更新系统和安装必要组件
    echo "正在更新系统并安装必要组件..."
    if ! sudo apt update && sudo apt upgrade -y && sudo apt install -y build-essential pkg-config libssl-dev git-all protobuf-compiler curl unzip screen; then
        echo "安装基础组件失败"
        exit 1
    fi

    # 检查并安装tmux（根据需求，可忽略此步骤）
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

    # 提示用户创建 screen 会话并运行命令
    echo "请使用以下命令创建新的 screen 会话并运行节点:"
    echo "  screen -S nexus"
    echo "进入 screen 会话后，执行以下命令:"
    echo "  curl https://cli.nexus.xyz/ | sh"
    echo "节点启动成功！节点将开始运行。"
    echo "使用 'screen -r nexus' 可以重新连接到 screen 会话查看节点状态。"
    read -p "按任意键返回主菜单"
}
