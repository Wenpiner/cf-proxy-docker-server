#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 恢复默认颜色

# 输出带颜色的信息
info() {
  echo -e "${BLUE}[信息]${NC} $1"
}

success() {
  echo -e "${GREEN}[成功]${NC} $1"
}

warning() {
  echo -e "${YELLOW}[警告]${NC} $1"
}

error() {
  echo -e "${RED}[错误]${NC} $1"
}

header() {
  echo -e "\n${CYAN}====== $1 ======${NC}"
}

# 检查root权限
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    error "请使用root权限运行此脚本"
    exit 1
  fi
  success "已验证root权限"
}

# 检测操作系统
detect_os() {
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "macos"
  elif [[ "$(uname)" == "Linux" ]]; then
    # 检测Linux发行版
    if [ -f /etc/os-release ]; then
      . /etc/os-release
      echo "$ID"
    elif [ -f /etc/lsb-release ]; then
      . /etc/lsb-release
      echo "$DISTRIB_ID" | tr '[:upper:]' '[:lower:]'
    elif [ -f /etc/debian_version ]; then
      echo "debian"
    elif [ -f /etc/redhat-release ]; then
      echo "rhel"
    else
      echo "linux"
    fi
  else
    error "不支持的操作系统"
    exit 1
  fi
}

# 安装Docker (Ubuntu/Debian)
install_docker_debian() {
  info "正在安装Docker (Debian/Ubuntu)..."
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  apt-get update
  apt-get install -y docker-ce
  systemctl enable docker
  systemctl start docker
  success "Docker安装完成 (Debian/Ubuntu)"
}

# 安装Docker (CentOS/RHEL)
install_docker_rhel() {
  info "正在安装Docker (CentOS/RHEL)..."
  yum install -y yum-utils
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  yum install -y docker-ce docker-ce-cli containerd.io
  systemctl enable docker
  systemctl start docker
  success "Docker安装完成 (CentOS/RHEL)"
}

# 检查yq是否安装
check_yq() {
  if ! command -v yq &> /dev/null; then
    warning "yq 未安装，正在安装..."
    local os_type=$(detect_os)
    case "$os_type" in
      "macos")
        # 下载 yq 二进制文件并安装
        sudo curl -L "https://github.com/mikefarah/yq/releases/latest/download/yq_darwin_amd64" -o /usr/local/bin/yq
        sudo chmod +x /usr/local/bin/yq
        ;;
      "ubuntu"|"debian")
        sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
        sudo chmod +x /usr/local/bin/yq
        ;;
      "centos"|"rhel"|"fedora")
        sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
        sudo chmod +x /usr/local/bin/yq
        ;;
      "alpine")
        apk add --no-cache yq
        ;;
      *)
        error "无法自动安装 yq，请手动安装: https://github.com/mikefarah/yq"
        exit 1
        ;;
    esac
    success "yq 安装完成"
  else
    success "yq 已安装"
  fi
}

# 安装Docker (Fedora)
install_docker_fedora() {
  info "正在安装Docker (Fedora)..."
  dnf -y install dnf-plugins-core
  dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
  dnf install -y docker-ce docker-ce-cli containerd.io
  systemctl enable docker
  systemctl start docker
  success "Docker安装完成 (Fedora)"
}

# 安装Docker (Alpine)
install_docker_alpine() {
  info "正在安装Docker (Alpine)..."
  apk add --update docker
  rc-update add docker boot
  service docker start
  success "Docker安装完成 (Alpine)"
}

# 安装Docker
install_docker() {
  local os_type=$1
  
  case "$os_type" in
    "macos")
      warning "请从官方网站下载并安装Docker Desktop for Mac: https://www.docker.com/products/docker-desktop"
      warning "安装完成后，请重新运行此脚本"
      exit 0
      ;;
    "ubuntu"|"debian")
      install_docker_debian
      ;;
    "centos"|"rhel")
      install_docker_rhel
      ;;
    "fedora")
      install_docker_fedora
      ;;
    "alpine")
      install_docker_alpine
      ;;
    *)
      warning "未能识别的Linux发行版，尝试使用通用安装方法..."
      install_docker_debian
      ;;
  esac
}

