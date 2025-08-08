#!/bin/bash

# Passwall2节点ping测试脚本
# 功能：提取节点信息，批量ping测试，找出延迟最低的节点

# 配置参数
TIMEOUT=3           # ping超时时间（秒）
PING_COUNT=3        # ping次数
MAX_CONCURRENT=20   # 最大并发数

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 内存数据结构
declare -a NODE_IDS=()      # 节点ID数组
declare -a ADDRESSES=()     # 地址数组
declare -a NODE_NAMES=()    # 节点名称数组
declare -a LATENCIES=()     # 延迟数组
declare -a STATUSES=()      # 状态数组

# 清理函数
cleanup() {
    echo -e "\n${YELLOW}清理进程...${NC}"
    # 清理可能残留的后台进程
    jobs -p | xargs -r kill 2>/dev/null
    # 清理临时文件
    rm -f /tmp/ping_result_*_$$
    exit 0
}

# 捕获退出信号
trap cleanup INT TERM EXIT

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}       Passwall2 节点Ping测试工具      ${NC}"
echo -e "${BLUE}========================================${NC}"

# 第一步：提取节点信息
echo -e "\n${YELLOW}步骤1: 提取Passwall2节点信息...${NC}"

# 获取passwall2配置并提取节点信息
raw_data=$(uci show passwall2 | grep address)

if [ -z "$raw_data" ]; then
    echo -e "${RED}错误：未找到passwall2配置或没有地址信息${NC}"
    exit 1
fi

