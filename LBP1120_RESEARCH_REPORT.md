# Canon Laser Shot LBP-1120 — отчёт по разведке (сбор информации)

**Дата:** 2026-11-01  
**Цель:** понять, какой драйвер нужен, есть ли исходники/открытые реализации, состояние USB на текущем ПК. Код драйвера **не писался** — только сбор фактов для будущего x64-драйвера под современные Windows.

---

## 1. Локальная проверка (этот компьютер)

| Параметр | Значение |
|----------|----------|
| ОС | Microsoft Windows 10 Домашняя |
| Разрядность | **64-bit** (Build 19045, 10.0.19045) |
| Имя ПК | DESKTOP-56AKN6F |

### USB-подключение — **работает, принтер виден**

| Уровень | Имя | Status | Драйвер INF / класс |
|---------|-----|--------|---------------------|
| USB | Поддержка USB принтера | OK | `usbprint.inf`, сервис `usbprint` |
| USBPRINT | CanonLASER SHOT LBP-1120 | OK | **Универсальный принтер** (Microsoft), `CID_MS_GENERICPRINT` |

**Идентификация USB:**

- **VID:PID** — `04A9:262B` (Canon, Inc. — LaserShot LBP-1120)
- **Hardware ID:** `USB\VID_04A9&PID_262B&REV_0100`, `USB\VID_04A9&PID_262B`
- **USB class:** Printer (Class 07, SubClass 01, Prot 02)
- **Серийный суффикс в InstanceId:** `49IGRV` (регистр в pnputil: `49IGRv`)

**IEEE 1284 Device ID (из документации/Linux, типично для этого аппарата):**

```text
MFG:Canon;MDL:LASER SHOT LBP-1120;CMD:CAPT;VER:1.0;CLS:PRINTER;DES:Canon LASER SHOT LBP-1120
```

### Очереди печати Windows

В списке `Get-Printer` **нет** Canon LBP-1120 — только стандартные виртуальные принтеры (PDF, XPS, Fax, OneNote).  
**Вывод:** шина USB и generic USB Print Class подняты; **полноценного CAPT-драйвера и очереди печати нет** → печать с GDI/приложений сейчас недоступна.

---

## 2. Что за принтер и какой драйвер «официально» нужен

| Характеристика | Данные |
|----------------|--------|
| Модель | Canon Laser Shot **LBP-1120** |
| Тип | Ч/б лазер, ~10 стр/мин (A4) |
| Картридж | Canon **EP-22** (совместим с LBP810 и др.) |
| Макс. разрешение | **600 dpi** |
| Протокол | **CAPT v1.0** (не IPP, не чистый PCL/PostScript на USB) |
| Сжатие растра | **SCoA** (Smart Compression Architecture), построчное RLE + delta между строками |
| Год выпуска (ориентир) | ~2003–2004 |

### Canon Advanced Printing Technology (CAPT)

Windows-драйвер семейства **CAPT** — проприетарный стек Canon:

- Пользовательский UI / монитор (`captmon`, tray)
- Фильтры spooler (PostScript → CAPT raster, `pstocapt` / `captfilter` в Linux-аналогах)
- **32-bit** модули сжатия и протокола (`uictlcapt` и т.п. в PPD Canon)
- INF для установки, часто **`CAP3SETK.INF`** (Windows)

**Официальный последний пакет для Windows (Canon Europe):**

| Поле | Значение |
|------|----------|
| Название | Canon CAPT Printer Driver |
| Версия | **R1.10 V1.1** |
| Дата | 23 December 2009 (на сайте EU); в других регионах встречается **14 October 2014** в метаданных зеркал |
| Файл | `LBP-1120_R110_V110_Win_x32_EN_7.exe` (~1 MB) |
| Поддерживаемые ОС (реально в INF) | **Windows Vista / 7 — только 32-bit** |

**Linux (официально от Canon):**

- CAPT Printer Driver for Linux **V2.71** (32-bit, май 2017) — пакет `cndrvcups-capt`, GPL-части + бинарные фильтры.

### Критично для проекта x64

