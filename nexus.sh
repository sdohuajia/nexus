#!/bin/bash
set -e

BASE_CONTAINER_NAME="nexus-node"
IMAGE_NAME="nexus-node:latest"
LOG_DIR="/root/nexus_logs"

# 检查并安装 Node.js 和 pm2
function check_node_pm2() {
    # 检查是否安装了 Node.js
    if ! command -v node >/dev/null 2>&1; then
        echo "检测到未安装 Node.js，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
    fi

    # 检查是否安装了 pm2
    if ! command -v pm2 >/dev/null 2>&1; then
        echo "检测到未安装 pm2，正在安装..."
        npm install -g pm2
    fi
}

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

RUN apt-get update && apt-get install -y \
    curl \
    screen \
    bash \
    && rm -rf /var/lib/apt/lists/*

# 自动下载安装最新版 nexus-network
RUN curl -sSL https://cli.nexus.xyz/ | NONINTERACTIVE=1 sh \
    && ln -sf /root/.nexus/bin/nexus-network /usr/local/bin/nexus-network

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

# 启动容器（挂载宿主机日志文件）
function run_container() {
    local node_id=$1
    local container_name="${BASE_CONTAINER_NAME}-${node_id}"
    local log_file="${LOG_DIR}/nexus-${node_id}.log"

    if docker ps -a --format '{{.Names}}' | grep -qw "$container_name"; then
        echo "检测到旧容器 $container_name，先删除..."
        docker rm -f "$container_name"
    fi

    # 确保日志目录存在
    mkdir -p "$LOG_DIR"
    
    # 确保宿主机日志文件存在并有写权限
    if [ ! -f "$log_file" ]; then
        touch "$log_file"
        chmod 644 "$log_file"
    fi

    docker run -d --name "$container_name" -v "$log_file":/root/nexus.log -e NODE_ID="$node_id" "$IMAGE_NAME"
    echo "容器 $container_name 已启动！"
}

# 停止并卸载容器和镜像、删除日志
function uninstall_node() {
    local node_id=$1
    local container_name="${BASE_CONTAINER_NAME}-${node_id}"
    local log_file="${LOG_DIR}/nexus-${node_id}.log"

    echo "停止并删除容器 $container_name..."
    docker rm -f "$container_name" 2>/dev/null || echo "容器不存在或已停止"

    if [ -f "$log_file" ]; then
        echo "删除日志文件 $log_file ..."
        rm -f "$log_file"
    else
        echo "日志文件不存在：$log_file"
    fi

    echo "节点 $node_id 已卸载完成。"
}

# 显示所有运行中的节点
function list_nodes() {
    echo "当前节点状态："
    echo "------------------------------------------------------------------------------------------------------------------------"
    printf "%-6s %-20s %-10s %-10s %-10s %-20s %-20s\n" "序号" "节点ID" "CPU使用率" "内存使用" "内存限制" "状态" "启动时间"
    echo "------------------------------------------------------------------------------------------------------------------------"
    
    local all_nodes=($(get_all_nodes))
    for i in "${!all_nodes[@]}"; do
        local node_id=${all_nodes[$i]}
        local container_name="${BASE_CONTAINER_NAME}-${node_id}"
        local container_info=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}" $container_name 2>/dev/null)
        
        if [ -n "$container_info" ]; then
            # 解析容器信息
            IFS=',' read -r cpu_usage mem_usage mem_limit mem_perc <<< "$container_info"
            local status=$(docker ps -a --filter "name=$container_name" --format "{{.Status}}")
            local created_time=$(docker ps -a --filter "name=$container_name" --format "{{.CreatedAt}}")
            
            # 格式化内存显示
            mem_usage=$(echo $mem_usage | sed 's/\([0-9.]*\)\([A-Za-z]*\)/\1 \2/')
            mem_limit=$(echo $mem_limit | sed 's/\([0-9.]*\)\([A-Za-z]*\)/\1 \2/')
            
            # 显示节点信息
            printf "%-6d %-20s %-10s %-10s %-10s %-20s %-20s\n" \
                $((i+1)) \
                "$node_id" \
                "$cpu_usage" \
                "$mem_usage" \
                "$mem_limit" \
                "$(echo $status | cut -d' ' -f1)" \
                "$created_time"
        else
            # 如果容器不存在或未运行
            local status=$(docker ps -a --filter "name=$container_name" --format "{{.Status}}")
            local created_time=$(docker ps -a --filter "name=$container_name" --format "{{.CreatedAt}}")
            if [ -n "$status" ]; then
                printf "%-6d %-20s %-10s %-10s %-10s %-20s %-20s\n" \
                    $((i+1)) \
                    "$node_id" \
                    "N/A" \
                    "N/A" \
                    "N/A" \
                    "$(echo $status | cut -d' ' -f1)" \
                    "$created_time"
            fi
        fi
    done
    echo "------------------------------------------------------------------------------------------------------------------------"
    echo "提示："
    echo "- CPU使用率：显示容器CPU使用百分比"
    echo "- 内存使用：显示容器当前使用的内存"
    echo "- 内存限制：显示容器内存使用限制"
    echo "- 状态：显示容器的运行状态"
    echo "- 启动时间：显示容器的创建时间"
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

# 查看节点日志
function view_node_logs() {
    local node_id=$1
    local container_name="${BASE_CONTAINER_NAME}-${node_id}"
    
    if docker ps -a --format '{{.Names}}' | grep -qw "$container_name"; then
        echo "请选择日志查看模式："
        echo "1. 原始日志（可能包含颜色代码）"
        echo "2. 清理后的日志（移除颜色代码）"
        read -rp "请选择(1-2): " log_mode

        echo "查看日志，按 Ctrl+C 退出日志查看"
        if [ "$log_mode" = "2" ]; then
            docker logs -f "$container_name" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/\x1b\[?25l//g' | sed 's/\x1b\[?25h//g'
        else
            docker logs -f "$container_name"
        fi
    else
        echo "容器未运行，请先安装并启动节点（选项1）"
        read -p "按任意键返回菜单"
    fi
}

# 批量启动多个节点
function batch_start_nodes() {
    echo "请输入多个 node-id，每行一个，输入空行结束："
    echo "（输入完成后按回车键，然后按 Ctrl+D 结束输入）"
    
    local node_ids=()
    while read -r line; do
        if [ -n "$line" ]; then
            node_ids+=("$line")
        fi
    done

    if [ ${#node_ids[@]} -eq 0 ]; then
        echo "未输入任何 node-id，返回主菜单"
        read -p "按任意键继续"
        return
    fi

    echo "开始构建镜像..."
    build_image

    echo "开始启动节点..."
    for node_id in "${node_ids[@]}"; do
        echo "正在启动节点 $node_id ..."
        run_container "$node_id"
        sleep 2  # 添加短暂延迟，避免同时启动太多容器
    done

    echo "所有节点启动完成！"
    read -p "按任意键返回菜单"
}

# 选择要查看的节点
function select_node_to_view() {
    local all_nodes=($(get_all_nodes))
    
    if [ ${#all_nodes[@]} -eq 0 ]; then
        echo "当前没有节点"
        read -p "按任意键返回菜单"
        return
    fi

    echo "请选择要查看的节点："
    echo "0. 返回主菜单"
    for i in "${!all_nodes[@]}"; do
        local node_id=${all_nodes[$i]}
        local container_name="${BASE_CONTAINER_NAME}-${node_id}"
        local status=$(docker ps -a --filter "name=$container_name" --format "{{.Status}}")
        if [[ $status == Up* ]]; then
            echo "$((i+1)). 节点 $node_id [运行中]"
        else
            echo "$((i+1)). 节点 $node_id [已停止]"
        fi
    done

    read -rp "请输入选项(0-${#all_nodes[@]}): " choice

    if [ "$choice" = "0" ]; then
        return
    fi

    if [ "$choice" -ge 1 ] && [ "$choice" -le ${#all_nodes[@]} ]; then
        local selected_node=${all_nodes[$((choice-1))]}
        view_node_logs "$selected_node"
    else
        echo "无效的选项"
        read -p "按任意键继续"
    fi
}

# 批量停止并卸载节点
function batch_uninstall_nodes() {
    local all_nodes=($(get_all_nodes))
    
    if [ ${#all_nodes[@]} -eq 0 ]; then
        echo "当前没有节点"
        read -p "按任意键返回菜单"
        return
    fi

    echo "当前节点状态："
    echo "----------------------------------------"
    echo "序号  节点ID                状态"
    echo "----------------------------------------"
    for i in "${!all_nodes[@]}"; do
        local node_id=${all_nodes[$i]}
        local container_name="${BASE_CONTAINER_NAME}-${node_id}"
        local status=$(docker ps -a --filter "name=$container_name" --format "{{.Status}}")
        if [[ $status == Up* ]]; then
            printf "%-6d %-20s [运行中]\n" $((i+1)) "$node_id"
        else
            printf "%-6d %-20s [已停止]\n" $((i+1)) "$node_id"
        fi
    done
    echo "----------------------------------------"

    echo "请选择要删除的节点（可多选，输入数字，用空格分隔）："
    echo "0. 返回主菜单"
    
    read -rp "请输入选项(0 或 数字，用空格分隔): " choices

    if [ "$choices" = "0" ]; then
        return
    fi

    # 将输入的选项转换为数组
    read -ra selected_choices <<< "$choices"
    
    # 验证输入并执行卸载
    for choice in "${selected_choices[@]}"; do
        if [ "$choice" -ge 1 ] && [ "$choice" -le ${#all_nodes[@]} ]; then
            local selected_node=${all_nodes[$((choice-1))]}
            echo "正在卸载节点 $selected_node ..."
            uninstall_node "$selected_node"
        else
            echo "跳过无效选项: $choice"
        fi
    done

    echo "批量卸载完成！"
    read -p "按任意键返回菜单"
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
        uninstall_node "$node_id"
    done

    echo "所有节点已删除完成！"
    read -p "按任意键返回菜单"
}

# 批量节点轮换启动
function batch_rotate_nodes() {
    echo "请输入多个 node-id，每行一个，输入空行结束："
    echo "（输入完成后按回车键，然后按 Ctrl+D 结束输入）"
    
    local node_ids=()
    while read -r line; do
        if [ -n "$line" ]; then
            node_ids+=("$line")
        fi
    done

    if [ ${#node_ids[@]} -eq 0 ]; then
        echo "未输入任何 node-id，返回主菜单"
        read -p "按任意键继续"
        return
    fi

    # 设置每两小时启动的节点数量
    read -rp "请输入每两小时要启动的节点数量（默认：${#node_ids[@]}的一半，向上取整）: " nodes_per_round
    if [ -z "$nodes_per_round" ]; then
        nodes_per_round=$(( (${#node_ids[@]} + 1) / 2 ))
    fi

    # 验证输入
    if ! [[ "$nodes_per_round" =~ ^[0-9]+$ ]] || [ "$nodes_per_round" -lt 1 ] || [ "$nodes_per_round" -gt ${#node_ids[@]} ]; then
        echo "无效的节点数量，请输入1到${#node_ids[@]}之间的数字"
        read -p "按任意键返回菜单"
        return
    fi

    # 计算需要多少组
    local total_nodes=${#node_ids[@]}
    local num_groups=$(( (total_nodes + nodes_per_round - 1) / nodes_per_round ))
    echo "节点将分为 $num_groups 组进行轮换"

    # 检查并安装 Node.js 和 pm2
    check_node_pm2

    # 直接删除旧的轮换进程
    echo "停止旧的轮换进程..."
    pm2 delete nexus-rotate 2>/dev/null || true

    echo "开始构建镜像..."
    build_image

    # 创建启动脚本目录
    local script_dir="/root/nexus_scripts"
    mkdir -p "$script_dir"

    # 为每组创建启动脚本
    for ((group=1; group<=num_groups; group++)); do
        cat > "$script_dir/start_group${group}.sh" <<EOF
#!/bin/bash
set -e

# 停止并删除所有现有容器
docker ps -a --filter "name=${BASE_CONTAINER_NAME}" --format "{{.Names}}" | xargs -r docker rm -f

# 启动第${group}组节点
EOF
    done

    # 添加节点到对应的启动脚本
    for i in "${!node_ids[@]}"; do
        local node_id=${node_ids[$i]}
        local container_name="${BASE_CONTAINER_NAME}-${node_id}"
        local log_file="${LOG_DIR}/nexus-${node_id}.log"
        
        # 计算节点属于哪一组
        local group_num=$(( i / nodes_per_round + 1 ))
        if [ $group_num -gt $num_groups ]; then
            group_num=$num_groups
        fi
        
        # 确保日志目录和文件存在
        mkdir -p "$LOG_DIR"
        # 如果日志文件是目录，先删除
        if [ -d "$log_file" ]; then
            rm -rf "$log_file"
        fi
        # 如果日志文件不存在则新建
        if [ ! -f "$log_file" ]; then
            touch "$log_file"
            chmod 644 "$log_file"
        fi

        # 添加到对应组的启动脚本
        echo "echo \"[$(date '+%Y-%m-%d %H:%M:%S')] 启动节点 $node_id ...\"" >> "$script_dir/start_group${group_num}.sh"
        echo "docker run -d --name $container_name -v $log_file:/root/nexus.log -e NODE_ID=$node_id $IMAGE_NAME" >> "$script_dir/start_group${group_num}.sh"
        echo "sleep 30" >> "$script_dir/start_group${group_num}.sh"
    done

    # 创建轮换脚本
    cat > "$script_dir/rotate.sh" <<EOF
#!/bin/bash
set -e

while true; do
EOF

    # 添加每组启动命令到轮换脚本
    for ((group=1; group<=num_groups; group++)); do
        # 计算当前组的节点数量
        local start_idx=$(( (group-1) * nodes_per_round ))
        local end_idx=$(( group * nodes_per_round ))
        if [ $end_idx -gt $total_nodes ]; then
            end_idx=$total_nodes
        fi
        local current_group_nodes=$(( end_idx - start_idx ))

        cat >> "$script_dir/rotate.sh" <<EOF
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 启动第${group}组节点（${current_group_nodes}个）..."
    bash "$script_dir/start_group${group}.sh"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 等待2小时..."
    sleep 7200

EOF
    done

    # 完成轮换脚本
    echo "done" >> "$script_dir/rotate.sh"

    # 设置脚本权限
    chmod +x "$script_dir"/*.sh

    # 使用 pm2 启动轮换脚本
    pm2 start "$script_dir/rotate.sh" --name "nexus-rotate"
    pm2 save

    echo "节点轮换已启动！"
    echo "总共 $total_nodes 个节点，分为 $num_groups 组"
    echo "每组启动 $nodes_per_round 个节点（最后一组可能不足），每2小时轮换一次"
    echo "使用 'pm2 status' 查看运行状态"
    echo "使用 'pm2 logs nexus-rotate' 查看轮换日志"
    echo "使用 'pm2 stop nexus-rotate' 停止轮换"
    read -p "按任意键返回菜单"
}

# 主菜单
while true; do
    clear
    echo "脚本由哈哈哈哈编写，推特 @ferdie_jhovie，免费开源，请勿相信收费"
    echo "如有问题，可联系推特，仅此只有一个号"
    echo "========== Nexus 多节点管理 =========="
    echo "1. 批量节点轮换启动"
    echo "2. 显示所有节点状态"
    echo "3. 批量停止并卸载指定节点"
    echo "4. 查看指定节点日志"
    echo "5. 删除全部节点"
    echo "6. 退出"
    echo "==================================="

    read -rp "请输入选项(1-6): " choice

    case $choice in
        1)
            check_docker
            batch_rotate_nodes
            ;;
        2)
            list_nodes
            ;;
        3)
            batch_uninstall_nodes
            ;;
        4)
            select_node_to_view
            ;;
        5)
            uninstall_all_nodes
            ;;
        6)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            echo "无效选项，请重新输入。"
            read -p "按任意键继续"
            ;;
    esac
done 
