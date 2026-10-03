# 🚀 MC-ExamGO CBT Platform — Auto-Installer & Server Management

MC-ExamGO adalah Platform terpadu Computer Based Test (CBT), Learning Management System (LMS), In-Browser Coding IDE, dan 15 Instrumen Psikotes bertenaga **Golang murni & Vue 3 SPA.** Dirancang khusus untuk konkurensi ekstrem ribuan siswa serentak dengan konsumsi memori ultra-rendah dan latensi sub-milidetik.

---

## 📱 Instalasi & Panduan di Android (Termux)

Jadikan smartphone atau tablet Android Anda sebagai **Server CBT Portabel Mandiri** lengkap dengan database PostgreSQL native dan fitur pembuatan soal AI.

### 1. Perintah Instalasi 1-Baris
Buka aplikasi **Termux** di Android, lalu tempel (*paste*) perintah berikut:
```bash
pkg update -y && pkg install -y curl && curl -sSL https://raw.githubusercontent.com/maulanacod3/MC-ExamGo/main/bin/scripts/install_termux.sh | bash
```

---

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

---

### 3. Tips Optimalisasi Ujian di Android
1. **Matikan Optimasi Baterai (*Unrestricted Battery*):**
   - Buka Pengaturan HP ➔ **Aplikasi** ➔ **Termux** ➔ **Penggunaan Baterai** ➔ Pilih **"Tidak Dibatasi" / *Unrestricted*** agar server tidak dimatikan Android saat layar padam.
2. **Izin Akses Penyimpanan (Storage Permission):**
   - Jalankan perintah berikut sekali di Termux untuk mempermudah ekspor/impor bank soal dan cadangan database:
     ```bash
     termux-setup-storage
     ```
3. **Menggunakan Hotspot HP untuk Siswa:**
   - Aktifkan fitur *Hotspot Portabel / Tethering* pada HP server.
   - Sambungkan HP/Laptop siswa ke hotspot tersebut.
   - Ketik `examgo ip` untuk mengetahui alamat URL akses siswa (contoh: `http://192.168.43.1:8080`).

---

## 💻 Instalasi di Linux Server / VPS (Ubuntu, Debian, AlmaLinux)

Untuk deployment di server sekolah, lab komputer, atau Cloud VPS (DigitalOcean, AWS, IDCloudHost, dll):

```bash
curl -sSL https://raw.githubusercontent.com/maulanacod3/MC-ExamGo/main/bin/scripts/install_vps.sh | bash
```

---

## 📦 Rilis Binary Resmi & Multi-Platform

Unduh paket binary yang sudah dikompilasi langsung dari tab [GitHub Releases](https://github.com/maulanacod3/MC-ExamGo/releases):
- 🪟 **Windows x64 / x86** (`mc-exam-go-windows-amd64.exe`)
- 🐧 **Linux Server x64** (`mc-exam-go-linux-amd64`)
- 📱 **Linux ARM64 / Android Termux** (`mc-exam-go-linux-arm64`)
- 🍎 **macOS Apple Silicon & Intel**
