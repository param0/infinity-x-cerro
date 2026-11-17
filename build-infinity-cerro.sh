#!/bin/bash
# Project Infinity X 17 (Android 17) для Nubia Z60 Ultra (NX721J / cerro)
#
# Запуск с хоста:  bash ~/build-infinity-cerro.sh
# Скрипт сам зайдёт в distrobox-контейнер "rom" и продолжит уже внутри него.
#
#   Синк   -> 3 потока  (медленно, но переживает обрывы; есть авто-ретраи)
#   Сборка -> 16 потоков
#
# Что и откуда берётся:
#   * PIX: манифест ProjectInfinity-X/manifest ветка 17. База — lineage-24.0
#     (в default.xml так и записано), то есть деревья lineage-стиля подходят.
#   * Деревья устройства: nukisystems, ветка cnb. Имена веток у EvoX и
#     nukisystems идут по кодовым именам AOSP: bka = Baklava (Android 16),
#     cnb = Cinnamon Bun (Android 17). На cnb лежат блобы нового стока
#     NebulaAIOS2.0.3_NX721J — та самая "версия 2.0".
#   * Блобы живут на GitLab (у nukisystems на GitHub их веток cnb нет),
#     ядро — у Evolution-X-Devices. Так прописано в evolution.dependencies
#     общего дерева, оттуда и взято.
#
# Полезные переопределения:
#   NO_SYNC=1    bash ~/build-infinity-cerro.sh   # пропустить синк, сразу собирать
#   SYNC_ONLY=1  bash ~/build-infinity-cerro.sh   # только исходники
#   WIPE_OUT=1   bash ~/build-infinity-cerro.sh   # снести out/
#   SYNC_THREADS=1 ...                            # если плохой канал
#   BUILD_THREADS=8 ...                           # если мало памяти
#   WITH_GAPPS=false ...                          # собрать без GApps
#   VARIANT=user ...                              # по умолчанию userdebug

if [ -z "$CONTAINER_ID" ]; then
    SELF="$(readlink -f "$0")"
    if [ "${KEEP_AWAKE:-1}" = "1" ] && command -v systemd-inhibit >/dev/null; then
        echo "== Сон и автоблокировка заблокированы на время сборки =="
        exec systemd-inhibit \
            --what=idle:sleep:handle-lid-switch \
            --who="Infinity X build" \
            --why="Идёт сборка Project Infinity X для cerro" \
            --mode=block \
            distrobox enter rom -- bash "$SELF" "$@"
    fi
    exec distrobox enter rom -- bash "$SELF" "$@"
fi

set -e

# ==========================================
WORK_DIR="${WORK_DIR:-$HOME/infinity}"

MANIFEST_URL="https://github.com/ProjectInfinity-X/manifest"
MANIFEST_BRANCH="17"                 # Project Infinity X v4.x, база lineage-24.0
MANIFEST_GROUPS="default,-mips,-darwin,-notdefault"

DEVICE="cerro"                       # Nubia Z60 Ultra, NX721J
PRODUCT="infinity_$DEVICE"
VARIANT="${VARIANT:-userdebug}"
TREE_BRANCH="cnb"                    # Android 17 (Cinnamon Bun) у nukisystems/EvoX

MAINTAINER="sasha_paramonov"
WITH_GAPPS="${WITH_GAPPS:-true}"

# About phone в интерфейсе PIX
MARKETNAME="nubia Z60 Ultra"
SOC="Snapdragon 8 Gen 3"
CAMERA="50MP + 50MP + 64MP"

SYNC_THREADS="${SYNC_THREADS:-3}"
BUILD_THREADS="${BUILD_THREADS:-16}"
SYNC_RETRIES="${SYNC_RETRIES:-8}"

NO_SYNC="${NO_SYNC:-0}"
SYNC_ONLY="${SYNC_ONLY:-0}"
WIPE_OUT="${WIPE_OUT:-auto}"
USE_CCACHE_BUILD="true"
CCACHE_SIZE="${CCACHE_SIZE:-50G}"

# 31 ГБ RAM на 16 потоков — впритык, ограничиваем тяжёлые по памяти шаги
HIGHMEM_JOBS="${HIGHMEM_JOBS:-4}"

# Полная прошивка куда прожорливее recovery: исходники ~120 ГБ + out ~150 ГБ
# Порог свободного места. Полный прогон тянет исходники (~145 ГБ) и
# раскладывает out/ (~155 ГБ) с нуля; при NO_SYNC=1 и то и другое уже на диске,
# и дописывается только упаковка (target_files, образы, OTA-zip) — отдельный,
# куда меньший порог, иначе проверка впустую блокирует доработку сборки.
if [ "$NO_SYNC" = "1" ]; then
    NEED_FREE_GB="${NEED_FREE_GB:-60}"
else
    NEED_FREE_GB="${NEED_FREE_GB:-280}"
fi
# ==========================================

export PATH="$HOME/.local/bin:$PATH"
LOG_DIR="$WORK_DIR/logs"
DT="device/nubia/$DEVICE"

echo "=============================================="
echo " Project Infinity X $MANIFEST_BRANCH (Android 17) -> $DEVICE"
echo " продукт: $PRODUCT-$VARIANT   деревья: $TREE_BRANCH"
echo " sync: -j$SYNC_THREADS   build: -j$BUILD_THREADS"
echo "=============================================="

command -v repo >/dev/null || { echo "!! repo не найден в PATH ($PATH)"; exit 1; }

mkdir -p "$WORK_DIR" "$LOG_DIR" && cd "$WORK_DIR"

free_gb=$(df -BG --output=avail . | tail -1 | tr -dc '0-9')
echo "== Свободно: ${free_gb} ГБ (нужно >= ${NEED_FREE_GB}) =="
if [ "$free_gb" -lt "$NEED_FREE_GB" ]; then
    echo "!! Места не хватит: исходники ~145 ГБ + out/ ~155 ГБ."
    echo "   Освободи место (например, снеси ~/aera — recovery уже выпущен"
    echo "   и пересобирается скриптом ~/build-aera-cerro.sh) либо запусти"
    echo "   с NEED_FREE_GB=$free_gb, если уверен."
    if [ "$NEED_FREE_GB" != "$free_gb" ]; then
        exit 1
    fi
fi

if [ "$NO_SYNC" != "1" ]; then

echo "== repo init -b $MANIFEST_BRANCH =="
repo init --depth=1 --no-repo-verify --git-lfs \
    -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" -g "$MANIFEST_GROUPS"

