#!/bin/bash

set -e

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /app/logs/supervisor.log
}

log "开始初始化 Cloudflared 代理服务..."

# 将日志重定向到 supervisor.log
exec > >(tee -a /app/logs/supervisor.log) 2>&1

# 初始化 supervisor 配置文件
SUPERVISOR_CONF="/etc/supervisor/conf.d/cloudflared.conf"
echo "[supervisord]" > $SUPERVISOR_CONF
echo "nodaemon=true" >> $SUPERVISOR_CONF
echo "user=root" >> $SUPERVISOR_CONF
echo "logfile=/app/logs/supervisor.log" >> $SUPERVISOR_CONF
echo "logfile_maxbytes=50MB" >> $SUPERVISOR_CONF
echo "logfile_backups=10" >> $SUPERVISOR_CONF
echo "loglevel=info" >> $SUPERVISOR_CONF

# 创建必要的目录
mkdir -p /app/logs/tunnels

# 检查是否提供了凭证文件
if [ -f "/root/.cloudflared/cert.pem" ]; then
    log "使用已存在的凭证文件"
else
    # 否则，登录到 cloudflare（交互式）
    log "没有找到凭证文件，请先登录 Cloudflare"
    cloudflared tunnel login
    
    # 验证登录是否成功
    if [ ! -f "/root/.cloudflared/cert.pem" ]; then
        log "错误: 登录失败或未正确保存凭证。请确保您已成功登录并且凭证已保存"
        exit 1
    else
        log "登录成功，凭证已保存"
    fi
fi

# 检查配置文件是否存在
CONFIG_FILE="/app/config/tunnels.json"
if [ ! -f "$CONFIG_FILE" ]; then
    log "错误: 找不到隧道配置文件 $CONFIG_FILE"
    log "请创建 tunnels.json 文件并映射到容器的 /app/config/tunnels.json 路径"
    log "示例配置格式:"
    cat << EOF
{
  "tunnels": [
    {
      "name": "rdp-server",
      "hostname": "rdp.example.com",
      "target": "192.168.1.100:3389",
      "protocol": "rdp",
      "local_port": 3389
    },
    {
      "name": "ssh-server",
      "hostname": "ssh.example.com",
      "target": "192.168.1.100:22",
      "protocol": "ssh",
      "local_port": 2222
    },
    {
      "name": "web-server",
      "hostname": "web.example.com",
      "target": "192.168.1.100:80",
      "protocol": "http",
      "local_port": 8080
    },
    {
      "name": "database",
      "hostname": "db.example.com",
      "target": "192.168.1.100:5432",
      "protocol": "tcp",
      "local_port": 5432
    }
  ]
}
EOF
    exit 1
fi

# 验证 JSON 格式是否有效
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    log "错误: 配置文件不是有效的 JSON 格式"
    exit 1
fi

log "找到隧道配置文件: $CONFIG_FILE"

# 获取隧道数量
if ! TUNNELS_COUNT=$(jq '.tunnels | length' $CONFIG_FILE); then
    log "错误: 无法解析配置文件中的隧道数量"
    exit 1
fi

log "找到 $TUNNELS_COUNT 个隧道配置"

# 添加 Supervisor 项目组配置以便批量重启
echo "[group:cloudflared_tunnels]" >> $SUPERVISOR_CONF
echo "programs=" >> $SUPERVISOR_CONF

