#requires -Version 5.1
<#
.SYNOPSIS
    Профессиональная диагностика работоспособности ноутбука: железо, диски, батарея, сеть, система.

.DESCRIPTION
    Комплексный тест ноутбука по 10 категориям с итоговой оценкой здоровья (Health Score 0-100):
    - Система: ОС, модель, BIOS, uptime, активация
    - CPU: модель, ядра, текущая загрузка, температура (если доступна)
    - Память: объём, использование, модули RAM
    - Диски: SMART-статус, свободное место, тип носителя, скорость записи
    - Батарея: заряд, износ (Design vs Full Charge Capacity), состояние
    - GPU: видеоадаптеры, драйверы
    - Сеть: адаптеры, интернет (ping), DNS, задержка
    - Устройства: PnP-устройства с ошибками, камера, аудио, Bluetooth
    - Безопасность: Windows Defender, брандмауэр, ожидающие обновления
    - Стабильность: критические ошибки и внезапные отключения (Event Log, 7 дней)

    Цветной вывод, итоговый Health Score, экспорт отчёта в JSON.

.PARAMETER Export
    Сохранить полный отчёт в JSON файл (папка reports).

.PARAMETER Full
    Расширенный режим: замер скорости диска, отчёт батареи powercfg, стресс-проба CPU (10 сек).

.PARAMETER ReportPath
    Папка для отчётов. По умолчанию: ..\reports относительно скрипта.

.PARAMETER KeepReports
    Сколько последних пар отчётов (JSON+HTML) хранить в ReportPath.
    Старые удаляются автоматически. По умолчанию: 30. 0 = не удалять.

.EXAMPLE
    .\Test-LaptopHealth.ps1
    .\Test-LaptopHealth.ps1 -Full -Export
#>
[CmdletBinding()]
param (
    [switch]$Export,
    [switch]$Full,
    [string]$ReportPath = (Join-Path $PSScriptRoot ".." "reports"),
    [ValidateRange(0, 1000)][int]$KeepReports = 30
)

$ErrorActionPreference = 'Continue'
if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
    Write-Warning 'Скрипт предназначен для Windows: большинство проверок использует WMI/CIM и журнал событий Windows.'
}
$script:IssuesFound = 0
$script:WarningsFound = 0
$script:CurrentSection = ''
$script:Lines = New-Object System.Collections.Generic.List[object]
$script:Report = [ordered]@{ GeneratedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); Computer = $env:COMPUTERNAME; Sections = [ordered]@{} }

function Write-StatusLine {
    param([string]$Label, [string]$Value, [ValidateSet('OK','WARN','ERROR','INFO','SKIP')][string]$Status = 'INFO')
    $color = switch ($Status) { 'OK' { 'Green' }; 'WARN' { 'Yellow' }; 'ERROR' { 'Red' }; 'INFO' { 'Cyan' }; 'SKIP' { 'DarkGray' } }
    $icon = switch ($Status) { 'OK' { '[OK]' }; 'WARN' { '[!] ' }; 'ERROR' { '[X]' }; 'INFO' { '[i]' }; 'SKIP' { '[-]' } }
    Write-Host "  $($icon.PadRight(5)) " -ForegroundColor $color -NoNewline
    Write-Host "${Label}: " -ForegroundColor Gray -NoNewline
    Write-Host $Value -ForegroundColor White
    if ($Status -eq 'ERROR') { $script:IssuesFound++ }
    if ($Status -eq 'WARN') { $script:WarningsFound++ }
    $script:Lines.Add([pscustomobject]@{ Section = $script:CurrentSection; Label = $Label; Value = $Value; Status = $Status })
}

function Write-Section {
    param([string]$Title)
    $script:CurrentSection = $Title
    Write-Host ""; Write-Host "  $( '=' * 58 )" -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "  $( '=' * 58 )" -ForegroundColor DarkGray
}

function Add-ReportSection { param([string]$Name, $Data); $script:Report.Sections[$Name] = $Data }

