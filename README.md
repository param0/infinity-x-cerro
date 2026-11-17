# Project Infinity X 17 для nubia Z60 Ultra (cerro) — неофициальная сборка

*[English version](README.en.md)*

Android 17 (SDK 37) на nubia Z60 Ultra / NX721J. Собрано из исходников
Project Infinity X ветки `17` на деревьях устройства от nukisystems и
Evolution-X-Devices.

Дерево устройства существовало, но под Android 17 не собиралось и не
работало. Здесь — скрипт сборки, тринадцать правок, которые понадобились,
и готовый пакет. Каждая правка найдена на живом устройстве: по логам,
дизассемблеру, дампам окон и скриншотам, а не подбором.

| | |
|---|---|
| Версия | `Project_Infinity-X-4.2-cerro-17.11.2026` |
| Android | 17, SDK 37, патч безопасности 2026-11-01 |
| Вариант | GAPPS, UNOFFICIAL, userdebug |
| Мейнтейнер | sasha_paramonov |

Сборка **неофициальная**, поддержки Project Infinity X не имеет. За
последствия установки отвечает тот, кто прошивает.

---

## Установка

### Что нужно заранее

* Разблокированный загрузчик.
* Recovery, умеющий `adb sideload` полного OTA-пакета: подойдут штатный
  recovery этой же прошивки, OrangeFox или TWRP под cerro.
* `adb` и `fastboot` на компьютере (`platform-tools` от Google).
* Заряд от 50%.

Пакет — **полный OTA** с `payload.bin`. Он ставится в неактивный слот и
**не трогает `/data`**: приложения, настройки и файлы остаются на месте.
Поэтому для обновления поверх предыдущей сборки вайп не нужен.