# ------------------------------------------------------------------
# Деревья устройства. В манифест PIX они не входят, roomservice тут не
# поможет: ветка cnb не совпадает с именем ветки ROM, блобы лежат на
# GitLab, а ядро — в организации Evolution-X-Devices. Прописываем явно.
# ------------------------------------------------------------------
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/cerro.xml <<MANIFEST
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="nuki"   fetch="https://github.com/nukisystems" />
  <remote name="nukigl" fetch="https://gitlab.com/nukisystems" />
  <remote name="evox"   fetch="https://github.com/Evolution-X-Devices" />

  <project path="device/nubia/$DEVICE"            name="android_device_nubia_$DEVICE"            remote="nuki"   revision="$TREE_BRANCH" />
  <project path="device/nubia/sm8650-common"      name="android_device_nubia_sm8650-common"      remote="nuki"   revision="$TREE_BRANCH" />

  <project path="vendor/nubia/$DEVICE"            name="proprietary_vendor_nubia_$DEVICE"        remote="nukigl" revision="$TREE_BRANCH" />
  <project path="vendor/nubia/sm8650-common"      name="proprietary_vendor_nubia_sm8650-common"  remote="nukigl" revision="$TREE_BRANCH" />

  <!-- NubiaParts подключён в common.mk жёстко (inherit-product), без него
       не проходит даже lunch. У nukisystems ветки cnb нет, актуальная —
       у Evolution-X-Devices. ViPER и hardware/dolby подключены мягко
       (inherit-product-if-exists) и НЕ добавлены: ViPER тянет модуль
       libviperaidl, которого нет ни в одном публичном репозитории
       (kati падает с "libv4a_re requires non-existent TARGET module"),
       а у dolby четыре cnb-варианта и неясно, какой берёт мейнтейнер. -->
  <project path="packages/apps/NubiaParts"        name="packages_apps_NubiaParts"                remote="evox"   revision="$TREE_BRANCH" />

  <!-- Dolby Atmos. Ветка cnb, а не cnb-aidl: аудио у устройства HIDL
       (manifest.xml объявляет android.hardware.audio.effect @7.0::IEffectsFactory),
       и имена библиотек в device/nubia/sm8650-common/audio/audio_effects.xml
       (libswdap.so, libdlbvol.so, libswgamedap.so) — ровно из cnb; в cnb-aidl
       они называются libswdapaidl.so и т.д. Дерево подключает Dolby само:
       common.mk делает inherit-product-if-exists hardware/dolby/dolby.mk,
       поэтому достаточно наличия каталога. Чтобы отключить — убрать проект
       отсюда и удалить hardware/dolby. -->
  <project path="hardware/dolby"                  name="hardware_dolby"                          remote="evox"   revision="cnb" />

  <project path="kernel/nubia/sm8650"             name="kernel_nubia_sm8650"                     remote="evox"   revision="$TREE_BRANCH" />
  <project path="kernel/nubia/sm8650-devicetrees" name="kernel_nubia_sm8650-devicetrees"         remote="evox"   revision="$TREE_BRANCH" />
  <project path="kernel/nubia/sm8650-modules"     name="kernel_nubia_sm8650-modules"             remote="evox"   revision="$TREE_BRANCH" />
</manifest>
MANIFEST

echo "== repo sync -j$SYNC_THREADS (до $SYNC_RETRIES попыток) =="
SYNC_CMD="repo sync -c -j$SYNC_THREADS --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync"
sync_ok=0
for attempt in $(seq 1 "$SYNC_RETRIES"); do
    echo "---- sync: попытка $attempt/$SYNC_RETRIES ----"
    # через script(1): repo рисует прогресс только когда видит tty
    if command -v script >/dev/null; then
        script -q -e -a "$LOG_DIR/sync.log" -c "$SYNC_CMD"
    else
        $SYNC_CMD 2>&1 | tee -a "$LOG_DIR/sync.log"
    fi
    if [ $? -eq 0 ]; then sync_ok=1; break; fi
    echo "---- обрыв, пауза 20с перед повтором ----"
    sleep 20
done

if [ "$sync_ok" != "1" ]; then
    echo
    echo "!! repo sync не завершился за $SYNC_RETRIES попыток (лог: $LOG_DIR/sync.log)."
    echo "   Включи VPN и перезапусти — докачает только недостающее."
    exit 1
fi
echo "== repo sync завершён =="

fi # NO_SYNC

[ -d "$WORK_DIR/$DT" ] || { echo "!! нет $DT — деревья не синкнулись"; exit 1; }

# ------------------------------------------------------------------
# Правки дерева под PIX. Идемпотентны: применяются при каждом запуске,
# чтобы не терялись после re-sync и правок самого скрипта.
#
# Дерево nukisystems рассчитано на LineageOS/EvoX, у PIX вместо
# vendor/lineage свой vendor/infinity с теми же именами конфигов.
# ------------------------------------------------------------------
echo "== Готовлю дерево под Project Infinity X =="

# 1) продукт infinity_cerro: копия lineage_cerro с подменой vendor-конфига
sed -e 's|vendor/lineage/config/|vendor/infinity/config/|g' \
    -e "s|^PRODUCT_NAME := lineage_$DEVICE$|PRODUCT_NAME := $PRODUCT|" \
    "$DT/lineage_$DEVICE.mk" > "$DT/$PRODUCT.mk"

cat >> "$DT/$PRODUCT.mk" <<PIXFLAGS

# --- флаги Project Infinity X (добавлено build-infinity-cerro.sh)
INFINITY_MAINTAINER := "$MAINTAINER"
WITH_GAPPS := $WITH_GAPPS
# TARGET_HAS_UDFPS уже выставлен в device/nubia/sm8650-common/common.mk

# About phone — в $DT/product.prop, см. шаг 3.
PIXFLAGS

grep -q "^PRODUCT_NAME := $PRODUCT$" "$DT/$PRODUCT.mk" || {
    echo "!! в $DT/lineage_$DEVICE.mk не нашлось PRODUCT_NAME := lineage_$DEVICE"
    grep -n 'PRODUCT_NAME' "$DT/lineage_$DEVICE.mk"; exit 1; }

# 2) продукт в AndroidProducts.mk + выбор в lunch
if ! grep -q "$PRODUCT.mk" "$DT/AndroidProducts.mk"; then
    sed -i "s|\(.*\)lineage_$DEVICE.mk|\1lineage_$DEVICE.mk \\\\\n    \$(LOCAL_DIR)/$PRODUCT.mk|" \
        "$DT/AndroidProducts.mk"
fi
grep -q "COMMON_LUNCH_CHOICES" "$DT/AndroidProducts.mk" || \
    echo "COMMON_LUNCH_CHOICES := $PRODUCT-$VARIANT" >> "$DT/AndroidProducts.mk"

# 3) About phone: PIX читает эти свойства в разделе "О телефоне".
#    Дважды проверено на устройстве, чем это НЕ делается:
#    - vendor.prop: свойства с vendor-партиции init выставляет в контексте
#      vendor_init, которому не разрешён тип default_prop, и они молча пустые
#      (avc: denied { set } for property=ro.product.marketname ... vendor_init);
#    - PRODUCT_PRODUCT_PROPERTIES: это список make, он разбивается по пробелам,
#      и значения обрезаются до первого слова ("nubia" вместо "nubia Z60 Ultra").
#    Работает файл product.prop: его строки попадают в product/etc/build.prop
#    как есть. Дерево уже подключает общий $COMMON/product.prop, а device-файл
#    при этом не подхватывается автоматически (build/make/core/config.mk берёт
#    $(TARGET_DEVICE_DIR)/product.prop только если переменная пустая), поэтому
#    добавляем его в TARGET_PRODUCT_PROP сами.
cat > "$DT/product.prop" <<PRODUCTPROP
# About phone (читает Project Infinity X), добавлено build-infinity-cerro.sh
ro.product.marketname=$MARKETNAME
ro.infinity.soc=$SOC
ro.infinity.camera=$CAMERA
PRODUCTPROP
grep -q 'TARGET_PRODUCT_PROP += $(DEVICE_PATH)/product.prop' "$DT/BoardConfig.mk" || \
    sed -i 's|^TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop$|&\nTARGET_PRODUCT_PROP += $(DEVICE_PATH)/product.prop|' \
        "$DT/BoardConfig.mk"
# и убираем прежнюю (неработавшую) версию из vendor.prop
sed -i -E '/^(ro\.product\.marketname|ro\.infinity\.soc|ro\.infinity\.camera)=/d' \
    "$DT/vendor.prop"

# 4) резервные размеры разделов: в общем дереве подключается lineage-вариант,
#    у PIX тот же файл лежит в vendor/infinity. Строка с -include не обязательная,
#    без неё размеры образов считаются без запаса.
CDT="device/nubia/sm8650-common"
CBC="$CDT/BoardConfigCommon.mk"
if ! grep -q 'vendor/infinity/config/BoardConfigReservedSize.mk' "$CBC"; then
    sed -i 's|-include vendor/lineage/config/BoardConfigReservedSize.mk|&\n-include vendor/infinity/config/BoardConfigReservedSize.mk|' "$CBC"
fi

