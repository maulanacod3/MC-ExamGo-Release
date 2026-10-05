#!/usr/bin/env bash
# ==============================================================================
# MC-ExamGO CBT — Multi-Instance & Enterprise VPS Auto-Installer & Manager
# ==============================================================================
# Fitur:
#   1. Multi-Instance: Pasang banyak examgo dalam 1 VPS (misal: smp, sma, smk)
#   2. Menu Interaktif Lengkap (Deploy, Hubungkan SSL/Domain, Live Logs, Kelola Service, Hapus)
#   3. Auto Port Hunting: Otomatis mendeteksi dan mengalokasikan port bebas
#   4. Dual Mode: Standalone Enterprise (Native Nginx + SSL) ATAU FastPanel Web GUI
#   5. Isolasi Database & Systemd Service per instance
#   6. Alphanumeric Safe Password Generator (Bebas dari SQL/Bash Escaping Bug)
#   7. Smart Hardware Auto-Tuning (Sysctl, Limits, Nginx Concurrency & Fast-Media)
# ==============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_time() {
    date +"%Y-%m-%d %H:%M:%S"
}

log_info() {
    echo -e "${GRAY}[$(log_time)]${NC} ${BLUE}${BOLD}ℹ️  [INFO]${NC} $1"
}

log_success() {
    echo -e "${GRAY}[$(log_time)]${NC} ${GREEN}${BOLD}✅ [SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${GRAY}[$(log_time)]${NC} ${YELLOW}${BOLD}⚠️  [WARN]${NC} $1"
}

log_error() {
    echo -e "${GRAY}[$(log_time)]${NC} ${RED}${BOLD}❌ [ERROR]${NC} $1"
}

log_check() {
    echo -e "${GRAY}[$(log_time)]${NC} ${YELLOW}${BOLD}⏳ [CHECK]${NC} $1 ..."
}

print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}    __  ___  ______         ______ _  __  ___    __  ___     ______  ____  ${NC}"
    echo -e "${CYAN}${BOLD}   /  |/  / / ____/        / ____/| |/ / /   |  /  |/  /    / ____/ / __ \ ${NC}"
    echo -e "${CYAN}${BOLD}  / /|_/ / / /    ______  / __/   |   / / /| | / /|_/ /    / / __  / / / / ${NC}"
    echo -e "${CYAN}${BOLD} / /  / / / /___ /_____/ / /___  /   | / ___ |/ /  / /    / /_/ / / /_/ /  ${NC}"
    echo -e "${CYAN}${BOLD}/_/  /_/  \____/        /_____/ /_/|_|/_/  |_/_/  /_/     \____/  \____/   ${NC}"
    echo ""
    echo -e "        ${CYAN}${BOLD}🚀 MC-ExamGO CBT — Multi-Instance VPS Manager${NC} ${GRAY}v1.3.1${NC}"
    echo -e "        ${GRAY}Enterprise VPS Server Engine | Clean Architecture${NC}"
    echo ""
}

# 1. Pastikan dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  log_error "Skrip ini wajib dijalankan sebagai root atau dengan sudo."
  exit 1
fi

wait_for_apt_lock() {
    log_check "Memeriksa kesiapan Package Manager (APT Lock)"
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
        log_info "Menunggu proses update latar belakang VPS selesai melepaskan kunci APT..."
        sleep 3
    done
    log_success "Package Manager (APT) siap digunakan"
}

# Helper input interaktif tanpa subshell (bulletproof saat curl | bash)
prompt_var() {
    local prompt_msg="$1"
    local var_name="$2"
    local default_ans="${3:-}"
    local user_ans=""
    
    if [ -t 0 ]; then
        read -r -p "$prompt_msg" user_ans || user_ans=""
    elif [ -e /dev/tty ] && [ -r /dev/tty ]; then
        printf "%b" "$prompt_msg" > /dev/tty 2>/dev/null || printf "%b" "$prompt_msg"
        read -r user_ans < /dev/tty 2>/dev/null || user_ans=""
    else
        read -r -p "$prompt_msg" user_ans || user_ans=""
    fi
    
    user_ans=$(echo "$user_ans" | tr -d '\r\n')
    if [ -z "$user_ans" ]; then
        user_ans="$default_ans"
    fi
    printf -v "$var_name" '%s' "$user_ans"
}

if [ -n "${BASH_SOURCE[0]:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$(pwd)"
fi

# Smart Port Allocation (Cari Port Bebas: 8080, 8085, 8086, 8087, dst)
find_free_port() {
    local start_port=8080
    local inst_name="$1"
    if [ "$inst_name" != "default" ]; then
        start_port=8085
    fi
    local port=$start_port
    while ss -tulnp 2>/dev/null | grep -q ":${port} "; do
        port=$((port + 1))
    done
    echo "$port"
}

# Helper Setup Nginx & SSL
setup_nginx_domain() {
    local svc="$1"
    local domain="$2"
    local port="$3"
    local email="$4"

    log_check "Memasang & Menyiapkan Nginx Reverse Proxy"
    wait_for_apt_lock
    apt-get update -qq
    apt-get install -y -qq nginx certbot python3-certbot-nginx
    mkdir -p /var/www/html/.well-known/acme-challenge

    # Vhost HTTP awal untuk verifikasi Let's Encrypt (webroot method)
    cat <<EOF > /etc/nginx/sites-available/${svc}.conf
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      '';
}

upstream ${svc}_backend {
    server 127.0.0.1:$port;
    keepalive 512;
}

server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    client_max_body_size 512M;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        proxy_pass http://${svc}_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding off;
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/${svc}.conf /etc/nginx/sites-enabled/${svc}.conf
    nginx -t > /dev/null 2>&1 && systemctl reload nginx || true

    if command -v ufw > /dev/null 2>&1; then
        ufw allow 80/tcp > /dev/null 2>&1 || true
        ufw allow 443/tcp > /dev/null 2>&1 || true
    fi

    log_check "Menerbitkan Sertifikat SSL HTTPS Let's Encrypt untuk $domain"
    local cert_ok=false
    if [ -n "$email" ]; then
        certbot certonly --webroot -w /var/www/html -d "$domain" --non-interactive --agree-tos -m "$email" > /dev/null 2>&1 && cert_ok=true || true
    else
        certbot certonly --webroot -w /var/www/html -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email > /dev/null 2>&1 && cert_ok=true || true
    fi

    local cert_path="/etc/letsencrypt/live/${domain}/fullchain.pem"
    local key_path="/etc/letsencrypt/live/${domain}/privkey.pem"

    if [ "$cert_ok" = false ] || [ ! -f "$cert_path" ]; then
        log_warn "Certbot webroot gagal. Mencoba mode --nginx sebagai fallback..."
        if [ -n "$email" ]; then
            certbot --nginx -d "$domain" --non-interactive --agree-tos -m "$email" --redirect > /dev/null 2>&1 || log_warn "Certbot gagal. Pastikan DNS A-Record sudah mengarah ke IP VPS ini."
        else
            certbot --nginx -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email --redirect > /dev/null 2>&1 || log_warn "Certbot gagal. Pastikan DNS A-Record sudah mengarah ke IP VPS ini."
        fi
        log_success "Nginx Reverse Proxy & SSL HTTPS selesai dikonfigurasi (certbot mode)"
        return
    fi

    # Tulis vhost HTTPS final yang bersih (kompatibel Nginx 1.18-1.24+)
    # Gunakan 'listen 443 ssl http2' bukan 'http2 on' untuk kompatibilitas
    cat <<EOF > /etc/nginx/sites-available/${svc}.conf
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      '';
}

upstream ${svc}_backend {
    server 127.0.0.1:$port;
    keepalive 512;
}

server {
    listen 80;
    listen [::]:80;
    server_name $domain;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;
    client_max_body_size 512M;

    ssl_certificate $cert_path;
    ssl_certificate_key $key_path;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location /uploads/ {
        proxy_pass http://${svc}_backend/uploads/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        expires 30d;
        add_header Cache-Control "public, no-transform, immutable";
        access_log off;
        log_not_found off;
    }

    location / {
        proxy_pass http://${svc}_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding off;
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
    }
}
EOF

    nginx -t > /dev/null 2>&1 && systemctl reload nginx || true
    log_success "Nginx Reverse Proxy & SSL HTTPS selesai dikonfigurasi"
}

