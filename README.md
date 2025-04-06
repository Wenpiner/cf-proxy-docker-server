# Cloudflared Proxy Docker Solution

English | [简体中文](README_zh.md)

This is a Docker-based solution that uses the Cloudflared tool to create and manage multiple Cloudflare Access tunnels for securely accessing various services in your internal network through Cloudflare. This solution supports multiple protocols, multiple ports, multiple Cloudflare accounts, and regions, and provides comprehensive health checks and monitoring functions.

## Features

- **Multiple Protocol Support**: Supports various protocols including TCP, HTTP/HTTPS, SSH, RDP, etc.
- **Arbitrary Port Support**: Ability to map to any local port, supporting simultaneous operation of multiple tunnels on different ports
- **Multi-Account Management**: Support for configuring and using multiple Cloudflare accounts simultaneously
- **Multi-Region Deployment**: Support for running Cloudflared instances in different regions simultaneously
- **Simple Configuration**: Uses JSON format to define all tunnel configurations, allowing adding, removing, or modifying tunnels without code changes
- **Automatic Fault Tolerance**: Auto-restart when individual tunnels fail, auto-recovery when containers stop unexpectedly
- **Complete Logging**: All tunnel logs are unified in regional log files for easy troubleshooting

## Directory Structure

```
.
├── Dockerfile            # Container build file
├── start.sh              # Startup script
├── docker-compose.yml    # Docker Compose configuration file
├── README.md             # Project documentation
└── regions/              # Region configuration directory
    ├── region_1/         # Region 1
    │   ├── credentials/  # Cloudflare credentials
    │   ├── config.json   # Tunnel configuration file
    │   └── log/          # Log directory
    └── region_2/         # Region 2
        ├── credentials/  # Cloudflare credentials
        ├── config.json   # Tunnel configuration file
        └── log/          # Log directory (or log.txt file)
```

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- Cloudflare account
- Domain that can be used with Cloudflare Tunnel

### Configuration Steps

1. Clone the repository or download the source code

```bash
git clone https://github.com/Wenpiner/cf-proxy-docker.git
cd cf-proxy-docker
```

2. Create configuration folders for each region you need to deploy

```bash
# region_1 and region_2 are pre-created
mkdir -p regions/region_1/credentials
mkdir -p regions/region_2/credentials
```

3. Edit the config.json file for each region

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

4. Start the service

```bash
docker-compose up -d
```

5. For the first time startup, you need to log in to your Cloudflare account

```bash
# View logs and follow login instructions
docker logs cloudflared-region1

# If needed, you can enter the container to complete interactive login
docker exec -it cloudflared-region1 bash
cloudflared login
exit
```

### Configuration File Details

Each tunnel configuration includes the following fields:

- `name`: Tunnel name, used for identification and logging
- `hostname`: Cloudflare domain, must be a domain registered and authorized on Cloudflare
- `target`: Target service address and port, in the format `IP:PORT`
- `protocol`: Protocol type, supports "rdp", "ssh", "http", "https", "tcp"
- `local_port`: Local listening port, ensure this port is not in use locally

### Docker Compose Configuration Details

```yaml
version: '3'

services:
  cloudflared-region1:
    build: .
    volumes:
      - ./regions/region_1/credentials:/root/.cloudflared
      - ./regions/region_1/config.json:/app/config/tunnels.json
      - ./regions/region_1/log/:/app/logs
    network_mode: "host"  # Use host network to support arbitrary ports
    restart: unless-stopped
    container_name: cloudflared-region1

  cloudflared-region2:
    build: .
    volumes:
      - ./regions/region_2/credentials:/root/.cloudflared
      - ./regions/region_2/config.json:/app/config/tunnels.json
      - ./regions/region_2/log.txt:/app/logs/supervisor.log
    network_mode: "host"  # Use host network to support arbitrary ports
    restart: unless-stopped
    container_name: cloudflared-region2
```

You can add more regions or accounts as needed. Note that region1 uses directory mounting for logs, while region2 uses single file mounting for the main log.

