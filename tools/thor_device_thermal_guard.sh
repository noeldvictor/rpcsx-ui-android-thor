#!/system/bin/sh
# Keep the bounded PS3 thermal guard on the Thor during a direct host wait.
# The host validates these exact sources against a full preflight before it
# starts this process. Any missing sensor stops the package.

set -u

package="${1:?package}"
silicon_stop_milli_c="${2:?silicon stop}"
silicon_hard_milli_c="${3:?silicon hard limit}"
junction_hard_milli_c="${4:?junction hard limit}"
battery_hard_milli_c="${5:?battery hard limit}"
skin_hard_c="${6:?skin hard limit}"

silicon_zones="31 32 33 34 55 63 64 65 66 67 68 69 70 82 90"
junction_zones="35 36 37 38 39 40 41 42 43 44 45 47 48 49"
battery_zone=94
seen_process=0
sample=0
last_skin=""

stop_package() {
    am force-stop "$package" >/dev/null 2>&1
}

while :; do
    pid="$(pidof "$package" 2>/dev/null || true)"
    if [ -z "$pid" ]; then
        if [ "$seen_process" -eq 1 ]; then
            echo "sample=$sample status=complete reason=package-stopped"
            exit 0
        fi
        sleep 1
        continue
    fi
    seen_process=1
    sample=$((sample + 1))

    silicon_max=0
    silicon_source="none"
    silicon_count=0
    for zone in $silicon_zones; do
        path="/sys/class/thermal/thermal_zone$zone"
        [ -r "$path/type" ] && [ -r "$path/temp" ] || continue
        type="$(cat "$path/type" 2>/dev/null || true)"
        value="$(cat "$path/temp" 2>/dev/null || true)"
        case "$value" in ''|*[!0-9-]*) continue;; esac
        silicon_count=$((silicon_count + 1))
        if [ "$value" -gt "$silicon_max" ]; then
            silicon_max="$value"
            silicon_source="$type"
        fi
    done

    junction_max=0
    junction_source="none"
    junction_count=0
    for zone in $junction_zones; do
        path="/sys/class/thermal/thermal_zone$zone"
        [ -r "$path/type" ] && [ -r "$path/temp" ] || continue
        type="$(cat "$path/type" 2>/dev/null || true)"
        value="$(cat "$path/temp" 2>/dev/null || true)"
        case "$value" in ''|*[!0-9-]*) continue;; esac
        junction_count=$((junction_count + 1))
        if [ "$value" -gt "$junction_max" ]; then
            junction_max="$value"
            junction_source="$type"
        fi
    done

    battery_path="/sys/class/thermal/thermal_zone$battery_zone"
    battery_value="$(cat "$battery_path/temp" 2>/dev/null || true)"
    case "$battery_value" in ''|*[!0-9-]*) battery_value=-1;; esac

    # Skin changes slowly. Read the Android hardware service at the first
    # sample and every fifth sample; retain the last validated value between.
    if [ -z "$last_skin" ] || [ $((sample % 5)) -eq 0 ]; then
        last_skin="$(dumpsys hardware_properties 2>/dev/null | sed -n 's/^Skin temperatures: \[\([0-9][0-9.]*\)\].*/\1/p' | head -n 1)"
    fi

    if [ "$silicon_count" -ne 15 ] || [ "$junction_count" -ne 14 ] ||
       [ "$battery_value" -lt 0 ] || [ -z "$last_skin" ]; then
        echo "sample=$sample status=failed code=sensor-set silicon_count=$silicon_count junction_count=$junction_count battery_milli_c=$battery_value skin_c=${last_skin:-unknown}"
        stop_package
        exit 40
    fi

    echo "sample=$sample status=ok pid=$pid silicon_milli_c=$silicon_max silicon_source=$silicon_source junction_milli_c=$junction_max junction_source=$junction_source battery_milli_c=$battery_value skin_c=$last_skin"

    if [ "$silicon_max" -ge "$silicon_hard_milli_c" ]; then
        echo "sample=$sample status=failed code=silicon-hard-limit value=$silicon_max limit=$silicon_hard_milli_c"
        stop_package
        exit 44
    fi
    if [ "$silicon_max" -ge "$silicon_stop_milli_c" ]; then
        echo "sample=$sample status=failed code=silicon-early-stop value=$silicon_max limit=$silicon_stop_milli_c hard_limit=$silicon_hard_milli_c"
        stop_package
        exit 43
    fi
    if [ "$junction_max" -ge "$junction_hard_milli_c" ]; then
        echo "sample=$sample status=failed code=junction-hard-limit value=$junction_max limit=$junction_hard_milli_c"
        stop_package
        exit 45
    fi
    if [ "$battery_value" -ge "$battery_hard_milli_c" ]; then
        echo "sample=$sample status=failed code=battery-hard-limit value=$battery_value limit=$battery_hard_milli_c"
        stop_package
        exit 46
    fi
    if awk -v value="$last_skin" -v limit="$skin_hard_c" 'BEGIN { exit !(value >= limit) }'; then
        echo "sample=$sample status=failed code=skin-hard-limit value=$last_skin limit=$skin_hard_c"
        stop_package
        exit 47
    fi

    sleep 2
done
