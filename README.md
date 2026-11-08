# Canon LBP-1120 на Windows 10 x64 (CAPT, captwin)

Рабочая сборка: **1.1.22**. Готовый установщик лежит рядом, в папке `01-установщик` (на GitHub его лучше прикрепить к **Release**, а не коммитить в историю).

Официального драйвера Canon CAPT для 64-битной Windows нет. Здесь свой сервер печати: USB через WinUSB (Zadig), очередь Windows, Ghostscript, печать по Ctrl+P.

Проверено на Windows 10 x64, принтер Canon Laser Shot LBP-1120 (USB `04A9:262B`).

## Что внутри

| Папка | Зачем |
|---|---|
| `captwin` | программа сервера (`captwin.exe`) |
| `installer` | скрипты GUI, мастер, Inno Setup (`CaptWinSetup.iss`) |
| `libcapt` | протокол CAPT |
| `third_party/ghostscript` | Ghostscript, который кладётся в установщик |
| `tools/zadig` | Zadig для WinUSB |
| `release` | распакованный комплект последней сборки |

Сборка установщика (нужны MinGW в `C:\mingw64` и Inno Setup 6):

```text
.\pack-release.ps1
ISCC installer\CaptWinSetup.iss
```

Результат: `dist\Canon-LBP1120-CAPT-Setup.exe`.

Компилятор и CMake в архив не входят: `tools\winlibs.zip` и `tools\cmake.zip` слишком большие для GitHub. Поставьте MinGW и CMake сами.

## Лицензии

Смотрите `release\LICENSES.txt` и лицензии Ghostscript, Zadig, libusb. Это сторонняя сборка, не продукт Canon.