# 从配置文件中读取并为每个隧道创建 supervisor 配置
for (( i=0; i<$TUNNELS_COUNT; i++ ))
do
    # 使用 jq 时添加错误检查
    if ! TUNNEL_NAME=$(jq -r ".tunnels[$i].name" $CONFIG_FILE); then
        log "错误: 无法解析第 $i 个隧道的名称"
        continue
    fi
    
    if ! HOSTNAME=$(jq -r ".tunnels[$i].hostname" $CONFIG_FILE); then
        log "错误: 无法解析第 $i 个隧道 ($TUNNEL_NAME) 的主机名"
        continue
    fi
    
    if ! TARGET=$(jq -r ".tunnels[$i].target" $CONFIG_FILE); then
        log "错误: 无法解析第 $i 个隧道 ($TUNNEL_NAME) 的目标地址"
        continue
    fi
    
    PROTOCOL=$(jq -r ".tunnels[$i].protocol // \"tcp\"" $CONFIG_FILE)
    if [ -z "$PROTOCOL" ] || [ "$PROTOCOL" == "null" ]; then
        log "警告: 第 $i 个隧道 ($TUNNEL_NAME) 未指定协议，将使用 TCP 协议"
        PROTOCOL="tcp"
    fi
    
    if ! LOCAL_PORT=$(jq -r ".tunnels[$i].local_port" $CONFIG_FILE); then
        log "错误: 无法解析第 $i 个隧道 ($TUNNEL_NAME) 的本地端口"
        continue
    fi
    
    # 确保本地端口是有效数字
    if ! [[ "$LOCAL_PORT" =~ ^[0-9]+$ ]]; then
        log "错误: 第 $i 个隧道 ($TUNNEL_NAME) 的本地端口 '$LOCAL_PORT' 不是有效数字"
        continue
    fi
    
    PROGRAM_NAME="tunnel_${i}_${TUNNEL_NAME}"
    
    log "配置隧道 #$i: $TUNNEL_NAME, 协议: $PROTOCOL, 主机名: $HOSTNAME, 目标: $TARGET, 本地端口: $LOCAL_PORT"
    
    # 根据协议创建相应的命令
    case "$PROTOCOL" in
        "rdp")
            CMD="cloudflared access rdp --hostname \"$HOSTNAME\" --url \"rdp://$TARGET\" --local-port $LOCAL_PORT"
            ;;
        "ssh")
            CMD="cloudflared access ssh --hostname \"$HOSTNAME\" --url \"ssh://$TARGET\" --local-port $LOCAL_PORT"
            ;;
        "http")
            CMD="cloudflared access http --hostname \"$HOSTNAME\" --url \"http://$TARGET\" --local-port $LOCAL_PORT"
            ;;
        "https")
            CMD="cloudflared access http --hostname \"$HOSTNAME\" --url \"https://$TARGET\" --local-port $LOCAL_PORT"
            ;;
        "tcp")
            CMD="cloudflared access tcp --hostname \"$HOSTNAME\" --url \"tcp://$TARGET\" --local-port $LOCAL_PORT"
            ;;
        *)
            log "警告: 不支持的协议 '$PROTOCOL'，将使用 TCP 协议"
            CMD="cloudflared access tcp --hostname \"$HOSTNAME\" --url \"tcp://$TARGET\" --local-port $LOCAL_PORT"
            ;;
    esac
    
    # 创建隧道日志目录
    mkdir -p "/app/logs/tunnels/$TUNNEL_NAME"
    
    # 将命令添加到 supervisor 配置
    {
        echo "[program:$PROGRAM_NAME]"
        echo "command=$CMD"
        echo "autostart=true"
        echo "autorestart=true"
        echo "startretries=10"
        echo "startsecs=10"
        echo "stderr_logfile=/app/logs/tunnels/${TUNNEL_NAME}/${TUNNEL_NAME}_err.log"
        echo "stderr_logfile_maxbytes=10MB"
        echo "stderr_logfile_backups=5"
        echo "stdout_logfile=/app/logs/tunnels/${TUNNEL_NAME}/${TUNNEL_NAME}.log"
        echo "stdout_logfile_maxbytes=10MB"
        echo "stdout_logfile_backups=5"
        echo ""
    } >> $SUPERVISOR_CONF
    
    # 添加到项目组
    # 注意：在循环中追加，我们需要读取当前值并更新
    CURRENT_PROGRAMS=$(grep "^programs=" $SUPERVISOR_CONF | cut -d= -f2)
    if [ -z "$CURRENT_PROGRAMS" ]; then
        sed -i "s/^programs=.*/programs=$PROGRAM_NAME/" $SUPERVISOR_CONF
    else
        sed -i "s/^programs=.*/programs=$CURRENT_PROGRAMS,$PROGRAM_NAME/" $SUPERVISOR_CONF
    fi
done

# 添加监控和状态检查配置
{
    echo "[program:healthcheck]"
    echo "command=bash -c 'while true; do echo \"[$(date +\"%Y-%m-%d %H:%M:%S\")] Health check running...\"; sleep 300; done'"
    echo "autostart=true"
    echo "autorestart=true"
    echo "stdout_logfile=/app/logs/healthcheck.log"
    echo "stderr_logfile=/app/logs/healthcheck_err.log"
    echo ""
} >> $SUPERVISOR_CONF

log "所有隧道已配置，启动 supervisor..."

# 显示当前配置情况总结
log "================================="
log "配置摘要:"
log "- 隧道总数: $TUNNELS_COUNT"
log "- 隧道日志位置: /app/logs/tunnels/[隧道名称]/*.log"
log "- Supervisor 配置文件: $SUPERVISOR_CONF"
log "- Cloudflared 凭证位置: /root/.cloudflared"
log "================================="

# 启动 supervisor
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
