# Cloudflared 代理 Docker 解决方案

这是一个基于 Docker 的解决方案，使用 Cloudflared 工具创建和管理多个 Cloudflare Access 隧道，以便通过 Cloudflare 安全地访问内部网络中的各种服务。该解决方案支持多个协议、多个端口、多个 Cloudflare 账户和区域。

## 功能特性

- **多协议支持**：支持 TCP、HTTP/HTTPS、SSH、RDP 等多种协议
- **任意端口支持**：能够映射到任意本地端口，支持同时运行多个不同端口的隧道
- **多账户管理**：支持同时配置和使用多个 Cloudflare 账户
- **多区域部署**：支持在不同地区同时运行 Cloudflared 实例
- **配置简单**：使用 JSON 格式定义所有隧道配置，无需修改代码即可添加、删除或修改隧道
- **自动容错**：单个隧道故障时自动重启，容器意外停止时自动恢复
- **完整日志**：所有隧道日志统一输出到区域日志文件，便于故障排查

## 目录结构

```
.
├── Dockerfile
├── start.sh
├── docker-compose.yml
├── README.md
└── regions/
    ├── region_1/
    │   ├── credentials/  # Cloudflare 凭证
    │   ├── config.json   # 隧道配置文件
    │   └── log.txt       # 日志文件
    └── region_2/
        ├── credentials/
        ├── config.json
        └── log.txt
```

## 快速开始

### 前提条件

- 安装 Docker 和 Docker Compose
- 拥有 Cloudflare 账户
- 拥有可以使用 Cloudflare Tunnel 的域名

### 配置步骤

1. 克隆仓库或下载源代码到本地

```bash
git clone https://github.com/Wenpiner/cf-proxy-docker-server.git
cd cloudflare-proxy-docker
```

2. 为每个需要部署的区域创建配置文件夹

```bash
# 已经预创建了 region_1 和 region_2
mkdir -p regions/region_1/credentials
mkdir -p regions/region_2/credentials
```

3. 编辑每个区域的 config.json 文件

```json
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
    }
  ]
}
```

4. 启动服务

```bash
docker-compose up -d
```

5. 首次启动时，您需要登录 Cloudflare 账户

```bash
# 查看日志，按照提示进行登录
docker logs cloudflared-region1

# 如果需要，可以通过下面命令进入容器完成交互式登录
docker exec -it cloudflared-region1 bash
cloudflared login
exit
```

### 配置文件详解

每个隧道配置包含以下字段：

- `name`：隧道名称，用于标识和日志记录
- `hostname`：Cloudflare 域名，必须是您在 Cloudflare 上注册并授权的域名
- `target`：目标服务地址和端口，格式为 `IP:PORT`
- `protocol`：协议类型，支持 "rdp", "ssh", "http", "https", "tcp"
- `local_port`：本地监听端口，确保该端口在本地未被占用

### Docker Compose 配置详解

```yaml
version: '3'

services:
  cloudflared-region1:
    build: .
    volumes:
      - ./regions/region_1/credentials:/etc/cloudflared
      - ./regions/region_1/config.json:/app/config/tunnels.json
      - ./regions/region_1/log.txt:/app/logs/supervisor.log
    network_mode: "host"
    restart: unless-stopped
    container_name: cloudflared-region1

  cloudflared-region2:
    build: .
    volumes:
      - ./regions/region_2/credentials:/etc/cloudflared
      - ./regions/region_2/config.json:/app/config/tunnels.json
      - ./regions/region_2/log.txt:/app/logs/supervisor.log
    network_mode: "host"
    restart: unless-stopped
    container_name: cloudflared-region2
```

可以根据需要添加更多区域或账号。

## 管理操作

### 查看日志

```bash
# 查看特定区域的主日志
docker exec -it cloudflared-region1 cat /app/logs/supervisor.log

# 查看特定隧道的日志
docker exec -it cloudflared-region1 cat /app/logs/tunnels/rdp-server/rdp-server.log
```

### 重启服务

```bash
# 重启特定区域的所有隧道
docker restart cloudflared-region1

# 仅重启特定隧道
docker exec -it cloudflared-region1 supervisorctl restart tunnel_0_rdp-server
```

### 添加新隧道

1. 编辑对应区域的 config.json 文件，添加新的隧道配置
2. 重启对应的容器

```bash
docker restart cloudflared-region1
```

### 删除隧道

1. 编辑对应区域的 config.json 文件，删除不需要的隧道配置
2. 重启对应的容器

```bash
docker restart cloudflared-region1
```

## 故障排查

### 无法连接到 Cloudflare

- 检查凭证文件是否正确：`/etc/cloudflared/cert.pem`
- 尝试重新登录：`cloudflared login`
- 检查网络连接

### 隧道无法启动

- 查看特定隧道的错误日志：`/app/logs/tunnels/[隧道名称]/[隧道名称]_err.log`
- 检查配置文件中的参数是否正确
- 确保本地端口没有被占用：`netstat -tuln | grep [端口号]`

### 无法访问服务

- 确保隧道正在运行：`supervisorctl status tunnel_[序号]_[隧道名称]`
- 检查目标服务是否正常运行
- 检查防火墙设置
- 查看 Cloudflare 仪表盘中隧道的状态

## 安全建议

- 使用独立的 Cloudflare 账户管理隧道
- 定期更新 Cloudflared 版本
- 在 Cloudflare 控制台为隧道设置访问策略
- 避免将敏感信息直接写入配置文件
- 限制容器的资源访问权限

## 高级配置

### 自定义超时时间

修改 start.sh 脚本中的 cloudflared 命令，添加超时参数：

```bash
CMD="cloudflared access rdp --hostname \"$HOSTNAME\" --url \"rdp://$TARGET\" --local-port $LOCAL_PORT --timeout 10m"
```

### 自定义日志级别

修改 start.sh 脚本中的 cloudflared 命令，添加日志级别参数：

```bash
CMD="cloudflared access rdp --hostname \"$HOSTNAME\" --url \"rdp://$TARGET\" --local-port $LOCAL_PORT --loglevel debug"
```

## 更新说明

- 优化 Docker 镜像，减少大小并提高安全性
- 增强错误处理和恢复机制
- 改进日志结构和管理
- 增加健康检查功能
- 添加容器运行状态监控
- 优化时区设置
- 添加更多网络诊断工具