# 5) ABI-страховка QTI codec2: в дереве лежит static_assert на
#    sizeof(ComponentStore) и сверху пропатчены два vendor-блоба.
#    Блобы вызывают operator new с размером, зашитым в их собственной
#    сборке; ComponentStore виртуально наследует RefBase, поэтому mRefs
#    лежит в хвосте объекта, и при росте класса запись в mRefs уходит
#    за пределы выделенной блобом памяти (порча хипа в codec2-сервисе).
#    На A16 размер был 272, на A17 (lineage-24.0) стал 288, поэтому
#    правим и assert, и immediate у movz w0 перед bl operator new:
#      movz w0, #272 = 00 22 80 52   ->   movz w0, #288 = 00 24 80 52
#    Размер перепроверяется компилятором: если AOSP снова поменяет
#    класс, assert упадёт, и число надо пересчитать (см. README).
C2_SIZE=288
sed -i "s/ComponentStore) == [0-9]\+,/ComponentStore) == $C2_SIZE,/" \
    "$CDT/c2_store_abi_check/abi_check_1_0.cpp" \
    "$CDT/c2_store_abi_check/abi_check_1_2.cpp"
sed -i "s|\(\.binary_regex_replace(b'\\\\x00\\\\x21\\\\x80\\\\x52', b'\\\\x00\\\\x\)[0-9a-f]\{2\}\(\\\\x80\\\\x52')\)|\1""24""\2|" \
    "$CDT/extract-files.py"
for f in "$WORK_DIR/vendor/nubia/sm8650-common/proprietary/vendor/bin/hw/vendor.qti.media.c2@1.0-service" \
         "$WORK_DIR/vendor/nubia/sm8650-common/proprietary/vendor/bin/hw/vendor.qti.media.c2audio@1.0-service"; do
    [ -f "$f" ] || { echo "!! нет блоба $f"; exit 1; }
    python3 - "$f" <<'C2PY'
import sys
f = sys.argv[1]
d = open(f, 'rb').read()
want = b'\x00\x24\x80\x52'          # movz w0, #288
if d.count(want) == 1:
    sys.exit(0)                      # уже пропатчен
for old in (b'\x00\x22\x80\x52',     # movz w0, #272 (патч под A16)
            b'\x00\x21\x80\x52'):    # movz w0, #264 (сток)
    if d.count(old) == 1:
        open(f, 'wb').write(d.replace(old, want))
        print('   пропатчен', f.rsplit('/', 1)[1])
        sys.exit(0)
sys.exit('!! в %s не нашёлся ожидаемый movz w0, #размер' % f)
C2PY
done

#    Та же мина в блобе Dolby, если он подключён (шаг 11): его codec2-сервис
#    тоже конструирует V1_0::utils::ComponentStore после operator new, и в
#    репозитории лежит стоковый вариант с 264. Проверено дизассемблером:
#      mov w0, #264; bl operator new; bl android::GetCodec2DolbyComponentStore();
#      bl ...V1_0::utils::ComponentStore::ComponentStore(...)
#    Файл необязательный — если hardware/dolby не синкнут, просто пропускаем.
DOLBY_C2="$WORK_DIR/hardware/dolby/proprietary/vendor/bin/hw/vendor.dolby.media.c2@1.0-service"
if [ -f "$DOLBY_C2" ]; then
    python3 - "$DOLBY_C2" <<'C2PY'
import sys
f = sys.argv[1]
d = open(f, 'rb').read()
want = b'\x00\x24\x80\x52'          # movz w0, #288
if d.count(want) == 1:
    sys.exit(0)
for old in (b'\x00\x22\x80\x52',     # movz w0, #272
            b'\x00\x21\x80\x52'):    # movz w0, #264 (как лежит в репозитории)
    if d.count(old) == 1:
        open(f, 'wb').write(d.replace(old, want))
        print('   пропатчен', f.rsplit('/', 1)[1])
        sys.exit(0)
sys.exit('!! в %s не нашёлся ожидаемый movz w0, #размер' % f)
C2PY
fi

# 6) sepolicy-совместимость NubiaParts. Дерево добавляет в публичную
#    политику свои типы (sysfs_fan, sysfs_gamekey через
#    packages/apps/NubiaParts/sepolicy/public/file.te), а каждый новый
#    публичный тип обязан быть перечислен в compat-мэппинге самого свежего
#    API level, иначе treble_sepolicy_tests падает с «public types were
#    found added to the policy without an entry into the compatibility
#    mapping file(s)». В NubiaParts есть только compat/202404 (A16),
#    а на A17 PLATFORM_SEPOLICY_VERSION = 202604 и старший compat-уровень
#    стал 202504 — дописываем такой же ignore.cil для него.
#    Актуальные значения смотреть в out/soong/soong.$PRODUCT.variables:
#    PlatformSepolicyVersion и PlatformSepolicyCompatVersions (последний
#    элемент списка и есть нужный уровень).
NP_COMPAT="packages/apps/NubiaParts/sepolicy/private/compat"
if [ -f "$WORK_DIR/$NP_COMPAT/202404/202404.ignore.cil" ] && \
   [ ! -f "$WORK_DIR/$NP_COMPAT/202504/202504.ignore.cil" ]; then
    mkdir -p "$WORK_DIR/$NP_COMPAT/202504"
    sed 's/202404/202504/g' "$WORK_DIR/$NP_COMPAT/202404/202404.ignore.cil" \
        > "$WORK_DIR/$NP_COMPAT/202504/202504.ignore.cil"
    echo "   добавлен $NP_COMPAT/202504/202504.ignore.cil"
fi

# 7) treble labeling: домен nubia_parts переносится в платформенную политику.
#    Приложения NubiaParts (включая NubiaGameSwitch) ставятся в
#    system_ext/priv-app, то есть платформенные, а домен nubia_parts дерево
#    объявляет в vendor-политике. С BOARD_API_LEVEL >= 202604 (A17) включился
#    treble_labeling_tests, который требует: платформенные приложения помечены
#    coredomain-типом, и coredomain нельзя объявлять в vendor-политике
#    (см. system/sepolicy/tests/treble_labeling_tests.md). Поэтому раскладываем
#    как system_app в AOSP: тип в public, атрибуты и правила в private, а в
#    vendor остаётся только доступ к vendor-типам — vendor-политика видит
#    публичные типы платформы, поэтому тип и объявлен в public, а не в private.
#    Новый публичный тип обязан попасть в compat-мэппинг (см. шаг 6).
NPS="$WORK_DIR/packages/apps/NubiaParts/sepolicy"
mkdir -p "$NPS/public" "$NPS/private"
cat > "$NPS/public/nubia_parts.te" <<'NPPUB'
# Домен приложений NubiaParts. Объявлен в public, потому что правила на
# vendor-типы (vendor_sysfs_battery_supply) остаются в vendor-политике,
# а она видит только публичные типы платформы.
# Атрибуты и сами правила — в private/nubia_parts.te (как system_app в AOSP).
type nubia_parts, domain;
NPPUB

cat > "$NPS/private/nubia_parts.te" <<'NPPRIV'
# NubiaParts и его спутники (NubiaGameSwitch, NubiaPowerUtils, ...) ставятся
# в system_ext/priv-app, то есть это платформенные приложения. С
# BOARD_API_LEVEL >= 202604 treble_labeling_tests требует, чтобы такие
# приложения были помечены coredomain-типом, а coredomain нельзя объявлять
# в vendor-политике. Поэтому домен живёт здесь, на стороне платформы.
typeattribute nubia_parts coredomain, mlstrustedsubject;

app_domain(nubia_parts)

allow nubia_parts {
  activity_service
  activity_task_service
  audio_service
  audioserver_service
  autofill_service
  batteryproperties_service
  batterystats_service
  content_capture_service
  game_service
  gpu_service
  hint_service
  media_session_service
  netstats_service
  sensorservice_service
  surfaceflinger_service
  trust_service
  voiceinteraction_service
  vibrator_manager_service
}:service_manager find;