# 检查Docker服务是否运行
check_docker_running() {
  info "检查Docker服务状态..."
  local os_type=$(detect_os)
  
  if [[ "$os_type" == "macos" ]]; then
    # macOS下检查Docker Desktop是否运行
    if ! docker info &>/dev/null; then
      error "Docker服务未运行，正在尝试启动..."
    open -a Docker &>/dev/null
    # 等待几秒钟让Docker有时间启动
    sleep 5
    if ! docker info &>/dev/null; then
      error "无法自动启动Docker Desktop"
      warning "请启动Docker Desktop应用程序，然后重试"
      exit 1
    else
      success "已成功启动Docker Desktop"
    fi
      warning "请启动Docker Desktop应用程序，然后重试"
      exit 1
    fi
  else
    # Linux下检查Docker服务
    if systemctl is-active --quiet docker; then
      success "Docker服务正在运行"
    else
      error "Docker服务未运行！"
      warning "正在尝试启动Docker服务..."
      systemctl start docker
      
      # 等待Docker服务启动
      sleep 3
      
      if systemctl is-active --quiet docker; then
        success "Docker服务已成功启动"
      else
        error "无法启动Docker服务，请手动启动后重试"
        info "您可以使用以下命令启动Docker服务："
        info "sudo systemctl start docker"
        exit 1
      fi
    fi
  fi
}

# 安装Docker Compose (特定版本)
install_docker_compose() {
  local os_type=$1
  info "正在安装Docker Compose..."
  
  if [[ "$os_type" == "macos" ]]; then
    warning "Docker Desktop for Mac已经包含了Docker Compose"
  else
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    
    case "$os_type" in
      "ubuntu"|"debian"|"centos"|"rhel"|"fedora")
        curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        ;;
      "alpine")
        apk add --update py-pip python3-dev libffi-dev openssl-dev gcc libc-dev make
        pip install docker-compose
        ;;
      *)
        curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        ;;
    esac
    
    success "Docker Compose安装完成"
  fi
}

# 检查Docker是否安装
check_docker() {
  if ! command -v docker &> /dev/null; then
    warning "Docker未安装，正在安装..."
    install_docker $(detect_os)
  else
    success "Docker已安装"
  fi
}

# 检查Docker Compose是否安装
check_docker_compose() {
  if ! command -v docker-compose &> /dev/null; then
    if ! docker compose version &> /dev/null; then
      warning "Docker Compose未安装，正在安装..."
      install_docker_compose $(detect_os)
    else
      success "使用内置Docker Compose插件"
    fi
  else
    success "Docker Compose已安装"
  fi
}

# 获取Docker Compose命令
get_docker_compose_cmd() {
  if command -v docker-compose &> /dev/null; then
    echo "docker-compose"
  else
    echo "docker compose"
  fi
}

# 验证域名格式
validate_domain() {
  local domain=$1
  if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    return 0
  else
    return 1
  fi
}

# 验证IP地址
validate_ip() {
  local ip=$1
  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    return 0
  else
    return 1
  fi
}

# 验证端口
validate_port() {
  local port=$1
  if [[ $port =~ ^[0-9]+$ ]] && [ $port -ge 1 ] && [ $port -le 65535 ]; then
    # 检查端口是否被占用
    if netstat -tuln | grep -q ":$port "; then
      return 1
    else
      return 0
    fi
  else
    return 1
  fi
}

# 验证协议类型
validate_protocol() {
  local protocol=$1
  if [[ "$protocol" == "tcp" || "$protocol" == "ssh" || "$protocol" == "http" || "$protocol" == "rdp" ]]; then
    return 0
  else
    return 1
  fi
}

# 验证服务名称
validate_server_name() {
  local server_name=$1
  if [[ $server_name =~ ^[a-z0-9]+$ ]]; then
    return 0
  else
    return 1
  fi
}

