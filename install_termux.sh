#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# MC-ExamGO CBT — 1-Click Android & Termux Auto-Installer & Server Manager
# ==============================================================================
# Mendukung:
#   • Android ARM64 (aarch64) & x86_64 via Native Termux Engine
#   • Auto Setup PostgreSQL Database Native di Termux
#   • Background Daemon Management (Start / Stop / Restart / Live Logs)
#   • Auto WiFi/LAN IP Discovery (Bisa langsung diakses dari HP Siswa / Laptop)
#   • Shortcut CLI 'examgo' di Termux
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
    echo -e "        ${CYAN}${BOLD}📱 MC-ExamGO CBT — Android & Termux Server Manager${NC} ${GRAY}v1.3.1${NC}"
    echo -e "        ${GRAY}Jadikan Smartphone Android Sebagai Server CBT Portabel${NC}"
    echo ""
}

# Helper input interaktif
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

# Deteksi direktori script saat ini
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$(pwd)"
fi

# Deteksi IP WiFi Android
get_android_ip() {
    local ip=""
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n 1)
        if [ -z "$ip" ]; then
            ip=$(ip -4 addr show ap0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n 1)
        fi
        if [ -z "$ip" ]; then
            ip=$(ip -4 addr 2>/dev/null | awk '/inet /{print $2}' | grep -v '127.0.0.1' | cut -d/ -f1 | head -n 1)
        fi
    fi
    if [ -z "$ip" ] && command -v getprop >/dev/null 2>&1; then
        ip=$(getprop dhcp.wlan0.ipaddress 2>/dev/null || true)
    fi
    if [ -z "$ip" ]; then
        ip="127.0.0.1"
    fi
    echo "$ip"
}

# Smart Port Allocation (Mencari port bebas secara otomatis: 8080, 8081, 8082, dst)
find_free_port() {
    local start_port=8080
    local port=$start_port
    while (command -v ss >/dev/null 2>&1 && ss -tuln 2>/dev/null | grep -q ":${port} ") || \
          (command -v netstat >/dev/null 2>&1 && netstat -tuln 2>/dev/null | grep -q ":${port} ") || \
          (command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 $port 2>/dev/null); do
        port=$((port + 1))
    done
    echo "$port"
}

