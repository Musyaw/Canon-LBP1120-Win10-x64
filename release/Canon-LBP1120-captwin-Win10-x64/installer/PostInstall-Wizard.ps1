# Мастер настройки Canon LBP1120 CAPT (WinForms). Запускается с ярлыка «быстрый запуск» до первого «Готово».
param(
    [string]$InstallDir = "${env:ProgramFiles}\CanonLBP1120Capt",
    [switch]$Force
)

$ErrorActionPreference = "Continue"

$logScript = Join-Path $InstallDir "installer\CaptWin-Logging.ps1"
if (Test-Path -LiteralPath $logScript) { . $logScript; Initialize-CaptWinLog -InstallDir $InstallDir -Source "Wizard" }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

if (-not (Test-Path $InstallDir)) {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Не найден каталог программы:`n$InstallDir",
        "Canon LBP1120 CAPT", "OK", "Error")
    exit 1
}

$doneFlag = Join-Path $InstallDir "data\setup-wizard.done"
if ((Test-Path $doneFlag) -and -not $Force) {
    exit 0
}

$Zadig = Join-Path $InstallDir "tools\zadig.exe"
$PrinterBat = Join-Path $InstallDir "Setup-PrinterQueue.bat"
$GuideTxt = Join-Path $InstallDir "installer\Setup-Guide.ru.txt"

function Open-Tool([string]$path) {
    if (Test-Path $path) {
        Start-Process -FilePath $path
    } else {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Файл не найден:`n$path", "Canon LBP1120 CAPT", "OK", "Warning")
    }
}

function Complete-Setup {
    New-Item -ItemType Directory -Force -Path (Split-Path $doneFlag) | Out-Null
    Set-Content -Path $doneFlag -Value (Get-Date).ToString("o") -Encoding UTF8
}

function Format-StepText {
    param([string[]]$Lines)
    ($Lines | ForEach-Object { [string]$_ }) -join "`r`n"
}

$steps = @(
    @{
        Title = "Шаг 1 из 5 — Принтер"
        Lines = @(
            "Программа установлена в:"
            $InstallDir
            ""
            "• Подключите Canon LBP-1120 к USB и включите питание."
        )
        ButtonText = $null
    },
    @{
        Title = "Шаг 2 из 5 — Драйвер USB (WinUSB)"
        Lines = @(
            "1. «Открыть Zadig» → tools\zadig.exe"
            "2. Options → List All Devices"
            "3. Устройство: Canon LBP-1120 / VID_04A9 PID_262B"
            "4. Драйвер справа: WinUSB → Replace Driver"
            "5. Дождитесь Success, USB отключите на 5 сек и снова подключите."
            ""
            "Подробнее: installer\Setup-Guide.ru.txt"
        )
        ButtonText = "Открыть Zadig"
        ActionName = "Zadig"
    },
    @{
        Title = "Шаг 3 из 5 — Принтер в Windows"
        Lines = @(
            "Для Ctrl+P в браузере нужен принтер «Canon LBP1120 (CAPT)»."
            ""
            "Параметры → Принтеры и сканеры → выберите «Canon LBP1120 (CAPT)»."
            "Кнопка «Открыть очередь» — окно очереди (может быть пустым, это нормально)."
            ""
            "Если принтера нет в списке — «Добавить очередь» (от администратора)."
        )
        ButtonText = "Открыть принтеры"
        ActionName = "Printers"
        ButtonText2 = "Добавить очередь"
        ActionName2 = "Queue"
    },
    @{
        Title = "Шаг 4 из 5 — Сервер печати"
        Lines = @(
            "После «Готово» откроется окно сервера (этот же ярлык с рабочего стола)."
            ""
            "• Нажмите «Запустить», если сервер ещё не запущен."
            "• Три зелёных индикатора → «Готов к печати»."
            "• Красный принтер → WinUSB (шаг 2) или «Обновить»."
        )
        ButtonText = $null
    },
    @{
        Title = "Шаг 5 из 5 — Проверка"
        Lines = @(
            "• В окне сервера одна кнопка «Тестовая страница» — один лист."
            "• Браузер: Ctrl+P → «Canon LBP1120 (CAPT)»."
            ""
            "Не печатает → вернитесь к шагу 2 (Zadig)."
            ""
            "Справка: README.ru.txt"
        )
        ButtonText = "Открыть справку"
        ActionName = "Readme"
    }
)

$form = New-Object System.Windows.Forms.Form
$form.Text = "Canon LBP1120 CAPT — настройка"
$form.Size = New-Object Drawing.Size(520, 420)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Font = New-Object Drawing.Font("Segoe UI", 9)
$form.TopMost = $true

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.AutoSize = $false
$lblTitle.Size = New-Object Drawing.Size(480, 28)
$lblTitle.Location = New-Object Drawing.Point(16, 12)
$lblTitle.Font = New-Object Drawing.Font("Segoe UI", 11, [Drawing.FontStyle]::Bold)

