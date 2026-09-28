#!/usr/bin/env bash
# ==============================================================================
# MC-ExamGO — Smart Hardware Auto-Tuning Engine (High Concurrency & Low Latency)
# ==============================================================================
# Skrip ini otomatis mendeteksi spesifikasi vCPU & RAM server VPS Anda,
# lalu menghitung dan menerapkan parameter optimal untuk:
#   1. Linux Kernel TCP Socket & Network Queue (Sysctl)
#   2. File Descriptors & Process Limits (limits.conf)
#   3. Nginx Worker Processes, Worker Connections, & Keepalive Pool
#   4. High-Speed Image Loading (Zero-Copy Sendfile, Open File Cache, Fast Caching)
#   5. High-Capacity Upload Optimization (512MB max size, Buffering, Extended Timeouts)
# ==============================================================================

set -euo pipefail

# Warna terminal
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Harap jalankan skrip ini sebagai root atau dengan sudo:${NC}"
    echo "sudo bash $0"
    exit 1
fi

echo ""
echo -e "${CYAN}${BOLD}🧠 [1/3] Mendeteksi Spesifikasi Hardware VPS...${NC}"
CPU_CORES=$(nproc)
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
TOTAL_RAM_GB=$(awk "BEGIN {print int($TOTAL_RAM_MB / 1024 + 0.5)}")

echo -e "   • CPU Cores     : ${GREEN}${CPU_CORES} vCPU${NC}"
echo -e "   • Kapasitas RAM : ${GREEN}${TOTAL_RAM_MB} MB (~${TOTAL_RAM_GB} GB)${NC}"

# Kalkulasi Profil Berdasarkan Spesifikasi
if [ "$TOTAL_RAM_MB" -lt 2048 ]; then
    PROFILE="VPS Standar (~1.000 Siswa Serentak)"
    WORKER_CONN=4096
    OPEN_FILES=20000
elif [ "$TOTAL_RAM_MB" -le 4096 ]; then
    PROFILE="VPS Menengah (2.000 - 4.000 Siswa Serentak)"
    WORKER_CONN=8192
    OPEN_FILES=50000
elif [ "$TOTAL_RAM_MB" -le 8192 ]; then
    PROFILE="VPS Besar (5.000 - 10.000 Siswa Serentak)"
    WORKER_CONN=16384
    OPEN_FILES=100000
else
    PROFILE="VPS Enterprise Cluster (10.000+ Siswa Serentak)"
    WORKER_CONN=32768
    OPEN_FILES=200000
fi

echo -e "   • Profil Terpilih: ${YELLOW}${PROFILE}${NC}"
echo ""
echo -e "${CYAN}${BOLD}⚙️  [2/3] Menerapkan Auto-Tuning Sistem Operasi...${NC}"

# 1. Konfigurasi Batas File Descriptors OS
mkdir -p /etc/security/limits.d
cat << 'EOF' > /etc/security/limits.d/99-examgo.conf
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
www-data soft nofile 65535
www-data hard nofile 65535
EOF
echo -e "   ${GREEN}✓${NC} Batas File Descriptors diatur ke 65.535 (/etc/security/limits.d/99-examgo.conf)"

# 2. Konfigurasi Kernel TCP & Socket Antrean
mkdir -p /etc/sysctl.d
cat << 'EOF' > /etc/sysctl.d/99-examgo.conf
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
EOF
sysctl --system > /dev/null 2>&1 || true
echo -e "   ${GREEN}✓${NC} Kernel TCP Socket & Buffer Queue dioptimalkan (/etc/sysctl.d/99-examgo.conf)"

# 3. Konfigurasi Nginx Global (Concurrency + Image Load/Upload Performance)
if [ -f /etc/nginx/nginx.conf ]; then
    echo ""
    echo -e "${CYAN}${BOLD}🚀 [3/3] Mengonfigurasi Nginx Core & Media Delivery Engine...${NC}"
    
    # 3.1 Worker Configuration
    sed -i 's/worker_processes.*/worker_processes auto;/' /etc/nginx/nginx.conf
    
    if ! grep -q "worker_rlimit_nofile" /etc/nginx/nginx.conf; then
        sed -i '1s/^/worker_rlimit_nofile 65535;\n/' /etc/nginx/nginx.conf
    else
        sed -i 's/worker_rlimit_nofile.*/worker_rlimit_nofile 65535;/' /etc/nginx/nginx.conf
    fi

    sed -i "s/worker_connections [0-9]\+/worker_connections $WORKER_CONN/" /etc/nginx/nginx.conf

    if ! grep -q "multi_accept" /etc/nginx/nginx.conf; then
        sed -i "/worker_connections/a \    multi_accept on;\n    use epoll;" /etc/nginx/nginx.conf
    fi

    # 3.2 Pasang Konfigurasi Khusus Optimasi Upload & Image Loading
    mkdir -p /etc/nginx/conf.d
    cat << EOF > /etc/nginx/conf.d/99-examgo-tuning.conf
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
open_file_cache max=${OPEN_FILES} inactive=60s;
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
EOF

    echo -e "   ${GREEN}✓${NC} Parameter Nginx Upload (512MB) & Image Fast-Delivery aktif (/etc/nginx/conf.d/99-examgo-tuning.conf)"

    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx
        echo -e "   ${GREEN}✓${NC} Nginx worker_connections disetel ke ${GREEN}${WORKER_CONN}${NC} (Nginx Reload Sukses)"
    else
        echo -e "   ${YELLOW}⚠️  Peringatan sintaks Nginx. Silakan periksa 'nginx -t'.${NC}"
    fi
else
    echo -e "   ℹ️  Nginx belum terpasang, konfigurasi kernel dan OS limits telah aktif."
fi

echo ""
echo -e "${GREEN}${BOLD}========================================================================${NC}"
echo -e "${GREEN}${BOLD}   🎉 AUTO-TUNING HARDWARE & IMAGE ENGINE SUKSES DITERAPKAN!${NC}"
echo -e "${GREEN}${BOLD}========================================================================${NC}"
echo -e "• Upload file/gambar besar : ${CYAN}Hingga 512 MB aktif tanpa antrean (413 Payload Solved)${NC}"
echo -e "• Pengiriman gambar soal   : ${CYAN}Zero-Copy Sendfile & Microcache (${OPEN_FILES} files cache)${NC}"
echo -e "• Kapasitas konkurensi     : ${GREEN}${PROFILE}${NC}"
echo ""
