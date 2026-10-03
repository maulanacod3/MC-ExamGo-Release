# 🚀 MC-ExamGO CBT Platform — Auto-Installer & Server Management

MC-ExamGO adalah platform Computer-Based Testing (CBT) modern, mandiri, dan berkinerja tinggi berbasis **Golang Clean Architecture** & **Vue 3 SPA**.

---

## 📱 Instalasi & Panduan di Android (Termux)

Jadikan smartphone atau tablet Android Anda sebagai **Server CBT Portabel Mandiri** lengkap dengan database PostgreSQL native dan fitur pembuatan soal AI.

### 1. Perintah Instalasi 1-Baris
Buka aplikasi **Termux** di Android, lalu tempel (*paste*) perintah berikut:
```bash
pkg update -y && pkg install -y curl && curl -sSL https://raw.githubusercontent.com/maulanacod3/MC-ExamGo-Release/main/install_termux.sh | bash
```

### 2. Perintah Manajemen CLI (`examgo`)
Setelah proses instalasi selesai, perintah pintasan `examgo` dapat langsung dipanggil kapan saja dari terminal Termux:

| Perintah | Fungsi / Kegunaan |
| :--- | :--- |
| `examgo` | Membuka **Menu Interaktif Lengkap** (pilihan 0–9) |
| `examgo start` | Menyalakan server CBT & database + mengaktifkan *Wake-Lock* Android |
| `examgo stop` | Menghentikan server CBT dan melepas *Wake-Lock* |
| `examgo restart` | Memulai ulang (*restart*) layanan server CBT |
| `examgo status` | Memeriksa status kesehatan (*Running/Stopped*) Database & Backend Go |
| `examgo logs` | Menampilkan *live logs* server secara *real-time* (Ctrl+C untuk keluar) |
| `examgo ip` | Menampilkan IP jaringan WiFi / Hotspot Android untuk akses siswa & guru |
| `examgo doctor` | **Diagnostik Sistem & AI**: Menguji koneksi DNS ke provider AI (OpenRouter, Gemini, OpenAI) |
| `examgo fix-dns` | **Perbaikan DNS Instan**: Mereset DNS Termux ke Google (8.8.8.8) & Cloudflare (1.1.1.1) |
| `examgo backup` | Mencadangkan database PostgreSQL & menyalin file `.sql` ke folder `/sdcard/Download/` |

### 3. Tips Optimalisasi Ujian di Android
1. **Matikan Optimasi Baterai (*Unrestricted Battery*):**
   - Buka Pengaturan HP ➔ **Aplikasi** ➔ **Termux** ➔ **Penggunaan Baterai** ➔ Pilih **"Tidak Dibatasi" / *Unrestricted*** agar server tidak dimatikan Android saat layar padam.
2. **Izin Akses Penyimpanan (Storage Permission):**
   - Jalankan perintah berikut di Termux untuk mempermudah ekspor/impor bank soal dan cadangan database:
     ```bash
     termux-setup-storage
     ```
3. **Menggunakan Hotspot HP untuk Siswa:**
   - Aktifkan fitur *Hotspot Portabel / Tethering* pada HP server.
   - Sambungkan HP/Laptop siswa ke hotspot tersebut.
   - Ketik `examgo ip` untuk mengetahui alamat URL akses siswa (contoh: `http://192.168.43.1:8080`).

---

## 💻 Instalasi di Linux Server / VPS (Ubuntu, Debian, AlmaLinux)