# ============================== 1. СИСТЕМА ==============================
function Test-SystemInfo {
    Write-Section "1/10  СИСТЕМА"
    $r = @{}
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $bios = Get-CimInstance Win32_BIOS
        $r.OSName = $os.Caption; $r.OSVersion = $os.Version; $r.Build = $os.BuildNumber
        $r.Model = "$($cs.Manufacturer) $($cs.Model)".Trim()
        $r.BIOS = "$($bios.SMBIOSBIOSVersion) ($(([datetime]$bios.ReleaseDate).ToString('yyyy-MM-dd')))"
        $uptime = (Get-Date) - $os.LastBootUpTime
        $r.UptimeDays = [math]::Round($uptime.TotalDays, 1)
        Write-StatusLine 'Модель' $r.Model 'INFO'
        Write-StatusLine 'ОС' "$($r.OSName) (build $($r.Build))" 'INFO'
        Write-StatusLine 'BIOS' $r.BIOS 'INFO'
        $upStatus = if ($uptime.TotalDays -gt 14) { 'WARN' } else { 'OK' }
        Write-StatusLine 'Uptime' "$($r.UptimeDays) дн. $(if ($upStatus -eq 'WARN') { '— рекомендуется перезагрузка' })" $upStatus
    } catch { Write-StatusLine 'Система' $_.Exception.Message 'ERROR'; $r.Error = $_.Exception.Message }
    Add-ReportSection 'System' $r
}

# ============================== 2. CPU ==============================
function Test-Cpu {
    Write-Section "2/10  ПРОЦЕССОР"
    $r = @{}
    try {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $r.Name = $cpu.Name.Trim(); $r.Cores = $cpu.NumberOfCores; $r.Threads = $cpu.NumberOfLogicalProcessors
        $r.MaxClockMHz = $cpu.MaxClockSpeed; $r.LoadPercent = $cpu.LoadPercentage
        Write-StatusLine 'Модель' $r.Name 'INFO'
        Write-StatusLine 'Ядра / потоки' "$($r.Cores) / $($r.Threads), до $([math]::Round($r.MaxClockMHz/1000.0,2)) GHz" 'INFO'
        $loadStatus = if ($r.LoadPercent -ge 90) { 'ERROR' } elseif ($r.LoadPercent -ge 70) { 'WARN' } else { 'OK' }
        Write-StatusLine 'Текущая загрузка' "$($r.LoadPercent)%" $loadStatus
        # Температура через ACPI (доступна не на всех моделях, требует прав администратора)
        try {
            $tz = Get-CimInstance -Namespace 'root/wmi' -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | Select-Object -First 1
            $tempC = [math]::Round(($tz.CurrentTemperature / 10.0) - 273.15, 1)
            $r.TemperatureC = $tempC
            $tStatus = if ($tempC -ge 90) { 'ERROR' } elseif ($tempC -ge 75) { 'WARN' } else { 'OK' }
            Write-StatusLine 'Температура (ACPI)' "$tempC °C" $tStatus
        } catch { Write-StatusLine 'Температура' 'недоступна через WMI (это нормально для многих моделей)' 'SKIP' }
        if ($Full) {
            # Стресс-проба: 10 секунд нагрузки на все потоки, проверяем что система остаётся отзывчивой
            Write-Host "  ... стресс-проба CPU (10 сек)" -ForegroundColor DarkGray
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $jobs = 1..$r.Threads | ForEach-Object { Start-Job -ScriptBlock { $end = (Get-Date).AddSeconds(10); $x = 1.0001; while ((Get-Date) -lt $end) { $x = [math]::Sqrt($x * 12345.678) + 1 } } }
            $jobs | Wait-Job -Timeout 25 | Out-Null; $jobs | Remove-Job -Force
            $sw.Stop()
            $r.StressTestSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            $sStatus = if ($sw.Elapsed.TotalSeconds -gt 20) { 'WARN' } else { 'OK' }
            Write-StatusLine 'Стресс-проба' "все $($r.Threads) потоков, завершена за $($r.StressTestSeconds) сек" $sStatus
        }
    } catch { Write-StatusLine 'CPU' $_.Exception.Message 'ERROR'; $r.Error = $_.Exception.Message }
    Add-ReportSection 'CPU' $r
}

