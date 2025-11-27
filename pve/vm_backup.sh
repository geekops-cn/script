#!/bin/bash
# Proxmox VE 多虚拟机备份脚本
# 版本：3.2（新增 dump 清理同步机制）
# 最后更新：2025-11-28

#################### 配置参数 ####################
VMIDS=(100 101 102 103)               # 要备份的虚拟机ID数组
BACKUP_STORAGE="local-hdd"            # Proxmox 存储名称
TARGET_DIR="/mnt/vm_backup"           # 备份目标路径
LOG_DIR="/var/log/pve_backups"        # 日志目录
RETENTION_DAYS=3                      # 保留天数
MAX_PARALLEL=2                        # 最大并行任务数
NOTIFY_EMAIL="geekops@pangshare.com"    # 邮箱通知

#################### 初始化 ####################
mkdir -p "$TARGET_DIR" "$LOG_DIR"
LOG_FILE="$LOG_DIR/pve_backups_$(date +%Y%m%d).log"

#################### 日志函数 ####################
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error_continue() {
    log "VM$1 ERROR: $2"
    [ -n "$NOTIFY_EMAIL" ] && send_notification "$1" "$2"
}

send_notification() {
    local subject="[PVE备份告警] VM$1 备份失败"
    local message="错误详情：$2\n完整日志：$LOG_FILE"
    echo -e "$message" | mail -s "$subject" "$NOTIFY_EMAIL"
}

#################### 工具函数 ####################
get_storage_path() {
    local path=$(pvesm status | awk -v storage="$BACKUP_STORAGE" '$1 == storage {print $2}')
    [ -z "$path" ] && path="/var/lib/vz/dump"
    echo "$path"
}

validate_directory() {
    if [ ! -d "$1" ]; then
        log "FATAL ERROR: 目录不存在 $1"
        exit 1
    fi
    if [ ! -w "$1" ]; then
        log "FATAL ERROR: 目录不可写 $1"
        exit 1
    fi
}

#################### 新增：dump 清理（v3.2） ####################
delete_old_backups_for_vmid() {
    local vmid="$1"
    local retention="$2"
    local dump_dir="/mnt/hdd/dump"

    if [ ! -d "$dump_dir" ]; then
        log "[VM$vmid] dump 目录不存在，跳过 dump 清理。"
        return
    fi

    log "[VM$vmid] 同步清理 dump 中超过 ${retention} 天的备份："

    # 显示删除列表
    find "$dump_dir" -name "vzdump-qemu-$vmid-*.vma.zst" -mtime +$((retention-1)) -ls 2>/dev/null

    # 执行删除
    find "$dump_dir" -name "vzdump-qemu-$vmid-*.vma.zst" -mtime +$((retention-1)) -print0 | \
        xargs -0 -r rm -f

    local remain=$(find "$dump_dir" -name "vzdump-qemu-$vmid-*.vma.zst" | wc -l)
    log "[VM$vmid] dump 目录剩余文件数：$remain"
}

#################### 单虚拟机备份函数 ####################
backup_single_vm() {
    local vmid=$1
    local vm_log="[VM$vmid]"
    local storage_path=$(get_storage_path)
    local tmp_log=$(mktemp)

    log "$vm_log ======== 开始备份 ========"

    if ! vzdump "$vmid" --storage "$BACKUP_STORAGE" --mode stop --compress zstd 2>&1 | tee "$tmp_log"; then
        error_continue "$vmid" "vzdump 执行失败"
        rm "$tmp_log"
        return 1
    fi

    cat "$tmp_log" | tee -a "$LOG_FILE"

    # 定位备份文件
    local backup_file=$(
        grep -iP "creating.*archive.*'?$vmid" "$tmp_log" | grep -oP "'\K[^']+(?=')" ||
        find "$storage_path" -name "vzdump-$vmid-*.zst" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-
    )

    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        error_continue "$vmid" "无法定位备份文件"
        rm "$tmp_log"
        return 1
    fi

    # 复制备份文件
    if ! cp -v "$backup_file" "$TARGET_DIR" | tee -a "$LOG_FILE"; then
        error_continue "$vmid" "复制备份文件失败"
        rm "$tmp_log"
        return 1
    fi

    local copied_file="${TARGET_DIR}/$(basename "$backup_file")"

    if [ ! -f "$copied_file" ]; then
        error_continue "$vmid" "副本验证失败"
        rm "$tmp_log"
        return 1
    fi

    log "$vm_log 备份成功，大小：$(du -h "$copied_file" | cut -f1)"
    rm "$tmp_log"
}

#################### 主程序 ####################
validate_directory "$TARGET_DIR"

log "====== 开始批量备份任务 ======"
log "目标 VM: ${VMIDS[*]} | 并行数: $MAX_PARALLEL"

# 开始并行任务
declare -A pids
for vmid in "${VMIDS[@]}"; do
    while [ $(jobs -rp | wc -l) -ge $MAX_PARALLEL ]; do
        sleep 1
    done
    backup_single_vm $vmid &
    pids[$!]=$vmid
done

# 等待所有任务完成
declare -a results
for pid in "${!pids[@]}"; do
    wait $pid
    status=$?
    vmid=${pids[$pid]}
    results+=("VM$vmid: $([ $status -eq 0 ] && echo 成功 || echo 失败)")
done

#################### v3.2 新增：同步清理 TARGET_DIR 和 dump ####################
log "====== 同步开始清理过期备份（$RETENTION_DAYS 天） ======"

for vmid in "${VMIDS[@]}"; do
    log "[VM$vmid] 清理 TARGET_DIR："
    find "$TARGET_DIR" -name "vzdump-qemu-$vmid-*.vma.zst" -mtime +$((RETENTION_DAYS-1)) -ls
    find "$TARGET_DIR" -name "vzdump-qemu-$vmid-*.vma.zst" -mtime +$((RETENTION_DAYS-1)) -delete

    # 同步清理 dump（最核心）
    delete_old_backups_for_vmid "$vmid" "$RETENTION_DAYS"
done

log "====== 清理完成 ======"

#################### 存储状态输出 ####################
log "存储状态统计："
{
    echo "目标目录内容："
    ls -lh "$TARGET_DIR"
    echo ""
    echo "磁盘使用情况："
    df -h "$TARGET_DIR" | awk '{printf "%-15s %5s / %5s (%s)\n", $1, $3, $2, $5}'
} | tee -a "$LOG_FILE"

log "====== 备份流程结束 ======"
exit 0
