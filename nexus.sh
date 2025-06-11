#!/bin/bash
set -e

BASE_CONTAINER_NAME="nexus-node"
IMAGE_NAME="nexus-node:latest"
LOG_DIR="/root/nexus_logs"

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

if [ -z "\$NODE_ID" ]; then
    echo "错误：未设置 NODE_ID 环境变量"
    exit 1
fi

echo "\$NODE_ID" > "\$PROVER_ID_FILE"
echo "使用的 node-id: \$NODE_ID"

if ! command -v nexus-network >/dev/null 2>&1; then
    echo "错误：nexus-network 未安装或不可用"
    exit 1
fi

screen -S nexus -X quit >/dev/null 2>&1 || true

echo "启动 nexus-network 节点..."
screen -dmS nexus bash -c "nexus-network start --node-id \$NODE_ID &>> /root/nexus.log"

sleep 3

if screen -list | grep -q "nexus"; then
    echo "节点已在后台启动。"
    echo "日志文件：/root/nexus.log"
    echo "可以使用 docker logs \$CONTAINER_NAME 查看日志"
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

# 显示所有运行中的节点
function list_nodes() {
    echo "当前节点状态："
    echo "--------------------------------------------------------------------------------------------------------"
    printf "%-6s %-20s %-10s %-10s %-10s %-20s\n" "序号" "节点ID" "CPU使用率" "内存使用" "内存限制" "状态"
    echo "--------------------------------------------------------------------------------------------------------"
    
    local all_nodes=($(get_all_nodes))
    for i in "${!all_nodes[@]}"; do
        local node_id=${all_nodes[$i]}
        local container_name="${BASE_CONTAINER_NAME}-${node_id}"
        local container_info=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}" $container_name 2>/dev/null)
        
        if [ -n "$container_info" ]; then
            # 解析容器信息
            IFS=',' read -r cpu_usage mem_usage mem_limit mem_perc <<< "$container_info"
            local status=$(docker ps -a --filter "name=$container_name" --format "{{.Status}}")
            
            # 格式化内存显示
            mem_usage=$(echo $mem_usage | sed 's/\([0-9.]*\)\([A-Za-z]*\)/\1 \2/')
            mem_limit=$(echo $mem_limit | sed 's/\([0-9.]*\)\([A-Za-z]*\)/\1 \2/')
            
            # 显示节点信息
            printf "%-6d %-20s %-10s %-10s %-10s %-20s\n" \
                $((i+1)) \
                "$node_id" \
                "$cpu_usage" \
                "$mem_usage" \
                "$mem_limit" \
                "$(echo $status | cut -d' ' -f1)"
        else
            # 如果容器不存在或未运行
            local status=$(docker ps -a --filter "name=$container_name" --format "{{.Status}}")
            if [ -n "$status" ]; then
                printf "%-6d %-20s %-10s %-10s %-10s %-20s\n" \
                    $((i+1)) \
                    "$node_id" \
                    "N/A" \
                    "N/A" \
                    "N/A" \
                    "$(echo $status | cut -d' ' -f1)"
            fi
        fi
    done
    echo "--------------------------------------------------------------------------------------------------------"
    echo "提示："
    echo "- CPU使用率：显示容器CPU使用百分比"
    echo "- 内存使用：显示容器当前使用的内存"
    echo "- 内存限制：显示容器内存使用限制"
    echo "- 状态：显示容器的运行状态"
    read -p "按任意键返回菜单"
}

# 获取所有运行中的节点ID
function get_running_nodes() {
    docker ps --filter "name=${BASE_CONTAINER_NAME}" --filter "status=running" --format "{{.Names}}" | sed "s/${BASE_CONTAINER_NAME}-//"
}

# 获取所有节点ID（包括已停止的）
function get_all_nodes() {
    docker ps -a --filter "name=${BASE_CONTAINER_NAME}" --format "{{.Names}}" | sed "s/${BASE_CONTAINER_NAME}-//"
}