# ============================== 3. ПАМЯТЬ ==============================
function Test-Memory {
    Write-Section "3/10  ОПЕРАТИВНАЯ ПАМЯТЬ"
    $r = @{}
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $usedPct = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 0)
        $r.TotalGB = $totalGB; $r.FreeGB = $freeGB; $r.UsedPercent = $usedPct
        Write-StatusLine 'Всего' "$totalGB GB" 'INFO'
        $memStatus = if ($usedPct -ge 92) { 'ERROR' } elseif ($usedPct -ge 80) { 'WARN' } else { 'OK' }
        Write-StatusLine 'Используется' "$usedPct% (свободно $freeGB GB)" $memStatus
        $modules = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
        if ($modules) {
            $r.Modules = @($modules | ForEach-Object { @{ SizeGB = [math]::Round($_.Capacity / 1GB, 0); SpeedMHz = $_.Speed; Slot = $_.DeviceLocator } })
            $modStr = ($r.Modules | ForEach-Object { "$($_.SizeGB)GB@$($_.SpeedMHz)MHz" }) -join ' + '
            Write-StatusLine 'Модули' $modStr 'INFO'
        }
    } catch { Write-StatusLine 'RAM' $_.Exception.Message 'ERROR'; $r.Error = $_.Exception.Message }
    Add-ReportSection 'Memory' $r
}

# ============================== 4. ДИСКИ ==============================
function Test-Disks {
    Write-Section "4/10  ДИСКИ И SMART"
    $r = @{ Physical = @(); Volumes = @() }
    try {
        # Физические диски: здоровье по SMART (Get-PhysicalDisk на Win 8+)
        $phys = Get-PhysicalDisk -ErrorAction SilentlyContinue
        if ($phys) {
            foreach ($d in $phys) {
                $sizeGB = [math]::Round($d.Size / 1GB, 0)
                $r.Physical += @{ Model = $d.FriendlyName; MediaType = "$($d.MediaType)"; SizeGB = $sizeGB; Health = "$($d.HealthStatus)" }
                $hStatus = if ("$($d.HealthStatus)" -eq 'Healthy') { 'OK' } elseif ("$($d.HealthStatus)" -eq 'Warning') { 'WARN' } else { 'ERROR' }
                Write-StatusLine "$($d.FriendlyName)" "$($d.MediaType), $sizeGB GB — SMART: $($d.HealthStatus)" $hStatus
            }
        } else {
            $drives = Get-CimInstance Win32_DiskDrive
            foreach ($d in $drives) {
                $st = if ($d.Status -eq 'OK') { 'OK' } else { 'ERROR' }
                $r.Physical += @{ Model = $d.Model; SizeGB = [math]::Round($d.Size / 1GB, 0); Health = $d.Status }
                Write-StatusLine "$($d.Model)" "статус: $($d.Status)" $st
            }
        }
        # Логические тома: свободное место
        $vols = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
        foreach ($v in $vols) {
            $freeGB = [math]::Round($v.FreeSpace / 1GB, 1); $totGB = [math]::Round($v.Size / 1GB, 1)
            $freePct = if ($v.Size -gt 0) { [math]::Round($v.FreeSpace / $v.Size * 100, 0) } else { 0 }
            $r.Volumes += @{ Drive = $v.DeviceID; FreeGB = $freeGB; TotalGB = $totGB; FreePercent = $freePct }
            $vStatus = if ($freePct -lt 10) { 'ERROR' } elseif ($freePct -lt 20) { 'WARN' } else { 'OK' }
            Write-StatusLine "Том $($v.DeviceID)" "свободно $freeGB / $totGB GB ($freePct%)" $vStatus
        }
        if ($Full) {
            # Замер скорости записи: 200 MB во временный файл
            Write-Host "  ... замер скорости записи (200 MB)" -ForegroundColor DarkGray
            $testFile = Join-Path $env:TEMP "disk-speed-test.tmp"
            $data = New-Object byte[] (8MB); (New-Object Random).NextBytes($data)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $fs = [System.IO.File]::OpenWrite($testFile)
            try { 1..25 | ForEach-Object { $fs.Write($data, 0, $data.Length) }; $fs.Flush($true) } finally { $fs.Close() }
            $sw.Stop()
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            $speedMBs = [math]::Round(200 / $sw.Elapsed.TotalSeconds, 0)
            $r.WriteSpeedMBs = $speedMBs
            $wStatus = if ($speedMBs -lt 50) { 'WARN' } else { 'OK' }
            Write-StatusLine 'Скорость записи' "$speedMBs MB/s" $wStatus
        }
    } catch { Write-StatusLine 'Диски' $_.Exception.Message 'ERROR'; $r.Error = $_.Exception.Message }
    Add-ReportSection 'Disks' $r
}