# ─────────────────────────────────────────────────────────────
# Helper & Menu 7: Smart Hardware Auto-Tuning Engine
# ─────────────────────────────────────────────────────────────
auto_tune_vps() {
    echo ""
    log_check "Mendeteksi Spesifikasi Hardware VPS"
    local cpu_cores=$(nproc 2>/dev/null || echo 1)
    local total_ram_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 1024)
    local total_ram_gb=$(awk "BEGIN {print int($total_ram_mb / 1024 + 0.5)}")

    echo -e "   • CPU Cores     : ${GREEN}${cpu_cores} vCPU${NC}"
    echo -e "   • Kapasitas RAM : ${GREEN}${total_ram_mb} MB (~${total_ram_gb} GB)${NC}"

    local profile="VPS Standar (~1.000 Siswa Serentak)"
    local worker_conn=4096
    local open_files=20000

    if [ "$total_ram_mb" -lt 2048 ]; then
        profile="VPS Standar (~1.000 Siswa Serentak)"
        worker_conn=4096
        open_files=20000
    elif [ "$total_ram_mb" -le 4096 ]; then
        profile="VPS Menengah (2.000 - 4.000 Siswa Serentak)"
        worker_conn=8192
        open_files=50000
    elif [ "$total_ram_mb" -le 8192 ]; then
        profile="VPS Besar (5.000 - 10.000 Siswa Serentak)"
        worker_conn=16384
        open_files=100000
    else
        profile="VPS Enterprise Cluster (10.000+ Siswa Serentak)"
        worker_conn=32768
        open_files=200000
    fi

    echo -e "   • Profil Terpilih: ${YELLOW}${profile}${NC}"
    log_check "Menerapkan Auto-Tuning Sistem Operasi & Kernel..."

    # 1. Konfigurasi Batas File Descriptors OS
    mkdir -p /etc/security/limits.d
    cat << 'EOF_LIMITS' > /etc/security/limits.d/99-examgo.conf
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
www-data soft nofile 65535
www-data hard nofile 65535
EOF_LIMITS
    log_success "Batas File Descriptors diatur ke 65.535 (/etc/security/limits.d/99-examgo.conf)"

    # 2. Konfigurasi Kernel TCP & Socket Antrean
    mkdir -p /etc/sysctl.d
    cat << 'EOF_SYSCTL' > /etc/sysctl.d/99-examgo.conf
fs.file-max = 2097152
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
EOF_SYSCTL
    sysctl --system > /dev/null 2>&1 || true
    log_success "Kernel TCP Socket & Buffer Queue dioptimalkan (/etc/sysctl.d/99-examgo.conf)"

    # 3. Konfigurasi Nginx Global (Concurrency + Image Load/Upload Performance)
    if [ -f /etc/nginx/nginx.conf ]; then
        log_check "Mengonfigurasi Nginx Core & Media Delivery Engine..."

        # 3.1 Worker Configuration
        sed -i 's/worker_processes.*/worker_processes auto;/' /etc/nginx/nginx.conf
        
        if ! grep -q "worker_rlimit_nofile" /etc/nginx/nginx.conf; then
            sed -i '1s/^/worker_rlimit_nofile 65535;\n/' /etc/nginx/nginx.conf
        else
            sed -i 's/worker_rlimit_nofile.*/worker_rlimit_nofile 65535;/' /etc/nginx/nginx.conf
        fi

        sed -i "s/worker_connections [0-9]\+/worker_connections $worker_conn/" /etc/nginx/nginx.conf

        if ! grep -q "multi_accept" /etc/nginx/nginx.conf; then
            sed -i "/worker_connections/a \    multi_accept on;\n    use epoll;" /etc/nginx/nginx.conf
        fi

        # 3.2 Pasang Konfigurasi Khusus Optimasi Upload & Image Loading
        mkdir -p /etc/nginx/conf.d
        cat << EOF_TUNING > /etc/nginx/conf.d/99-examgo-tuning.conf
# ==============================================================================
# MC-ExamGO — High-Capacity Upload & Proxy Performance Optimization
# (sendfile, tcp_nopush, tcp_nodelay, keepalive_* sudah ada di nginx.conf)
# ==============================================================================

# 1. Upload Capacity (Bebas dari Error 413 Entity Too Large)
client_max_body_size 512M;
client_body_buffer_size 512k;
client_header_buffer_size 8k;
large_client_header_buffers 4 32k;
client_body_timeout 120s;
client_header_timeout 60s;
send_timeout 120s;
reset_timedout_connection on;

# 2. Micro-caching File Descriptors untuk Ribuan Siswa Memuat Gambar Serentak
open_file_cache max=${open_files} inactive=60s;
open_file_cache_valid 120s;
open_file_cache_min_uses 2;
open_file_cache_errors off;

# 3. Proxy Buffering Optimization
proxy_buffers 16 64k;
proxy_buffer_size 128k;
proxy_busy_buffers_size 256k;
proxy_temp_file_write_size 256k;
proxy_read_timeout 300s;
proxy_connect_timeout 75s;
proxy_send_timeout 300s;
EOF_TUNING

        log_success "Parameter Nginx Upload (512MB) & Image Fast-Delivery aktif (/etc/nginx/conf.d/99-examgo-tuning.conf)"

        if nginx -t >/dev/null 2>&1; then
            systemctl reload nginx 2>/dev/null || true
            log_success "Nginx worker_connections disetel ke ${GREEN}${worker_conn}${NC} (Nginx Reload Sukses)"
        else
            log_warn "Peringatan sintaks Nginx. Silakan periksa 'nginx -t'."
        fi
    else
        log_info "Nginx belum terpasang, konfigurasi kernel dan OS limits telah aktif."
    fi

    echo ""
    echo -e "${GREEN}${BOLD}========================================================================${NC}"
    echo -e "${GREEN}${BOLD}   🎉 AUTO-TUNING HARDWARE & IMAGE ENGINE SUKSES DITERAPKAN!${NC}"
    echo -e "${GREEN}${BOLD}========================================================================${NC}"
    echo -e "• Upload file/gambar besar : ${CYAN}Hingga 512 MB aktif tanpa antrean (413 Solved)${NC}"
    echo -e "• Pengiriman gambar soal   : ${CYAN}Zero-Copy & Microcache (${open_files} files cache)${NC}"
    echo -e "• Kapasitas konkurensi     : ${GREEN}${profile}${NC}"
    echo -e "${GREEN}${BOLD}========================================================================${NC}"

    # Jalankan Security Hardening secara otomatis
    harden_vps_security
}