$txtBody = New-Object System.Windows.Forms.TextBox
$txtBody.Multiline = $true
$txtBody.ReadOnly = $true
$txtBody.WordWrap = $true
$txtBody.ScrollBars = "Vertical"
$txtBody.Location = New-Object Drawing.Point(16, 48)
$txtBody.Size = New-Object Drawing.Size(472, 260)
$txtBody.BorderStyle = "FixedSingle"
$txtBody.TabStop = $false

$btnAction = New-Object System.Windows.Forms.Button
$btnAction.Size = New-Object Drawing.Size(160, 32)
$btnAction.Location = New-Object Drawing.Point(16, 318)
$btnAction.Visible = $false

$btnAction2 = New-Object System.Windows.Forms.Button
$btnAction2.Size = New-Object Drawing.Size(160, 32)
$btnAction2.Location = New-Object Drawing.Point(182, 318)
$btnAction2.Visible = $false

$btnBack = New-Object System.Windows.Forms.Button
$btnBack.Text = "Назад"
$btnBack.Size = New-Object Drawing.Size(90, 32)
$btnBack.Location = New-Object Drawing.Point(228, 318)

$btnNext = New-Object System.Windows.Forms.Button
$btnNext.Text = "Далее"
$btnNext.Size = New-Object Drawing.Size(90, 32)
$btnNext.Location = New-Object Drawing.Point(326, 318)

$btnFinish = New-Object System.Windows.Forms.Button
$btnFinish.Text = "Готово"
$btnFinish.Size = New-Object Drawing.Size(90, 32)
$btnFinish.Location = New-Object Drawing.Point(326, 318)
$btnFinish.Visible = $false

$btnSkip = New-Object System.Windows.Forms.Button
$btnSkip.Text = "Пропустить"
$btnSkip.Size = New-Object Drawing.Size(90, 32)
$btnSkip.Location = New-Object Drawing.Point(422, 318)

$form.Controls.AddRange(@($lblTitle, $txtBody, $btnAction, $btnAction2, $btnBack, $btnNext, $btnFinish, $btnSkip))

$script:idx = 0
$script:closedOk = $false

function Show-Step {
    $s = $steps[$script:idx]
    $lblTitle.Text = $s.Title
    $txtBody.Text = Format-StepText -Lines $s.Lines
    $btnBack.Enabled = ($script:idx -gt 0)
    $isLast = ($script:idx -eq ($steps.Count - 1))
    $btnNext.Visible = -not $isLast
    $btnFinish.Visible = $isLast
    if ($s.ButtonText) {
        $btnAction.Text = $s.ButtonText
        $btnAction.Visible = $true
    } else {
        $btnAction.Visible = $false
    }
    if ($s.ButtonText2) {
        $btnAction2.Text = $s.ButtonText2
        $btnAction2.Visible = $true
    } else {
        $btnAction2.Visible = $false
    }
}

$btnAction.Add_Click({
    $name = $steps[$script:idx].ActionName
    switch ($name) {
        "Zadig" { Open-Tool $Zadig }
        "Printers" {
            Start-Process "ms-settings:printers"
        }
        "Queue" {
            if (Test-Path $PrinterBat) { Start-Process -FilePath $PrinterBat -Verb RunAs }
        }
        "Readme" {
            $readme = Join-Path $InstallDir "README.ru.txt"
            if (Test-Path $readme) { Start-Process -FilePath "notepad.exe" -ArgumentList @($readme) }
            elseif (Test-Path $GuideTxt) { Start-Process -FilePath "notepad.exe" -ArgumentList @($GuideTxt) }
        }
    }
})

$btnAction2.Add_Click({
    $name = $steps[$script:idx].ActionName2
    if ($name -eq "Queue" -and (Test-Path $PrinterBat)) {
        Start-Process -FilePath $PrinterBat -Verb RunAs
    }
})

$btnBack.Add_Click({
    if ($script:idx -gt 0) {
        $script:idx--
        Show-Step
    }
})

$btnNext.Add_Click({
    if ($script:idx -lt ($steps.Count - 1)) {
        $script:idx++
        Show-Step
    }
})

$btnFinish.Add_Click({
    $script:closedOk = $true
    Complete-Setup
    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Close()
})

$btnSkip.Add_Click({
    $script:closedOk = $false
    $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Close()
})

$form.Add_Shown({ $form.TopMost = $false; $form.Activate() })

Show-Step
try {
    [void]$form.ShowDialog()
} catch {
    if (Get-Command Write-CaptWinLog -ErrorAction SilentlyContinue) {
        Write-CaptWinLog $_.Exception.Message "ERROR"
    }
    [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Canon LBP1120 CAPT", "OK", "Error")
    exit 1
}

if ($script:closedOk) { exit 0 }
exit 0