# ============================== 5. БАТАРЕЯ ==============================
function Test-Battery {
    Write-Section "5/10  БАТАРЕЯ"
    $r = @{}
    try {
        $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $bat) { Write-StatusLine 'Батарея' 'не обнаружена (настольный ПК или док-станция)' 'SKIP'; Add-ReportSection 'Battery' @{ Present = $false }; return }
        $r.Present = $true; $r.ChargePercent = $bat.EstimatedChargeRemaining
        $statusMap = @{ 1 = 'Разряжается'; 2 = 'От сети'; 3 = 'Полностью заряжена'; 4 = 'Низкий заряд'; 5 = 'Критический заряд'; 6 = 'Заряжается'; 7 = 'Заряжается (высокий)'; 8 = 'Заряжается (низкий)'; 9 = 'Заряжается (критический)'; 11 = 'Частично заряжена' }
        $r.State = if ($statusMap.ContainsKey([int]$bat.BatteryStatus)) { $statusMap[[int]$bat.BatteryStatus] } else { "Код $($bat.BatteryStatus)" }
        $cStatus = if ($r.ChargePercent -lt 15 -and $bat.BatteryStatus -eq 1) { 'WARN' } else { 'OK' }
        Write-StatusLine 'Заряд' "$($r.ChargePercent)% — $($r.State)" $cStatus
        # Износ: сравниваем проектную и фактическую полную ёмкость
        try {
            $design = (Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity
            $fullCharge = (Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity
            if ($design -gt 0 -and $fullCharge -gt 0) {
                $wear = [math]::Round((1 - $fullCharge / $design) * 100, 0)
                $r.DesignCapacity = $design; $r.FullChargeCapacity = $fullCharge; $r.WearPercent = $wear
                $wStatus = if ($wear -ge 50) { 'ERROR' } elseif ($wear -ge 30) { 'WARN' } else { 'OK' }
                Write-StatusLine 'Износ' "$wear% (ёмкость $fullCharge из $design mWh)$(if ($wStatus -eq 'ERROR') { ' — рекомендуется замена' })" $wStatus
            }
        } catch { Write-StatusLine 'Износ' 'данные о ёмкости недоступны — используйте -Full для отчёта powercfg' 'SKIP' }
        if ($Full) {
            $reportFile = Join-Path $env:TEMP "battery-report.html"
            $null = powercfg /batteryreport /output $reportFile 2>&1
            if (Test-Path $reportFile) { $r.PowercfgReport = $reportFile; Write-StatusLine 'Отчёт powercfg' $reportFile 'INFO' }
        }
    } catch { Write-StatusLine 'Батарея' $_.Exception.Message 'ERROR'; $r.Error = $_.Exception.Message }
    Add-ReportSection 'Battery' $r
}

# ============================== 6. GPU ==============================
function Test-Gpu {
    Write-Section "6/10  ВИДЕОАДАПТЕРЫ"
    $r = @{ Adapters = @() }
    try {
        $gpus = Get-CimInstance Win32_VideoController
        foreach ($g in $gpus) {
            $vramGB = if ($g.AdapterRAM -gt 0) { [math]::Round($g.AdapterRAM / 1GB, 1) } else { $null }
            $r.Adapters += @{ Name = $g.Name; DriverVersion = $g.DriverVersion; DriverDate = if ($g.DriverDate) { $g.DriverDate.ToString('yyyy-MM-dd') } else { $null }; VramGB = $vramGB; Status = $g.Status }
            $gStatus = if ($g.Status -eq 'OK') { 'OK' } else { 'ERROR' }
            $vramStr = if ($vramGB) { ", VRAM $vramGB GB" } else { '' }
            Write-StatusLine $g.Name "драйвер $($g.DriverVersion)$vramStr — $($g.Status)" $gStatus
            if ($g.DriverDate -and $g.DriverDate -lt (Get-Date).AddYears(-2)) {
                Write-StatusLine 'Драйвер' "старше 2 лет ($($g.DriverDate.ToString('yyyy-MM-dd'))) — проверьте обновления" 'WARN'
            }
        }
    } catch { Write-StatusLine 'GPU' $_.Exception.Message 'ERROR'; $r.Error = $_.Exception.Message }
    Add-ReportSection 'GPU' $r
}

# ============================== 7. СЕТЬ ==============================
function Test-Network {
    Write-Section "7/10  СЕТЬ И ИНТЕРНЕТ"
    $r = @{ Adapters = @() }
    try {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
        if ($adapters) {
            foreach ($a in $adapters) {
                $r.Adapters += @{ Name = $a.Name; Description = $a.InterfaceDescription; LinkSpeed = "$($a.LinkSpeed)"; Status = "$($a.Status)" }
                Write-StatusLine $a.Name "$($a.InterfaceDescription) — $($a.LinkSpeed)" 'OK'
            }
        } else { Write-StatusLine 'Адаптеры' 'нет активных сетевых подключений' 'ERROR' }
        # Ping до 8.8.8.8 — есть ли интернет и какая задержка
        $ping = Test-Connection -ComputerName 8.8.8.8 -Count 4 -ErrorAction SilentlyContinue
        if ($ping) {
            $avgMs = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average, 0)
            $r.InternetOK = $true; $r.AvgLatencyMs = $avgMs
            $pStatus = if ($avgMs -gt 150) { 'WARN' } else { 'OK' }
            Write-StatusLine 'Интернет (8.8.8.8)' "доступен, задержка $avgMs ms" $pStatus
        } else { $r.InternetOK = $false; Write-StatusLine 'Интернет' 'недоступен (ping 8.8.8.8 не прошёл)' 'ERROR' }
        # DNS
        try { $null = Resolve-DnsName 'github.com' -ErrorAction Stop; $r.DnsOK = $true; Write-StatusLine 'DNS' 'работает (github.com разрешается)' 'OK' }
        catch { $r.DnsOK = $false; Write-StatusLine 'DNS' 'не разрешает имена' 'ERROR' }
    } catch { Write-StatusLine 'Сеть' $_.Exception.Message 'ERROR'; $r.Error = $_.Exception.Message }
    Add-ReportSection 'Network' $r
}