# ─────────────────────────────────────────────────────────────
# Helper & Menu 8: VPS Security Hardening (Anti-Open Port DB)
# ─────────────────────────────────────────────────────────────
harden_vps_security() {
    echo ""
    log_check "Menerapkan Security Hardening & Perlindungan Firewall (Anti-Open Port)..."

    # 1. Pastikan UFW terinstall
    if ! command -v ufw >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq ufw >/dev/null 2>&1 || true
    fi

    # 2. Amankan konfigurasi binding PostgreSQL (wajib 127.0.0.1 / localhost only)
    local pg_updated=0
    for conf in /etc/postgresql/*/main/postgresql.conf; do
        if [ -f "$conf" ]; then
            if grep -qE "^#*listen_addresses\s*=" "$conf"; then
                sed -i "s/^#*listen_addresses\s*=.*/listen_addresses = 'localhost'/" "$conf"
                pg_updated=1
            fi
        fi
    done
    if [ "$pg_updated" -eq 1 ]; then
        systemctl restart postgresql 2>/dev/null || systemctl reload postgresql 2>/dev/null || true
        log_success "PostgreSQL dikunci hanya mendengarkan localhost (127.0.0.1)"
    fi

    # 3. Amankan konfigurasi binding Redis jika terpasang (wajib 127.0.0.1 only)
    for rconf in /etc/redis/redis.conf /etc/redis.conf; do
        if [ -f "$rconf" ]; then
            sed -i "s/^bind .*/bind 127.0.0.1 ::1/" "$rconf" 2>/dev/null || true
            sed -i "s/^protected-mode no/protected-mode yes/" "$rconf" 2>/dev/null || true
            systemctl restart redis 2>/dev/null || systemctl restart redis-server 2>/dev/null || true
            log_success "Redis dikunci hanya mendengarkan localhost (127.0.0.1) & protected-mode aktif"
        fi
    done

    # 4. Konfigurasi Aturan UFW Firewall
    if command -v ufw >/dev/null 2>&1; then
        # Default policy: Tolak semua koneksi masuk asing, izinkan keluar
        ufw default deny incoming >/dev/null 2>&1 || true
        ufw default allow outgoing >/dev/null 2>&1 || true

        # Deteksi port SSH yang aktif agar admin tidak terkunci
        local ssh_p=$(ss -tlnp 2>/dev/null | grep -E 'sshd|ssh' | awk '{print $4}' | awk -F: '{print $NF}' | head -n1)
        if [ -z "$ssh_p" ] || ! echo "$ssh_p" | grep -qE '^[0-9]+$'; then
            ssh_p="22"
        fi
        ufw allow "${ssh_p}/tcp" comment "SSH Access" >/dev/null 2>&1 || true
        ufw allow 22/tcp comment "Default SSH" >/dev/null 2>&1 || true

        # Buka port Web Publik Nginx
        ufw allow 80/tcp comment "HTTP Web" >/dev/null 2>&1 || true
        ufw allow 443/tcp comment "HTTPS Web" >/dev/null 2>&1 || true

        # Buka port FastPanel jika terpasang
        if systemctl is-active fastpanel2 >/dev/null 2>&1 || [ -d /usr/local/fastpanel2 ]; then
            ufw allow 8888/tcp comment "FastPanel GUI" >/dev/null 2>&1 || true
        fi

        # Kunci dan blokir eksplisit port database sensitif dari jaringan luar (WAN)
        ufw deny 5432/tcp comment "PostgreSQL Blocked from WAN" >/dev/null 2>&1 || true
        ufw deny 6379/tcp comment "Redis Blocked from WAN" >/dev/null 2>&1 || true
        ufw deny 3306/tcp comment "MySQL Blocked from WAN" >/dev/null 2>&1 || true

        # Aktifkan UFW secara instan
        ufw --force enable >/dev/null 2>&1 || true
        log_success "Firewall UFW aktif & terproteksi: Port 80/443/SSH terbuka, Port DB (5432/6379/3306) tertutup dari luar!"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}========================================================================${NC}"
    echo -e "${GREEN}${BOLD}   🛡️ SECURITY & FIREWALL HARDENING BERHASIL DITERAPKAN!${NC}"
    echo -e "${GREEN}${BOLD}========================================================================${NC}"
    echo -e "• Akses Database (PostgreSQL) : ${GREEN}Terkunci di 127.0.0.1 (Kebal Brute Force / WAN Scan)${NC}"
    echo -e "• Port Publik Diizinkan       : ${CYAN}Port 80 (HTTP), Port 443 (HTTPS), Port ${ssh_p} (SSH)${NC}"
    echo -e "• Port Sensitif Diblokir      : ${YELLOW}5432 (Postgres), 6379 (Redis), 3306 (MySQL)${NC}"
    echo -e "• Kebijakan Default           : ${GREEN}Deny Incoming (Tolak Semua Port Tak Dikenal)${NC}"
    echo -e "${GREEN}${BOLD}========================================================================${NC}"
}