- Canon **не выпускал** нативный **64-bit** CAPT-драйвер для LBP-1120.
- При установке на x64 Windows типичная ошибка: *«The folder you specified doesn't contain a compatible software driver… designed to work with Windows for x64-based systems»* при выборе `CAP3SETK.INF`.
- Canon в FAQ указывал отсутствие планов поддержки LBP-1120 на **Windows 7 x64** (и аналогично для Win 10/11 x64).
- Обходные пути пользователей (не нативный драйвер): VM Win XP/7 x86 + USB passthrough, сетевой редирект, «Generic/Text Only» (только plain text — **не** полноценная печать).

**Исходники официального Windows-драйвера:** **не публикуются** Canon (закрытый проприетарный код).  
Частично открыты **Linux-обёртки** и **PPD** под GPL в пакете CUPS CAPT.

---

## 3. Архитектура протокола (для будущей реализации)

Источники: wiki [captdriver](https://github.com/mounaiban/captdriver/wiki/SPECS%3A-CAPT-Protocol-Executive-Summary), issue [#38](https://github.com/agalakhov/captdriver/issues/38) (разбор ответа `0xA1A1`), диссертационные материалы по reverse CAPT.

### Версии CAPT

| Версия | Примеры моделей | LBP-1120 |
|--------|-----------------|----------|
| **1.0** | LBP800, LBP810, **LBP1120**, LBP3200 | **Да** |
| 2.0+ | LBP5200, цвет, HiSCoA | Нет |
| 2.1 | LBP2900, LBP3000 | Нет |
| 3.x | LBP3010, LBP6000, … | Нет |

LBP-1120 — **ранняя модель**; управляющие команды **отличаются** от LBP2900/LBP3000 (см. комментарии maintainer `agalakhov/captdriver`: «quite different», нужен отдельный glue-код).

### Особенности LBP-1120 в ответе статуса (opcode `0xA1A1`)

Кратко (сравнение с LBP2900):

- Reply size: **20** байт (у LBP2900 — 56)
- CAPT Version ID: **0x0300** (v1-линейка)
- Product ID: **0x00DD** (221)
- Buffer size: **32767**, buffers: **16**
- Max speed в таблице для 1120 часто «—» (короткий ответ)

Пример дампа ответа (из issue):  
`A1 A1 14 00 00 03 DD 00 01 00 FF 7F 10 00 00 00 FF FF 01 00`

### Транспорт

- USB **bulk** transfers, двунаправленный обмен.
- Команды: little-endian, opcode + размер + payload.
- Страница: SCoA-поток команд (`CopyThenRepeat`, `CopyThenRaw`, …).

---

## 4. Открытый исходный код — что есть на GitHub / в сообществе

### Готовый драйвер под Windows x64

**Не найден.** Все значимые OSS-проекты — **Linux/CUPS** или библиотека протокола без Windows spooler integration.

### Linux / CUPS — релевантные репозитории

| Репозиторий | Лицензия | LBP-1120 | Зрелость | Комментарий |
|-------------|----------|----------|----------|-------------|
| **[darkvision77/captppd](https://github.com/darkvision77/captppd)** | BSD-2 | **Поддерживается** | Активный (2025+), тесты на железе | CUPS backend + libusb; PPD `LBP1120CAPTPPD.ppd`; **лучший текущий OSS для 1120** |
| **[darkvision77/libcapt](https://github.com/darkvision77/libcapt)** | BSD-2 | **Да** | Протокол + SCoA полностью RE | **MSVC 19.44 тестировался** — потенциальная база для Windows-порта |
| **[agalakhov/captdriver](https://github.com/agalakhov/captdriver)** | GPL-3 | **Нет** (issue #20) | Зрелый для LBP2900+ | Явно: для 1120 не написан glue-код управления |
| **[mounaiban/captdriver](https://github.com/mounaiban/captdriver)** | GPL-3 | Нет в списке | Alpha, новые CAPT | Не целевой для v1/1120 |
| **[caxapyk/capt_lbp810-1120](https://github.com/caxapyk/capt_lbp810-1120)** | — | LBP810/1120 | Старый форк Boichat | «Magic blob», без полного понимания протокола |
| **[Magister/cndrvcups-capt](https://github.com/Magister/cndrvcups-capt)** | GPL (части) | PPD **CNCUPSLBP1120CAPTK.ppd** | Зеркало Canon Linux | PPD + GPL обёртка; бинарный `captfilter` от Canon |
| Nicolas Boichat [capt](http://www.boichat.ch/nicolas/capt/) | — | Исторический | Устарел | Предшественник многих форков |

**Практический отзыв (2026):** пользователи подтверждают работу **captppd** на реальном LBP-1120 под Linux, в т.ч. возобновление печати после замены бумаги без перезапуска ccpd.

### Что можно «переиспользовать» для Windows x64 (идеи, не готовый продукт)

1. **libcapt** — протокол CAPT v1 + SCoA, CMake, unit-тесты, пример `printpbm` → USB (`/dev/usb/lp0` / libusb).
2. **captppd** — логика job handshake, cleaning, multi-page (ориентир для поведения).
3. **Canon Linux PPD** — размеры полей, margins (`*HWMargins: 11.34 17.01 11.34 14.17`), 600 dpi, `captmon`/`ccpdReady`.
4. **captdriver wiki SPECS** — документация по opcodes и версиям CAPT.

### Windows open source

Поиск не выявил maintained-проекта «LBP1120 Win10 x64 driver». Встречаются только SEO-гисты и советы установить x86-драйвер / VM.

---

## 5. Официальные ссылки Canon (драйверы и документация)

- [Canon Europe — Laser Shot LBP1120](https://www.canon-europe.com/support/consumer/products/printers/laser/lbp-series/laser-shot-lbp1120.html) — драйвер **R1.10 x32**
- [Canon Australia support](https://www.canon.com.au/laser-printers/laser-shot-lbp1120/support) — исторические версии R1.02 (Win98/Me/2000/XP), R1.10 (Vista/7), DEP module для XP SP2
- DEP-support module: **V1.01** (Data Execution Prevention на старых Windows)

**Доп. ПО (Windows, 32-bit era):**

- Модуль DEP для CAPT на XP SP2+
- Утилиты статуса/tray из пакета CAPT

---

## 6. Известные проблемы старого Canon CAPT (контекст для нового драйвера)

- Крэши **Print Spooler** / UMBus на некоторых конфигурациях (VirtualBox + XP workaround).
- Зависание задания при «out of paper» у **ccpd** (официальный Linux-стек); captppd это обходит.
- Баг в **оригинальном captfilter** при SCoA (`CopyThenRawLong` + смещение указателя) — задокументирован в libcapt README.

---

## 7. Выводы для следующего этапа (переписывание x64)

| Вопрос | Ответ |
|--------|--------|
| USB на ПК sabir | **OK**, `04A9:262B`, generic usbprint |
| Есть ли официальный x64? | **Нет** |
| Есть ли готовый OSS под Windows? | **Нет** |
| Есть ли качественный RE протокола для 1120? | **Да** — **libcapt** + **captppd** |
| Разумная стратегия | Порт/обёртка **libcapt** (C/C++, уже MSVC) + Windows print stack: пользовательский port monitor или virtual printer + отправка CAPT по USB (WinUSB/libusbK/IOCTL usbprint) |
| Альтернатива без своего драйвера | Linux-мини-ПК / Raspberry Pi с captppd + общий доступ по сети; не цель проекта, но plan B |

---

## 8. Рекомендуемые материалы для клонирования локально (следующий шаг)

```text
git clone https://github.com/darkvision77/libcapt.git
git clone https://github.com/darkvision77/captppd.git
git clone https://github.com/Magister/cndrvcups-capt.git   # PPD + GPL части
git clone https://github.com/mounaiban/captdriver.git       # wiki SPECS
```

Официальный Windows CAPT R1.10 x32 (для реверса бинарников при необходимости, только на изолированной x86 VM):

- `LBP-1120_R110_V110_Win_x32_EN_7.exe` с сайта Canon EU.

---

## 9. Статус репозитория «printer fix»

На момент отчёта папка проекта **пустая** (кроме этого файла). Исходный код драйвера **не создавался**.

---

*Отчёт подготовлен автоматически по результатам локальной диагностики Windows и обзора публичных источников.*