Skrip [`install_vps.sh`](file:///c:/xampp/htdocs/mc-cbt-exam-go/bin/scripts/install_vps.sh) dirancang untuk kebutuhan **Enterprise & Skala Besar (1.000 – 10.000+ Siswa Serentak)** dengan arsitektur multi-instance, Nginx Reverse Proxy, otomatisasi SSL HTTPS Let's Encrypt, serta *hardware tuning*.

### 1. Perintah Instalasi 1-Baris
Jalankan perintah ini di terminal server VPS Anda (sebagai `root` atau `sudo`):
```bash
curl -sSL https://raw.githubusercontent.com/maulanacod3/MC-ExamGo-Release/main/install_vps.sh | bash
```

---

### 2. Fitur Utama & Menu Manajemen VPS

Skrip menyediakan **Dashboard Interaktif Berbasis Terminal** dengan menu:

```text
============================================================
                 MENU UTAMA MC-ExamGO VPS
============================================================
  [1]  🚀 Pasang / Deploy Instance Baru MC-ExamGO
  [2]  🔄 Update / Upgrade Binary MC-ExamGO (In-Place Rescue)
  [3]  🌐 Hubungkan Domain & Pasang / Perbarui SSL HTTPS
  [4]  📜 Pantau Live Logs Server Real-Time (journalctl)
  [5]  ⚙️  Kelola Service Instance (Start / Stop / Restart / Status)
  [6]  🎛️  Pasang MC-Panel (Ultra-Light Server & App Manager) ⭐
  [7]  🖥️  Pasang FastPanel Control Panel (Port 8888)
  [8]  🗑️  Hapus / Uninstall Instance MC-ExamGO
  [9]  ⚡ Auto-Tuning Hardware & Optimasi VPS (High-Concurrency)
  [10] 🛡️ Security Hardening & Firewall (Tutup Open Port Database)
  [0]  🚪 Keluar
============================================================
```

#### Detail Kemampuan Modul:

| Menu / Fitur | Penjelasan Teknis & Keunggulan |
| :--- | :--- |
| **Multi-Instance Deployment** | Memungkinkan menjalankan banyak instance CBT sekaligus dalam 1 VPS (misal: `mc-examgo-smp`, `mc-examgo-sma`, `tryout`) dengan port & database terisolasi. |
| **In-Place Binary Rescue Update** | Memperbarui binary tanpa downtime berlebih, otomatis membuat backup binary lama (`.bak`) dan menyediakan fitur **Auto-Rollback** jika binary baru bermasalah. |
| **Nginx & SSL Automation** | Reverse Proxy otomatis dengan dukungan **HTTP/2**, batas upload hingga **512 MB** (bebas error *413 Request Entity Too Large*), dan SSL gratis Let's Encrypt. |
| **Hardware & Kernel Auto-Tuning** | Mengoptimasi `limits.d` (65.535 File Descriptors), TCP Socket Queue (`somaxconn`, `tcp_tw_reuse`), dan Nginx Fast-Delivery Microcache untuk gambar soal. |
| **Security & Firewall Hardening** | Mengunci database PostgreSQL ke `127.0.0.1` (localhost only), memblokir port sensitif (5432, 6379, 3306) dari akses publik luar (WAN), dan hanya membuka port 80, 443, dan SSH. |
| **Integrasi Web Panel** | Opsi instalasi **MC-Panel** (panel ultra-ringan <25MB RAM) atau **FastPanel Web GUI** (port 8888) untuk mengelola server via browser. |

---

### 3. Eksekusi Cepat via CLI Argument (Tanpa Menu)

Anda juga dapat menjalankan fitur optimasi dan keamanan secara langsung melalui perintah satu baris:

- **Jalankan Hardware & Kernel Tuning Saja:**
  ```bash
  bash /path/ke/install_vps.sh --tune
  ```
- **Jalankan Security Hardening & Firewall Saja:**
  ```bash
  bash /path/ke/install_vps.sh --harden
  ```

---

## 📦 Rilis Binary Resmi & Multi-Platform

Unduh paket binary yang sudah dikompilasi langsung dari tab [GitHub Releases MC-ExamGo-Release](https://github.com/maulanacod3/MC-ExamGo-Release/releases):
- 🪟 **Windows x64 / x86** (`mc-exam-go-windows-amd64.exe`)
- 🐧 **Linux Server x64** (`mc-exam-go-linux-amd64`)
- 📱 **Linux ARM64 / Android Termux** (`mc-exam-go-linux-arm64`)
- 🍎 **macOS Apple Silicon & Intel**
