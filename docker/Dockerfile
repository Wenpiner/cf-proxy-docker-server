FROM ubuntu:22.04

LABEL maintainer="Cloudflared Proxy Docker Solution"
LABEL description="Multi-region, multi-account Cloudflare tunnel proxy solution"
LABEL version="1.0.0"

# 安装依赖
RUN apt-get update && \
    apt-get install -y \
    curl \
    wget \
    unzip \
    jq \
    supervisor \
    ca-certificates \
    tzdata \
    procps \
    iputils-ping \
    net-tools \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 设置时区
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 安装最新版本的 cloudflared，支持多架构
RUN ARCH=$(dpkg --print-architecture) && \
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb && \
    dpkg -i cloudflared.deb && \
    rm cloudflared.deb && \
    cloudflared version

# 创建必要的目录结构
RUN mkdir -p /etc/cloudflared /app/config /app/logs/tunnels

# 设置工作目录
WORKDIR /app

# 复制启动脚本
COPY start.sh /app/
RUN chmod +x /app/start.sh

# 容器健康检查
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD pgrep supervisord || exit 1

# 设置环境变量
ENV PATH="/app:${PATH}"
ENV CLOUDFLARED_CONFIG="/app/config"
ENV CLOUDFLARED_LOGS="/app/logs"

# 启动隧道管理服务
ENTRYPOINT ["/app/start.sh"]