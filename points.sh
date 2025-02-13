#!/bin/bash

# 设置工作目录
WORKING_DIR=$HOME/aios
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 切换目录前先检查
if [ ! -d "$WORKING_DIR" ]; then
    echo "错误: 工作目录 $WORKING_DIR 不存在"
    exit 1
fi

cd "$WORKING_DIR"

# 日志函数
write_log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp: $message"
    echo "$timestamp: $message" >> "$CURRENT_DIR/points_monitor.log"
}

# 获取 hive points 并保存
get_hive_points() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local output_file="$CURRENT_DIR/points_history.txt"
    
    write_log "Starting to get hive points..."
    
    # 检查守护进程状态
    if ./aios-cli status | grep "Daemon running" > /dev/null; then
        write_log "Daemon is running, getting points..."
        points=$(./aios-cli hive points | tr '\n' ' ' | tr -s ' ')
        
        if echo "$points" | grep "Failed to fetch points" > /dev/null; then
            write_log "Failed to fetch points: $points"
            echo "[$timestamp] Failed to fetch points: $points" >> "$output_file"
            echo "" >> "$output_file"
        elif [ -z "$points" ]; then
            write_log "No points data received"
            echo "[$timestamp] No points data received" >> "$output_file"
            echo "" >> "$output_file"
        else
            echo "[$timestamp] $points" >> "$output_file"
            echo "" >> "$output_file"
            write_log "Points data:"
            echo "[$timestamp] $points"
            write_log "Hive points recorded successfully"
        fi
    else
        write_log "Daemon not running, skipping points check"
        echo "[$timestamp] Daemon not running, skipping points check" >> "$output_file"
        echo "" >> "$output_file"
    fi
}

# 主循环
while true; do
    get_hive_points || {
        write_log "Error occurred in points recorder: $?"
        sleep 30
    }
    sleep 3600  # 1小时
done 
