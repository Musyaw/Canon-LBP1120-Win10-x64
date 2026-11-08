' Запуск: мастер настройки (первый раз) + окно сервера (отдельные окна PowerShell, без Hidden)
Option Explicit
Dim sh, fso, dir, ps1, cmd
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = dir & "\CaptWin-Launcher.ps1"
If Not fso.FileExists(ps1) Then
  MsgBox "Не найден CaptWin-Launcher.ps1" & vbCrLf & ps1, vbCritical, "Canon LBP1120 CAPT"
  WScript.Quit 1
End If
cmd = "powershell.exe -NoProfile -STA -NoLogo -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"
sh.Run cmd, 0, False