# ============================== 8. УСТРОЙСТВА ==============================
function Test-Devices {
    Write-Section "8/10  УСТРОЙСТВА"
    $r = @{}
    try {
        # PnP-устройства с кодами ошибок диспетчера устройств
        $broken = Get-CimInstance Win32_PnPEntity -Filter "ConfigManagerErrorCode <> 0" -ErrorAction SilentlyContinue |
            Where-Object { $_.ConfigManagerErrorCode -ne 22 }  # 22 = отключено вручную, не считаем проблемой
        $r.DevicesWithErrors = @($broken | ForEach-Object { @{ Name = $_.Name; ErrorCode = $_.ConfigManagerErrorCode } })
        if ($broken) {
            foreach ($b in $broken) { Write-StatusLine 'Проблемное устройство' "$($b.Name) (код $($b.ConfigManagerErrorCode))" 'ERROR' }
        } else { Write-StatusLine 'Диспетчер устройств' 'нет устройств с ошибками' 'OK' }
        # Камера, аудио, Bluetooth — присутствие
        $cam = Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Camera' OR PNPClass='Image'" -ErrorAction SilentlyContinue | Select-Object -First 1
        Write-StatusLine 'Камера' $(if ($cam) { "$($cam.Name)" } else { 'не обнаружена' }) $(if ($cam) { 'OK' } else { 'WARN' })
        $r.Camera = if ($cam) { $cam.Name } else { $null }
        $audio = Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' } | Select-Object -First 1
        Write-StatusLine 'Аудио' $(if ($audio) { "$($audio.Name)" } else { 'нет рабочих аудиоустройств' }) $(if ($audio) { 'OK' } else { 'ERROR' })
        $r.Audio = if ($audio) { $audio.Name } else { $null }
        $bt = Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Bluetooth'" -ErrorAction SilentlyContinue | Select-Object -First 1
        Write-StatusLine 'Bluetooth' $(if ($bt) { 'присутствует' } else { 'не обнаружен' }) $(if ($bt) { 'OK' } else { 'SKIP' })
        $r.Bluetooth = [bool]$bt
    } catch { Write-StatusLine 'Устройства' $_.Exception.Message 'ERROR'; $r.Error = $_.Exception.Message }
    Add-ReportSection 'Devices' $r
}