Вайп `/data` понадобится только в двух случаях: если вы приходите с другой
прошивки (не Infinity X) или если после установки система ведёт себя
странно — у чужой прошивки в `/data` остаются настройки, которые эта
система истолкует по-своему. Подробнее в разделе
[«Грязная прошивка»](#грязная-прошивка-чего-ждать).

### Шаг 1. Скачать и склеить

Пакет разрезан на две части: GitHub не принимает файлы больше 2 ГиБ.
Скачайте **обе** части и `SHA256SUMS` из
[релиза](../../releases/latest), положите рядом.

Linux / macOS:

```sh
cat Project_Infinity-X-4.2-cerro-17.11.2026-GAPPS-UNOFFICIAL.zip.part-* \
  > Project_Infinity-X-4.2-cerro-17.11.2026-GAPPS-UNOFFICIAL.zip
sha256sum -c SHA256SUMS
```

Windows (PowerShell):

```powershell
cmd /c copy /b Project_Infinity-X-4.2-cerro-17.11.2026-GAPPS-UNOFFICIAL.zip.part-00 ^
  + Project_Infinity-X-4.2-cerro-17.11.2026-GAPPS-UNOFFICIAL.zip.part-01 ^
  Project_Infinity-X-4.2-cerro-17.11.2026-GAPPS-UNOFFICIAL.zip
Get-FileHash Project_Infinity-X-4.2-cerro-17.11.2026-GAPPS-UNOFFICIAL.zip -Algorithm SHA256
```

Проверка суммы — не формальность: `adb sideload` на битом архиве выдаст
`E: footer is wrong` или оборвётся на 47%, и вы потеряете время, гадая,
дело в recovery или в файле.

Ожидаемая сумма:

```
7f84ca74b673aea0a78af3397eba0d46b8edef3c4f57b2867c7c4c9de3939f8f
```

### Шаг 2. Прошить

```sh
adb reboot sideload-auto-reboot
adb sideload Project_Infinity-X-4.2-cerro-17.11.2026-GAPPS-UNOFFICIAL.zip
```

Суффикс `-auto-reboot` важен: recovery сразу входит в режим приёма и сам
перезагружается после установки. Без него (`adb reboot sideload`) придётся
выходить из режима руками через меню.

Если телефон высадил в меню recovery, а не в sideload — выберите
**Apply update → Apply from ADB** и повторите вторую команду.

Установка идёт 3–6 минут. Прогресс в процентах показывает recovery;
`adb sideload` на 47% не завис — это нормальная пауза на распаковке
`payload.bin`.

### Шаг 3. Первая загрузка

Первый старт занимает 3–7 минут: система оптимизирует приложения. Если
прошиваете поверх другой прошивки, он может быть и дольше.

### Если нужен root

OTA перезаписывает `init_boot` в том слоте, куда ставится. Любой патч
KernelSU / ReSuKiSU / Magisk при обновлении слетает — это нормально.

Порядок такой: **сначала** прошить OTA и загрузиться, убедиться, что всё
работает, и **только потом** патчить `init_boot.img` **от этой же сборки**.
Образ лежит в релизе рядом с частями пакета.

```sh
adb reboot bootloader
fastboot flash init_boot init_boot_patched.img
fastboot reboot
```

Патч образа от другой сборки даст загрузку в петлю.

### Откат

Устройство A/B: предыдущая система остаётся в соседнем слоте, пока вы не
прошьёте что-то ещё. Вернуться можно из fastboot:

```sh
fastboot --set-active=other
fastboot reboot
```

Это работает ровно один раз и только до следующей установки OTA.

---

## Что работает

Всё основное: звонки и SIM, мобильный интернет, Wi-Fi, Bluetooth, NFC,
камеры, подэкранный сканер отпечатка, датчики, звук, Dolby Atmos,
жестовая навигация, Play-сервисы.

## Что не работает и чего нет

* **ViPER4Android** собрать невозможно: его нативная часть требует модуль
  `libviperaidl`, которого нет ни в одном публичном репозитории. Мёртвая
  ссылка на него убрана из конфигурации звуковых эффектов.
* **Сертификация Play** на свежей установке отсутствует, как у любой
  кастомной прошивки. Лечится штатной регистрацией устройства на
  `google.com/android/uncertified` — к сборке отношения не имеет.

---

## Что исправлено

Коротко — тринадцать правок. Первые пять нужны, чтобы сборка вообще
прошла; остальные чинят поведение уже работающей системы.

| # | Что было | Чем лечится |
|---|---|---|
| 1 | Дерево требует `NubiaParts`, которого нет ни в одном манифесте | проект добавлен в local manifest |
| 2 | Блобы codec2 выделяют 272 байта под класс, занимающий 288 → порча кучи | патч immediate у `movz` в трёх блобах |
| 3 | Новые публичные типы SELinux без compat-мэппинга → сборка падает | добавлен `202504.ignore.cil` |
| 4 | Treble labeling на A17: домен приложений объявлен в vendor-политике | домен перенесён в платформенную политику |
| 5 | Нет продукта `infinity_cerro` | генерируется из `lineage_cerro` |
| 6 | SystemUI умирал циклом при создании навигационной панели | повтор вместо фатального исключения |
| 7 | Часы статусбара не центрируются, иконки наезжают на них | часы вынесены в собственный контейнер |
| 8 | Поля «О телефоне» пустые | свойства перенесены в `product.prop` |
| 9 | Dolby Atmos не запускается | sepolicy + манифест VINTF + матрица совместимости |
| 10 | Нет чёрной точки под подэкранной фронталкой | реализована с нуля |
| 11 | `nubia_parts` не видит Trust-сервис | добавлено правило sepolicy |
| 12 | Подсистема Wi-Fi-геолокации пишет отладочный лог круглосуточно | уровень понижен до предупреждений |
| 13 | Конфиг звука ссылается на несуществующую библиотеку | ссылка убрана |

<details>
<summary><b>Подробно: почему каждая правка такая, а не другая</b></summary>

### 1. NubiaParts — обязательная зависимость

`device/nubia/sm8650-common/common.mk:409` подключает приложение жёстким
`inherit-product`, а не `inherit-product-if-exists`. В манифестах ни
Project Infinity X, ни Evolution X этого проекта нет, в
`lineage.dependencies` дерева он тоже не упомянут. Без него `lunch`
обрывается на `packages/apps/NubiaParts/config.mk does not exist`.

Берём `Evolution-X-Devices/packages_apps_NubiaParts` ветки `cnb`: у
nukisystems ветки под Android 17 нет вовсе.

### 2. ABI codec2: 272 → 288 байт

В дереве лежит ловушка мейнтейнера — `c2_store_abi_check` с
`static_assert(sizeof(ComponentStore) == 272)`. На Android 17 класс
вырос до **288**.

Поднять число в assert было нельзя. Блобы QTI зовут `operator new` с
размером, зашитым в их собственной сборке, а `ComponentStore`
виртуально наследует `RefBase` — счётчик ссылок лежит в хвосте объекта.
При выросшем классе запись в него уходит за границу выделенной памяти:
это порча кучи в сервисе codec2, то есть отвалившееся видео и падения
записи, а не честная ошибка сборки.

Настоящий размер снят компилятором, без сборки: взята готовая команда
clang из `out/siso_failed_commands.sh`, ей подсунут зонд с неопределённым
шаблоном — `ShowSize<sizeof(T)> x;` — и clang напечатал число в тексте
ошибки.

Патчится immediate у `movz w0` перед `bl operator new`:

```
mov w0, #264 = 00 21 80 52   (сток)
mov w0, #272 = 00 22 80 52   (патч дерева под Android 16)
mov w0, #288 = 00 24 80 52   (нужное)
```

В трёх файлах: `vendor.qti.media.c2@1.0-service`,
`vendor.qti.media.c2audio@1.0-service` и — отдельной находкой — в
`vendor.dolby.media.c2@1.0-service` из дерева Dolby, где лежал стоковый
вариант с 264. То же число правится в `extract-files.py`, чтобы
переизвлечение блобов с телефона давало правильный патч.

Не путать с `280` в `c2.dolby.store.so`: это размер их собственного
класса `DolbyC2Store`, видно по вызову конструктора сразу после
выделения. Его трогать нельзя.

### 3. Compat-мэппинг SELinux

NubiaParts объявляет в публичной политике свои типы `sysfs_fan` и
`sysfs_gamekey`. Каждый новый публичный тип обязан быть в compat-мэппинге
старшего API level, иначе `treble_sepolicy_tests` считает это поломкой
совместимости vendor-политики.

В дереве есть только `private/compat/202404/202404.ignore.cil` — под
Android 16. На Android 17 `PlatformSepolicyVersion = 202604`, старший
compat-уровень — **202504**, и файла под него нет.

### 4. Treble labeling

С `BOARD_API_LEVEL >= 202604` включается новая проверка: платформенные
приложения обязаны иметь `coredomain`-тип, а `coredomain` нельзя
объявлять в vendor-политике. Приложения NubiaParts ставятся в
`system_ext/priv-app`, то есть платформенные, а домен `nubia_parts`
дерево объявляет в `sepolicy/vendor`.

Разложено по образцу `system_app` из AOSP: тип в `public`, атрибуты и
правила в `private`, а в `vendor` остаётся только доступ к vendor-типам —
vendor-политика видит лишь публичные типы платформы.

Попутно убрано правило `sysfs_leds:file`: из `coredomain` туда нельзя
(neverallow в `coredomain.te`, исключения — только init, apexd, ueventd,
vold и system_app). Оно и не нужно — конкретные узлы переразмечены в
`genfs_contexts` в `sysfs_fan` и `sysfs_gamekey`.

### 6. SystemUI умирал при создании навигационной панели

В dropbox — 78 записей за секунду, в логе загрузки — 125 падений:

```
BadTokenException: Unable to add window -- another window of type 2019
                   already exists           (2019 = TYPE_NAVIGATION_BAR)
  at NavigationBar.onInit
  at NavigationBarControllerImpl.createNavigationBar
  at CommandQueueInitializer.start
```

Исключение уходило наверх и роняло `KeyguardService`, а с ним весь
SystemUI; тот перезапускался, снова натыкался на чужое окно и падал
опять. Отсюда долгая загрузка со сломанным интерфейсом — белое системное
меню питания рисует `system_server`, пока SystemUI мёртв, — и смерть при
любой правке настроек навигации.

Окно принадлежит **лончеру**: на телефоне в режиме жестов Launcher3
всегда создаёт `Taskbar` типа `TYPE_NAVIGATION_BAR`. Так задумано, и
SystemUI в этой схеме должен уступать окно, отдавая обязанности
`TaskbarDelegate`.

Сделано две вещи: проверка, что панель для дисплея уже создана, и —
главное — замена фатального исключения на ограниченный повтор. Чужое
окно исчезает, как только систему покидает его владелец.

> **Грабли на будущее.** Флаг `com.android.wm.shell.enable_taskbar_on_phones`
> выключать **нельзя**, как бы ни хотелось. Он и есть та самая передача
> обязанностей. Если его выключить, SystemUI полезет создавать своё окно и
> навигации не будет вовсе.

### 7. Часы статусбара по центру

При выборе центрального положения часы прижимались к левому краю, а
иконки уведомлений рисовались поверх цифр.

`@id/clock_center` лежал в `@id/centered_area` — горизонтальном
`LinearLayout` с `gravity="center"`, — а `StatusBarRoot.kt` добавляет в
этот же контейнер `ComposeView` для popup-чипов шириной `MATCH_PARENT`.
Ребёнок на всю ширину съедает свободное место, распределять под
`gravity` становится нечего.

Часы вынесены в собственный контейнер `@id/clock_center_area`;
`centered_area` оставлен на месте пустым — он нужен и `StatusBarRoot.kt`
(там `requireViewById`), и `PhoneStatusBarView`.

### 8. Свойства «О телефоне»

Дважды не сработало, прежде чем получилось.

Через `vendor.prop` — нельзя: свойства с vendor-партиции init выставляет
в контексте `vendor_init`, которому не разрешён тип `default_prop`, и они
молча остаются пустыми:

```
avc: denied { set } for property=ro.product.marketname
     scontext=u:r:vendor_init:s0 tcontext=u:object_r:default_prop:s0
```

Через `PRODUCT_PRODUCT_PROPERTIES` — тоже: это список make, он
разбивается по пробелам, и значения обрезались до первого слова
(`nubia` вместо `nubia Z60 Ultra`).

Работает файл `product.prop`: его строки попадают в
`product/etc/build.prop` как есть.

### 9. Dolby Atmos

Три слоя, и не хватало всех трёх.

**sepolicy.** Сервис `dms-hal-2-0` падал каждые 5 секунд с отказами на
`vendor_audio_prop` — это тип из QTI-политики, в дереве Dolby о нём не
знают. Закрывается одним `set_prop`.

**Объявление HAL в VINTF.** Дальше сервис выходил с кодом 1 уже молча:

```
hwservicemanager: getTransport: Cannot find entry
  vendor.dolby.hardware.dms@2.0::IDms/default
  in either framework or device VINTF manifest
```

Манифест кладётся туда, куда дерево устройства уже смотрит само —
`BoardConfigCommon.mk` содержит `-include hardware/dolby/configs/vintf/config.mk`,
а в ветке `cnb` этого каталога нет. Через `PRODUCT_COPY_FILES` положить
нельзя: сборка отвечает «VINTF metadata found in PRODUCT_COPY_FILES».

**Матрица совместимости.** Одного манифеста мало — `check_vintf` требует,
чтобы HAL был разрешён в матрице, иначе сборка падает на «instances are
in the device manifest but not specified in framework compatibility
matrix».

Побочный эффект починки виден в расходе батареи: пока сервис падал,
init каждые 5 секунд выставлял `sys.init.updatable_crashing=1` и запускал
`flags_health_check`, а приложение Dolby падало следом — в логе набегало
по три с половиной тысячи падений.

Выбор ветки `cnb`, а не `cnb-aidl`, не на вкус: манифест устройства
объявляет HIDL-аудио (`android.hardware.audio.effect @7.0::IEffectsFactory`),
и имена библиотек в `audio_effects.xml` — `libswdap.so`, `libdlbvol.so`,
`libswgamedap.so` — ровно из `cnb`; в `cnb-aidl` они называются иначе.

### 10. Чёрная точка под фронтальной камерой

У cerro фронтальная камера под матрицей. Пока над ней светятся пиксели,
сенсор снимает через них, и стоковая прошивка на время работы фронталки
гасит этот участок.

В дереве под это была оставлена **пустая заготовка**: `CameraHelper`
детектил фронтальную камеру в `onCameraAvailable`/`onCameraUnavailable`,
и обе ветки были пустые, а broadcast, который вообще включает callback,
никто не посылал.

Реализовано в `NubiaPartsHelper`: `Application` с `android:persistent`,
системное окно-оверлей с чёрным овалом. Три неочевидные детали:

* окно помечается `setTrustedOverlay()`, иначе точка выходит
  полупрозрачной — `TYPE_SYSTEM_OVERLAY` попадает под
  `isSystemAlertWindowType()`, и `DisplayPolicy` принудительно опускает
  alpha до `mMaximumObscuringOpacityForTouch` (0.8) у недоверенного окна
  с `FLAG_NOT_TOUCHABLE`. Одного `INTERNAL_SYSTEM_WINDOW` мало;
* решение о показе принимает единая функция, а не обработчик изменения
  дисплея: иначе смена частоты обновления посреди затухания возвращала
  точку в полную видимость, и она висела навсегда — ровно это случалось
  при записи кружков в мессенджере;
* поворот экрана пересчитывается в ту кромку, где физически оказалась
  камера.

Геометрия по умолчанию выверена на устройстве: 72 × 71 px, отступ 3
вправо и 18 вниз, анимация мягким масштабированием 260 мс. Всё правится
на лету, без пересборки:

```sh
adb shell settings put secure udc_dot_offset_y 20
adb shell settings put secure udc_dot_anim_ms 350
adb shell settings put secure udc_dot_enabled 0
```

### 12. Отладочный лог Wi-Fi-геолокации

`lowi.conf` приезжает со стока с `LOWI_LOG_LEVEL = 4` — это `EL_DEBUG` по
легенде в самом файле. В релизной прошивке подсистема круглосуточно пишет
отладочный поток: 2624 строки за одно окно лога, то есть работа
процессора и записи logd без всякой пользы. Поставлено 2 —
предупреждения и ошибки остаются.

Для сравнения: `DEBUG_LEVEL` в `gps.conf` уже минимальный, там крутить
нечего, а у драйвера wlan конфига с уровнем логирования в блобах нет, и
гадать не стали.

</details>

---

## Грязная прошивка: чего ждать

Если вы ставите эту сборку поверх другой прошивки Android 17 без вайпа,
часть «багов» будет не от неё. В `/data` живут настройки, которые новая
система читает по-своему. Проверено на практике:

| Симптом | Причина | Лечение без перепрошивки |
|---|---|---|
| Нет навигации и жеста «назад» совсем | `force_show_navbar` = 0 от прошлой ROM | `content insert --uri content://lineagesettings/system --bind name:s:force_show_navbar --bind value:s:1` и перезагрузка |
| Жест «назад» пропал, остальное работает | включён таскбар | выключить таскбар в настройках навигации |
| Приложение падает каждые 10 секунд | остаток прошлой ROM в `/data/app` | удалить его |
| Странная тема, не те иконки | `theme_customization_overlay_packages` ссылается на несуществующие оверлеи | очистить значение |

`force_show_navbar` читает `DisplayPolicy.updateSettings()`, и значение
живёт в `/data` — перезапуска SystemUI мало, нужна перезагрузка.

---

## Деревья и ревизии

Ревизии, на которых собран этот релиз:

| проект | путь | ветка | коммит |
|---|---|---|---|
| [`manifest`](https://github.com/ProjectInfinity-X/manifest) | `.repo/manifests` | [`17`](https://github.com/ProjectInfinity-X/manifest/tree/17) | [`657f87c`](https://github.com/ProjectInfinity-X/manifest/commit/657f87c) |
| [`android_device_nubia_cerro`](https://github.com/nukisystems/android_device_nubia_cerro) | `device/nubia/cerro` | [`cnb`](https://github.com/nukisystems/android_device_nubia_cerro/tree/cnb) | [`a6f0c88`](https://github.com/nukisystems/android_device_nubia_cerro/commit/a6f0c88) |
| [`android_device_nubia_sm8650-common`](https://github.com/nukisystems/android_device_nubia_sm8650-common) | `device/nubia/sm8650-common` | [`cnb`](https://github.com/nukisystems/android_device_nubia_sm8650-common/tree/cnb) | [`011ffef`](https://github.com/nukisystems/android_device_nubia_sm8650-common/commit/011ffef) |
| [`proprietary_vendor_nubia_cerro`](https://gitlab.com/nukisystems/proprietary_vendor_nubia_cerro) | `vendor/nubia/cerro` | [`cnb`](https://gitlab.com/nukisystems/proprietary_vendor_nubia_cerro/-/tree/cnb) | [`c28dcb4`](https://gitlab.com/nukisystems/proprietary_vendor_nubia_cerro/-/commit/c28dcb4) |
| [`proprietary_vendor_nubia_sm8650-common`](https://gitlab.com/nukisystems/proprietary_vendor_nubia_sm8650-common) | `vendor/nubia/sm8650-common` | [`cnb`](https://gitlab.com/nukisystems/proprietary_vendor_nubia_sm8650-common/-/tree/cnb) | [`9bc8a04`](https://gitlab.com/nukisystems/proprietary_vendor_nubia_sm8650-common/-/commit/9bc8a04) |
| [`packages_apps_NubiaParts`](https://github.com/Evolution-X-Devices/packages_apps_NubiaParts) | `packages/apps/NubiaParts` | [`cnb`](https://github.com/Evolution-X-Devices/packages_apps_NubiaParts/tree/cnb) | [`09b3a58`](https://github.com/Evolution-X-Devices/packages_apps_NubiaParts/commit/09b3a58) |
| [`hardware_dolby`](https://github.com/Evolution-X-Devices/hardware_dolby) | `hardware/dolby` | [`cnb`](https://github.com/Evolution-X-Devices/hardware_dolby/tree/cnb) | [`8b67465`](https://github.com/Evolution-X-Devices/hardware_dolby/commit/8b67465) |
| [`kernel_nubia_sm8650`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650) | `kernel/nubia/sm8650` | [`cnb`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650/tree/cnb) | [`ce0a3f0`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650/commit/ce0a3f0) |
| [`kernel_nubia_sm8650-devicetrees`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650-devicetrees) | `kernel/nubia/sm8650-devicetrees` | [`cnb`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650-devicetrees/tree/cnb) | [`2047747`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650-devicetrees/commit/2047747) |
| [`kernel_nubia_sm8650-modules`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650-modules) | `kernel/nubia/sm8650-modules` | [`cnb`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650-modules/tree/cnb) | [`4efca25`](https://github.com/Evolution-X-Devices/kernel_nubia_sm8650-modules/commit/4efca25) |

Ветка `cnb` — это Cinnamon Bun, кодовое имя Android 17. Для Android 16
соответствующая ветка называется `bka` (Baklava).

---

## Патчи

В каталоге `patches/` лежат готовые диффы против указанных выше коммитов.

| файл | дерево | что внутри |
|---|---|---|
| `0001-device_nubia_cerro.patch` | `device/nubia/cerro` | продукт `infinity_cerro`, `product.prop` со свойствами «О телефоне», подключение product.prop в BoardConfig |
| `0002-device_nubia_sm8650-common.patch` | `device/nubia/sm8650-common` | размер `ComponentStore` в обеих ABI-проверках и в `extract-files.py`, резервные размеры разделов, мёртвая ссылка на ViPER |
| `0003-packages_apps_NubiaParts.patch` | `packages/apps/NubiaParts` | перенос домена в платформенную политику, compat-мэппинг 202504, доступ к Trust-сервису, чёрная точка UDC целиком |
| `0004-hardware_dolby.patch` | `hardware/dolby` | sepolicy на `vendor_audio_prop`, манифест VINTF и матрица совместимости |
| `0005-frameworks_base_SystemUI.patch` | `frameworks/base` | повтор вместо падения при создании навигационной панели, контейнер центральных часов |
| `0006-proprietary_vendor_nubia_sm8650-common.patch` | `vendor/nubia/sm8650-common` | уровень лога LOWI |

Применяются из корня соответствующего дерева:

```sh
cd device/nubia/cerro && git apply /путь/к/patches/0001-device_nubia_cerro.patch
```

**Патч блобов codec2 в диффы не входит.** Это изменение четырёх байт в
трёх проприетарных исполняемых файлах, и выкладывать их здесь было бы
перераспространением чужих бинарников. Скрипт сборки делает это сам,
идемпотентно: ищет `movz w0` со стоковым или промежуточным значением и
ставит 288. Код — шаг 5 в `build-infinity-cerro.sh`.

---

## Сборка из исходников

```sh
bash build-infinity-cerro.sh
```

Скрипт делает всё сам: `repo init`/`sync` ветки `17`, создаёт
`.repo/local_manifests/cerro.xml` с деревьями из таблицы выше, применяет
все тринадцать правок **идемпотентно** и собирает `m bacon`.

Полезные переопределения:

```sh
NO_SYNC=1    bash build-infinity-cerro.sh   # пересборка без синка
SYNC_ONLY=1  bash build-infinity-cerro.sh   # только исходники
WITH_GAPPS=false bash build-infinity-cerro.sh
VARIANT=user bash build-infinity-cerro.sh
BUILD_THREADS=8 bash build-infinity-cerro.sh
```

Требуется примерно 300 ГБ свободного места (исходники ~145 ГБ, `out/`
~155 ГБ) и distrobox-контейнер с именем `rom` — скрипт заходит в него
сам и держит `systemd-inhibit`, чтобы машина не уснула.

Каждая правка в скрипте снабжена комментарием с причиной: что именно
ломалось, какое сообщение выдавала сборка или устройство и почему
выбрано такое решение. Патчи из `patches/` делают то же самое, но их
удобнее читать и ревьюить.

---

## Лицензии

Скрипт сборки и код чёрной точки (`UdcDot.java`) — Apache-2.0.

Деревья устройства, ядро, `hardware/dolby` и vendor-блобы принадлежат их
авторам (nukisystems, Evolution-X-Devices, Qualcomm, nubia) и здесь не
дублируются — в таблице выше указаны точные ревизии.