allow nubia_parts system_app_data_file:dir create_dir_perms;
allow nubia_parts system_app_data_file:{
  file
  lnk_file
} create_file_perms;

# sysfs_leds:file запрещён neverallow'ом в system/sepolicy/private/coredomain.te
# (full_treble_only, из coredomain туда можно только init/apexd/ueventd/vold/
# system_app). И не нужен: конкретные узлы переразмечены в
# sepolicy/vendor/genfs_contexts — /class/leds/fan -> sysfs_fan,
# /class/leds/sar (включая sar0/sar1) -> sysfs_gamekey. От sysfs_leds нужен
# только обход каталога /sys/class/leds и чтение симлинков в нём; на dir и
# lnk_file neverallow не распространяется.
allow nubia_parts sysfs_leds:dir r_dir_perms;
allow nubia_parts sysfs_leds:lnk_file r_file_perms;

allow nubia_parts sysfs_fan:dir r_dir_perms;
allow nubia_parts sysfs_fan:{ file lnk_file } rw_file_perms;

allow nubia_parts sysfs_gamekey:dir r_dir_perms;
allow nubia_parts sysfs_gamekey:{ file lnk_file } rw_file_perms;
NPPRIV

cat > "$NPS/vendor/nubiaparts.te" <<'NPVND'
# Доступ к vendor-типам. Сам домен nubia_parts объявлен в платформенной
# политике (sepolicy/public + sepolicy/private): он coredomain, а coredomain
# в vendor-политике объявлять нельзя (treble_labeling_tests).
allow nubia_parts vendor_sysfs_battery_supply:dir r_dir_perms;
allow nubia_parts vendor_sysfs_battery_supply:{ file lnk_file } rw_file_perms;
NPVND
for cil in "$NPS/private/compat"/*/*.ignore.cil; do
    grep -q nubia_parts "$cil" || \
        sed -i 's/^    sysfs_gamekey))$/    sysfs_gamekey\n    nubia_parts))/' "$cil"
done

# 8) ВАЖНО, чтобы не наступить повторно: флаг
#    com.android.wm.shell.enable_taskbar_on_phones выключать НЕЛЬЗЯ.
#    Было искушение это сделать, когда пропала навигация, но причина тогда
#    оказалась другой — LineageSettings.System.force_show_navbar в /data стоял
#    в 0 после грязной прошивки (см. память проекта). А флаг отвечает за
#    штатную схему Android: на телефоне в режиме жестов Launcher3 ВСЕГДА
#    создаёт окно типа TYPE_NAVIGATION_BAR с заголовком Taskbar —
#    TaskbarManagerImpl.recreateTaskbarForDisplay выходит досрочно только если
#    навигация отключена целиком, а не когда таскбара нет на экране. При
#    включённом флаге SystemUI это окно не занимает, а отдаёт обязанности
#    TaskbarDelegate. Выключишь флаг — SystemUI полезет создавать своё окно,
#    получит BadTokenException ("another window of type 2019 already exists"),
#    и навигации не будет вовсе: проверено на устройстве дважды.

# 9) часы статусбара по центру. Проверено на устройстве (скриншоты + код):
#    при LineageSettings.System.status_bar_clock = 1 (CENTER) часы прижимаются
#    к левому краю и на них налезают иконки уведомлений. Причина в layout:
#    центральные часы @id/clock_center лежат в @id/centered_area — горизонтальном
#    LinearLayout с gravity="center", — а StatusBarRoot.kt добавляет в этот же
#    контейнер ComposeView для popup-чипов с шириной MATCH_PARENT. Ребёнок на всю
#    ширину съедает свободное место, центрировать нечего, часы встают слева.
#    Чиним без трогания compose-кода: часы переезжают в собственный контейнер
#    @id/clock_center_area, а centered_area остаётся на месте (пустым) — он нужен
#    и StatusBarRoot.kt (requireViewById), и PhoneStatusBarView. Тому же
#    PhoneStatusBarView добавляем отрицательные отступы для нового контейнера,
#    иначе на устройстве с вырезом центр уедет.
python3 - "$WORK_DIR" <<'CLOCKPY'
import sys, os
work = sys.argv[1]
lay = os.path.join(work, 'frameworks/base/packages/SystemUI/res/layout/status_bar.xml')
src = os.path.join(work, 'frameworks/base/packages/SystemUI/src/com/android/systemui/'
                         'statusbar/phone/PhoneStatusBarView.java')

s = open(lay, encoding='utf-8').read()
if 'clock_center_area' not in s:
    old = ('    <com.android.keyguard.AlphaOptimizedLinearLayout\n'
           '        android:id="@+id/centered_area"\n')
    new = ('    <!-- Часы вынесены из centered_area: туда StatusBarRoot.kt кладёт\n'
           '         ComposeView на всю ширину, и gravity="center" перестаёт работать. -->\n'
           '    <com.android.keyguard.AlphaOptimizedLinearLayout\n'
           '        android:id="@+id/clock_center_area"\n')
    assert s.count(old) == 1, 'не нашёл centered_area в status_bar.xml'
    s = s.replace(old, new)
    tail_old = ('    </com.android.keyguard.AlphaOptimizedLinearLayout>\n\n'
                '    <com.android.systemui.infinity.batterybar.BatteryBarController')
    tail_new = ('    </com.android.keyguard.AlphaOptimizedLinearLayout>\n\n'
                '    <com.android.keyguard.AlphaOptimizedLinearLayout\n'
                '        android:id="@+id/centered_area"\n'
                '        android:gravity="center"\n'
                '        android:orientation="horizontal"\n'
                '        android:layout_width="match_parent"\n'
                '        android:layout_height="match_parent"\n'
                '        android:paddingTop="@dimen/status_bar_padding_top"\n'
                '        android:clipChildren="false"\n'
                '        android:clipToPadding="false"\n'
                '        />\n\n'
                '    <com.android.systemui.infinity.batterybar.BatteryBarController')
    assert s.count(tail_old) == 1, 'не нашёл хвост status_bar.xml'
    s = s.replace(tail_old, tail_new)
    open(lay, 'w', encoding='utf-8').write(s)
    print('   status_bar.xml: часы вынесены в clock_center_area')

j = open(src, encoding='utf-8').read()
if 'clock_center_area' not in j:
    old = ('        centeredAreaParams.rightMargin =\n'
           '                winRotation == Surface.ROTATION_0 ? -insets.right : 0;\n'
           '    }')
    new = ('        centeredAreaParams.rightMargin =\n'
           '                winRotation == Surface.ROTATION_0 ? -insets.right : 0;\n\n'
           '        View clockCenterArea = findViewById(R.id.clock_center_area);\n'
           '        if (clockCenterArea != null) {\n'
           '            if (clockCenterArea instanceof ViewGroup) {\n'
           '                ((ViewGroup) clockCenterArea).setClipToPadding(false);\n'
           '                ((ViewGroup) clockCenterArea).setClipChildren(false);\n'
           '            }\n'
           '            LayoutParams clockCenterAreaParams =\n'
           '                    (LayoutParams) clockCenterArea.getLayoutParams();\n'
           '            clockCenterAreaParams.leftMargin =\n'
           '                    winRotation == Surface.ROTATION_0 ? -insets.left : 0;\n'
           '            clockCenterAreaParams.rightMargin =\n'
           '                    winRotation == Surface.ROTATION_0 ? -insets.right : 0;\n'
           '        }\n'
           '    }')
    assert j.count(old) == 1, 'не нашёл блок отступов в PhoneStatusBarView.java'
    open(src, 'w', encoding='utf-8').write(j.replace(old, new))
    print('   PhoneStatusBarView.java: отступы для clock_center_area')
CLOCKPY

# 10) чёрная точка над подэкранной фронтальной камерой (UDC). В дереве была
#     только заготовка: helper/CameraHelper.java детектил фронтальную камеру в
#     onCameraAvailable/onCameraUnavailable, и обе ветки были пустые, а broadcast,
#     который вообще включает этот callback, никто не посылал. Реализуем как
#     системное окно-оверлей в NubiaPartsHelper: пока фронталка занята, над ней
#     гасится участок экрана, иначе сенсор снимает через светящиеся пиксели.
#     Приложение подписано платформенным ключом и привилегировано
#     (NubiaParts_defaults), поэтому INTERNAL_SYSTEM_WINDOW выдаётся по подписи,
#     а privapp-allowlist не нужен. Геометрия — из
#     rro_overlays/FrameworksResTarget_Vendor/res/values/config.xml
#     (config_mainBuiltInDisplayCutoutRectApproximation: 68 x 93 px по центру
#     сверху, без @dp — значит пиксели). Размеры правятся на лету через
#     Settings.Secure (udc_dot_*), без пересборки.
#     Android.bp трогать не надо: srcs у NubiaPartsHelper — glob helper/*.java.
NPH="$WORK_DIR/packages/apps/NubiaParts/src/org/lineageos/device/NubiaParts/helper"
cat > "$NPH/UdcDot.java" <<'UDCDOT'
/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Чёрная точка над подэкранной фронтальной камерой (UDC) у nubia Z60 Ultra.
 *
 * У cerro фронтальная камера находится под матрицей, поэтому пока над ней
 * светятся пиксели, сенсор снимает через них. Стоковая прошивка на время
 * работы фронталки гасит этот участок — получается та самая «чёрная точка».
 *
 * В дереве под это была оставлена заготовка: CameraHelper детектил фронтальную
 * камеру в onCameraAvailable/onCameraUnavailable, но обе ветки были пустые.
 * Здесь заготовка доведена до рабочего вида: окно-оверлей системного типа с
 * чёрным овалом показывается, пока фронтальная камера занята.
 *
 * Геометрия взята из
 * device/nubia/sm8650-common/rro_overlays/FrameworksResTarget_Vendor/res/values/config.xml,
 * где config_mainBuiltInDisplayCutoutRectApproximation описывает область камеры
 * как прямоугольник 68 x 93 px по центру верхней кромки (суффикса @dp нет,
 * значит пиксели). По умолчанию рисуется круг 68 px, вписанный в этот
 * прямоугольник по вертикали (отступ сверху 13 px).
 *
 * Все размеры правятся на лету, без пересборки:
 *   adb shell settings put secure udc_dot_width 72
 *   adb shell settings put secure udc_dot_offset_y 10
 *   adb shell settings put secure udc_dot_anim_ms 0     (без анимации)
 *   adb shell settings put secure udc_dot_enabled 0
 */

