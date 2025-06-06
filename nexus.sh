#!/bin/bash
set -e

CONTAINER_NAME="nexus-node"
IMAGE_NAME="nexus-node:latest"
LOG_FILE="/root/nexus.log"

# 检查 Docker 是否安装
function check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "检测到未安装 Docker，正在安装..."
        apt update
        apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        apt update
        apt install -y docker-ce
        systemctl enable docker
        systemctl start docker
    fi
}

# 构建docker镜像函数
function build_image() {
    WORKDIR=$(mktemp -d)
    cd "$WORKDIR"

    cat > Dockerfile <<EOF
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PROVER_ID_FILE=/root/.nexus/node-id

RUN apt-get update && apt-get install -y \\
    curl \\
    screen \\
    bash \\
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSL https://cli.nexus.xyz/ | sh

RUN ln -sf /root/.nexus/bin/nexus-network /usr/local/bin/nexus-network

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
EOF

    cat > entrypoint.sh <<EOF
#!/bin/bash
set -e

PROVER_ID_FILE="/root/.nexus/node-id"

echo "$NODE_ID" > "\$PROVER_ID_FILE"
echo "使用的 node-id: $NODE_ID"

if ! command -v nexus-network >/dev/null 2>&1; then
    echo "错误：nexus-network 未安装或不可用"
    exit 1
fi

screen -S nexus -X quit >/dev/null 2>&1 || true

echo "启动 nexus-network 节点..."
screen -dmS nexus bash -c "nexus-network start --node-id $NODE_ID &>> /root/nexus.log"

sleep 3

if screen -list | grep -q "nexus"; then
    echo "节点已在后台启动。"
    echo "日志文件：/root/nexus.log"
    echo "可以使用 docker logs $CONTAINER_NAME 查看日志"
else
    echo "节点启动失败，请检查日志。"
    cat /root/nexus.log
    exit 1
fi

tail -f /root/nexus.log
EOF

    docker build -t "$IMAGE_NAME" .

    cd -
    rm -rf "$WORKDIR"
}

# 启动容器（挂载宿主机日志文件）
function run_container() {
    if docker ps -a --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
        echo "检测到旧容器 $CONTAINER_NAME，先删除..."
        docker rm -f "$CONTAINER_NAME"
    fi

    # 确保宿主机日志文件存在并有写权限
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi

    docker run -d --name "$CONTAINER_NAME" -v "$LOG_FILE":/root/nexus.log "$IMAGE_NAME"
    echo "容器已启动！"
}

# 停止并卸载容器和镜像、删除日志
function uninstall_node() {
    echo "停止并删除容器 $CONTAINER_NAME..."
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || echo "容器不存在或已停止"

    echo "删除镜像 $IMAGE_NAME..."
    docker rmi "$IMAGE_NAME" 2>/dev/null || echo "镜像不存在或已删除"

    if [ -f "$LOG_FILE" ]; then
        echo "删除日志文件 $LOG_FILE ..."
        rm -f "$LOG_FILE"
    else
        echo "日志文件不存在：$LOG_FILE"
    fi

    echo "节点已卸载完成。"
}

# 主菜单
while true; do
    clear
    echo "脚本由哈哈哈哈编写，推特 @ferdie_jhovie，免费开源，请勿相信收费"
    echo "如有问题，可联系推特，仅此只有一个号"
    echo "========== Nexus 节点管理 =========="
    echo "1. 安装并启动节点"
    echo "2. 显示节点 ID"
    echo "3. 停止并卸载节点"
    echo "4. 查看节点日志"
    echo "5. 退出"
    echo "==================================="

    read -rp "请输入选项(1-5): " choice

    case $choice in
        1)
            check_docker
            read -rp "请输入您的 node-id: " NODE_ID
            if [ -z "$NODE_ID" ]; then
                echo "node-id 不能为空，请重新选择。"
                read -p "按任意键继续"
                continue
            fi
            echo "开始构建镜像并启动容器..."
            build_image
            run_container
            read -p "按任意键返回菜单"
            ;;
        2)
            if docker ps -a --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
                echo "节点 ID:"
                docker exec "$CONTAINER_NAME" cat /root/.nexus/node-id || echo "无法读取节点 ID"
            else
                echo "容器未运行，请先安装并启动节点（选项1）"
            fi
            read -p "按任意键返回菜单"
            ;;
        3)
            uninstall_node
            read -p "按任意键返回菜单"
            ;;
        4)
            if docker ps --format '{{.Names}}' | grep -qw "$CONTAINER_NAME"; then
                echo "查看日志，按 Ctrl+C 退出日志查看"
                docker logs -f "$CONTAINER_NAME"
            else
                echo "容器未运行，请先安装并启动节点（选项1）"
                read -p "按任意键返回菜单"
            fi
            ;;
        5)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo "无效选项，请重新输入。"
            read -p "按任意键返回菜单"
            ;;
    esac
done
