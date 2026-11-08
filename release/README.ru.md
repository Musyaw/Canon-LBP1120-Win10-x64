# Canon Laser Shot LBP-1120 — печать на Windows 10/11 x64

Портативный комплект **captwin**: открытый драйвер CAPT v1 (без официального Canon CAPT x64).

---

## Что это и что мы сделали

| Проблема | Решение |
|----------|---------|
| Canon **не выпускал** драйвер LBP-1120 для Windows **64-bit** | Стек на базе реверса **[libcapt](https://github.com/darkvision77/libcapt)** + **[captppd](https://github.com/darkvision77/captppd)** |
| Принтер говорит по протоколу **CAPT v1** + сжатие **SCoA**, не PCL/PostScript | Программа **captwin.exe** сама шлёт команды на USB |
| Windows по умолчанию ставит **usbprint** — libusb не может открыть устройство | Один раз ставим **WinUSB** через **Zadig** (скрипт в комплекте) |

**На этом ПК уже проверено:** WinUSB → `status` (deviceId **221** = LBP-1120) → **testpage** печатает.

**Ограничение:** пока стоит WinUSB, **обычная** установка принтера в «Устройства и принтеры» для **этого USB** не работает. Печать — через **captwin** (или будущий сетевой сервис). Чтобы снова печатать через Windows-очередь, в Zadig можно вернуть **usbprint** (как было).

---

## Требования

- Windows **10 или 11**, **64-bit**
- USB-кабель, Canon **Laser Shot LBP-1120**
- Права **администратора** (только для установки WinUSB)
- Бумага A4 в лотке, принтер включён (Ready)

---

## Установка «из коробки» (рекомендуется)

1. Запустите **`dist\Canon-LBP1120-CAPT-Setup.exe`** (или **`Setup.bat`** из zip) **от администратора**.

Установщик сам:
- копирует файлы в `C:\Program Files\CanonLBP1120Capt`;
- ставит **Ghostscript** (если ещё нет);
- ставит **WinUSB** (INF) или подскажет Zadig;
- создаёт принтер Windows **`Canon LBP1120 (CAPT)`** (порт `127.0.0.1:9100`);
- ярлык на рабочем столе **«Canon LBP1120 — печать»** — окно сервера (не чёрная консоль).

**Как печатать:**
1. Откройте **«Canon LBP1120 — печать»** (сервер должен быть «работает»).
2. В браузере или Word: **Ctrl+P** → **Canon LBP1120 (CAPT)**.
3. Тест без браузера: кнопка **«Тестовая страница»** в окне сервера.

Сборка установщика: `.\pack-release.ps1`, затем Inno Setup → `installer\CaptWinSetup.iss` → `dist\Canon-LBP1120-CAPT-Setup.exe`.

Удаление программы: «Параметры → Приложения» (Inno uninstall снимает очередь принтера; Ghostscript остаётся в системе — его можно удалить отдельно).

---

## Установка вручную (пошагово)

1. Скопируйте **всю папку** `Canon-LBP1120-captwin-Win10-x64` на диск (путь **без кириллицы** предпочтительно, но не обязательно).

2. **WinUSB (один раз):**  
   Правый клик → **Запуск от имени администратора** → **`install-winusb.bat`**

   В **Zadig**:
   - **Options → List All Devices**
   - **Canon CAPT USB Printer** (USB ID **04A9 262B**)
   - Справа: **WinUSB**
   - **Replace Driver** / **Reinstall Driver** → **Success**

3. **Проверка** (обычный PowerShell или cmd, из папки комплекта):

   ```powershell
   cd "путь\к\Canon-LBP1120-captwin-Win10-x64"
   .\captwin.exe list
   .\captwin.exe status
   .\captwin.exe testpage
   ```

   Или двойной клик **`print-testpage.bat`**.

   Ожидание **«Waiting for paper…»** — нормально, пока принтер не готов; затем **Sending page…** и лист из лотка.

---

## Команды captwin

| Команда | Описание |
|---------|----------|
| `captwin.exe list` | USB-принтеры (ожидается **04a9:262b**) |
| `captwin.exe status` | Статус CAPT, готовность, бумага |
| `captwin.exe testpage` | Тест из `data\example-1.pbm` |
| `captwin.exe print файл.pbm` | Печать P4 PBM, 600 dpi, ширина кратна 8 px |

Опции: `--vid 04a9 --pid 262b`, `-v` (отладка libusb).

---

## Состав папки

```
captwin.exe              — программа печати
libwinpthread-1.dll      — нужна для запуска (MinGW)
data\example-1.pbm       — тестовая страница
tools\zadig.exe          — установка WinUSB
install-winusb.bat       — запуск Zadig (от админа)
print-testpage.bat       — быстрый тест
README.ru.md             — эта инструкция
LICENSES.txt             — лицензии open source
```

---

## Устранение неполадок

| Симптом | Что делать |
|---------|------------|
| `captwin.exe` не запускается | Положите **`libwinpthread-1.dll`** рядом с exe |
| `NOT_SUPPORTED` / не открывает USB | WinUSB не установлен → **install-winusb.bat** |
| Долго **Waiting for paper** | Бумага, крышка, картридж, кнопка Ready на принтере |
| После Zadig нет принтера в Windows | Так и задумано для WinUSB; печать только через **captwin** |
| Нужен снова драйвер Windows | Zadig → то же устройство → **usbprint** (если доступно) |

---

## Печать из браузера и любых программ (Ctrl+P)

Нужны **WinUSB** (Zadig), **Ghostscript** и запущенный сервер.

### 1. Ghostscript (один раз)

Скачайте и установите **GPL Ghostscript** для Windows (64-bit):  
https://ghostscript.com/releases/gsdnld.html  

После установки должен быть `gswin64c.exe` (обычно в `C:\Program Files\gs\...`).

### 2. Принтер в Windows (один раз, от администратора)

```powershell
powershell -ExecutionPolicy Bypass -File ".\install-system-printer.ps1"
```

Или **`install-system-printer.bat`** от администратора.

Появится принтер **`Canon LBP1120 (CAPT)`** на адрес **127.0.0.1:9100** (PostScript → сервер → CAPT).

Если скрипт не нашёл драйвер — вручную: **Параметры → Принтеры → Добавить → IP** `127.0.0.1`, порт **9100**, драйвер **Microsoft PS Class Driver** (Publisher Color Printer).

### 3. Перед печатью с сайта

Запустите и **не закрывайте** окно:

- **`start-print-server.bat`**, или  
- `captwin.exe serve --port 9100`

### 4. В Chrome / Edge / Firefox

**Ctrl+P** → принтер **`Canon LBP1120 (CAPT)`** → Печать.

Страница уходит как PostScript → Ghostscript → растр 600 dpi A4 → CAPT на USB.

**Замечания:** сервер должен быть запущен; первый лист может идти дольше; сложные страницы зависят от Ghostscript; цвет печатается как оттенки серого.

---

- Порт **9100** + очередь Windows → печать из Word/браузера  
- Конвертация PDF/PNG в PBM (Ghostscript)  
- Собственный INF-драйвер x64  

---

## Лицензии

- **libcapt**, **captppd** — BSD-2-Clause  
- **libusb** — LGPL-2.1 (исходники: https://github.com/libusb/libusb)  
- **Zadig** — GPL-3 (https://github.com/pbatard/libwdi)  

Подробнее: **LICENSES.txt**

*Не аффилировано с Canon Inc.*