## Management Operations

### View Logs

```bash
# View the main log for a specific region
docker exec -it cloudflared-region1 cat /app/logs/supervisor.log

# View logs for a specific tunnel
docker exec -it cloudflared-region1 cat /app/logs/tunnels/mysql/mysql.log

# View error logs
docker exec -it cloudflared-region1 cat /app/logs/tunnels/mysql/mysql_err.log

# View health check logs
docker exec -it cloudflared-region1 cat /app/logs/healthcheck.log
```

### Restart Service

```bash
# Restart all tunnels in a specific region
docker restart cloudflared-region1

# Restart only a specific tunnel
docker exec -it cloudflared-region1 supervisorctl restart tunnel_0_rdp-server
```

### Add New Tunnel

1. Edit the config.json file for the corresponding region, add the new tunnel configuration
2. Restart the corresponding container

```bash
docker restart cloudflared-region1
```

### Delete Tunnel

1. Edit the config.json file for the corresponding region, remove the unwanted tunnel configuration
2. Restart the corresponding container

```bash
docker restart cloudflared-region1
```

## Troubleshooting

### Cannot Connect to Cloudflare

- Check if the credential file is correct: `/etc/cloudflared/cert.pem`
- Try logging in again: `cloudflared login`
- Check network connection

### Tunnel Cannot Start

- Check the error log for the specific tunnel: `/app/logs/tunnels/[tunnel_name]/[tunnel_name]_err.log`
- Verify that the parameters in the configuration file are correct
- Ensure that the local port is not being used: `netstat -tuln | grep [port]`

### Cannot Access Service

- Ensure the tunnel is running: `supervisorctl status tunnel_[index]_[tunnel_name]`
- Check if the target service is running properly
- Check firewall settings
- View the tunnel status in the Cloudflare dashboard

## Security Recommendations

- Use separate Cloudflare accounts to manage tunnels
- Regularly update Cloudflared version
- Set access policies for tunnels in the Cloudflare console
- Avoid writing sensitive information directly into configuration files
- Limit container resource access permissions

## Advanced Configuration

### Custom Timeout

Modify the cloudflared command in the start.sh script by adding a timeout parameter:

```bash
CMD="cloudflared access rdp --hostname \"$HOSTNAME\" --url \"rdp://$TARGET\" --local-port $LOCAL_PORT --timeout 10m"
```

### Custom Log Level

Modify the cloudflared command in the start.sh script by adding a log level parameter:

```bash
CMD="cloudflared access rdp --hostname \"$HOSTNAME\" --url \"rdp://$TARGET\" --local-port $LOCAL_PORT --loglevel debug"
```

## Container Features

The container includes the following main features:

- **Multiple Protocol Support**: Supports RDP, SSH, HTTP, HTTPS, TCP, and other protocols
- **Automatic Restart Mechanism**: Manages tunnel processes through Supervisor, automatically restarts failed tunnels
- **Health Check**: Built-in health check mechanism executed every 5 minutes
- **Complete Logging System**: Manages standard output and error logs separately for each tunnel
- **Error Handling**: Comprehensive error handling and reporting mechanisms
- **Timezone Setting**: Default set to Asia/Shanghai timezone
- **Network Diagnostic Tools**: Built-in ping, netstat, and other network diagnostic tools
- **Multi-Architecture Support**: Supports deployment on various CPU architectures

## Dockerfile Description

The Dockerfile includes the following main features:

```
FROM ubuntu:22.04
# Install necessary tools and dependencies
# Set timezone to Asia/Shanghai
# Install the latest version of cloudflared, supporting multiple architectures
# Set up health checks
# Set environment variables and working directory
```

## Update Notes

Latest version (1.0.0) updates:

- Optimized Docker image, reduced size and improved security
- Enhanced error handling and recovery mechanisms
- Improved log structure and management
- Added health check functionality
- Added container status monitoring
- Optimized timezone settings (default Asia/Shanghai)
- Added more network diagnostic tools
- Support for multi-architecture deployment
