# RuPod Tunnel Service

A collection of automated scripts for managing Cloudflare Tunnels, Docker environments, and system configurations. This project is designed to simplify the deployment and management of secure tunnels and web services on Ubuntu (specifically optimized for ARM64/Tokyocabinet environments).

## 🚀 Features

- **Automated Cloudflare Tunnel Management**:
  - Create and delete tunnels with automatic DNS routing.
  - Support for multiple service types: Web (HTTP), SSH, VNC, RDP, and Ollama.
  - Persistent tunnel sessions using `tmux`.
- **Tunnel Lifecycle Management**:
  - Automatic cleanup of unhealthy or disconnected tunnels.
  - Batch start/recovery of existing tunnels.
- **Environment Setup**:
  - One-click Docker installation (optimized for ARM64).
  - Quick Nginx deployment via Docker.
  - System configuration management (`.bashrc`, `PS1`, etc.).

## 📂 Core Scripts

| Script | Description |
| :--- | :--- |
| `cf-auto.sh` | The main tool for creating/deleting Cloudflare tunnels with DNS integration. Now supports automatic token loading and improved service detection. |
| `cf-tmux-all.sh` | Scans `/etc/cloudflared/*.yml` and ensures all tunnels are running in a `tmux` session. |
| `0_clean_empty_tunnels.sh` | Automatically detects and removes tunnels without active connections (unhealthy) and their associated DNS records. |
| `1_delete_CNAME-4-tunnels-gone.sh` | Advanced cleanup tool that scans Cloudflare DNS records and removes CNAMEs pointing to non-existent tunnels. |
| `arm64_docker_install.sh` | Installs Docker and Docker Compose on Ubuntu ARM64. |
| `docker_nginx_on.sh` | Quickly launches an Nginx container. |
| `set_ps1.sh` | Customizes the Bash prompt (PS1) for better visibility. |

## 🛠 Installation & Prerequisites

### Prerequisites

- **Cloudflare Account**: You need a Cloudflare account and a registered domain.
- **Cloudflared CLI**: Install `cloudflared` on your system.
- **Authentication**: Run `cloudflared tunnel login` to authenticate before using the scripts.
- **API Token**: For DNS management, place your Cloudflare API token in `/etc/cloudflared/.cf_token` (Format: `CF_TOKEN="your_token"`) or set it as an environment variable.

### Setup

1. Clone the repository:
   ```bash
   git clone git@github.com:tom522118/RuPod-Tunnel-Service.git
   cd RuPod-Tunnel-Service
   ```

2. Make scripts executable:
   ```bash
   chmod +x *.sh
   ```

## 📖 Usage Examples

### 1. Create a Web Tunnel
Automatically creates a tunnel, sets up DNS for `web01.yourdomain.com`, and points it to local port 80.
```bash
sudo ./cf-auto.sh web01.yourdomain.com
```

### 2. Create a Tunnel for a Specific Port
```bash
sudo ./cf-auto.sh myapp.yourdomain.com 8080
```

### 3. Delete a Tunnel and its DNS Record
```bash
sudo ./cf-auto.sh delete web01.yourdomain.com
```

### 4. Restart All Tunnels in Background
```bash
sudo ./cf-tmux-all.sh
```
To view the running tunnels, use: `tmux a -t cf-tunnels`.

### 5. Cleanup Dead Tunnels (Unhealthy)
```bash
./0_clean_empty_tunnels.sh
```

### 6. Cleanup Stale DNS Records (Missing Tunnels)
```bash
./1_delete_CNAME-4-tunnels-gone.sh
```

## 🛡 Security Note

- **API Tokens**: Never commit your `CF_TOKEN` or `GITHUB_TOKEN` to the repository.
- **Permissions**: Tunnels created by `cf-auto.sh` store credentials in `/etc/cloudflared/` with restricted permissions (600).

## 📄 License

This project is open-source. Feel free to use and modify it for your own needs.