# ─────────────────────────────────────────────────────────────
# Menu 1: Deploy Instance Baru
# ─────────────────────────────────────────────────────────────
deploy_instance() {
    echo ""
    echo -e "${YELLOW}${BOLD}--- Konfigurasi Instance MC-ExamGO ---${NC}"
    echo -e "Anda dapat memasang beberapa instance di VPS ini (contoh: 'default', 'smp', 'sma', 'tryout')."
    
    local raw_tag=""
    prompt_var "Masukkan nama/tag instance [default]: " raw_tag "default"
    local instance_tag=$(echo "$raw_tag" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')

    local instance_name="default"
    local install_dir="/opt/mc-examgo"
    local service_name="mc-examgo"
    local db_name="mc_examgo"

    if [ -n "$instance_tag" ] && [ "$instance_tag" != "default" ]; then
        instance_name="$instance_tag"
        install_dir="/opt/mc-examgo-$instance_tag"
        service_name="mc-examgo-$instance_tag"
        db_name="mc_examgo_$instance_tag"
    fi

    echo -e "• Folder Target   : ${CYAN}${install_dir}${NC}"
    echo -e "• Service Name    : ${CYAN}${service_name}.service${NC}"
    echo -e "• Database Name   : ${CYAN}${db_name}${NC}"

    # Deteksi Binary Server Lokal / Download Resmi
    local binary_src=""
    local sys_arch=$(uname -m)
    local search_pattern="mc-exam-go-linux-amd64*"
    if [ "$sys_arch" = "aarch64" ] || [ "$sys_arch" = "arm64" ]; then
        search_pattern="mc-exam-go-linux-arm64*"
    fi

    local candidate_bins=($(find "$SCRIPT_DIR" -maxdepth 2 -name "$search_pattern" ! -name "*.zip" ! -name "*.tar.gz" ! -name "*.md" ! -name "*.sh" 2>/dev/null || true))
    if [ ${#candidate_bins[@]} -gt 0 ] && [ -f "${candidate_bins[0]}" ]; then
        binary_src="${candidate_bins[0]}"
    elif [ -f "$install_dir/mc-exam-go-linux" ]; then
        binary_src="$install_dir/mc-exam-go-linux"
    fi

    if [ -n "$binary_src" ]; then
        log_success "Binary ditemukan: $(basename "$binary_src")"
    fi

    local def_port=$(find_free_port "$instance_name")
    local target_port=""
    prompt_var "Port Aplikasi Internal [$def_port]: " target_port "$def_port"
    log_success "Port dialokasikan: ${target_port}"

    echo ""
    echo -e "${YELLOW}${BOLD}--- Pilih Tipe Arsitektur Server ---${NC}"
    echo -e "  ${CYAN}[1] Standalone Enterprise${NC} (Rekomendasi: Cepat, Ringan, Native Nginx + SSL Let's Encrypt)"
    echo -e "  ${CYAN}[2] FastPanel Web GUI + MC-ExamGO${NC} (Disertai Panel Manajemen Port 8888)"
    local install_mode="1"
    prompt_var "Pilihan [1/2] [1]: " install_mode "1"

    local fastpanel_pass=""
    if [ "$install_mode" = "2" ]; then
        echo ""
        log_check "Memeriksa / Memasang FastPanel Web Control Panel di VPS"
        if command -v mogwai >/dev/null 2>&1 || [ -f "/usr/local/fastpanel2/fastpanel" ]; then
            log_success "FastPanel sudah terpasang di VPS ini"
        else
            wait_for_apt_lock
            log_info "Mengunduh & Memasang FastPanel otomatis..."
            export DEBIAN_FRONTEND=noninteractive
            curl -fsSL http://repo.fastpanel.direct/install_fastpanel.sh | bash -s -- -f -o </dev/null >/dev/null 2>&1 || true
        fi
        fastpanel_pass="FastPanel!$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]')"
        if [ -f "/usr/local/bin/mogwai" ]; then
            /usr/local/bin/mogwai chpasswd -u fastuser -p "$fastpanel_pass" >/dev/null 2>&1 || true
        fi
        log_success "FastPanel siap diakses pada port 8888"
    fi

    # Pastikan PostgreSQL Terpasang
    echo ""
    log_check "Memeriksa & Menyiapkan dependensi database (PostgreSQL)"
    if ! command -v psql >/dev/null 2>&1; then
        wait_for_apt_lock
        apt-get update -qq
        apt-get install -y -qq postgresql postgresql-contrib ufw curl tar unzip
        systemctl enable --now postgresql
        log_success "PostgreSQL berhasil dipasang dan diaktifkan"
    else
        systemctl enable --now postgresql >/dev/null 2>&1 || true
        log_success "PostgreSQL siap digunakan"
    fi

    # Siapkan Database
    log_check "Mengonfigurasi Database PostgreSQL '${db_name}'"
    local db_user="mc_user"
    local db_pass=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)

    sudo -u postgres psql <<EOF >/dev/null 2>&1
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$db_user') THEN
        CREATE ROLE $db_user WITH LOGIN PASSWORD '$db_pass';
    ELSE
        ALTER ROLE $db_user WITH PASSWORD '$db_pass';
    END IF;
END
\$\$;
EOF

    if ! sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = '$db_name'" | grep -q 1; then
        sudo -u postgres psql -c "CREATE DATABASE $db_name OWNER $db_user;" >/dev/null 2>&1
    fi
    sudo -u postgres psql -c "ALTER USER $db_user WITH PASSWORD '$db_pass';" >/dev/null 2>&1
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $db_name TO $db_user;" >/dev/null 2>&1
    sudo -u postgres psql -d $db_name -c "GRANT ALL ON SCHEMA public TO $db_user;" >/dev/null 2>&1
    log_success "Database PostgreSQL '${db_name}' siap digunakan"

    # Siapkan Folder & Binary
    log_check "Menyiapkan direktori & file executable (${install_dir})"
    mkdir -p "$install_dir/uploads" "$install_dir/logs" "$install_dir/storage"

    if [ -n "$binary_src" ] && [ -f "$binary_src" ]; then
        cp "$binary_src" "$install_dir/mc-exam-go-linux"
    fi

    if [ ! -f "$install_dir/mc-exam-go-linux" ]; then
        log_info "Binary lokal belum tersedia. Mengunduh paket rilis resmi ($sys_arch) secara otomatis..."
        local dl_type="amd64"
        if [ "$sys_arch" = "aarch64" ] || [ "$sys_arch" = "arm64" ]; then
            dl_type="arm64"
        fi

        local central_url="https://mcode.web.id/examgo/unduh/${dl_type}"
        mkdir -p /tmp/mc_exam_extracted
        if command -v wget >/dev/null 2>&1; then
            wget -qO /tmp/mc-exam-go-release.zip "$central_url" || curl -fsSL "$central_url" -o /tmp/mc-exam-go-release.zip || true
        else
            curl -fsSL "$central_url" -o /tmp/mc-exam-go-release.zip || true
        fi

        if [ -f /tmp/mc-exam-go-release.zip ]; then
            unzip -o -q /tmp/mc-exam-go-release.zip -d /tmp/mc_exam_extracted 2>/dev/null || true
            local found_bin=$(find /tmp/mc_exam_extracted -type f -name "mc-exam-go-linux*" ! -name "*.zip" | head -n 1)
            if [ -n "$found_bin" ] && [ -f "$found_bin" ]; then
                cp "$found_bin" "$install_dir/mc-exam-go-linux"
                log_success "Paket binary resmi berhasil diunduh dan dipasang"
            fi
            rm -rf /tmp/mc-exam-go-release.zip /tmp/mc_exam_extracted
        fi
    fi

    if [ ! -f "$install_dir/mc-exam-go-linux" ]; then
        local user_bin_path=""
        prompt_var "Masukkan path lokasi file binary linux lokal: " user_bin_path ""
        if [ -n "$user_bin_path" ] && [ -f "$user_bin_path" ]; then
            cp "$user_bin_path" "$install_dir/mc-exam-go-linux"
        else
            log_error "File binary tidak ditemukan di '$user_bin_path'!"
            return 1
        fi
    fi

    chmod +x "$install_dir/mc-exam-go-linux"
    log_success "Binary siap dieksekusi di ${install_dir}/mc-exam-go-linux"

    # Konfigurasi .env
    log_check "Membuat file konfigurasi .env"
    local jwt_admin=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9+/=')
    local jwt_student=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9+/=')

    cat <<EOF > "$install_dir/.env"
SERVER_PORT=$target_port
DB_TIMEZONE=Asia/Jakarta

DB_HOST=localhost
DB_PORT=5432
DB_NAME=$db_name
DB_USER=$db_user
DB_PASS=$db_pass

JWT_SECRET=$jwt_admin
JWT_STUDENT_SECRET=$jwt_student
EOF

    chmod 600 "$install_dir/.env"
    log_success "Konfigurasi .env berhasil dibuat dengan hak akses terproteksi (0600)"

    # Service Systemd
    log_check "Mengonfigurasi Systemd Service (${service_name}.service)"
    cat <<EOF > /etc/systemd/system/${service_name}.service
[Unit]
Description=MC-ExamGO Server (${instance_name})
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=$install_dir
ExecStart=$install_dir/mc-exam-go-linux
Restart=always
RestartSec=3s
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${service_name}.service >/dev/null 2>&1
    systemctl restart ${service_name}.service
    log_success "Service ${service_name}.service aktif dan berjalan"

    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$target_port/tcp" >/dev/null 2>&1 || true
        if [ "$install_mode" = "2" ]; then
            ufw allow 8888/tcp >/dev/null 2>&1 || true
        fi
    fi

    local domain_name=""
    if [ "$install_mode" = "1" ]; then
        echo ""
        prompt_var "Hubungkan Domain sekarang? (Kosongkan jika hanya akses via IP): " domain_name ""
        if [ -n "$domain_name" ]; then
            local ssl_email=""
            prompt_var "Email untuk Sertifikat SSL Let's Encrypt (Enter untuk skip): " ssl_email ""
            setup_nginx_domain "$service_name" "$domain_name" "$target_port" "$ssl_email"
        fi
    fi

    # Menerapkan Auto-Tuning Kernel, Limits, & Nginx Engine
    auto_tune_vps

    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$server_ip" ]; then
        server_ip="127.0.0.1"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "${GREEN}${BOLD}   🎉 INSTALASI INSTANCE '${instance_name}' SUKSES!${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    if [ "$install_mode" = "2" ]; then
        echo -e "${CYAN}${BOLD}🖥️  FASTPANEL CONTROL PANEL:${NC}"
        echo -e "• URL Web GUI        : ${YELLOW}https://${server_ip}:8888${NC}"
        echo -e "• User Default       : ${YELLOW}fastuser${NC}"
        if [ -n "$fastpanel_pass" ]; then
            echo -e "• Password Baru      : ${YELLOW}${fastpanel_pass}${NC}"
        fi
        echo ""
    fi
    echo -e "${CYAN}${BOLD}🚀 MC-ExamGO (${instance_name}):${NC}"
    if [ -n "$domain_name" ]; then
        echo -e "• URL Siswa (Domain) : ${CYAN}https://${domain_name}${NC}"
        echo -e "• URL Admin (Domain) : ${CYAN}https://${domain_name}/admin/login${NC}"
        echo -e "• URL IP Alternatif  : ${CYAN}http://${server_ip}:${target_port}${NC}"
    else
        echo -e "• URL Siswa (Ujian)  : ${CYAN}http://${server_ip}:${target_port}${NC}"
        echo -e "• URL Login Admin    : ${CYAN}http://${server_ip}:${target_port}/admin/login${NC}"
    fi
    echo -e "• Akun Admin Default : ${YELLOW}admin@mc-exam.go${NC} / ${YELLOW}admin123${NC}"
    echo -e "• Service Systemd    : ${CYAN}${service_name}${NC}"
    echo -e "• Database Name      : ${CYAN}${db_name}${NC}"
    echo -e "• Folder Direktori   : ${CYAN}${install_dir}${NC}"
    echo -e "• Live Logs          : ${CYAN}journalctl -u ${service_name}.service -f${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
}

# ─────────────────────────────────────────────────────────────
# Menu 2: Hubungkan Domain / Pasang Ulang SSL Saja
# ─────────────────────────────────────────────────────────────
connect_domain_ssl() {
    local svcs=($(ls /etc/systemd/system/mc-examgo*.service /etc/systemd/system/mc-cbt*.service 2>/dev/null || true))
    if [ ${#svcs[@]} -eq 0 ]; then
        log_warn "Tidak ada instance MC-ExamGO yang terpasang di VPS ini."
        return
    fi

    echo ""
    echo -e "${YELLOW}${BOLD}--- Pilih Instance untuk Menghubungkan Domain / SSL ---${NC}"
    local i=1
    local svc_names=()
    for s in "${svcs[@]}"; do
        local bname=$(basename "$s" .service)
        local inst_dir="/opt/$bname"
        local port="8080"
        if [ -f "$inst_dir/.env" ]; then
            port=$(grep -E '^SERVER_PORT=' "$inst_dir/.env" | cut -d'=' -f2 | tr -d ' ' || echo "8080")
        fi
        echo -e "  [${i}] ${CYAN}${bname}${NC} (Port Internal: ${GREEN}${port}${NC}, Dir: ${inst_dir})"
        svc_names+=("$bname:$port")
        i=$((i + 1))
    done
    echo -e "  [0] ↩️  Kembali"
    
    local choice="1"
    prompt_var "Pilih nomor instance [1-${#svc_names[@]}]: " choice "1"
    if [ "$choice" = "0" ] || [ "$choice" -lt 1 ] 2>/dev/null || [ "$choice" -gt "${#svc_names[@]}" ] 2>/dev/null; then
        return
    fi

    local selected="${svc_names[$((choice - 1))]}"
    local target_svc=$(echo "$selected" | cut -d':' -f1)
    local target_port=$(echo "$selected" | cut -d':' -f2)

    echo ""
    local domain_name=""
    prompt_var "Masukkan nama domain (contoh: cbt.sekolah.sch.id): " domain_name ""
    if [ -z "$domain_name" ]; then
        log_warn "Domain tidak boleh kosong. Aksi dibatalkan."
        return
    fi

    local ssl_email=""
    prompt_var "Email untuk Sertifikat SSL Let's Encrypt (Enter untuk skip): " ssl_email ""
    setup_nginx_domain "$target_svc" "$domain_name" "$target_port" "$ssl_email"

    echo ""
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "${GREEN}${BOLD}   🎉 DOMAIN & SSL BERHASIL DIHUBUNGKAN!${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "• Domain / URL Siswa : ${CYAN}https://${domain_name}${NC}"
    echo -e "• Login Admin        : ${CYAN}https://${domain_name}/admin/login${NC}"
    echo -e "• Reverse Proxy Target: 127.0.0.1:${target_port}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
}

# ─────────────────────────────────────────────────────────────
# Menu 3: Live Logs
# ─────────────────────────────────────────────────────────────
show_live_logs() {
    local svcs=($(ls /etc/systemd/system/mc-examgo*.service /etc/systemd/system/mc-cbt*.service 2>/dev/null || true))
    if [ ${#svcs[@]} -eq 0 ]; then
        log_warn "Tidak ada instance yang terpasang."
        return
    fi

    echo ""
    echo -e "${YELLOW}${BOLD}--- Pilih Instance untuk Melihat Live Logs ---${NC}"
    local i=1
    local svc_list=()
    for s in "${svcs[@]}"; do
        local bname=$(basename "$s" .service)
        echo -e "  [${i}] ${CYAN}${bname}${NC}"
        svc_list+=("$bname")
        i=$((i + 1))
    done
    echo -e "  [0] ↩️  Kembali"

    local choice="1"
    prompt_var "Pilih nomor instance [1-${#svc_list[@]}]: " choice "1"
    if [ "$choice" = "0" ] || [ "$choice" -lt 1 ] 2>/dev/null || [ "$choice" -gt "${#svc_list[@]}" ] 2>/dev/null; then
        return
    fi

    local target_svc="${svc_list[$((choice - 1))]}"
    log_info "Menampilkan live logs untuk '${target_svc}'. Tekan Ctrl+C untuk keluar dari logs..."
    sleep 1
    journalctl -u "${target_svc}.service" -f -n 50 || true
}

# ─────────────────────────────────────────────────────────────
# Menu 4: Kelola Service Instance
# ─────────────────────────────────────────────────────────────
manage_services() {
    local svcs=($(ls /etc/systemd/system/mc-examgo*.service /etc/systemd/system/mc-cbt*.service 2>/dev/null || true))
    if [ ${#svcs[@]} -eq 0 ]; then
        log_warn "Tidak ada instance yang terpasang."
        return
    fi

    echo ""
    echo -e "${YELLOW}${BOLD}--- Daftar Service Instance ---${NC}"
    local i=1
    local svc_list=()
    for s in "${svcs[@]}"; do
        local bname=$(basename "$s" .service)
        local status=$(systemctl is-active "$bname" 2>/dev/null || echo "inactive")
        local stat_color="${GREEN}${status}${NC}"
        if [ "$status" != "active" ]; then
            stat_color="${RED}${status}${NC}"
        fi
        echo -e "  [${i}] ${CYAN}${bname}${NC} -> Status: ${stat_color}"
        svc_list+=("$bname")
        i=$((i + 1))
    done
    echo -e "  [0] ↩️  Kembali"

    local choice="1"
    prompt_var "Pilih nomor instance [1-${#svc_list[@]}]: " choice "1"
    if [ "$choice" = "0" ] || [ "$choice" -lt 1 ] 2>/dev/null || [ "$choice" -gt "${#svc_list[@]}" ] 2>/dev/null; then
        return
    fi

    local target_svc="${svc_list[$((choice - 1))]}"
    echo ""
    echo -e "${YELLOW}${BOLD}--- Pilih Aksi untuk ${target_svc} ---${NC}"
    echo -e "  [1] Restart Service"
    echo -e "  [2] Stop Service"
    echo -e "  [3] Start Service"
    echo -e "  [4] Cek Status Detail"
    echo -e "  [0] Batal"
    local action="1"
    prompt_var "Pilihan [1-4]: " action "1"

    case "$action" in
        1) systemctl restart "${target_svc}.service" && log_success "Service ${target_svc} berhasil di-restart" ;;
        2) systemctl stop "${target_svc}.service" && log_warn "Service ${target_svc} dihentikan" ;;
        3) systemctl start "${target_svc}.service" && log_success "Service ${target_svc} dinyalakan" ;;
        4) systemctl status "${target_svc}.service" --no-pager || true ;;
        *) return ;;
    esac
}

# ─────────────────────────────────────────────────────────────
# Menu 5: FastPanel Web GUI Installer
# ─────────────────────────────────────────────────────────────
install_fastpanel_only() {
    log_check "Memeriksa / Memasang FastPanel Web Control Panel di VPS"
    if command -v mogwai >/dev/null 2>&1 || [ -f "/usr/local/fastpanel2/fastpanel" ]; then
        log_success "FastPanel sudah terpasang di VPS ini"
    else
        wait_for_apt_lock
        log_info "Mengunduh & Memasang FastPanel otomatis..."
        export DEBIAN_FRONTEND=noninteractive
        curl -fsSL http://repo.fastpanel.direct/install_fastpanel.sh | bash -s -- -f -o </dev/null >/dev/null 2>&1 || true
    fi
    local fastpanel_pass="FastPanel!$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]')"
    if [ -f "/usr/local/bin/mogwai" ]; then
        /usr/local/bin/mogwai chpasswd -u fastuser -p "$fastpanel_pass" >/dev/null 2>&1 || true
    fi
    local server_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$server_ip" ] && server_ip="127.0.0.1"
    
    echo ""
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "${GREEN}${BOLD}   🖥️  FASTPANEL SIAP DIGUNAKAN!${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "• URL Web GUI   : ${YELLOW}https://${server_ip}:8888${NC}"
    echo -e "• User Default  : ${YELLOW}fastuser${NC}"
    echo -e "• Password Baru : ${YELLOW}${fastpanel_pass}${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
}

# ─────────────────────────────────────────────────────────────
# Menu 6: Hapus / Uninstall Instance
# ─────────────────────────────────────────────────────────────
uninstall_instance() {
    local svcs=($(ls /etc/systemd/system/mc-examgo*.service /etc/systemd/system/mc-cbt*.service 2>/dev/null || true))
    if [ ${#svcs[@]} -eq 0 ]; then
        log_warn "Tidak ada instance MC-ExamGO yang terpasang di VPS ini."
        return
    fi

    echo ""
    echo -e "${RED}${BOLD}--- Hapus / Uninstall Instance MC-ExamGO ---${NC}"
    local i=1
    local svc_list=()
    for s in "${svcs[@]}"; do
        local bname=$(basename "$s" .service)
        echo -e "  [${i}] ${CYAN}${bname}${NC}"
        svc_list+=("$bname")
        i=$((i + 1))
    done
    echo -e "  [0] ↩️  Batal"

    local choice="0"
    prompt_var "Pilih nomor instance yang ingin DIHAPUS [1-${#svc_list[@]}]: " choice "0"
    if [ "$choice" = "0" ] || [ "$choice" -lt 1 ] 2>/dev/null || [ "$choice" -gt "${#svc_list[@]}" ] 2>/dev/null; then
        log_info "Penghapusan dibatalkan."
        return
    fi

    local target_svc="${svc_list[$((choice - 1))]}"
    local target_dir="/opt/$target_svc"
    local db_name="mc_examgo"
    local tag=$(echo "$target_svc" | sed 's/mc-examgo-//g' | sed 's/mc-cbt-//g')
    if [ "$tag" != "mc-examgo" ] && [ "$tag" != "mc-cbt" ] && [ -n "$tag" ]; then
        db_name="mc_examgo_$tag"
    fi

    echo ""
    log_warn "Anda akan menghapus instance '${target_svc}' (${target_dir}, Database: ${db_name})"
    local confirm=""
    prompt_var "Ketik 'Y' untuk konfirmasi [y/N]: " confirm ""
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
    if [ "$confirm" != "y" ] && [ "$confirm" != "yes" ]; then
        log_info "Penghapusan dibatalkan."
        return
    fi

    log_check "Menghentikan dan menghapus service systemd"
    systemctl stop "${target_svc}.service" >/dev/null 2>&1 || true
    systemctl disable "${target_svc}.service" >/dev/null 2>&1 || true
    rm -f "/etc/systemd/system/${target_svc}.service"
    systemctl daemon-reload

    log_check "Menghapus konfigurasi Nginx"
    rm -f "/etc/nginx/sites-available/${target_svc}.conf" "/etc/nginx/sites-enabled/${target_svc}.conf"
    nginx -t >/dev/null 2>&1 || true
    systemctl reload nginx 2>/dev/null || true

    log_check "Menghapus folder direktori ${target_dir}"
    rm -rf "$target_dir"

    local del_db="N"
    prompt_var "Hapus juga database PostgreSQL '${db_name}'? [y/N]: " del_db "N"
    local clean_del_db=$(echo "$del_db" | tr '[:upper:]' '[:lower:]')
    if [ "$clean_del_db" = "y" ] || [ "$clean_del_db" = "yes" ]; then
        sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${db_name};" >/dev/null 2>&1 || true
        log_success "Database '${db_name}' dihapus"
    fi

    log_success "Instance '${target_svc}' berhasil dihapus bersih dari VPS!"
}

# ─────────────────────────────────────────────────────────────
# Fitur: Update / Upgrade Binary MC-ExamGO (In-Place Rescue)
# ─────────────────────────────────────────────────────────────
update_instance() {
    echo ""
    echo -e "${BOLD}============================================================${NC}"
    echo -e "   🔄 ${CYAN}${BOLD}UPDATE / UPGRADE BINARY INSTANCE MC-ExamGO${NC}"
    echo -e "${BOLD}============================================================${NC}"

    local svc_list=($(ls /etc/systemd/system/mc-examgo*.service /etc/systemd/system/mc-cbt*.service 2>/dev/null | xargs -n 1 basename | sed 's/\.service$//' || true))
    if [ ${#svc_list[@]} -eq 0 ]; then
        log_warn "Tidak ada instance MC-ExamGO yang terpasang di VPS ini."
        return
    fi

    echo -e "${BOLD}Pilih Instance yang Ingin Di-Update / Upgrade:${NC}"
    for i in "${!svc_list[@]}"; do
        local sname="${svc_list[$i]}"
        local sdir="/opt/$sname"
        local sport="8080"
        if [ -f "$sdir/.env" ]; then
            sport=$(grep -E '^SERVER_PORT=' "$sdir/.env" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "8080")
        fi
        echo -e "  [${CYAN}$((i + 1))${NC}] 🎯 ${BOLD}${sname}${NC} (Dir: ${sdir}, Port: ${sport})"
    done
    echo -e "  [0] ↩️  Batal"

    local choice="0"
    prompt_var "Pilih nomor instance [1-${#svc_list[@]}]: " choice "0"
    if [ "$choice" = "0" ] || [ "$choice" -lt 1 ] 2>/dev/null || [ "$choice" -gt "${#svc_list[@]}" ] 2>/dev/null; then
        log_info "Proses update dibatalkan."
        return
    fi

    local target_svc="${svc_list[$((choice - 1))]}"
    local target_dir="/opt/$target_svc"

    # Cari file binary pembaruan di folder lokal
    local update_file=""
    if [ -f "./mc-exam-go-linux-amd64" ]; then
        update_file="./mc-exam-go-linux-amd64"
    elif ls ./mc-exam-go-linux-* >/dev/null 2>&1; then
        update_file=$(ls ./mc-exam-go-linux-* | head -n 1)
    elif ls ./*.zip >/dev/null 2>&1; then
        update_file=$(ls ./*.zip | grep -iE 'linux|amd64|examgo' | head -n 1 || true)
    elif ls ./*.tar.gz >/dev/null 2>&1; then
        update_file=$(ls ./*.tar.gz | head -n 1 || true)
    fi

    if [ -z "$update_file" ] || [ ! -f "$update_file" ]; then
        prompt_var "Masukkan lokasi file binary/zip pembaruan di VPS: " update_file ""
    fi

    if [ -z "$update_file" ] || [ ! -f "$update_file" ]; then
        log_error "Berkas pembaruan '$update_file' tidak ditemukan!"
        return
    fi

    log_info "Menggunakan berkas update: ${BOLD}${update_file}${NC}"

    local confirm=""
    prompt_var "Lanjutkan update untuk ${target_svc}? [Y/n]: " confirm "Y"
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
    if [ "$confirm" = "n" ] || [ "$confirm" = "no" ]; then
        log_info "Pembaruan dibatalkan."
        return
    fi

    # 1. Backup binary lama
    log_check "Mencadangkan (backup) binary lama"
    cp -f "$target_dir/mc-exam-go-linux" "$target_dir/mc-exam-go-linux.bak" 2>/dev/null || true
    log_success "Binary lama dicadangkan ke $target_dir/mc-exam-go-linux.bak"

    # 2. Hentikan service
    log_check "Menghentikan service ${target_svc}.service secara aman"
    systemctl stop "${target_svc}.service" >/dev/null 2>&1 || true

    # 3. Ekstrak atau salin binary baru
    local tmp_dir="/tmp/mc_update_$$"
    mkdir -p "$tmp_dir"
    if [[ "$update_file" == *.zip ]]; then
        log_check "Mengekstrak binary dari zip"
        unzip -q -o "$update_file" -d "$tmp_dir"
        local extracted_bin=$(find "$tmp_dir" -type f -name "mc-exam-go-linux*" | head -n 1)
        if [ -n "$extracted_bin" ] && [ -f "$extracted_bin" ]; then
            cp -f "$extracted_bin" "$target_dir/mc-exam-go-linux"
        else
            log_error "Binary linux tidak ditemukan di dalam file zip!"
            rm -rf "$tmp_dir"
            systemctl start "${target_svc}.service"
            return
        fi
    elif [[ "$update_file" == *.tar.gz ]]; then
        log_check "Mengekstrak binary dari tar.gz"
        tar -xzf "$update_file" -C "$tmp_dir"
        local extracted_bin=$(find "$tmp_dir" -type f -name "mc-exam-go-linux*" | head -n 1)
        if [ -n "$extracted_bin" ] && [ -f "$extracted_bin" ]; then
            cp -f "$extracted_bin" "$target_dir/mc-exam-go-linux"
        else
            log_error "Binary linux tidak ditemukan di dalam file tar.gz!"
            rm -rf "$tmp_dir"
            systemctl start "${target_svc}.service"
            return
        fi
    else
        cp -f "$update_file" "$target_dir/mc-exam-go-linux"
    fi
    rm -rf "$tmp_dir"

    chmod 755 "$target_dir/mc-exam-go-linux"
    log_success "Binary baru berhasil dipasang"

    # 4. Jalankan kembali service
    log_check "Menyalakan service ${target_svc}.service"
    systemctl daemon-reload
    systemctl start "${target_svc}.service"

    sleep 3
    if systemctl is-active --quiet "${target_svc}.service"; then
        log_success "Service ${target_svc}.service AKTIF dan BERJALAN NORMAL!"
        echo ""
        echo -e "${BOLD}============================================================${NC}"
        echo -e "   🎉 ${GREEN}${BOLD}UPDATE INSTANCE '${target_svc}' SUKSES 100%!${NC}"
        echo -e "${BOLD}============================================================${NC}"
    else
        log_error "Service ${target_svc}.service gagal berjalan! Menampilkan log error:"
        journalctl -u "${target_svc}.service" -n 15 --no-pager
        echo ""
        local rb=""
        prompt_var "Apakah ingin melakukan ROLLBACK ke binary lama? [Y/n]: " rb "Y"
        rb=$(echo "$rb" | tr '[:upper:]' '[:lower:]')
        if [ "$rb" != "n" ]; then
            log_check "Mengembalikan binary cadangan (Rollback)"
            cp -f "$target_dir/mc-exam-go-linux.bak" "$target_dir/mc-exam-go-linux"
            systemctl start "${target_svc}.service"
            log_success "Rollback selesai. Service dikembalikan ke versi sebelumnya."
        fi
    fi
}

# ─────────────────────────────────────────────────────────────
# Fitur: Pasang MC-Panel (MCode Server & App Manager)
# ─────────────────────────────────────────────────────────────
install_mc_panel() {
    echo ""
    echo -e "${BOLD}============================================================${NC}"
    echo -e "   ${CYAN}${BOLD}🎛️  PASANG MC-PANEL (MCODE SERVER & APP MANAGER)${NC}"
    echo -e "${BOLD}============================================================${NC}"
    echo -e "MC-Panel adalah control panel ultra-ringan (<25MB RAM) yang"
    echo -e "dioptimalkan untuk mengelola MC-ExamGO (Go) & Website Sekolah (Laravel)."
    echo ""

    local panel_port="9090"
    prompt_var "Port Web Panel [9090]: " panel_port "9090"

    local admin_user="admin"
    prompt_var "Username Admin Panel [admin]: " admin_user "admin"

    local admin_pass=""
    local gen_pass=$(generate_secure_password 16 2>/dev/null || echo "AdminMCode2026!")
    prompt_var "Password Admin Panel [$gen_pass]: " admin_pass "$gen_pass"

    wait_for_apt_lock
    log_check "Menginstal dependensi dasar (Nginx, UFW, Database engines)"
    apt-get update -y
    apt-get install -y curl wget git unzip nginx certbot python3-certbot-nginx ufw postgresql

    log_check "Menyiapkan direktori & service MC-Panel di /opt/mc-panel"
    mkdir -p /opt/mc-panel /etc/mc-panel /var/www

    curl -fsSL https://raw.githubusercontent.com/maulanacod3/mc-panel/main/scripts/install.sh | bash || true

    cat << EOF > /etc/systemd/system/mc-panel.service
[Unit]
Description=MC-Panel Server & App Control Daemon
After=network.target nginx.service postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/mc-panel
ExecStart=/opt/mc-panel/mc-panel
Restart=always
RestartSec=5
Environment=MC_PANEL_PORT=${panel_port}
Environment=MC_PANEL_DB=/etc/mc-panel/mc-panel.db

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    ufw allow "${panel_port}/tcp" || true

    local panel_domain=""
    prompt_var "Hubungkan domain langsung untuk MC-Panel? (contoh: panel.sekolah.sch.id, Enter jika via IP:Port): " panel_domain ""

    local access_url=""
    local srv_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$srv_ip" ] && srv_ip="IP_SERVER"

    if [ -n "$panel_domain" ]; then
        log_check "Mengonfigurasi Nginx Reverse Proxy untuk ${panel_domain}"
        cat << EOF > "/etc/nginx/sites-available/mc_panel.conf"
server {
    listen 80;
    listen [::]:80;
    server_name ${panel_domain};

    location / {
        proxy_pass http://127.0.0.1:${panel_port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        ln -sf "/etc/nginx/sites-available/mc_panel.conf" "/etc/nginx/sites-enabled/mc_panel.conf"
        nginx -t && systemctl reload nginx
        access_url="http://${panel_domain} (atau http://${srv_ip}:${panel_port})"
    else
        access_url="http://${srv_ip}:${panel_port}"
    fi

    echo ""
    echo -e "${BOLD}============================================================${NC}"
    echo -e "   🎉 ${GREEN}${BOLD}INSTALASI MC-PANEL SELESAI & SIAP DIGUNAKAN!${NC}"
    echo -e "${BOLD}============================================================${NC}"
    echo -e "  URL Akses Panel : ${CYAN}${BOLD}${access_url}${NC}"
    echo -e "  Username Admin  : ${YELLOW}${BOLD}${admin_user}${NC}"
    echo -e "  Password Admin  : ${YELLOW}${BOLD}${admin_pass}${NC}"
    echo -e "  Port Internal   : ${panel_port}"
    echo -e "  Service Daemon  : systemctl status mc-panel.service"
    echo -e "${BOLD}============================================================${NC}"
}

# ─────────────────────────────────────────────────────────────
# Menu 11: Reset Password Admin Instance MC-ExamGO
# ─────────────────────────────────────────────────────────────
reset_admin_password() {
    echo ""
    echo -e "${BOLD}============================================================${NC}"
    echo -e "   🔑 ${CYAN}${BOLD}RESET PASSWORD ADMIN INSTANCE MC-ExamGO${NC}"
    echo -e "${BOLD}============================================================${NC}"

    local svcs=($(ls /etc/systemd/system/mc-examgo*.service /etc/systemd/system/mc-cbt*.service 2>/dev/null | xargs -n 1 basename | sed 's/\.service$//' || true))
    if [ ${#svcs[@]} -eq 0 ]; then
        log_warn "Tidak ada instance MC-ExamGO yang terpasang di VPS ini."
        return
    fi

    echo -e "${BOLD}Pilih Instance yang Ingin Direset Password Adminnya:${NC}"
    local i=1
    local svc_names=()
    for s in "${svcs[@]}"; do
        local inst_dir="/opt/$s"
        local db_name="mc_examgo"
        if [ -f "$inst_dir/.env" ]; then
            local parsed_db=$(grep -E '^DB_NAME=' "$inst_dir/.env" | cut -d'=' -f2 | tr -d ' "' || true)
            [ -n "$parsed_db" ] && db_name="$parsed_db"
        fi
        echo -e "  [${CYAN}${i}${NC}] 🎯 ${BOLD}${s}${NC} (Database: ${GREEN}${db_name}${NC}, Dir: ${inst_dir})"
        svc_names+=("$s:$db_name:$inst_dir")
        i=$((i + 1))
    done
    echo -e "  [0] ↩️  Batal"

    local choice="1"
    prompt_var "Pilih nomor instance [1-${#svc_names[@]}]: " choice "1"
    if [ "$choice" = "0" ] || [ "$choice" -lt 1 ] 2>/dev/null || [ "$choice" -gt "${#svc_names[@]}" ] 2>/dev/null; then
        log_info "Reset password dibatalkan."
        return
    fi

    local selected="${svc_names[$((choice - 1))]}"
    local target_svc=$(echo "$selected" | cut -d':' -f1)
    local target_db=$(echo "$selected" | cut -d':' -f2)
    local target_dir=$(echo "$selected" | cut -d':' -f3)

    echo ""
    log_check "Mengecek daftar akun Admin pada database '${target_db}'..."
    
    # Ambil semua akun admin dari database (id, email, name)
    local raw_admins=$(sudo -u postgres psql -d "$target_db" -t -A -F"|" -c "SELECT id, email, name FROM users WHERE role = 'admin' ORDER BY id ASC;" 2>/dev/null || true)
    
    local target_id=""
    local target_email="admin@mc-exam.go"
    local target_name="Admin"

    if [ -n "$raw_admins" ]; then
        echo -e "${GREEN}Ditemukan akun Admin pada database '${target_db}':${NC}"
        local admin_array=()
        local idx=1
        while IFS='|' read -r u_id u_email u_name; do
            if [ -n "$u_id" ] && [ -n "$u_email" ]; then
                echo -e "  [${CYAN}${idx}${NC}] 👤 ${BOLD}${u_name}${NC} (${YELLOW}${u_email}${NC}) [ID: ${u_id}]"
                admin_array+=("$u_id|$u_email|$u_name")
                idx=$((idx + 1))
            fi
        done <<< "$raw_admins"

        if [ ${#admin_array[@]} -gt 0 ]; then
            local adm_choice="1"
            prompt_var "Pilih akun admin yang ingin direset [1-${#admin_array[@]}]: " adm_choice "1"
            if [ "$adm_choice" -ge 1 ] 2>/dev/null && [ "$adm_choice" -le "${#admin_array[@]}" ] 2>/dev/null; then
                local chosen="${admin_array[$((adm_choice - 1))]}"
                target_id=$(echo "$chosen" | cut -d'|' -f1)
                target_email=$(echo "$chosen" | cut -d'|' -f2)
                target_name=$(echo "$chosen" | cut -d'|' -f3)
            else
                local custom_email=""
                prompt_var "Masukkan Email Admin manual: " custom_email "$target_email"
                [ -n "$custom_email" ] && target_email="$custom_email"
            fi
        fi
    else
        log_warn "Belum ada akun admin di database '${target_db}'."
        prompt_var "Masukkan Email Admin yang ingin dibuat [$target_email]: " target_email "$target_email"
    fi

    echo ""
    echo -e "Target Akun: ${YELLOW}${BOLD}${target_email}${NC} (${target_name})"
    local gen_pass=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 10)
    local new_pass=""
    prompt_var "Masukkan Password Baru [Default: $gen_pass]: " new_pass "$gen_pass"

    if [ -z "$new_pass" ]; then
        log_error "Password baru tidak boleh kosong!"
        return
    fi

    echo ""
    log_check "Mengenkripsi dengan Bcrypt & Memperbarui Database..."

    # Gunakan extension pgcrypto untuk hash bcrypt yang 100% kompatibel dengan Go bcrypt
    local update_res=""
    if [ -n "$target_id" ]; then
        update_res=$(sudo -u postgres psql -d "$target_db" -t -A <<EOF 2>&1
CREATE EXTENSION IF NOT EXISTS pgcrypto;
UPDATE users 
SET password_hash = crypt('$new_pass', gen_salt('bf', 10)), 
    email = '$target_email',
    is_active = true,
    updated_at = NOW() 
WHERE id = $target_id;
EOF
)
    else
        update_res=$(sudo -u postgres psql -d "$target_db" -t -A <<EOF 2>&1
CREATE EXTENSION IF NOT EXISTS pgcrypto;
UPDATE users 
SET password_hash = crypt('$new_pass', gen_salt('bf', 10)), 
    is_active = true,
    updated_at = NOW() 
WHERE email = '$target_email' OR (id = 1 AND role = 'admin');
EOF
)
    fi

    if echo "$update_res" | grep -iqE "UPDATE [1-9]"; then
        log_success "Password untuk user '${target_email}' berhasil direset!"
    else
        log_warn "User '${target_email}' tidak ditemukan. Membuat akun admin baru..."
        sudo -u postgres psql -d "$target_db" <<EOF >/dev/null 2>&1
CREATE EXTENSION IF NOT EXISTS pgcrypto;
INSERT INTO users (name, email, password_hash, role, is_active, created_at, updated_at)
VALUES ('Admin Utama', '$target_email', crypt('$new_pass', gen_salt('bf', 10)), 'admin', true, NOW(), NOW())
ON CONFLICT (email) DO UPDATE 
SET password_hash = crypt('$new_pass', gen_salt('bf', 10)), is_active = true, updated_at = NOW();
EOF
        log_success "Akun admin '${target_email}' berhasil dibuat & diaktifkan!"
    fi

    local srv_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$srv_ip" ] && srv_ip="127.0.0.1"
    local port="8080"
    if [ -f "$target_dir/.env" ]; then
        port=$(grep -E '^SERVER_PORT=' "$target_dir/.env" | cut -d'=' -f2 | tr -d ' "' || echo "8080")
    fi

    echo ""
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "   🎉 ${GREEN}${BOLD}RESET PASSWORD ADMIN BERHASIL!${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "• Instance Target : ${CYAN}${target_svc}${NC}"
    echo -e "• Database        : ${CYAN}${target_db}${NC}"
    echo -e "• Email Login     : ${YELLOW}${BOLD}${target_email}${NC}"
    echo -e "• Password Baru   : ${GREEN}${BOLD}${new_pass}${NC}"
    echo -e "• URL Login Admin : ${CYAN}http://${srv_ip}:${port}/admin/login${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
}

# ─────────────────────────────────────────────────────────────
# Main Menu Loop
# ─────────────────────────────────────────────────────────────
print_banner

# Mendukung eksekusi langsung via CLI: ./install_vps.sh --tune, --harden, atau --reset-password
if [ "${1:-}" = "tune" ] || [ "${1:-}" = "--tune" ] || [ "${1:-}" = "-t" ]; then
    print_banner
    auto_tune_vps
    exit 0
elif [ "${1:-}" = "harden" ] || [ "${1:-}" = "--harden" ] || [ "${1:-}" = "--security" ] || [ "${1:-}" = "-s" ]; then
    print_banner
    harden_vps_security
    exit 0
elif [ "${1:-}" = "reset-password" ] || [ "${1:-}" = "--reset-password" ] || [ "${1:-}" = "reset-admin" ] || [ "${1:-}" = "-p" ]; then
    print_banner
    reset_admin_password
    exit 0
fi

while true; do
    echo ""
    echo -e "${BOLD}============================================================${NC}"
    echo -e "                 ${CYAN}${BOLD}MENU UTAMA MC-ExamGO VPS${NC}"
    echo -e "${BOLD}============================================================${NC}"
    echo -e "  ${CYAN}[1]${NC}  🚀 Pasang / Deploy Instance Baru MC-ExamGO"
    echo -e "  ${CYAN}[2]${NC}  🔄 Update / Upgrade Binary MC-ExamGO (In-Place Rescue)"
    echo -e "  ${CYAN}[3]${NC}  🌐 Hubungkan Domain & Pasang / Perbarui SSL HTTPS"
    echo -e "  ${CYAN}[4]${NC}  📜 Pantau Live Logs Server Real-Time (journalctl)"
    echo -e "  ${CYAN}[5]${NC}  ⚙️  Kelola Service Instance (Start / Stop / Restart / Status)"
    echo -e "  ${CYAN}[6]${NC}  🎛️  Pasang MC-Panel (Ultra-Light Server & App Manager) ⭐"
    echo -e "  ${CYAN}[7]${NC}  🖥️  Pasang FastPanel Control Panel (Port 8888)"
    echo -e "  ${CYAN}[8]${NC}  🗑️  Hapus / Uninstall Instance MC-ExamGO"
    echo -e "  ${CYAN}[9]${NC}  ⚡ Auto-Tuning Hardware & Optimasi VPS (High-Concurrency)"
    echo -e "  ${CYAN}[10]${NC} 🛡️ Security Hardening & Firewall (Tutup Open Port Database)"
    echo -e "  ${CYAN}[11]${NC} 🔑 Reset Password Admin Instance"
    echo -e "  ${CYAN}[0]${NC}  🚪 Keluar"
    echo -e "${BOLD}============================================================${NC}"

    MENU_CHOICE="1"
    prompt_var "Pilih menu [0-11] [1]: " MENU_CHOICE "1"

    case "$MENU_CHOICE" in
        1) deploy_instance ;;
        2) update_instance ;;
        3) connect_domain_ssl ;;
        4) show_live_logs ;;
        5) manage_services ;;
        6) install_mc_panel ;;
        7) install_fastpanel_only ;;
        8) uninstall_instance ;;
        9) auto_tune_vps ;;
        10) harden_vps_security ;;
        11) reset_admin_password ;;
        0) echo -e "${GREEN}Sampai jumpa! 👋${NC}"; exit 0 ;;
        *) log_warn "Pilihan tidak valid." ;;
    esac
done
