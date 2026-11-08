# Отчёт: Canon Laser Shot LBP-1120 — драйверы, USB, открытый код

**Дата сбора:** 2026-11-01  
**Цель:** собрать факты для возможной разработки драйвера Windows x64. Код и установка драйверов на этом этапе **не выполнялись**.

---

## 1. Краткий вывод

| Вопрос | Ответ |
|--------|--------|
| Принтер виден по USB на этой машине? | **Да**, статус OK |
| Установлен Canon-драйвер / очередь печати? | **Нет**, только стандартный `usbprint` (Microsoft) |
| Официальный драйвер Windows x64? | **Нет** (Canon прямо указывает: только 32-bit Windows) |
| Открытый драйвер под Windows x64? | **Не найден** |
| Открытый стек с поддержкой LBP-1120? | **Да**, но **Linux/CUPS + libusb** (`libcapt` + `captppd`) |
| Есть ли «исходники» протокола? | **Частично:** reverse-engineered C/C++ (BSD/GPL), не исходники Canon |

**Для переписывания под Windows x64** наиболее ценная база — **`darkvision77/libcapt`** (протокол CAPT v1 + SCoA) и **`darkvision77/captppd`** (эталонная реализация обмена по USB). Официальный Windows-пакет — только бинарники x86.

---

## 2. Проверка на локальном ПК (sabir)

### ОС

- **Windows 10 Домашняя**, **64-bit** (build **10.0.19045**)

### USB / PnP

Обнаружены записи (все **Status: OK**, проблем PnP нет):

| Имя | InstanceId / идентификатор |
|-----|---------------------------|
| Поддержка USB принтера | `USB\VID_04A9&PID_262B\49IGRV` |
| Canon LASER SHOT LBP-1120 | `USBPRINT\CANONLASER_SHOT_LBP-1120\6&388D619E&0&USB001` |
| CanonLASER SHOT LBP-1120 (SoftwareDevice) | класс SoftwareDevice, OK |

**USB identity (Canon):**

- **VID:PID** — `04A9:262B` (Canon, Inc. LaserShot LBP-1120)
- **Hardware IDs** — `USB\VID_04A9&PID_262B&REV_0100`, `USB\VID_04A9&PID_262B`
- **USB class** — Printer (Class 07, SubClass 01, Prot 02)
- **Serial (на этом экземпляре)** — `49IGRV`
- **Сервис устройства** — `usbprint` (встроенный классовый драйвер Windows **10.0.19041.6157**, производитель в свойствах — Microsoft)

### Очереди печати Windows

`Get-Printer` показывает только стандартные виртуальные принтеры (PDF, XPS, OneNote, Fax). **Очереди «Canon LBP-1120» нет.**

### Ожидаемая IEEE-1284 / USB DEVICE_ID строка

По документации Linux/CUPS для этой модели (типичный ответ принтера):

```text
MFG:Canon;MDL:LASER SHOT LBP-1120;CMD:CAPT;VER:1.0;CLS:PRINTER;DES:Canon LASER SHOT LBP-1120
```

**CMD:CAPT; VER:1.0** — принтер не «dumb GDI/PCL», а **CAPT v1** (хост формирует растр и управляет протоколом).

---

## 3. Аппарат и протокол (справочно)