# 创建服务
create_service() {
  header "创建新的隧道服务"
  
  # 检查Docker是否运行
  check_docker_running
# 获取用户输入
local valid_input=false

while [ "$valid_input" = false ]; do
  # 输入代理名称
  while true; do
    echo -e -n "${PURPLE}请输入代理名称(name): ${NC}"
    read name
    if [ -d "./docker/$name" ]; then
      error "代理名称 '$name' 已存在，请选择其他名称"
    else
      break
    fi
  done

  # 输入服务名称
  while true; do
    echo -e -n "${PURPLE}请输入服务名称(server，仅支持小写字母和数字): ${NC}"
    read server
    if ! validate_server_name "$server"; then
      error "服务名称只能包含小写字母和数字"
    else
      break
    fi
  done

  # 输入主机名
  while true; do
    echo -e -n "${PURPLE}请输入主机名(hostname，如 example.com): ${NC}"
    read hostname
    if ! validate_domain "$hostname"; then
      error "主机名必须是有效的域名格式"
    else
      break
    fi
  done

  # 输入目标IP
  while true; do
    echo -e -n "${PURPLE}请输入本地目标IP(target，默认为 0.0.0.0): ${NC}"
    read target
    if [ -z "$target" ]; then
      target="0.0.0.0"
    fi
    if ! validate_ip "$target"; then
      error "目标必须是有效的IP地址"
    else
      break
    fi
  done

  # 输入协议类型
  while true; do
    echo -e -n "${PURPLE}请输入协议类型(protocol，支持: tcp/ssh/http/rdp): ${NC}"
    read protocol
    if ! validate_protocol "$protocol"; then
      error "协议类型必须是 tcp、ssh、http 或 rdp 之一"
    else
      break
    fi
  done

  # 输入本地端口
  while true; do
    echo -e -n "${PURPLE}请输入本地端口(local_port): ${NC}"
    read local_port
    if ! validate_port "$local_port"; then
      error "无效的端口号或端口已被占用"
    else
      break
    fi
  done

  valid_input=true
done
  
  # 创建目录
  info "创建目录结构..."
  mkdir -p "./docker/regions/$name/credentials" "./docker/regions/$name"
  touch "./docker/regions/$name/log.txt"
  
  # 创建配置文件
  info "创建配置文件..."
  cat > "./docker/regions/$name/config.json" << EOF
{
  "tunnels": [
    {
      "name": "$server",
      "hostname": "$hostname",
      "target": "$target",
      "protocol": "$protocol",
      "local_port": $local_port
    }
  ]
}
EOF
  
  # 更新docker-compose.yaml
  info "更新Docker Compose配置..."
  # 首先确保文件存在
  mkdir -p "./docker"
  if [ ! -f "./docker/docker-compose.yaml" ]; then
    echo "version: '3'" > "./docker/docker-compose.yaml"
    echo "services:" >> "./docker/docker-compose.yaml"
  fi
  
  # 检查是否已存在相同服务
if yq e ".services.cloudflared-$name" "./docker/docker-compose.yaml" > /dev/null 2>&1; then
  warning "发现现有配置，正在更新..."
  # 删除已存在的服务配置
  yq e "del(.services.cloudflared-$name)" -i "./docker/docker-compose.yaml"
fi

# 追加新服务配置
yq e ".services.cloudflared-$name = {
  \"build\": \".\",
  \"volumes\": [
    \"./regions/$name/credentials:/root/.cloudflared\",
    \"./regions/$name/config.json:/app/config/tunnels.json\",
    \"./regions/$name/log.txt:/app/logs/supervisor.log\"
  ],
  \"network_mode\": \"host\",
  \"restart\": \"unless-stopped\",
  \"container_name\": \"cloudflared-$name\"
}" -i "./docker/docker-compose.yaml"
  
  success "服务 '$name' '$server' 已成功创建"
}