# ─────────────────────────────────────────────────────────────
# 1. Instalasi Lingkungan Native Termux & PostgreSQL
# ─────────────────────────────────────────────────────────────
install_termux_environment() {
    echo ""
    log_check "Memeriksa arsitektur CPU perangkat Android..."
    local arch=$(uname -m)
    log_info "Arsitektur CPU terdeteksi: ${GREEN}${arch}${NC}"

    local bin_arch="arm64"
    if [ "$arch" = "x86_64" ]; then
        bin_arch="amd64"
    elif [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
        bin_arch="arm64"
    else
        log_warn "Arsitektur '$arch' mungkin membutuhkan binary ARM standar."
    fi

    # 1. Install dependensi Native Termux
    log_check "Memasang paket prasyarat Termux (postgresql, curl, unzip, psmisc, openssl-tool)..."
    pkg update -y
    pkg install -y postgresql curl tar unzip psmisc openssl-tool

    # Helper generator string acak aman
    generate_random_secret() {
        local len="${1:-16}"
        local val=""
        if command -v openssl >/dev/null 2>&1; then
            val=$(openssl rand -base64 48 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c "$len" || true)
        fi
        if [ -z "$val" ] && [ -r /dev/urandom ]; then
            val=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom 2>/dev/null | head -c "$len" || true)
        fi
        if [ -z "$val" ]; then
            val=$(date +%s%N | sha256sum 2>/dev/null | head -c "$len" || echo "mcexam$(date +%s)")
        fi
        echo "$val"
    }

    local app_dir="$PREFIX/var/mc-examgo"
    mkdir -p "$app_dir/uploads" "$app_dir/logs" "$app_dir/storage" "$app_dir/db"

    # 2. Setup PostgreSQL Native Termux
    log_check "Menyiapkan database PostgreSQL Native Termux..."
    if [ ! -f "$app_dir/db/PG_VERSION" ]; then
        log_info "Menginisialisasi cluster database (hanya butuh 1-2 detik)..."
        initdb -E UTF8 --locale=C.UTF-8 "$app_dir/db" 2>/dev/null || initdb "$app_dir/db"
        echo "host all all 127.0.0.1/32 trust" >> "$app_dir/db/pg_hba.conf"
        echo "local all all trust" >> "$app_dir/db/pg_hba.conf"
    fi

    if ! pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then
        log_info "Menyalakan daemon PostgreSQL..."
        pg_ctl -D "$app_dir/db" -l "$app_dir/logs/postgres.log" start || true
        sleep 2
    fi

    # Buat user & database
    local def_port=$(find_free_port)
    local target_port="$def_port"
    echo ""
    prompt_var "Port Aplikasi CBT Server [$def_port]: " target_port "$def_port"
    log_success "Port aplikasi dialokasikan: ${target_port}"
    local db_pass=$(generate_random_secret 16)
    local jwt_admin=$(generate_random_secret 32)
    local jwt_student=$(generate_random_secret 32)

    log_info "Mengonfigurasi database 'mc_examgo'..."
    local cur_user=$(whoami)
    createuser -s -h 127.0.0.1 mc_user 2>/dev/null || true
    psql -h 127.0.0.1 -U "$cur_user" -d postgres -c "
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mc_user') THEN
        CREATE ROLE mc_user WITH LOGIN PASSWORD '$db_pass';
    ELSE
        ALTER ROLE mc_user WITH PASSWORD '$db_pass';
    END IF;
END
\$\$;
" 2>/dev/null || true

    createdb -h 127.0.0.1 -U "$cur_user" -O mc_user mc_examgo 2>/dev/null || true
    log_success "Database PostgreSQL siap!"

    # 3. Cari Binary Lokal atau Download dari GitHub Releases
    log_check "Mencari binary MC-ExamGO Linux (${bin_arch})..."
    local found_bin=""
    local candidate_bins=($(find "$SCRIPT_DIR" -maxdepth 2 -name "mc-exam-go-linux-${bin_arch}*" ! -name "*.zip" ! -name "*.tar.gz" ! -name "*.md" ! -name "*.sh" 2>/dev/null || true))
    if [ ${#candidate_bins[@]} -gt 0 ] && [ -f "${candidate_bins[0]}" ]; then
        found_bin="${candidate_bins[0]}"
    fi

    if [ -n "$found_bin" ] && [ -f "$found_bin" ]; then
        log_success "Binary lokal ditemukan: $(basename "$found_bin")"
        cp "$found_bin" "$app_dir/mc-exam-go-linux"
        chmod +x "$app_dir/mc-exam-go-linux"
    else
        log_info "Binary lokal belum ada. Mengunduh paket resmi rilis (${bin_arch}) dari GitHub..."
        local downloaded=false
        local urls=(
            "https://github.com/maulanacod3/MC-ExamGo-Release/releases/download/v1.3.1/MC-ExamGo-${bin_arch}-v1.3.1.zip"
            "https://github.com/maulanacod3/MC-ExamGo-Release/releases/latest/download/MC-ExamGo-${bin_arch}-v1.3.1.zip"
            "https://github.com/maulanacod3/MC-ExamGo-Release/releases/latest/download/mc-exam-go-linux-${bin_arch}.zip"
            "https://cbt.mcode.web.id/examgo/unduh/${bin_arch}"
        )
        for dl_url in "${urls[@]}"; do
            log_info "Mencoba mengunduh dari: $dl_url"
            if curl -fL --connect-timeout 10 --max-time 180 "$dl_url" -o "$app_dir/release.zip" 2>/dev/null; then
                downloaded=true
                break
            fi
        done

        if [ "$downloaded" = true ] && [ -f "$app_dir/release.zip" ]; then
            unzip -o -q "$app_dir/release.zip" -d "$app_dir/extracted" 2>/dev/null || true
            local ext_bin=$(find "$app_dir/extracted" -type f -name "mc-exam-go-linux*" ! -name "*.zip" | head -n 1)
            if [ -n "$ext_bin" ] && [ -f "$ext_bin" ]; then
                cp "$ext_bin" "$app_dir/mc-exam-go-linux"
                chmod +x "$app_dir/mc-exam-go-linux"
                log_success "Binary resmi berhasil diunduh dan dipasang"
            fi
            rm -rf "$app_dir/release.zip" "$app_dir/extracted"
        else
            log_error "Gagal mengunduh binary MC-ExamGO. Pastikan rilis di GitHub sudah di-publish atau letakkan binary di folder lokal."
        fi
    fi

    # 4. Tulis .env
    cat << EOF > "$app_dir/.env"
SERVER_PORT=$target_port
DB_TIMEZONE=Asia/Jakarta

DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=mc_examgo
DB_USER=mc_user
DB_PASS=$db_pass

JWT_SECRET=$jwt_admin
JWT_STUDENT_SECRET=$jwt_student
EOF

    # 5. Tulis Launcher Script
    cat << 'EOF_START' > "$app_dir/start.sh"
#!/data/data/com.termux/files/usr/bin/bash
APP_DIR="$PREFIX/var/mc-examgo"

if ! pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then
    pg_ctl -D "$APP_DIR/db" -l "$APP_DIR/logs/postgres.log" start
    sleep 1
fi

cd "$APP_DIR"
if pgrep -f "mc-exam-go-linux" >/dev/null 2>&1; then
    echo "MC-ExamGO sudah berjalan."
    exit 0
fi

nohup ./mc-exam-go-linux > logs/app.log 2>&1 &
sleep 2

if pgrep -f "mc-exam-go-linux" >/dev/null 2>&1; then
    echo "MC-ExamGO Server berhasil dinyalakan."
else
    echo "Gagal menyalakan server. Cek logs: cat $APP_DIR/logs/app.log"
fi
EOF_START

    cat << 'EOF_STOP' > "$app_dir/stop.sh"
#!/data/data/com.termux/files/usr/bin/bash
pkill -f "mc-exam-go-linux" || true
echo "MC-ExamGO Server dihentikan."
EOF_STOP

    chmod +x "$app_dir/start.sh" "$app_dir/stop.sh"

    # 6. Pasang Global CLI Command 'examgo' di Termux
    cat << 'EOF_EXAMGO_CLI' > "$PREFIX/bin/examgo"
#!/data/data/com.termux/files/usr/bin/bash
ACTION="${1:-menu}"
APP_DIR="$PREFIX/var/mc-examgo"

get_cbt_port() {
    local env_file="$PREFIX/var/mc-examgo/.env"
    local port="8080"
    if [ -f "$env_file" ]; then
        port=$(grep -E '^SERVER_PORT=' "$env_file" | cut -d'=' -f2 | tr -d '\r\n ' || echo "8080")
    fi
    [ -z "$port" ] && port="8080"
    echo "$port"
}

get_wifi_ip() {
    local ip=""
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n 1)
        [ -z "$ip" ] && ip=$(ip -4 addr show ap0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n 1)
        [ -z "$ip" ] && ip=$(ip -4 addr 2>/dev/null | awk '/inet /{print $2}' | grep -v '127.0.0.1' | cut -d/ -f1 | head -n 1)
    fi
    if [ -z "$ip" ] && command -v getprop >/dev/null 2>&1; then
        ip=$(getprop dhcp.wlan0.ipaddress 2>/dev/null || true)
    fi
    [ -z "$ip" ] && ip="127.0.0.1"
    echo "$ip"
}

case "$ACTION" in
    start)
        echo "🚀 Menyalakan MC-ExamGO Server..."
        bash "$APP_DIR/start.sh"
        WIFI_IP=$(get_wifi_ip)
        CBT_PORT=$(get_cbt_port)
        echo ""
        echo "✅ MC-ExamGO Aktif!"
        echo "• Akses Lokal HP    : http://127.0.0.1:${CBT_PORT}"
        echo "• Akses WiFi Siswa  : http://${WIFI_IP}:${CBT_PORT}"
        echo "• Login Admin       : http://${WIFI_IP}:${CBT_PORT}/admin/login"
        echo "• Akun Default      : admin@mc-exam.go / admin123"
        ;;
    stop)
        echo "⏹️  Menghentikan MC-ExamGO Server..."
        bash "$APP_DIR/stop.sh"
        ;;
    restart)
        echo "🔄 Memulai ulang MC-ExamGO Server..."
        bash "$APP_DIR/stop.sh"
        sleep 1
        bash "$APP_DIR/start.sh"
        ;;
    status)
        echo "🔍 Memeriksa status server..."
        pg_isready -h 127.0.0.1 -p 5432 && echo "Status Database: RUNNING (Aktif)" || echo "Status Database: STOPPED (Mati)"
        pgrep -f "mc-exam-go-linux" >/dev/null 2>&1 && echo "Status CBT App  : RUNNING (Aktif)" || echo "Status CBT App  : STOPPED (Mati)"
        ;;
    logs)
        echo "📜 Menampilkan log real-time (Tekan Ctrl+C untuk keluar)..."
        tail -f -n 50 "$APP_DIR/logs/app.log"
        ;;
    ip|url)
        WIFI_IP=$(get_wifi_ip)
        CBT_PORT=$(get_cbt_port)
        echo ""
        echo "🌐 URL Akses MC-ExamGO Server:"
        echo "• HP Ini (Localhost): http://127.0.0.1:${CBT_PORT}"
        echo "• Laptop / Siswa    : http://${WIFI_IP}:${CBT_PORT}"
        echo "• Admin Login       : http://${WIFI_IP}:${CBT_PORT}/admin/login"
        ;;
    menu|*)
        while true; do
            WIFI_IP=$(get_wifi_ip)
            echo ""
            echo "============================================================"
            echo "           📱 MC-ExamGO CBT — Termux Server Manager"
            echo "============================================================"
            echo "  [1] 🚀 Nyalakan Server (Start)"
            echo "  [2] ⏹️  Hentikan Server (Stop)"
            echo "  [3] 🔄 Restart Server"
            echo "  [4] 📜 Lihat Live Logs Server"
            echo "  [5] 🌐 Lihat URL & IP Jaringan WiFi"
            echo "  [6] 🔍 Cek Status Layanan (Postgres & CBT)"
            echo "  [0] 🚪 Keluar"
            echo "============================================================"
            read -r -p "Pilih menu [0-6] [1]: " CH
            CH="${CH:-1}"
            case "$CH" in
                1) examgo start ;;
                2) examgo stop ;;
                3) examgo restart ;;
                4) examgo logs ;;
                5) examgo ip ;;
                6) examgo status ;;
                0) echo "Sampai jumpa! 👋"; exit 0 ;;
                *) echo "Pilihan tidak valid." ;;
            esac
            echo ""
            read -r -p "Tekan [Enter] untuk kembali ke menu..."
        done
        ;;