# 使用正则表达式提取节点ID和地址，直接存储到数组
node_count=0
while IFS= read -r line; do
    # 使用正则表达式提取节点ID和地址
    if [[ $line =~ passwall2\.([^.]+)\.address=\'([^\']+)\' ]]; then
        node_id="${BASH_REMATCH[1]}"
        address="${BASH_REMATCH[2]}"
        
        # 获取节点名称
        node_name=$(uci get passwall2.${node_id}.alias 2>/dev/null || uci get passwall2.${node_id}.remarks 2>/dev/null || echo "未知节点")
        
        NODE_IDS[$node_count]="$node_id"
        ADDRESSES[$node_count]="$address"
        NODE_NAMES[$node_count]="$node_name"
        LATENCIES[$node_count]="999999"  # 初始化为最大值
        STATUSES[$node_count]="pending"
        
        echo -e "发现节点: ${GREEN}$node_id${NC} (${YELLOW}$node_name${NC}) -> ${BLUE}$address${NC}"
        ((node_count++))
    fi
done <<< "$raw_data"

echo -e "\n${GREEN}总共发现 $node_count 个节点${NC}"

if [ "$node_count" -eq 0 ]; then
    echo -e "${RED}错误：没有有效的节点信息${NC}"
    exit 1
fi

# 第二步：并发ping测试
echo -e "\n${YELLOW}步骤2: 开始并发Ping测试...${NC}"
echo -e "参数: 超时=${TIMEOUT}s, 次数=${PING_COUNT}, 最大并发=${MAX_CONCURRENT}"

# ping测试函数
ping_node() {
    local index="$1"
    local node_id="${NODE_IDS[$index]}"
    local address="${ADDRESSES[$index]}"
    local node_name="${NODE_NAMES[$index]}"
    local temp_file="/tmp/ping_result_${index}_$$"
    
    # 执行ping命令并计算平均延迟
    ping_result=$(ping -c "$PING_COUNT" -W "$TIMEOUT" "$address" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        # 兼容不同系统的ping输出格式
        # 尝试多种模式提取延迟
        avg_time=$(echo "$ping_result" | grep -E "(round-trip|rtt)" | sed -n 's/.*avg[^0-9]*\([0-9]*\.*[0-9]*\).*/\1/p' | head -1)
        
        # 如果上面的方法失败，尝试另一种提取方式
        if [ -z "$avg_time" ]; then
            avg_time=$(echo "$ping_result" | grep -E "time=" | tail -1 | sed 's/.*time=\([0-9]*\.*[0-9]*\).*/\1/')
        fi
        
        if [ -n "$avg_time" ] && [ "$avg_time" != "0" ]; then
            echo "$index,$avg_time,success" > "$temp_file"
            echo -e "${GREEN}✓${NC} $address (${YELLOW}$node_name${NC}): ${avg_time}ms"
        else
            echo "$index,999999,failed" > "$temp_file"
            echo -e "${RED}✗${NC} $address (${YELLOW}$node_name${NC}): 解析延迟失败"
        fi
    else
        echo "$index,999999,timeout" > "$temp_file"
        echo -e "${RED}✗${NC} $address (${YELLOW}$node_name${NC}): 超时"
    fi
}

# 并发控制函数
run_concurrent_pings() {
    local job_count=0
    
    # 遍历所有节点进行测试
    for ((i=0; i<node_count; i++)); do
        # 控制并发数量
        while [ $(jobs -r | wc -l) -ge $MAX_CONCURRENT ]; do
            sleep 1
        done
        
        # 后台执行ping测试
        ping_node "$i" &
        job_count=$((job_count + 1))
        
        # 每启动10个任务显示一次进度
        if [ $((job_count % 10)) -eq 0 ]; then
            echo -e "${BLUE}已启动 $job_count 个测试任务...${NC}"
        fi
    done
    
    # 等待所有后台任务完成
    echo -e "\n${YELLOW}等待所有测试完成...${NC}"
    wait
}

# 执行并发ping测试
run_concurrent_pings

# 收集结果
echo -e "\n${YELLOW}收集测试结果...${NC}"
for ((i=0; i<node_count; i++)); do
    temp_file="/tmp/ping_result_${i}_$$"
    if [ -f "$temp_file" ]; then
        result=$(cat "$temp_file")
        IFS=',' read -r idx latency status <<< "$result"
        LATENCIES[$i]="$latency"
        STATUSES[$i]="$status"
        rm -f "$temp_file"
    fi
done

# 第三步：汇总结果并找出最快节点
echo -e "\n${YELLOW}步骤3: 分析测试结果...${NC}"

# 统计成功和失败的数量
success_count=0
failed_count=0
for ((i=0; i<node_count; i++)); do
    if [ "${STATUSES[$i]}" = "success" ]; then
        ((success_count++))
    else
        ((failed_count++))
    fi
done

echo -e "\n${BLUE}========== 测试结果统计 ==========${NC}"
echo -e "成功: ${GREEN}$success_count${NC} 个节点"
echo -e "失败: ${RED}$failed_count${NC} 个节点"

# 创建索引数组用于排序
declare -a sorted_indices=()
for ((i=0; i<node_count; i++)); do
    if [ "${STATUSES[$i]}" = "success" ]; then
        sorted_indices+=($i)
    fi
done

# 冒泡排序（按延迟排序）- 使用Shell内置比较
for ((i=0; i<${#sorted_indices[@]}; i++)); do
    for ((j=i+1; j<${#sorted_indices[@]}; j++)); do
        idx1=${sorted_indices[$i]}
        idx2=${sorted_indices[$j]}
        lat1=${LATENCIES[$idx1]}
        lat2=${LATENCIES[$idx2]}
        
        # 简单的数值比较，避免使用bc命令
        # 将浮点数转换为整数比较（乘以1000）
        lat1_int=$(echo "$lat1" | awk '{print int($1*1000)}')
        lat2_int=$(echo "$lat2" | awk '{print int($1*1000)}')
        
        if [ "$lat1_int" -gt "$lat2_int" ]; then
            # 交换索引
            temp=${sorted_indices[$i]}
            sorted_indices[$i]=${sorted_indices[$j]}
            sorted_indices[$j]=$temp
        fi
    done
done

# 显示前10个最快的节点
echo -e "\n${BLUE}========== Top 10 最快节点 ==========${NC}"
echo -e "${YELLOW}排名  节点ID        节点名称           地址                    延迟(ms)${NC}"
echo "-------------------------------------------------------------------------"

display_count=0
for idx in "${sorted_indices[@]}"; do
    if [ $display_count -ge 10 ]; then
        break
    fi
    
    ((display_count++))
    node_id="${NODE_IDS[$idx]}"
    node_name="${NODE_NAMES[$idx]}"
    address="${ADDRESSES[$idx]}"
    latency="${LATENCIES[$idx]}"
    
    # 截断过长的名称
    if [ ${#node_name} -gt 15 ]; then
        display_name="${node_name:0:12}..."
    else
        display_name="$node_name"
    fi
    
    printf "${GREEN}%2d${NC}    %-12s %-15s %-23s ${BLUE}%8s${NC}\n" "$display_count" "$node_id" "$display_name" "$address" "$latency"
done

# 找出最快的节点
if [ ${#sorted_indices[@]} -gt 0 ]; then
    fastest_idx=${sorted_indices[0]}
    fastest_node="${NODE_IDS[$fastest_idx]}"
    fastest_address="${ADDRESSES[$fastest_idx]}"
    fastest_latency="${LATENCIES[$fastest_idx]}"
    
    echo -e "\n${BLUE}========== 最快节点信息 ==========${NC}"
    echo -e "节点ID: ${GREEN}$fastest_node${NC}"
    echo -e "节点名称: ${GREEN}${NODE_NAMES[$fastest_idx]}${NC}"
    echo -e "地址: ${GREEN}$fastest_address${NC}"
    echo -e "延迟: ${GREEN}${fastest_latency}ms${NC}"

    echo -e "\n${YELLOW}正在切换到最快节点...${NC}"
    uci set passwall2.@global[0].node=$fastest_node
    uci commit passwall2
    # /etc/init.d/passwall2 restart
    
    current_node=$(uci get passwall2.@global[0].node)
    if [ "$current_node" != "$fastest_node" ]; then
        echo -e "${RED}错误：切换节点失败！请检查配置或手动切换。${NC}"
        exit 1
    fi
    echo -e "${GREEN}已切换到最快节点: $fastest_node (${NODE_NAMES[$fastest_idx]})${NC}"
    
else
    echo -e "\n${RED}警告：没有找到可用的节点！${NC}"
    exit 1
fi