package org.lineageos.device.NubiaParts.helper;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.app.Application;
import android.database.ContentObserver;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.drawable.GradientDrawable;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.hardware.display.DisplayManager;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;
import android.view.Display;
import android.view.Gravity;
import android.view.Surface;
import android.view.View;
import android.view.WindowManager;
import android.view.animation.PathInterpolator;

import java.util.concurrent.Executor;

public class UdcDot extends Application {

    private static final String TAG = "NubiaUdcDot";

    static final String KEY_ENABLED = "udc_dot_enabled";
    static final String KEY_WIDTH = "udc_dot_width";
    static final String KEY_HEIGHT = "udc_dot_height";
    static final String KEY_OFFSET_X = "udc_dot_offset_x";
    static final String KEY_OFFSET_Y = "udc_dot_offset_y";
    static final String KEY_ANIM_MS = "udc_dot_anim_ms";

    private static final int DEF_ENABLED = 1;
    private static final int DEF_WIDTH = 72;  // выверено на устройстве
    private static final int DEF_HEIGHT = 71;  // на 3 px ниже, выверено на устройстве
    private static final int DEF_OFFSET_X = 3;   // выверено на устройстве
    private static final int DEF_OFFSET_Y = 18;  // выверено на устройстве
    private static final int DEF_ANIM_MS = 260;

    // Масштаб, с которого точка раскрывается и в который сворачивается.
    // Строго меньше 1: окно размером ровно с точку, и всё, что крупнее,
    // обрезалось бы по краям.
    private static final float SHRUNK = 0.25f;

    // Кривые Material: «мягкое» раскрытие с быстрым началом и долгим
    // успокоением, и зеркальное сворачивание. Ровные ease-in/ease-out
    // выглядят механически, эти — заметно мягче.
    private static final PathInterpolator GROW =
            new PathInterpolator(0.05f, 0.7f, 0.1f, 1.0f);
    private static final PathInterpolator SHRINK =
            new PathInterpolator(0.3f, 0.0f, 0.8f, 0.15f);

    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private final Executor mExecutor = mHandler::post;

    private WindowManager mWindowManager;
    private CameraManager mCameraManager;
    private View mDot;
    private String mFrontCameraId;
    private boolean mInUse;
    private boolean mShown;
    private boolean mHiding;

    @Override
    public void onCreate() {
        super.onCreate();
        try {
            mWindowManager = getSystemService(WindowManager.class);
            mCameraManager = getSystemService(CameraManager.class);
            if (mWindowManager == null || mCameraManager == null) {
                Log.e(TAG, "Нет WindowManager/CameraManager, точка работать не будет");
                return;
            }
            mFrontCameraId = findFrontCameraId();
            mCameraManager.registerAvailabilityCallback(mExecutor, mAvailabilityCallback);
            registerSettingsObserver();
            registerDisplayListener();
            Log.i(TAG, "Готов, фронтальная камера: " + mFrontCameraId);
        } catch (Throwable t) {
            // Процесс persistent: падение здесь уронило бы его в цикл перезапусков.
            Log.e(TAG, "Не удалось инициализироваться", t);
        }
    }

    private String findFrontCameraId() {
        try {
            for (String id : mCameraManager.getCameraIdList()) {
                if (isFront(id)) {
                    return id;
                }
            }
        } catch (CameraAccessException e) {
            Log.e(TAG, "Не удалось получить список камер", e);
        }
        return null;
    }

    private boolean isFront(String cameraId) {
        if (cameraId == null) {
            return false;
        }
        if (cameraId.equals(mFrontCameraId)) {
            return true;
        }
        try {
            final CameraCharacteristics c = mCameraManager.getCameraCharacteristics(cameraId);
            final Integer facing = c.get(CameraCharacteristics.LENS_FACING);
            return facing != null && facing == CameraCharacteristics.LENS_FACING_FRONT;
        } catch (CameraAccessException | IllegalArgumentException e) {
            // id может относиться к камере, которой нет в публичном списке
            return false;
        }
    }

    private final CameraManager.AvailabilityCallback mAvailabilityCallback =
            new CameraManager.AvailabilityCallback() {
                @Override
                public void onCameraAvailable(String cameraId) {
                    if (isFront(cameraId)) {
                        setInUse(false);
                    }
                }

                @Override
                public void onCameraUnavailable(String cameraId) {
                    if (isFront(cameraId)) {
                        setInUse(true);
                    }
                }
            };

    private void setInUse(boolean inUse) {
        if (mInUse == inUse) {
            return;
        }
        mInUse = inUse;
        // Лог намеренный: если точка залипнет, он сразу покажет, чья это вина —
        // наша (события пришли, а точка осталась) или приложения, которое не
        // отпустило камеру (события «свободна» просто нет).
        Log.i(TAG, "фронтальная камера " + (inUse ? "занята" : "свободна"));
        update();
    }

    private void update() {
        final boolean wanted = mInUse && getInt(KEY_ENABLED, DEF_ENABLED) != 0;
        if (wanted) {
            show();
        } else {
            hide();
        }
    }