Источники: [руководство/тех. описание LBP1120 (PDF)](https://www.instructionsmanuals.com/sites/default/files/2019-03/Canon-LBP1120-en.pdf), Canon support.

| Параметр | Значение |
|----------|----------|
| Тип | монохромный лазер, desktop |
| Скорость | ~10 ppm (A4) |
| Разрешение | 600 × 600 dpi |
| Картридж | EP-22 (~2500 стр.) |
| Интерфейс | **USB 1.1** |
| Память принтера | 512 KB RAM, 8 KB ROM |
| Технология | **CAPT** — растр и часть обработки на **хосте** |
| Год модели (ориентир) | ~2003–2004 |

**CAPT на Windows (официальная модель):** драйвер переводит задание в ресурсы GDI → растр (точки) → по USB уходит **CAPT-команды + сжатый растр**. Статус/error — **двунаправленный** обмен (на Linux для этого же нужны `ccpd` / `captmon` / opbidi).

**Сжатие растра для LBP-1120:** **SCoA** (Smart Compression Architecture), не Hi-SCoA как у LBP2900+.

---

## 4. Официальные драйверы Canon

### Windows

| Версия / пакет | Примечание |
|----------------|------------|
| **R1.10 V1.1** | Файл: `LBP-1120_R110_V110_Win_x32_EN_7.exe` (~1 MB), дата в EU support: **23.12.2009** |
| Совместимость Canon EU | **Windows Vista/7 32-bit** (явно в карточке драйвера) |
| Более старые | R1.02 для Win 98/Me/2000/XP (32-bit) |
| DEP module | `DEP-support` для XP SP2+, **32-bit** |

**Позиция Canon по x64 Windows:** [KB ART119655](https://support.usa.canon.com/kb/s/article/ART119655) — продукт **не поддерживается** на 64-bit Windows, рассчитан **только на 32-bit**.

На форумах Microsoft подтверждают: установщик/INF **не содержит x64-драйвер** — сообщение «compatible software driver for x64» при указании папки с Win32-драйвером.

**Важно:** на сайтах Canon иногда в общем списке ОС фигурирует «Windows 10 64-bit», но **отдельного x64 CAPT-пакета для LBP-1120 нет**; рабочий официальный путь — **32-bit Windows** (или VM).

### Linux (официальный CAPT от Canon)

| Пакет | Версия | Архитектура |
|-------|--------|-------------|
| CAPT Printer Driver for Linux | **V2.71** (май 2017) | **i386 + x86_64** (.deb/.rpm) |
| PPD для LBP-1120 | `CNCUPSLBP1120CAPTK.ppd` / `CNCUPSLBP1120CAPTJ.ppd` | «Canon LBP1120 CAPT ver.1.5» |
| Фильтр CUPS | `pstocapt`, общие модули `cndrvcups-common`, `cndrvcups-capt` | **бинарники**, не полные исходники |
| Демон | **`ccpd`** + **`captmon`** (status monitor) | GPL-обёртки + проприетарные .so |

Состав типичной установки Linux (из README пакета): `ccpd`, `captstatusui`, `captfilter`, `pstocapt`, PPD, конфиги CUPS.

**Исходники Canon:** публикуются **не как полный Windows/Linux driver tree**, а отдельные компоненты под GPL (PPD, часть CUPS-интеграции). Ядро протокола — **закрытые бинарники** (`captfilter`, `uictlcapt` и т.д.).

---

## 5. Открытый код и community (GitHub и др.)

### 5.1. Рекомендуемая база для LBP-1120 (CAPT v1 + SCoA)

| Репозиторий | Лицензия | Роль | LBP-1120 |
|-------------|----------|------|----------|
| [darkvision77/libcapt](https://github.com/darkvision77/libcapt) | BSD-2 | **Протокол CAPT v1 + SCoA**, OS-agnostic | **Целевое устройство** |
| [darkvision77/captppd](https://github.com/darkvision77/captppd) | BSD-2 | CUPS backend **libusb**, PPD | **Поддерживается** (600 dpi, multi-page, cleaning, …) |
| Отзывы (2026) | — | captppd на реальном LBP-1120 | [agalakhov/captdriver#20](https://github.com/agalakhov/captdriver/issues/20) |

**captppd не ставится на Windows** — только Linux + CUPS + libusb-1.0.

### 5.2. Другие open-source проекты

| Репозиторий | LBP-1120 | Комментарий |
|-------------|----------|-------------|
| [mounaiban/captdriver](https://github.com/mounaiban/captdriver) (форк [agalakhov/captdriver](https://github.com/agalakhov/captdriver)) | **Нет** (нужен glue + SCoA) | Hi-SCoA, LBP2900/3000/3010…; в wiki: SCoA **не** в captdriver, отсылка к captppd |
| [caxapyk/capt_lbp810-1120](https://github.com/caxapyk/capt_lbp810-1120) | Через LBP-810 PPD | Форк Nicolas Boichat capt 0.1, «magic blobs», устаревший подход |
| [Magister/cndrvcups-capt](https://github.com/Magister/cndrvcups-capt) | PPD + зеркало Canon GPL | `CNCUPSLBP1120CAPTK.ppd`, не замена Windows-драйвера |
| Nicolas Boichat [capt](http://www.boichat.ch/nicolas/capt/) | Исторический Linux | Ранняя reverse engineering, минимум знаний протокола |
| [UoWPrint](https://printserver.ink/docs-en/printer-setup-canon/) | LBP-1120 через captppd (fw ≥1.23) | ARM print-server, не Windows host driver |

### 5.3. Windows x64 «обходы» (не нативный драйвер)

- **32-bit VM** (XP/7) + официальный Canon + проброс USB ([Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/2593138/unable-to-install-canon-laser-shot-lbp-1120-on-win)).
- **Print server на Linux** (captppd) + сеть с Windows.
- **Ghostscript + RedMon + PS-драйвер** на 32-bit «сервере» ([blog.a7in.com](https://blog.a7in.com/lpb-1120-windows-7-x64-driwer/?lang=en)) — костыль, не CAPT на x64.

**Вывод:** публичного «vibe-coded» **Windows x64 CAPT-драйвера** для LBP-1120 **нет**.

---

## 6. Архитектура: что придётся реализовать для Windows x64

Ориентир по слоям (сопоставление Linux ↔ Windows):

```text
Приложение → GDI / Print Spooler
    → User-mode print driver (UNIDRV / V4 или custom)
        → Rasterization (600 dpi, 1-bit / 8 bpp pipeline как в PPD)
        → SCoA compression          ← libcapt (готовая логика, C++)
        → CAPT v1 state machine     ← libcapt + captppd (handshake, job, status)
        → USB bulk/interrupt        ← WinUSB / libusb-win32 / custom I/O
    ← Bidirectional status (paper, toner, pause/resume)
Принтер (CAPT v1, VER 1.0)
```

**Отличие LBP-1120 от «молодых» LBP:** другой **control code** (не только компрессия). Galakhov: *«LBP-1120 is quite different… nobody wrote the corresponding glue code»* — glue для **1120** сделан в **captppd/libcapt**, не в captdriver.

**Что уже исследовано в open source (по README libcapt):**

- SCoA reverse-engineered, тесты против `captfilter` (GDB command log).
- Протокол CAPT v1 «достаточно известен» для печати и cleaning на перечисленных моделях.
- Не реализовано в captppd: 300 dpi, произвольный размер носителя.

**Что даёт официальный Windows x32 пакет (для RE, не redist):**

- INF, монитор порта, UI, `CAPT` user-mode DLL, spooler hooks — всё **x86-only**.
- Полезно для сравнения USB-трафика и поведения spooler, **не** для легального копирования кода.

---

## 7. Версии и файлы (шпаргалка)

| Компонент | Версия / имя |
|-----------|----------------|
| Windows CAPT (последний для 1120) | **R1.10 V1.1**, `LBP-1120_R110_V110_Win_x32_*` |
| Linux CAPT Canon | **2.71**, PPD **ver.1.5** |
| CAPT на устройстве | **VER:1.0** в DEVICE_ID |
| USB | **VID 04A9**, **PID 262B** |

---

## 8. Полезные ссылки

- Canon Europe support: https://www.canon-europe.com/support/consumer/products/printers/laser/lbp-series/laser-shot-lbp1120.html  
- Canon EU driver card (Win x32 R1.10): https://www.canon-europe.com/supportproduct/tabcontent/?detailId=tcm%3A13-727854  
- Canon x64 policy: https://support.usa.canon.com/kb/s/article/ART119655  
- libcapt: https://github.com/darkvision77/libcapt  
- captppd: https://github.com/darkvision77/captppd  
- captdriver / LBP-1120 issue: https://github.com/agalakhov/captdriver/issues/20  
- SCoA specs (captdriver wiki): https://github.com/mounaiban/captdriver/wiki/SPECS:-SCoA-Specifications  
- Habr (контекст LBP-1120, VM, captppd): https://habr.com/ru/articles/843898/  

---

## 9. Следующие шаги (когда перейдём от «только инфо»)

1. Снять **USB DEVICE_ID** локально (если нужно подтвердить строку для `49IGRV`) — через утилиту/port monitor или Linux live + `usb_printerid`.
2. Скачать **официальный Win x32** и **Linux x64 2.71** в архив проекта **только для анализа** (лицензии Canon).
3. Прогнать **captppd** на Linux/WSL2 с USB passthrough **или** сравнить трафик Win32 VM vs captppd.
4. Спроектировать **Windows port**: общая библиотека на базе **libcapt** (CMake + MSVC/clang-cl) + минимальный print pipeline (V4 или классический UNIDRV + custom rendering filter).

---

*Отчёт сгенерирован автоматически по результатам локальной диагностики и открытых источников. Установка драйверов и изменение системы не выполнялись.*