esac
EOF_EXAMGO_CLI
    chmod +x "$PREFIX/bin/examgo"
    log_success "Shortcut perintah 'examgo' berhasil dipasang di Termux!"

    # Jalankan server sekarang
    echo ""
    log_check "Menyalakan MC-ExamGO Server untuk pertama kali..."
    "$PREFIX/bin/examgo" start

    local wifi_ip=$(get_android_ip)
    echo ""
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "${GREEN}${BOLD}   🎉 INSTALASI MC-ExamGO DI TERMUX / ANDROID SUKSES!${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "🚀 Akses Server:"
    echo -e "• Akses HP ini (Browser) : ${CYAN}http://127.0.0.1:${target_port}${NC}"
    echo -e "• Akses Siswa via WiFi   : ${CYAN}http://${wifi_ip}:${target_port}${NC}"
    echo -e "• URL Admin              : ${CYAN}http://${wifi_ip}:${target_port}/admin/login${NC}"
    echo -e "• Akun Admin Default     : ${YELLOW}admin@mc-exam.go${NC} / ${YELLOW}admin123${NC}"
    echo ""
    echo -e "💡 Tips Penggunaan di Termux:"
    echo -e "  Cukup ketik perintah ${GREEN}${BOLD}examgo${NC} di terminal kapan saja untuk:"
    echo -e "  • ${CYAN}examgo start${NC}   -> Menyalakan server"
    echo -e "  • ${CYAN}examgo stop${NC}    -> Mematikan server"
    echo -e "  • ${CYAN}examgo logs${NC}    -> Melihat live logs"
    echo -e "  • ${CYAN}examgo ip${NC}      -> Cek IP WiFi HP"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
}

# ─────────────────────────────────────────────────────────────
# Entry Point
# ─────────────────────────────────────────────────────────────
print_banner

if [ -z "${PREFIX:-}" ] || [[ "$PREFIX" != *"com.termux"* ]]; then
    log_warn "Skrip ini dioptimalkan khusus untuk lingkungan aplikasi Termux di Android."
    prompt_var "Apakah Anda ingin tetap melanjutkan? [y/N]: " cont "N"
    cont=$(echo "$cont" | tr '[:upper:]' '[:lower:]')
    if [ "$cont" != "y" ] && [ "$cont" != "yes" ]; then
        exit 0
    fi
fi

install_termux_environment