# 列出服务
list_services() {
  header "当前服务列表"
  
  if [ ! -d "./docker/regions" ]; then
    warning "没有找到任何服务"
    return
  fi
  
  local index=1
  echo -e "${CYAN}序号  服务名称        状态${NC}"
  echo -e "${CYAN}---------------------------${NC}"
  
  for dir in ./docker/regions/*/; do
    if [ -d "$dir" ]; then
      local service_name=$(basename "$dir")
      
      # 检查服务状态
      local status="停止"
      local status_color=$RED
      if docker ps --format '{{.Names}}' | grep -q "cloudflared-$service_name"; then
        status="运行中"
        status_color=$GREEN
      fi
      
      printf "${YELLOW}%-5d${NC} %-15s ${status_color}%s${NC}\n" $index "$service_name" "$status"
      ((index++))
    fi
  done
  
  if [ $index -eq 1 ]; then
    warning "没有找到任何服务"
  fi
}

# 启动服务
start_service() {
  header "启动服务"
  
  # 检查Docker是否运行
  check_docker_running
  
  list_services
  
  if [ ! -d "./docker/regions" ] || [ -z "$(ls -A ./docker/regions 2>/dev/null)" ]; then
    warning "没有可用的服务，请先创建服务"
    return
  fi
  
  echo -e -n "${PURPLE}请选择要启动的服务序号: ${NC}"
  read selection
  
  local index=1
  for dir in ./docker/regions/*/; do
    if [ -d "$dir" ]; then
      if [ $index -eq $selection ]; then
        local service_name=$(basename "$dir")
        info "正在启动服务 '$service_name'..."
        
        local compose_cmd=$(get_docker_compose_cmd)
        cd ./docker && $compose_cmd up cloudflared-$service_name -d
        
        if [ $? -eq 0 ]; then
          success "服务 '$service_name' 已成功启动"
        else
          error "启动服务 '$service_name' 失败"
        fi
        return
      fi
      ((index++))
    fi
  done
  
  error "无效的选择"
}

# 停止服务
stop_service() {
  header "停止服务"
  
  # 检查Docker是否运行
  check_docker_running
  
  list_services
  
  if [ ! -d "./docker/regions" ] || [ -z "$(ls -A ./docker/regions 2>/dev/null)" ]; then
    warning "没有可用的服务，请先创建服务"
    return
  fi
  
  echo -e -n "${PURPLE}请选择要停止的服务序号: ${NC}"
  read selection
  
  local index=1
  for dir in ./docker/regions/*/; do
    if [ -d "$dir" ]; then
      if [ $index -eq $selection ]; then
        local service_name=$(basename "$dir")
        info "正在停止服务 '$service_name'..."
        
        docker stop cloudflared-$service_name
        
        if [ $? -eq 0 ]; then
          success "服务 '$service_name' 已成功停止"
        else
          error "停止服务 '$service_name' 失败"
        fi
        return
      fi
      ((index++))
    fi
  done
  
  error "无效的选择"
}

# 主菜单
main_menu() {
  while true; do
    header "Cloudflare 隧道管理工具"
    echo -e "${CYAN}1.${NC} 创建新服务"
    echo -e "${CYAN}2.${NC} 列出现有服务"
    echo -e "${CYAN}3.${NC} 启动服务"
    echo -e "${CYAN}4.${NC} 停止服务"
    echo -e "${CYAN}0.${NC} 退出"
    echo -e -n "${PURPLE}请选择操作: ${NC}"
    read choice
    
    case $choice in
      1)
        create_service
        ;;
      2)
        list_services
        ;;
      3)
        start_service
        ;;
      4)
        stop_service
        ;;
      0)
        success "感谢使用，再见！"
        exit 0
        ;;
      *)
        error "无效的选择，请重试"
        ;;
    esac
    
    echo -e -n "${YELLOW}按Enter键继续...${NC}"
    read
    clear
  done
}

# 程序入口
clear
header "Cloudflare 隧道管理工具初始化"
check_root
check_yq
check_docker
check_docker_compose
check_docker_running
main_menu