# 删除全部节点
function uninstall_all_nodes() {
    local all_nodes=($(get_all_nodes))
    
    if [ ${#all_nodes[@]} -eq 0 ]; then
        echo "当前没有节点"
        read -p "按任意键返回菜单"
        return
    fi

    echo "警告：此操作将删除所有节点！"
    echo "当前共有 ${#all_nodes[@]} 个节点："
    for node_id in "${all_nodes[@]}"; do
        echo "- $node_id"
    done
    
    read -rp "确定要删除所有节点吗？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消操作"
        read -p "按任意键返回菜单"
        return
    fi

    echo "开始删除所有节点..."
    for node_id in "${all_nodes[@]}"; do
        echo "正在卸载节点 $node_id ..."
        docker rm -f "${BASE_CONTAINER_NAME}-${node_id}" 2>/dev/null || true
    done

    # 删除轮换容器
    docker rm -f "${BASE_CONTAINER_NAME}-rotate" 2>/dev/null || true

    # 停止并删除轮换进程
    pm2 delete nexus-rotate 2>/dev/null || true

    echo "所有节点已删除完成！"
    read -p "按任意键返回菜单"
}

# 批量停止并卸载节点
function batch_uninstall_nodes() {
    // ... existing code ...
}

# 主菜单
while true; do
    clear
    echo "脚本由哈哈哈哈编写，推特 @ferdie_jhovie，免费开源，请勿相信收费"
    echo "如有问题，可联系推特，仅此只有一个号"
    echo "========== Nexus 多节点管理 =========="
    echo "1. 轮换启动节点（每2小时轮换）"
    echo "2. 显示所有节点状态"
    echo "3. 删除全部节点"
    echo "4. 退出"
    echo "==================================="

    read -rp "请输入选项(1-4): " choice

    case $choice in
        1)
            check_docker
            echo "请输入多个 node-id，每行一个，输入空行结束："
            echo "（输入完成后按回车键，然后按 Ctrl+D 结束输入）"
            
            node_ids=()
            while read -r line; do
                if [ -n "$line" ]; then
                    node_ids+=("$line")
                fi
            done

            if [ ${#node_ids[@]} -eq 0 ]; then
                echo "未输入任何 node-id，返回主菜单"
                read -p "按任意键继续"
                continue
            fi

            # 检查是否安装了 pm2
            if ! command -v pm2 >/dev/null 2>&1; then
                echo "正在安装 pm2..."
                npm install -g pm2
            fi

            # 直接删除旧的轮换进程
            echo "停止旧的轮换进程..."
            pm2 delete nexus-rotate 2>/dev/null || true

            echo "开始构建镜像..."
            build_image

            # 创建启动脚本目录
            script_dir="/root/nexus_scripts"
            mkdir -p "$script_dir"

            # 创建轮换脚本
            cat > "$script_dir/rotate.sh" <<EOF
#!/bin/bash
set -e

CONTAINER_NAME="${BASE_CONTAINER_NAME}-rotate"
LOG_FILE="${LOG_DIR}/nexus-rotate.log"

# 确保日志目录和文件存在
mkdir -p "${LOG_DIR}"
touch "\$LOG_FILE"
chmod 644 "\$LOG_FILE"

# 停止并删除现有容器
docker rm -f "\$CONTAINER_NAME" 2>/dev/null || true

# 启动容器（使用第一个node-id）
echo "启动容器，使用node-id: ${node_ids[0]}"
docker run -d --name "\$CONTAINER_NAME" -v "\$LOG_FILE:/root/nexus.log" -e NODE_ID="${node_ids[0]}" "$IMAGE_NAME"

# 等待容器启动
sleep 30

while true; do
    for node_id in "${node_ids[@]}"; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 切换到node-id: \$node_id"
        
        # 停止当前容器
        docker stop "\$CONTAINER_NAME" 2>/dev/null || true
        docker rm "\$CONTAINER_NAME" 2>/dev/null || true
        
        # 使用新的node-id启动容器
        docker run -d --name "\$CONTAINER_NAME" -v "\$LOG_FILE:/root/nexus.log" -e NODE_ID="\$node_id" "$IMAGE_NAME"
        
        # 等待2小时
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 等待2小时..."
        sleep 7200
    done
done
EOF

            # 设置脚本权限
            chmod +x "$script_dir/rotate.sh"

            # 使用 pm2 启动轮换脚本
            pm2 start "$script_dir/rotate.sh" --name "nexus-rotate"
            pm2 save

            echo "节点轮换已启动！"
            echo "总共 ${#node_ids[@]} 个节点将在同一个容器上轮换"
            echo "每2小时切换一次node-id"
            echo "使用 'pm2 status' 查看运行状态"
            echo "使用 'pm2 logs nexus-rotate' 查看轮换日志"
            echo "使用 'pm2 stop nexus-rotate' 停止轮换"
            read -p "按任意键返回菜单"
            ;;
        2)
            list_nodes
            ;;
        3)
            uninstall_all_nodes
            ;;
        4)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo "无效选项，请重新输入。"
            read -p "按任意键继续"
            ;;
    esac
done 
