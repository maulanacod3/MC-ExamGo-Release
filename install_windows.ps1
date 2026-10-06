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

# ── Helper Enterprise Progress Runner ────────────────────────────────────────
function Invoke-EnterpriseCommandWithProgress {
    param (
        [string]$Title,
        [string]$Command,
        [string]$Arguments
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Command
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $started = $proc.Start()
    } catch {
        return -1
    }

    if (-not $started) {
        return -1
    }

    $spinChars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $step = 0
    $subTexts = @(
        "Menghubungkan ke repositori paket...",
        "Mengunduh installer PostgreSQL (±350MB)...",
        "Mengekstrak dan memverifikasi berkas installer...",
        "Memasang PostgreSQL database engine...",
        "Menginisialisasi cluster database port 5432...",
        "Mengonfigurasi superuser postgres...",
        "Mendaftarkan dan menjalankan Windows Service..."
    )

    while (-not $proc.HasExited) {
        $elapsed = $stopwatch.Elapsed
        $elapsedStr = "{0:D2}:{1:D2}" -f [int]$elapsed.TotalMinutes, $elapsed.Seconds
        $spinner = $spinChars[$step % $spinChars.Length]
        $stageIndex = [Math]::Min([int]($elapsed.TotalSeconds / 15), $subTexts.Length - 1)
        $currentStage = $subTexts[$stageIndex]

        $statusMsg = " $spinner [⏱️ $elapsedStr] $Title : $currentStage"
        
        $winWidth = if ($Host.UI.RawUI.WindowSize.Width) { $Host.UI.RawUI.WindowSize.Width } else { 80 }
        $maxLen = [Math]::Max(10, $winWidth - 1)
        if ($statusMsg.Length -gt $maxLen) {
            $statusMsg = $statusMsg.Substring(0, $maxLen - 3) + "..."
        }
        $statusMsg = $statusMsg.PadRight($maxLen)

        Write-Host "`r$statusMsg" -NoNewline -ForegroundColor Cyan
        Start-Sleep -Milliseconds 150
        $step++
    }

    $stopwatch.Stop()
    $exitCode = $proc.ExitCode
    $winWidth = if ($Host.UI.RawUI.WindowSize.Width) { $Host.UI.RawUI.WindowSize.Width } else { 80 }
    $clearLine = "".PadRight([Math]::Max(10, $winWidth - 1))
    Write-Host "`r$clearLine`r" -NoNewline

    $totalTimeStr = "{0}m {1}s" -f [int]$stopwatch.Elapsed.TotalMinutes, $stopwatch.Elapsed.Seconds
    return @{
        ExitCode = $exitCode
        Duration = $totalTimeStr
    }
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
        $initialPass = Read-Host "Tentukan Password admin/postgres yang diinginkan [default: postgres]"
        if ([string]::IsNullOrWhiteSpace($initialPass)) { $initialPass = "postgres" }
        $script:INITIAL_DB_PASS = $initialPass

        Write-Info "Memulai instalasi otomatis PostgreSQL 16..."
        Write-Info "Password superuser 'postgres' akan otomatis diatur: $initialPass"
        Write-Warn "Proses mengunduh ±350MB dan menginstal engine (estimasi 1-3 menit tergantung kecepatan internet)..."

        $overrideArgs = "--unattendedmodeui none --mode unattended --superpassword `"$initialPass`" --serverport 5432"
        $wingetArgs = "install --id PostgreSQL.PostgreSQL.16 -s winget -e --accept-package-agreements --accept-source-agreements --override `"$overrideArgs`""

        $res = Invoke-EnterpriseCommandWithProgress -Title "Instalasi PostgreSQL 16" -Command "winget" -Arguments $wingetArgs
        if ($res.ExitCode -eq 0) {
            Write-Success "PostgreSQL 16 berhasil dipasang dalam waktu $($res.Duration) dengan password: $initialPass"
            Start-Sleep -Seconds 2
            return $true
        }

        # Fallback coba ID PostgreSQL general
        Write-Info "Mencoba paket alternatif PostgreSQL..."
        $wingetAltArgs = "install --id PostgreSQL.PostgreSQL -s winget -e --accept-package-agreements --accept-source-agreements --override `"$overrideArgs`""
        $resAlt = Invoke-EnterpriseCommandWithProgress -Title "Instalasi PostgreSQL" -Command "winget" -Arguments $wingetAltArgs
        if ($resAlt.ExitCode -eq 0) {
            Write-Success "PostgreSQL berhasil dipasang dalam waktu $($resAlt.Duration) dengan password: $initialPass"
            Start-Sleep -Seconds 2
            return $true
        }

        Write-Warn "Gagal memasang otomatis via winget."
        Write-Info "Silakan unduh & pasang PostgreSQL secara manual melalui tautan resmi:"
        Write-Host " 👉 https://www.postgresql.org/download/windows/`n" -ForegroundColor Cyan
        return $false
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

    $defaultPass = if ($script:INITIAL_DB_PASS) { $script:INITIAL_DB_PASS } else { "postgres" }
    $dbPass = Read-Host "DB Password [default: $defaultPass]"
    if ([string]::IsNullOrWhiteSpace($dbPass)) { $dbPass = $defaultPass }

    # Otomatis buat database jika tool psql ditemukan di PATH atau Program Files
    $psqlExe = Get-Command "psql.exe" -ErrorAction SilentlyContinue
    if (-not $psqlExe) {
        $stdPsql = Get-ChildItem -Path "C:\Program Files\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($stdPsql) { $psqlExe = $stdPsql.FullName }
    } else {
        $psqlExe = $psqlExe.Source
    }

    if ($psqlExe) {
        Write-Info "Memeriksa dan menyiapkan database '$dbName' di PostgreSQL..."
        $env:PGPASSWORD = $dbPass
        & $psqlExe -h $dbHost -p $dbPort -U $dbUser -d postgres -c "CREATE DATABASE $dbName;" 2>$null
        $env:PGPASSWORD = $null
        Write-Success "Database '$dbName' siap digunakan!"
    }

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

    $null = Ensure-PostgreSQL

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
            $null = Ensure-PostgreSQL
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