# ============================== 9. БЕЗОПАСНОСТЬ ==============================
function Test-Security {
    Write-Section "9/10  БЕЗОПАСНОСТЬ И ОБНОВЛЕНИЯ"
    $r = @{}
    try {
        # Windows Defender
        try {
            $mp = Get-MpComputerStatus -ErrorAction Stop
            $r.DefenderEnabled = $mp.RealTimeProtectionEnabled
            $r.SignaturesAgeDays = $mp.AntivirusSignatureAge
            Write-StatusLine 'Defender (реал-тайм)' $(if ($mp.RealTimeProtectionEnabled) { 'включён' } else { 'ВЫКЛЮЧЕН' }) $(if ($mp.RealTimeProtectionEnabled) { 'OK' } else { 'ERROR' })
            $sigStatus = if ($mp.AntivirusSignatureAge -gt 7) { 'WARN' } else { 'OK' }
            Write-StatusLine 'Антивирусные базы' "обновлены $($mp.AntivirusSignatureAge) дн. назад" $sigStatus
        } catch { Write-StatusLine 'Defender' 'статус недоступен (возможно сторонний антивирус)' 'SKIP' }
        # Брандмауэр
        try {
            $fw = Get-NetFirewallProfile -ErrorAction Stop
            $offProfiles = @($fw | Where-Object { -not $_.Enabled })
            $r.FirewallAllOn = ($offProfiles.Count -eq 0)
            if ($offProfiles.Count -eq 0) { Write-StatusLine 'Брандмауэр' 'включён во всех профилях' 'OK' }
            else { Write-StatusLine 'Брандмауэр' "выключен: $(($offProfiles | ForEach-Object { $_.Name }) -join ', ')" 'WARN' }
        } catch { Write-StatusLine 'Брандмауэр' 'статус недоступен' 'SKIP' }
        # Дата последнего установленного обновления
        $lastHotfix = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1
        if ($lastHotfix -and $lastHotfix.InstalledOn) {
            $daysAgo = [math]::Round(((Get-Date) - $lastHotfix.InstalledOn).TotalDays, 0)
            $r.LastUpdateDaysAgo = $daysAgo
            $uStatus = if ($daysAgo -gt 60) { 'WARN' } else { 'OK' }
            Write-StatusLine 'Последнее обновление' "$($lastHotfix.HotFixID), $daysAgo дн. назад" $uStatus
        } else { Write-StatusLine 'Обновления' 'история недоступна' 'SKIP' }
    } catch { Write-StatusLine 'Безопасность' $_.Exception.Message 'ERROR'; $r.Error = $_.Exception.Message }
    Add-ReportSection 'Security' $r
}