    private void ensureDot() {
        if (mDot != null) {
            return;
        }
        final GradientDrawable oval = new GradientDrawable();
        oval.setShape(GradientDrawable.OVAL);
        oval.setColor(Color.BLACK);
        mDot = new View(this);
        mDot.setBackground(oval);
    }

    /**
     * Короткое появление: точка проступает и чуть «раскрывается». Длительность
     * умышленно маленькая — пока идёт анимация, пиксели над сенсором ещё светятся.
     * При выключенных в системе анимациях ViewPropertyAnimator сам сведёт
     * длительность к нулю (animator_duration_scale), отдельной проверки не нужно.
     */
    private void show() {
        ensureDot();
        final long duration = animMs();
        try {
            if (mShown) {
                // Либо повернули экран, либо камеру открыли снова, пока точка
                // ещё догорала — в обоих случаях возвращаем её в полный вид.
                mDot.animate().cancel();
                mHiding = false;
                mWindowManager.updateViewLayout(mDot, buildParams());
            } else {
                mDot.setAlpha(duration > 0 ? 0f : 1f);
                mDot.setScaleX(duration > 0 ? SHRUNK : 1f);
                mDot.setScaleY(duration > 0 ? SHRUNK : 1f);
                mWindowManager.addView(mDot, buildParams());
                mShown = true;
                mHiding = false;
            }
            if (duration > 0) {
                mDot.animate()
                        .alpha(1f).scaleX(1f).scaleY(1f)
                        .setDuration(duration)
                        .setInterpolator(GROW)
                        .setListener(null)
                        .start();
            } else {
                mDot.setAlpha(1f);
                mDot.setScaleX(1f);
                mDot.setScaleY(1f);
            }
        } catch (Throwable t) {
            Log.e(TAG, "Не удалось показать точку", t);
        }
    }

    private void hide() {
        if (!mShown || mHiding) {
            return;
        }
        final long duration = animMs();
        if (duration <= 0) {
            removeDot();
            return;
        }
        mHiding = true;
        // Слушатель, а не withEndAction: тот не срабатывает при отмене анимации,
        // и mHiding залипал бы в true — после чего hide() выходил бы сразу и
        // точка оставалась на экране навсегда. onAnimationEnd у
        // ViewPropertyAnimator вызывается в обоих случаях.
        mDot.animate()
                .alpha(0f).scaleX(SHRUNK).scaleY(SHRUNK)
                .setDuration(duration)
                .setInterpolator(SHRINK)
                .setListener(new AnimatorListenerAdapter() {
                    @Override
                    public void onAnimationEnd(Animator animation) {
                        mHiding = false;
                        mDot.animate().setListener(null);
                        // Камеру могли успеть открыть снова, пока точка гасла —
                        // тогда убирать её нельзя.
                        if (!mInUse) {
                            removeDot();
                        }
                    }
                })
                .start();
    }

    private void removeDot() {
        mHiding = false;
        if (!mShown) {
            return;
        }
        try {
            mWindowManager.removeViewImmediate(mDot);
        } catch (Throwable t) {
            Log.e(TAG, "Не удалось убрать точку", t);
        }
        mShown = false;
    }

    private long animMs() {
        return Math.max(0, Math.min(1000, getInt(KEY_ANIM_MS, DEF_ANIM_MS)));
    }

    private WindowManager.LayoutParams buildParams() {
        final int w = getInt(KEY_WIDTH, DEF_WIDTH);
        final int h = getInt(KEY_HEIGHT, DEF_HEIGHT);
        final int ox = getInt(KEY_OFFSET_X, DEF_OFFSET_X);
        final int oy = getInt(KEY_OFFSET_Y, DEF_OFFSET_Y);

        final WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.TYPE_SYSTEM_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                        | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT);
        lp.setTitle(TAG);
        lp.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS;
        lp.setFitInsetsTypes(0);
        // Без этого точка выходит полупрозрачной (проверено на устройстве):
        // TYPE_SYSTEM_OVERLAY попадает под isSystemAlertWindowType(), и
        // DisplayPolicy.adjustWindowParamsLw принудительно опускает alpha до
        // mMaximumObscuringOpacityForTouch (по умолчанию 0.8) у недоверенного
        // окна с FLAG_NOT_TOUCHABLE — чтобы касания гарантированно проходили
        // насквозь. Одного INTERNAL_SYSTEM_WINDOW мало: WindowState
        // .isWindowTrustedOverlay() требует ещё и PRIVATE_FLAG_TRUSTED_OVERLAY,
        // который и ставит setTrustedOverlay(). Тип не меняем на
        // TYPE_SECURE_SYSTEM_OVERLAY (он доверенный сам по себе) только чтобы
        // точка оставалась видимой в screencap и её можно было выверять.
        lp.setTrustedOverlay();

        // Сенсор физически у верхней кромки панели. При повороте экрана система
        // поворачивает систему координат окна, а камера остаётся на месте,
        // поэтому «верх» пересчитываем в ту кромку, где она оказалась:
        // ROTATION_90 — натуральный верх уходит влево, ROTATION_270 — вправо.
        switch (getRotation()) {
            case Surface.ROTATION_90:
                lp.gravity = Gravity.LEFT | Gravity.CENTER_VERTICAL;
                lp.width = h;
                lp.height = w;
                lp.x = oy;
                lp.y = -ox;
                break;
            case Surface.ROTATION_180:
                lp.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
                lp.width = w;
                lp.height = h;
                lp.x = -ox;
                lp.y = oy;
                break;
            case Surface.ROTATION_270:
                lp.gravity = Gravity.RIGHT | Gravity.CENTER_VERTICAL;
                lp.width = h;
                lp.height = w;
                lp.x = oy;
                lp.y = ox;
                break;
            default:
                lp.gravity = Gravity.TOP | Gravity.CENTER_HORIZONTAL;
                lp.width = w;
                lp.height = h;
                lp.x = ox;
                lp.y = oy;
                break;
        }
        return lp;
    }

    private int getRotation() {
        final DisplayManager dm = getSystemService(DisplayManager.class);
        if (dm == null) {
            return Surface.ROTATION_0;
        }
        final Display display = dm.getDisplay(Display.DEFAULT_DISPLAY);
        return display != null ? display.getRotation() : Surface.ROTATION_0;
    }

    private void registerDisplayListener() {
        final DisplayManager dm = getSystemService(DisplayManager.class);
        if (dm == null) {
            return;
        }
        dm.registerDisplayListener(new DisplayManager.DisplayListener() {
            @Override
            public void onDisplayAdded(int displayId) {}

            @Override
            public void onDisplayRemoved(int displayId) {}

            @Override
            public void onDisplayChanged(int displayId) {
                // Только update(): раньше здесь был show(), и любое изменение
                // дисплея (например переключение частоты обновления, которое
                // делает запись кружка в мессенджере) возвращало точку в
                // полную видимость прямо посреди затухания. mInUse к тому
                // моменту уже false, и скрыть её было больше некому.
                if (displayId == Display.DEFAULT_DISPLAY && mShown) {
                    update();
                }
            }
        }, mHandler);
    }

    private void registerSettingsObserver() {
        final ContentObserver observer = new ContentObserver(mHandler) {
            @Override
            public void onChange(boolean selfChange) {
                update();
            }
        };
        for (String key : new String[] {
                KEY_ENABLED, KEY_WIDTH, KEY_HEIGHT,
                KEY_OFFSET_X, KEY_OFFSET_Y, KEY_ANIM_MS }) {
            getContentResolver().registerContentObserver(
                    Settings.Secure.getUriFor(key), false, observer);
        }
    }

    private int getInt(String key, int def) {
        try {
            return Settings.Secure.getInt(getContentResolver(), key, def);
        } catch (Throwable t) {
            return def;
        }
    }
}
UDCDOT
python3 - "$NPH/AndroidManifest.xml" <<'UDCMAN'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
if 'UdcDot' in s:
    sys.exit(0)
