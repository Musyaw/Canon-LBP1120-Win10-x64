# Драйвер Canon LBP-1120 для Windows 10 и Windows 11 (64 бит)

Печать на **Canon Laser Shot LBP-1120** (LBP1120) из 64-битной Windows без виртуальной машины.

Официального драйвера CAPT под Windows x64 нет. Эта сборка ставит свой сервер печати: принтер один раз переводится на WinUSB, дальше документы уходят через обычный Ctrl+P.

Проверено на Windows 10 x64 и Windows 11 x64, USB `04A9:262B`. Это не продукт Canon.

**Установщик 1.1.22:** [скачать](https://github.com/Musyaw/Canon-LBP1120-Win10-x64/releases/tag/v1.1.22)

## Как печатать

1. Подключите принтер по USB и включите его.
2. Запустите `Canon-LBP1120-CAPT-Setup-1.1.22.exe` от имени администратора.
3. На рабочем столе откройте **«LBP-1120 — быстрый запуск»**.
4. В мастере нажмите **«Открыть Zadig»**. Выберите Canon (`VID 04A9`, `PID 262B`), драйвер **WinUSB**, затем **Replace Driver**. Драйвер «Поддержка USB принтера» (`usbprint`) для этой программы не подходит.
5. Дождитесь трёх зелёных индикаторов и надписи **«Готов к печати»**.
6. Печатайте через Ctrl+P, принтер **Canon LBP1120 (CAPT)**. Окно сервера при этом должно быть открыто.

Сервер слушает порт 9100. Кнопка «Тестовая страница» печатает встроенный пример напрямую на USB.

## Что в репозитории

| Папка | Содержимое |
| --- | --- |
| `captwin` | сервер печати `captwin` |
| `installer` | окно, мастер настройки, скрипт Inno Setup |
| `libcapt` | реализация протокола CAPT |
| `third_party/ghostscript` | Ghostscript, который попадает в установщик |
| `tools/zadig` | Zadig для установки WinUSB |
| `release` | распакованный комплект рабочей сборки |

## Сборка

Нужны MinGW в `C:\mingw64` и Inno Setup 6. Архивы компилятора в репозиторий не входят.

```text
.\pack-release.ps1
ISCC installer\CaptWinSetup.iss
```

Готовый файл: `dist\Canon-LBP1120-CAPT-Setup.exe`.

## Лицензия

Свой код (captwin, установщик, скрипты настройки) — [MIT](LICENSE).

Чужие части остаются под своими лицензиями, список в `release\LICENSES.txt`: libcapt и captppd (BSD 2-Clause), libusb (LGPL-2.1), Zadig (GPL-3), Ghostscript (AGPL-3). Сборка не является драйвером Canon.

## Теги

`Canon LBP-1120` `LBP1120` `Laser Shot` `Windows 10 64 bit` `Windows 11 x64` `CAPT` `WinUSB` `драйвер`

Официального драйвера Canon под 64-битную Windows нет. Здесь рабочая замена: установщик, WinUSB и печать через Ctrl+P. Проверено на Windows 10 x64 и Windows 11 x64.

## Контакт

Сделал Musyaw. Написать в Telegram: [@bytebin](https://t.me/bytebin)