# ============================== 10. СТАБИЛЬНОСТЬ ==============================
function Test-Stability {
    Write-Section "10/10  СТАБИЛЬНОСТЬ (журнал за 7 дней)"
    $r = @{}
    try {
        $since = (Get-Date).AddDays(-7)
        # Критические события (Level 1) — BSOD, отказ ядра
        $critical = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1; StartTime = $since } -MaxEvents 50 -ErrorAction SilentlyContinue
        $r.CriticalCount = @($critical).Count
        $critStatus = if ($r.CriticalCount -gt 3) { 'ERROR' } elseif ($r.CriticalCount -gt 0) { 'WARN' } else { 'OK' }
        Write-StatusLine 'Критические события' "$($r.CriticalCount) за 7 дней" $critStatus
        # Kernel-Power 41 — внезапные отключения (зависание, перегрев, питание)
        $kp41 = @($critical | Where-Object { $_.Id -eq 41 })
        $r.UnexpectedShutdowns = $kp41.Count
        if ($kp41.Count -gt 0) { Write-StatusLine 'Внезапные отключения' "$($kp41.Count) (Kernel-Power 41) — проверьте перегрев/питание" 'WARN' }
        # Ошибки дисков (disk, ntfs, volmgr)
        $diskErrors = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 2; StartTime = $since; ProviderName = @('disk', 'Ntfs', 'volmgr') } -MaxEvents 50 -ErrorAction SilentlyContinue
        $r.DiskErrorCount = @($diskErrors).Count
        if ($r.DiskErrorCount -gt 0) { Write-StatusLine 'Ошибки дисков в журнале' "$($r.DiskErrorCount) — проверьте SMART и кабели" 'ERROR' }
        else { Write-StatusLine 'Ошибки дисков в журнале' 'нет' 'OK' }
        # Топ-3 источника ошибок
        $errors = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 2; StartTime = $since } -MaxEvents 200 -ErrorAction SilentlyContinue
        $r.ErrorCount = @($errors).Count
        if ($errors) {
            $top = $errors | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 3
            $r.TopErrorSources = @($top | ForEach-Object { @{ Source = $_.Name; Count = $_.Count } })
            Write-StatusLine 'Всего ошибок (Level 2)' "$($r.ErrorCount); топ: $(($top | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', ')" $(if ($r.ErrorCount -gt 50) { 'WARN' } else { 'INFO' })
        } else { Write-StatusLine 'Ошибки в журнале' 'нет за 7 дней' 'OK' }
    } catch { Write-StatusLine 'Журнал событий' $_.Exception.Message 'ERROR'; $r.Error = $_.Exception.Message }
    Add-ReportSection 'Stability' $r
}

# ============================== ЗАПУСК ==============================
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "  ║        ДИАГНОСТИКА НОУТБУКА — Test-LaptopHealth           ║" -ForegroundColor Magenta
Write-Host "  ║        $((Get-Date).ToString('yyyy-MM-dd HH:mm'))  •  $($env:COMPUTERNAME.PadRight(20))          ║" -ForegroundColor Magenta
Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
if (-not $Full) { Write-Host "  Подсказка: -Full добавит стресс-пробу CPU, замер диска и отчёт батареи" -ForegroundColor DarkGray }

Test-SystemInfo
Test-Cpu
Test-Memory
Test-Disks
Test-Battery
Test-Gpu
Test-Network
Test-Devices
Test-Security
Test-Stability

# Итог: Health Score = 100 - 10 за каждую ошибку - 3 за каждое предупреждение
$score = [math]::Max(0, 100 - ($script:IssuesFound * 10) - ($script:WarningsFound * 3))
$script:Report.HealthScore = $score
$script:Report.Errors = $script:IssuesFound
$script:Report.Warnings = $script:WarningsFound

Write-Section "ИТОГ"
$scoreColor = if ($score -ge 85) { 'Green' } elseif ($score -ge 60) { 'Yellow' } else { 'Red' }
$verdict = if ($score -ge 85) { 'Отличное состояние' } elseif ($score -ge 60) { 'Рабочее состояние, есть замечания' } else { 'Требуется внимание!' }
Write-Host ""
Write-Host "  HEALTH SCORE: $score / 100 — $verdict" -ForegroundColor $scoreColor
Write-Host "  Ошибок: $($script:IssuesFound)   Предупреждений: $($script:WarningsFound)" -ForegroundColor Gray
Write-Host ""