old = ('    <application\n'
       '        android:label="NubiaPartsHelper"\n'
       '        android:hasCode="true">')
new = ('    <!-- Для системного окна-оверлея с чёрной точкой над подэкранной камерой.\n'
       '         Разрешение signature-уровня, приложение подписано платформенным ключом\n'
       '         (NubiaParts_defaults: certificate: "platform"), поэтому в privapp-allowlist\n'
       '         его добавлять не нужно. -->\n'
       '    <uses-permission android:name="android.permission.INTERNAL_SYSTEM_WINDOW"/>\n\n'
       '    <!-- persistent: процесс должен жить всегда, иначе некому следить за тем,\n'
       '         когда откроют фронтальную камеру. Флаг действует только для приложений\n'
       '         из системного образа — это как раз наш случай (system_ext/priv-app). -->\n'
       '    <application\n'
       '        android:name=".UdcDot"\n'
       '        android:persistent="true"\n'
       '        android:label="NubiaPartsHelper"\n'
       '        android:hasCode="true">')
assert s.count(old) == 1, 'не нашёл <application> в helper/AndroidManifest.xml'
open(p, 'w', encoding='utf-8').write(s.replace(old, new))
print('   NubiaPartsHelper: добавлена чёрная точка UDC')
UDCMAN

# 11) sepolicy для Dolby. Проверено на устройстве: без этого
#     vendor.dolby.hardware.dms@2.0-service крутится в цикле перезапусков,
#     приложению Dolby не с кем говорить и Atmos не включается. В логе
#     каждые 5 секунд два отказа — чтение vendor_audio_prop и установка
#     persist.vendor.audio.scenario. vendor_audio_prop приходит из QTI-политики
#     (device/qcom/sepolicy_vndr), и в дереве Dolby о нём не знают.
#     Правка живёт в самом hardware/dolby, а не в дереве устройства, намеренно:
#     тип hal_dms_default существует только вместе с Dolby, и в device-политике
#     ссылка на него роняла бы сборку, когда hardware/dolby не синкнут.
DOLBY_TE="$WORK_DIR/hardware/dolby/sepolicy/vendor/hal_dms_default.te"
if [ -f "$DOLBY_TE" ] && ! grep -q vendor_audio_prop "$DOLBY_TE"; then
    cat >> "$DOLBY_TE" <<'DOLBYTE'

# Добавлено build-infinity-cerro.sh: set_prop закрывает оба отказа сразу —
# property_service set плюс get_prop, то есть чтение файла свойств.
set_prop(hal_dms_default, vendor_audio_prop)
DOLBYTE
    echo "   hardware/dolby: доступ к vendor_audio_prop"
fi

#     Второе, без чего Dolby не поднимается: объявление HAL в VINTF. Проверено
#     на устройстве — без него hwservicemanager отвечает
#       getTransport: Cannot find entry vendor.dolby.hardware.dms@2.0::IDms/default
#       in either framework or device VINTF manifest
#     сервис не регистрируется, выходит с кодом 1, init перезапускает его
#     каждые 5 секунд, а приложение Dolby падает следом с
#       AudioEffect: set/get parameter error.
#     Кладём туда, куда дерево устройства уже смотрит само:
#     device/nubia/sm8650-common/BoardConfigCommon.mk содержит строку
#       -include hardware/dolby/configs/vintf/config.mk
#     а в ветке cnb этого каталога нет. Поэтому ни дерево устройства, ни
#     dolby.mk править не нужно. Через PRODUCT_COPY_FILES положить нельзя —
#     сборка отвечает "VINTF metadata found in PRODUCT_COPY_FILES ... use
#     DEVICE_MANIFEST_FILE ... instead".
DOLBY_VINTF_DIR="$WORK_DIR/hardware/dolby/configs/vintf"
if [ -d "$WORK_DIR/hardware/dolby" ] && [ ! -f "$DOLBY_VINTF_DIR/config.mk" ]; then
    mkdir -p "$DOLBY_VINTF_DIR"
    cat > "$DOLBY_VINTF_DIR/vendor.dolby.hardware.dms@2.0-service.xml" <<'DOLBYVINTF'
<manifest version="1.0" type="device">
    <hal format="hidl">
        <name>vendor.dolby.hardware.dms</name>
        <transport>hwbinder</transport>
        <version>2.0</version>
        <interface>
            <name>IDms</name>
            <instance>default</instance>
        </interface>
    </hal>
</manifest>
DOLBYVINTF
    cat > "$DOLBY_VINTF_DIR/dolby_framework_matrix.xml" <<'DOLBYMATRIX'
<compatibility-matrix version="4.0" type="framework">
    <hal format="hidl" optional="true">
        <name>vendor.dolby.hardware.dms</name>
        <version>2.0</version>
        <interface>
            <name>IDms</name>
            <instance>default</instance>
        </interface>
    </hal>
    <hal format="hidl" optional="true">
        <name>android.hardware.media.c2</name>
        <version>1.0</version>
        <interface>
            <name>IComponentStore</name>
            <instance>default1</instance>
        </interface>
    </hal>
</compatibility-matrix>
DOLBYMATRIX
    cat > "$DOLBY_VINTF_DIR/config.mk" <<'DOLBYVINTFMK'
# Добавлено build-infinity-cerro.sh: дерево устройства подключает этот файл
# строкой -include hardware/dolby/configs/vintf/config.mk, а в ветке cnb
# каталога нет. Без объявления HAL сервис Dolby не регистрируется.
DEVICE_MANIFEST_FILE += \
    hardware/dolby/configs/vintf/vendor.dolby.hardware.dms@2.0-service.xml

# Одного манифеста мало: check_vintf требует, чтобы HAL был ещё и разрешён в
# матрице совместимости, иначе сборка падает с "instances are in the device
# manifest but not specified in framework compatibility matrix".
DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE += \
    hardware/dolby/configs/vintf/dolby_framework_matrix.xml
DOLBYVINTFMK
    echo "   hardware/dolby: HAL объявлен в VINTF"
fi

# 12) SystemUI умирал при создании навигационной панели. Проверено на
#     устройстве: 125 падений за одну загрузку, все с
#       BadTokenException: Unable to add window -- another window of
#       type 2019 already exists   (2019 = TYPE_NAVIGATION_BAR)
#         at NavigationBar.onInit
#         at NavigationBarControllerImpl.createNavigationBar
#         at CommandQueueInitializer.start
#     Исключение уходило наверх и роняло KeyguardService, а вместе с ним весь
#     SystemUI; тот перезапускался, снова натыкался на чужое окно и падал
#     опять. Отсюда и долгая загрузка со сломанным SystemUI (белое системное
#     меню питания рисует system_server, пока SystemUI мёртв), и смерть при
#     любой правке настроек навигации.
#     Две правки: защита от повторного создания внутри процесса и, главное,
#     замена фатального исключения на ограниченный повтор — чужое окно
#     исчезает, как только систему покидает его владелец.
python3 - "$WORK_DIR" <<'NAVPY'
import sys, os
p = os.path.join(sys.argv[1], 'frameworks/base/packages/SystemUI/src/com/android/systemui/'
                              'navigationbar/NavigationBarControllerImpl.java')
s = open(p, encoding='utf-8').read()
changed = False

if 'mNavigationBars.get(displayId) != null' not in s:
    old = ("        final boolean isOnDefaultDisplay = displayId == mDisplayTracker.getDefaultDisplayId();\n"
           "\n"
           "        if (!canCreateNavBarOrTaskBar(displayId)) {\n")
    new = ("        final boolean isOnDefaultDisplay = displayId == mDisplayTracker.getDefaultDisplayId();\n"
           "\n"
           "        // Панель для этого дисплея уже есть — второй раз создавать нельзя.\n"
           "        if (mNavigationBars.get(displayId) != null) {\n"
           "            return;\n"
           "        }\n"
           "\n"
           "        if (!canCreateNavBarOrTaskBar(displayId)) {\n")
    assert s.count(old) == 1, 'не нашёл createNavigationBar'
    s = s.replace(old, new); changed = True

