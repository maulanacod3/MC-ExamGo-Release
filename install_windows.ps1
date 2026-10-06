<#
.SYNOPSIS
    MC-ExamGO CBT Platform — PowerShell Auto-Installer & Server Management for Windows
.DESCRIPTION
    Script instalasi otomatis, setup database PostgreSQL, konfigurasi .env,
    dan peluncur server mandiri untuk lingkungan Windows 10/11 & Windows Server.
.EXAMPLE
    irm https://raw.githubusercontent.com/maulanacod3/MC-ExamGo-Release/main/install_windows.ps1 | iex
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "MC-ExamGO Windows Installer & Server Manager"

# ── Konfigurasi & Variabel Default ──────────────────────────────────────────
$INSTALL_DIR = "C:\MC-ExamGo"
$REPO_OWNER  = "maulanacod3"
$REPO_NAME   = "MC-ExamGo-Release"
$DEFAULT_PORT = 8080
$VERSION_TAG = "v1.3.3"

# ── Helper Output Functions ──────────────────────────────────────────────────
function Show-Banner {
    Clear-Host
    Write-Host @"
========================================================================
     __  __  ____        ______                         ____ ____  
    |  \/  |/ ___|      |  ____|                       / ___/ __ \ 
    | |\/| | |    ______| |__  __  ____ _ _ __ ___    | |  | |  | |
    | |  | | |   |______|  __| \ \/ / _` | '_ ` _ \   | |__| |__| |
    |_|  |_|\____|      | |____ >  < (_| | | | | | |   \____\____/ 
                        |______/_/\_\__,_|_| |_| |_|               
           HIGH-PERFORMANCE CBT PLATFORM (WINDOWS ENGINE)
========================================================================
"@ -ForegroundColor Cyan
}

function Write-Info    ([string]$msg) { Write-Host " [i] $msg" -ForegroundColor Cyan }
function Write-Success ([string]$msg) { Write-Host " [✓] $msg" -ForegroundColor Green }
function Write-Warn    ([string]$msg) { Write-Host " [!] $msg" -ForegroundColor Yellow }
function Write-ErrorMsg([string]$msg) { Write-Host " [x] $msg" -ForegroundColor Red }

# ── Periksa Hak Akses Administrator ──────────────────────────────────────────
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ── Generator 64-Karakter Acak Kriptografis Dual JWT ─────────────────────────
function New-CryptoJwtSecret {
    $bytes = New-Object byte[] 48
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $b64 = [Convert]::ToBase64String($bytes)
    return $b64.Replace('+', '-').Replace('/', '_').TrimEnd('=').Substring(0, 64)
}

# ── Deteksi / Pasang PostgreSQL di Windows ─────────────────────────────────────
function Ensure-PostgreSQL {
    Write-Info "Memeriksa instalasi PostgreSQL di komputer..."
    
    # 1. Cek dari PATH atau service
    $pgService = Get-Service -Name "postgresql*" -ErrorAction SilentlyContinue
    $pgCmd = Get-Command "psql.exe" -ErrorAction SilentlyContinue

    if ($pgService -or $pgCmd) {
        Write-Success "PostgreSQL terdeteksi sudah terpasang di sistem."
        return $true
    }

    # 2. Cek path standar Program Files
    $stdPaths = Get-ChildItem -Path "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue
    if ($stdPaths) {
        Write-Success "PostgreSQL terdeteksi di $($stdPaths[0].FullName)"
        return $true
    }

    Write-Warn "PostgreSQL belum terdeteksi di Windows Anda."
    $choice = Read-Host "Apakah Anda ingin memasang PostgreSQL otomatis via winget? (Y/N)"
    if ($choice -match '^[yY]') {
        Write-Info "Mengunduh dan menginstal PostgreSQL via Windows Package Manager (winget)..."
        try {
            winget install --id PostgreSQL.PostgreSQL -e --silent --accept-package-agreements --accept-source-agreements
            Write-Success "PostgreSQL berhasil dipasang! Password default admin postgres biasanya diminta saat setup."
            return $true
        } catch {
            Write-Warn "Gagal memasang otomatis via winget. Silakan unduh manual di https://www.postgresql.org/download/windows/"
            return $false
        }
    }
    return $false
}

# ── Buat Database PostgreSQL Lokal ───────────────────────────────────────────
function Setup-Database {
    Write-Host "`n--- Konfigurasi Database PostgreSQL ---" -ForegroundColor Yellow
    $dbHost = Read-Host "DB Host [default: 127.0.0.1]"
    if ([string]::IsNullOrWhiteSpace($dbHost)) { $dbHost = "127.0.0.1" }

    $dbPort = Read-Host "DB Port [default: 5432]"
    if ([string]::IsNullOrWhiteSpace($dbPort)) { $dbPort = "5432" }

    $dbName = Read-Host "DB Name [default: mc_examgo]"
    if ([string]::IsNullOrWhiteSpace($dbName)) { $dbName = "mc_examgo" }

    $dbUser = Read-Host "DB User [default: postgres]"
    if ([string]::IsNullOrWhiteSpace($dbUser)) { $dbUser = "postgres" }

    $dbPass = Read-Host "DB Password"

    return @{
        Host = $dbHost
        Port = $dbPort
        Name = $dbName
        User = $dbUser
        Pass = $dbPass
    }
}

# ── Unduh & Pasang Binary MC-ExamGO ──────────────────────────────────────────
function Install-MCExamGo {
    Show-Banner
    Write-Host ">>> MEMULAI INSTALASI MC-EXAMGO WINDOWS <<<`n" -ForegroundColor Yellow

    Ensure-PostgreSQL

    if (-not (Test-Path $INSTALL_DIR)) {
        New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
        Write-Success "Direktori instalasi dibuat di: $INSTALL_DIR"
    }

    # URL Unduhan Binary Windows Resmi
    $downloadUrl = "https://mcode.web.id/examgo/unduh/win"
    $zipPath = Join-Path $env:TEMP "MC-ExamGo-Win.zip"

    Write-Info "Mengunduh paket rilis resmi MC-ExamGO Windows terbaru..."
    Write-Info "URL: $downloadUrl"
    
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
        Write-Success "Unduhan selesai! Mengekstrak berkas ke $INSTALL_DIR..."
        
        $tempExtract = Join-Path $env:TEMP ("MCExamGo_Extract_" + [System.IO.Path]::GetRandomFileName())
        if (Test-Path $tempExtract) { Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null

        Expand-Archive -Path $zipPath -DestinationPath $tempExtract -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        # Cek jika di dalam zip terdapat subfolder pembungkus (misal: MC-ExamGo-Win/)
        $extractedItems = Get-ChildItem -Path $tempExtract
        $sourceDir = $tempExtract
        if ($extractedItems.Count -eq 1 -and $extractedItems[0].PSIsContainer) {
            $sourceDir = $extractedItems[0].FullName
        }

        # Pindahkan seluruh isi file & folder langsung ke root $INSTALL_DIR
        Get-ChildItem -Path $sourceDir | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $INSTALL_DIR -Recurse -Force
        }

        Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        Write-Success "Ekstraksi berkas ke direktori utama berhasil diselesaikan."
    } catch {
        Write-Warn "Gagal mengunduh atau mengekstrak rilis ($($_.Exception.Message))."
        Write-Info "Pastikan koneksi internet aktif untuk mengunduh rilis."
    }

    # Setup Konfigurasi .env
    $envFile = Join-Path $INSTALL_DIR ".env"
    $dbConfig = Setup-Database

    Write-Info "Mengenerate Dual JWT Secret (Admin & Siswa) 64-karakter kriptografis..."
    $jwtAdmin = New-CryptoJwtSecret
    $jwtSiswa = New-CryptoJwtSecret

    $envContent = @"
# Port HTTP Engine Server CBT
SERVER_PORT=$DEFAULT_PORT

# Zona Waktu Ujian
DB_TIMEZONE=Asia/Jakarta

# Konfigurasi Database PostgreSQL
DB_HOST=$($dbConfig.Host)
DB_PORT=$($dbConfig.Port)
DB_NAME=$($dbConfig.Name)
DB_USER=$($dbConfig.User)
DB_PASS=$($dbConfig.Pass)

# Keamanan Dual JWT Authentication (64-Char Random)
JWT_SECRET=$jwtAdmin
JWT_STUDENT_SECRET=$jwtSiswa
"@

    Set-Content -Path $envFile -Value $envContent -Encoding UTF8
    Write-Success "Berkas konfigurasi .env berhasil disimpan di $envFile"

    # Buat File Launcher Batch (Start Server)
    $exeFile = Get-ChildItem -Path $INSTALL_DIR -Filter "*.exe" | Where-Object { $_.Name -notmatch "unins" } | Select-Object -First 1
    $exeName = if ($exeFile) { $exeFile.Name } else { "mc-exam-go-windows-amd64.exe" }

    $batLauncher = @"
@echo off
title MC-ExamGO Server CBT
cd /d "$INSTALL_DIR"
echo ============================================================
echo   Menjalankan MC-ExamGO CBT Server Engine di Port $DEFAULT_PORT...
echo   Buka browser di: http://localhost:$DEFAULT_PORT
echo ============================================================
"$exeName"
pause
"@
    $batPath = Join-Path $INSTALL_DIR "Start-MC-ExamGO.bat"
    Set-Content -Path $batPath -Value $batLauncher -Encoding ASCII

    # Buat Shortcut di Desktop
    try {
        $wshShell = New-Object -ComObject WScript.Shell
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "MC-ExamGO CBT Server.lnk"
        $shortcut = $wshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $batPath
        $shortcut.WorkingDirectory = $INSTALL_DIR
        $shortcut.Description = "Jalankan Server CBT MC-ExamGO"
        $shortcut.Save()
        Write-Success "Pintasan (Shortcut) Desktop berhasil dibuat: $shortcutPath"
    } catch {
        Write-Warn "Gagal membuat shortcut desktop: $($_.Exception.Message)"
    }

    Write-Host "`n============================================================" -ForegroundColor Green
    Write-Success "INSTALASI MC-EXAMGO BERHASIL SELESAI!"
    Write-Host " Direktori : $INSTALL_DIR" -ForegroundColor Cyan
    Write-Host " Akses Web : http://localhost:$DEFAULT_PORT" -ForegroundColor Cyan
    Write-Host " Launcher  : $batPath" -ForegroundColor Cyan
    Write-Host "============================================================`n" -ForegroundColor Green

    $runNow = Read-Host "Apakah Anda ingin menyalakan server MC-ExamGO sekarang? (Y/N)"
    if ($runNow -match '^[yY]') {
        Start-Process $batPath
        Start-Process "http://localhost:$DEFAULT_PORT"
    }
}

