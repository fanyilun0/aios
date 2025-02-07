#!/bin/bash

# 设置工作目录和基本配置
WORKING_DIR=$HOME/Desktop/DePIN/aios
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOGS_DIR="$CURRENT_DIR/log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
OUTPUT_FILE="$LOGS_DIR/output_${TIMESTAMP}.txt"

# 关键错误模式
declare -a CRITICAL_ERRORS=(
    "Another instance is already running"
    "Failed to authenticate"
    "Failed to connect"
    "Internal server error"
    "Service Unavailable"
    "Failed to register models for inference"
    "panicked at aios-cli"
)

# # 检查工作目录
# if [ ! -d "$WORKING_DIR" ]; then
#     echo "Error: Working directory $WORKING_DIR does not exist"
#     exit 1
# fi

# # 创建日志目录
# if [ ! -d "$LOGS_DIR" ]; then
#     mkdir -p "$LOGS_DIR"
# fi

cd "$WORKING_DIR"

# 日志函数
write_log() {
    local message="$1"
    local type="${2:-INFO}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_message="[$timestamp] [$type] $message"
    echo "$log_message"
    echo "$log_message" >> "$OUTPUT_FILE"
}

# 清理旧进程
cleanup_process() {
    write_log "Cleaning up processes..." "INFO"
    if ./aios-cli status | grep "Daemon running" > /dev/null; then
        write_log "Found running instance, killing..." "WARN"
        ./aios-cli kill
        sleep 3
    fi
}

# 检查错误并处理
check_errors() {
    local line="$1"
    for error in "${CRITICAL_ERRORS[@]}"; do
        if echo "$line" | grep -q "$error"; then
            write_log "Critical error detected: $error" "ERROR"
            cleanup_process
            write_log "Process cleaned up, waiting before restart..." "INFO"
            
            if [ "$error" = "panicked at aios-cli" ]; then
                sleep 5
            else
                sleep 5
            fi
            return 1
        fi
    done
    return 0
}

# 添加心跳检测函数
check_heartbeat() {
    local log_file="$1"
    local max_reconnect_attempts=3  # 最大重连尝试次数
    local reconnect_pattern="Last pong received"
    
    # 检查最近的日志
    local reconnect_count=$(tail -n 20 "$log_file" | grep -c "$reconnect_pattern")
    
    if [ $reconnect_count -ge $max_reconnect_attempts ]; then
        write_log "检测到持续的重连尝试，需要重启服务" "WARN"
        return 1
    fi
    return 0
}

# 主循环
while true; do
    try_count=0
    max_tries=3
    
    write_log "Starting monitoring session..." "INFO"
    cleanup_process
    
    # 启动进程并监控
    write_log "Starting aios-cli daemon..." "INFO"
    ./aios-cli start --connect 2>&1 | while IFS= read -r line; do
        # 避免重复日志
        if ! echo "$line" | grep -q "^\[.*\] \[.*\]"; then
            write_log "$line"
        fi
        
        # 检查错误
        if ! check_errors "$line"; then
            try_count=$((try_count + 1))
            if [ $try_count -ge $max_tries ]; then
                write_log "Max retry count reached, waiting longer..." "WARN"
                sleep 5
                try_count=0
            fi
            break
        fi
        
        # 每分钟检查一次心跳状态
        if [ $((SECONDS % 60)) -eq 0 ]; then
            if ! check_heartbeat "$OUTPUT_FILE"; then
                write_log "检测到心跳异常，执行重启..." "WARN"
                cleanup_process
                sleep 10
                break
            fi
        fi
    done
    
    write_log "Process exited, restarting monitoring..." "INFO"
    sleep 5
done