if 'NAV_BAR_MAX_RETRIES' not in s:
    old = "    SparseArray<NavigationBar> mNavigationBars = new SparseArray<>();"
    new = ("    SparseArray<NavigationBar> mNavigationBars = new SparseArray<>();\n"
           "    private final android.util.SparseIntArray mNavBarRetries = new android.util.SparseIntArray();\n"
           "    private static final int NAV_BAR_MAX_RETRIES = 20;\n"
           "    private static final long NAV_BAR_RETRY_DELAY_MS = 500;")
    assert s.count(old) == 1, 'не нашёл mNavigationBars'
    s = s.replace(old, new)

    old = ("        NavigationBar navBar = component.getNavigationBar();\n"
           "        navBar.init();\n"
           "        mNavigationBars.put(displayId, navBar);")
    new = ("        NavigationBar navBar = component.getNavigationBar();\n"
           "        try {\n"
           "            navBar.init();\n"
           "        } catch (android.view.WindowManager.BadTokenException e) {\n"
           "            // Окно уже занято предыдущим экземпляром SystemUI. Раньше это\n"
           "            // исключение убивало SystemUI целиком; теперь ждём и пробуем снова.\n"
           "            final int tries = mNavBarRetries.get(displayId) + 1;\n"
           "            mNavBarRetries.put(displayId, tries);\n"
           "            navBar.destroyView();\n"
           "            if (tries <= NAV_BAR_MAX_RETRIES) {\n"
           "                Log.w(TAG, \"Окно навигационной панели занято, попытка \" + tries\n"
           "                        + \" из \" + NAV_BAR_MAX_RETRIES, e);\n"
           "                mContext.getMainThreadHandler().postDelayed(\n"
           "                        () -> createNavigationBar(display, savedState, result),\n"
           "                        NAV_BAR_RETRY_DELAY_MS);\n"
           "            } else {\n"
           "                Log.e(TAG, \"Навигационная панель так и не создалась\", e);\n"
           "            }\n"
           "            return;\n"
           "        }\n"
           "        mNavBarRetries.delete(displayId);\n"
           "        mNavigationBars.put(displayId, navBar);")
    assert s.count(old) == 1, 'не нашёл блок создания панели'
    s = s.replace(old, new); changed = True

if changed:
    open(p, 'w', encoding='utf-8').write(s)
    print('   SystemUI: панель создаётся с повтором вместо падения')
NAVPY

# 13) две мелочи, которые постоянно работают вхолостую. Обе найдены замером
#     лога на устройстве, а не по наитию.
#
#     LOWI (подсистема Wi-Fi-геолокации) идёт со стока с LOWI_LOG_LEVEL = 4,
#     то есть EL_DEBUG по легенде в самом файле
#     (EL_LOG_OFF=0, EL_ERROR=1, EL_WARNING=2, EL_INFO=3, EL_DEBUG=4...).
#     В окне лога это давало 2624 строки — отладочный поток в релизной
#     прошивке, то есть работа процессора и записи logd круглосуточно.
#     Ставим 2: предупреждения и ошибки остаются, отладка уходит.
#     Остальное в этом файле не трогаем — там параметры самой геолокации.
#     Для сравнения: DEBUG_LEVEL в gps.conf уже минимальный (2), там крутить
#     нечего, а у драйвера wlan в блобах нет конфига с уровнем логирования.
LOWI_CONF="$WORK_DIR/vendor/nubia/sm8650-common/proprietary/vendor/etc/lowi.conf"
if [ -f "$LOWI_CONF" ]; then
    sed -i 's/^LOWI_LOG_LEVEL = 4$/LOWI_LOG_LEVEL = 2/' "$LOWI_CONF"
fi

#     И мёртвая ссылка на ViPER: сам он не собирается (нужен libviperaidl,
#     которого нет нигде публично, см. п. 2 памяти проекта), а запись в
#     audio_effects.xml осталась и указывает на несуществующий libv4a_re.so.
#     Вреда почти нет, но это заведомо битый конфиг эффектов.
AEFF="$CDT/audio/audio_effects.xml"
if [ -f "$AEFF" ]; then
    sed -i '/<library name="v4a_re" path="libv4a_re.so"\/>/d; /<effect name="v4a_standard_re" library="v4a_re"/d' "$AEFF"
fi

echo "   продукт:    $DT/$PRODUCT.mk"
echo "   мейнтейнер: $MAINTAINER, GApps: $WITH_GAPPS"

if [ "$SYNC_ONLY" = "1" ]; then
    echo "== SYNC_ONLY=1: исходники и дерево готовы, сборку не запускаю =="
    exit 0
fi

# ------------------------------------------------------------------
# out/ от другой ветки несовместим
# ------------------------------------------------------------------
OUT_STAMP="$WORK_DIR/out/.infinity_branch"
if [ "$WIPE_OUT" = "1" ] || \
   { [ "$WIPE_OUT" = "auto" ] && [ -d "$WORK_DIR/out" ] && \
     [ "$(cat "$OUT_STAMP" 2>/dev/null)" != "$MANIFEST_BRANCH-$TREE_BRANCH" ]; }; then
    echo "== out/ остался от другой сборки — удаляю =="
    rm -rf "$WORK_DIR/out"
fi
mkdir -p "$WORK_DIR/out"
echo "$MANIFEST_BRANCH-$TREE_BRANCH" > "$OUT_STAMP"

if [ "$USE_CCACHE_BUILD" = "true" ] && command -v ccache >/dev/null; then
    export USE_CCACHE=1
    export CCACHE_EXEC=$(command -v ccache)
    ccache -M "$CCACHE_SIZE" >/dev/null
    echo "== ccache включён, лимит $CCACHE_SIZE =="
fi

export NINJA_HIGHMEM_NUM_JOBS="$HIGHMEM_JOBS"
export WITH_GAPPS

set +e
source build/envsetup.sh

lunch "$PRODUCT-$VARIANT" > "$LOG_DIR/lunch.log" 2>&1
rc=$?
cat "$LOG_DIR/lunch.log"
if [ $rc -ne 0 ] || [ "$TARGET_PRODUCT" != "$PRODUCT" ]; then
    echo
    echo "!! lunch $PRODUCT-$VARIANT не прошёл (лог: $LOG_DIR/lunch.log)."
    echo "   Если ругается на релиз — у PIX двухчастный lunch, попробуй"
    echo "   вручную: source build/envsetup.sh && lunch (меню)."
    exit 1
fi

BUILD_LOG="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"
echo "== Сборка: m bacon -j$BUILD_THREADS =="
echo "   лог: $BUILD_LOG"
m bacon -j"$BUILD_THREADS" 2>&1 | tee "$BUILD_LOG"
rc=${PIPESTATUS[0]}

OUT_PRODUCT="$WORK_DIR/out/target/product/$DEVICE"
if [ $rc -eq 0 ]; then
    echo
    echo "== Готово =="
    ls -lh "$OUT_PRODUCT"/*.zip 2>/dev/null
    echo
    echo "   Прошивка из recovery:  adb sideload <zip>"
    echo "   Это полный OTA-пакет (payload.bin), /data не трогается."
else
    echo
    echo "!! Сборка упала (код $rc). Первые ошибки:"
    grep -nE "error:|FAILED|ninja: build stopped" "$BUILD_LOG" | head -20
    echo "   полный лог: $BUILD_LOG"
    echo "   повтор без синка:  NO_SYNC=1 bash $0"
fi
exit $rc