# ── Menu Utama ───────────────────────────────────────────────────────────────
function Show-Menu {
    Show-Banner
    Write-Host "Pilih operasi yang ingin dijalankan:" -ForegroundColor White
    Write-Host " [1] 🚀 Pasang / Install MC-ExamGO (Auto-Setup Lengkap)" -ForegroundColor Green
    Write-Host " [2] 🗄️  Periksa & Pasang PostgreSQL Windows (via winget)" -ForegroundColor Cyan
    Write-Host " [3] 🔑 Generate Ulang Dual JWT Secret & .env Baru" -ForegroundColor Yellow
    Write-Host " [4] 🖥️  Buat Ulang Shortcut di Desktop Proktor" -ForegroundColor Magenta
    Write-Host " [5] ▶️  Jalankan Server MC-ExamGO Sekarang" -ForegroundColor White
    Write-Host " [0] 🚪 Keluar" -ForegroundColor DarkGray
    Write-Host ""
}

# ── Main Loop ────────────────────────────────────────────────────────────────
do {
    Show-Menu
    $choice = Read-Host "Masukkan pilihan [0-5]"
    switch ($choice) {
        "1" {
            Install-MCExamGo
            pause
        }
        "2" {
            Ensure-PostgreSQL
            pause
        }
        "3" {
            if (Test-Path $INSTALL_DIR) {
                $dbConfig = Setup-Database
                $jwtAdmin = New-CryptoJwtSecret
                $jwtSiswa = New-CryptoJwtSecret
                $envFile = Join-Path $INSTALL_DIR ".env"
                $envContent = @"
SERVER_PORT=$DEFAULT_PORT
DB_TIMEZONE=Asia/Jakarta
DB_HOST=$($dbConfig.Host)
DB_PORT=$($dbConfig.Port)
DB_NAME=$($dbConfig.Name)
DB_USER=$($dbConfig.User)
DB_PASS=$($dbConfig.Pass)
JWT_SECRET=$jwtAdmin
JWT_STUDENT_SECRET=$jwtSiswa
"@
                Set-Content -Path $envFile -Value $envContent -Encoding UTF8
                Write-Success "File .env berhasil diperbarui di $envFile"
            } else {
                Write-ErrorMsg "Folder $INSTALL_DIR belum ditemukan. Jalankan menu [1] terlebih dahulu."
            }
            pause
        }
        "4" {
            $batPath = Join-Path $INSTALL_DIR "Start-MC-ExamGO.bat"
            if (Test-Path $batPath) {
                $wshShell = New-Object -ComObject WScript.Shell
                $desktopPath = [Environment]::GetFolderPath("Desktop")
                $shortcutPath = Join-Path $desktopPath "MC-ExamGO CBT Server.lnk"
                $shortcut = $wshShell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath = $batPath
                $shortcut.WorkingDirectory = $INSTALL_DIR
                $shortcut.Save()
                Write-Success "Shortcut dibuat di: $shortcutPath"
            } else {
                Write-ErrorMsg "Launcher $batPath tidak ditemukan. Jalankan instalasi menu [1] dahulu."
            }
            pause
        }
        "5" {
            $batPath = Join-Path $INSTALL_DIR "Start-MC-ExamGO.bat"
            if (Test-Path $batPath) {
                Start-Process $batPath
                Start-Process "http://localhost:$DEFAULT_PORT"
            } else {
                Write-ErrorMsg "Launcher belum dibuat. Jalankan menu [1] dahulu."
            }
            pause
        }
        "0" {
            Write-Host "`nSampai jumpa! Terima kasih telah menggunakan MC-ExamGO." -ForegroundColor Green
            break
        }
        Default {
            Write-Warn "Pilihan tidak valid."
            Start-Sleep -Seconds 1
        }
    }
} while ($choice -ne "0")