if ($Export) {
    if (-not (Test-Path $ReportPath)) { New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null }
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $jsonFile = Join-Path $ReportPath "laptop-health-$stamp.json"
    $script:Report | ConvertTo-Json -Depth 6 | Out-File $jsonFile -Encoding UTF8
    Write-Host "  JSON-отчёт: $jsonFile" -ForegroundColor Cyan

    # HTML-отчёт: те же строки статусов, что и в консоли, сгруппированные по секциям
    function ConvertTo-HtmlSafe { param([string]$s); ($s -replace '&', '&amp;') -replace '<', '&lt;' -replace '>', '&gt;' }
    $scoreClass = if ($score -ge 85) { 'ok' } elseif ($score -ge 60) { 'warn' } else { 'err' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html><html lang="ru"><head><meta charset="utf-8"><title>Диагностика ноутбука</title><style>')
    [void]$sb.AppendLine('body{font-family:Segoe UI,Arial,sans-serif;background:#0f1420;color:#e6e9f0;max-width:860px;margin:24px auto;padding:0 16px}')
    [void]$sb.AppendLine('h1{font-size:1.4em}h2{font-size:1.05em;color:#7fd4ff;border-bottom:1px solid #2a3550;padding-bottom:4px;margin-top:28px}')
    [void]$sb.AppendLine('.score{font-size:2.4em;font-weight:700}.score.ok{color:#4ade80}.score.warn{color:#facc15}.score.err{color:#f87171}')
    [void]$sb.AppendLine('table{width:100%;border-collapse:collapse}td{padding:5px 8px;border-bottom:1px solid #1d2740;vertical-align:top}')
    [void]$sb.AppendLine('td.st{width:56px;font-weight:700;white-space:nowrap}td.lb{width:230px;color:#9aa5bd}')
    [void]$sb.AppendLine('.OK{color:#4ade80}.WARN{color:#facc15}.ERROR{color:#f87171}.INFO{color:#7fd4ff}.SKIP{color:#5b6478}')
    [void]$sb.AppendLine('.meta{color:#9aa5bd;font-size:.9em}</style></head><body>')
    [void]$sb.AppendLine("<h1>Диагностика ноутбука — $(ConvertTo-HtmlSafe $env:COMPUTERNAME)</h1>")
    [void]$sb.AppendLine("<div class='meta'>$($script:Report.GeneratedAt) • Test-LaptopHealth.ps1$(if ($Full) { ' • режим Full' })</div>")
    [void]$sb.AppendLine("<p class='score $scoreClass'>$score / 100</p><p>$verdict — ошибок: $($script:IssuesFound), предупреждений: $($script:WarningsFound)</p>")
    foreach ($group in ($script:Lines | Group-Object Section)) {
        [void]$sb.AppendLine("<h2>$(ConvertTo-HtmlSafe $group.Name)</h2><table>")
        foreach ($l in $group.Group) {
            [void]$sb.AppendLine("<tr><td class='st $($l.Status)'>$($l.Status)</td><td class='lb'>$(ConvertTo-HtmlSafe $l.Label)</td><td>$(ConvertTo-HtmlSafe $l.Value)</td></tr>")
        }
        [void]$sb.AppendLine('</table>')
    }
    [void]$sb.AppendLine('</body></html>')
    $htmlFile = Join-Path $ReportPath "laptop-health-$stamp.html"
    $sb.ToString() | Out-File $htmlFile -Encoding UTF8
    Write-Host "  HTML-отчёт: $htmlFile" -ForegroundColor Cyan

    # Ротация: храним только KeepReports последних отчётов каждого типа
    if ($KeepReports -gt 0) {
        foreach ($ext in @('json', 'html')) {
            Get-ChildItem $ReportPath -Filter "laptop-health-*.$ext" -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -Skip $KeepReports |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host ""
}
