#!/usr/bin/env bash
# Безопасная оптимизация Android TV / Mi Stick через ADB.
# Использование:
#   ./tvtool.sh connect <IP>[:порт]   подключиться по Wi-Fi
#   ./tvtool.sh diag                  только чтение: диагностика, ничего не меняет
#   ./tvtool.sh backup                резервная копия настроек и списка пакетов
#   ./tvtool.sh disable <пакет>       отключить приложение (обратимо, пользователь 0)
#   ./tvtool.sh anim <0|0.5|1>        масштаб анимаций (1 = по умолчанию)
#   ./tvtool.sh restore               откатить ВСЕ изменения из журнала
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BK="$DIR/backup"
LOG="$BK/changes.log"
mkdir -p "$BK"

command -v adb >/dev/null || { echo "adb не найден. Установите platform-tools."; exit 1; }

cmd="${1:-}"; shift || true

case "$cmd" in
connect)
  adb connect "${1:?укажите IP, например 192.168.1.50}"
  adb devices
  ;;

diag)
  echo "== Устройство =="
  adb shell getprop ro.product.model
  adb shell getprop ro.build.version.release
  echo "== Память =="
  adb shell cat /proc/meminfo | head -3
  echo "== Хранилище =="
  adb shell df /data
  echo "== Топ процессов по памяти =="
  adb shell dumpsys meminfo | sed -n '1,25p'
  echo "== Сторонние приложения =="
  adb shell pm list packages -3
  echo "== Уже отключённые =="
  adb shell pm list packages -d
  echo "== Автозапуск/фоновые сервисы (кол-во) =="
  adb shell dumpsys activity services | grep -c ServiceRecord || true
  echo "== Температура =="
  adb shell dumpsys thermalservice 2>/dev/null | head -15 || true
  ;;

backup)
  ts="$(date +%Y%m%d-%H%M%S)"
  adb shell pm list packages -f      > "$BK/packages-all-$ts.txt"
  adb shell pm list packages -d      > "$BK/packages-disabled-$ts.txt"
  adb shell pm list packages -3      > "$BK/packages-user-$ts.txt"
  for k in window_animation_scale transition_animation_scale animator_duration_scale; do
    echo "$k=$(adb shell settings get global $k | tr -d '\r')"
  done > "$BK/anim-original.txt"
  echo "Копия сохранена в $BK (anim-original.txt хранит исходные анимации)."
  ;;

disable)
  pkg="${1:?укажите имя пакета}"
  [ -f "$BK/anim-original.txt" ] || { echo "Сначала выполните: $0 backup"; exit 1; }
  read -r -p "Отключить $pkg? [y/N] " a
  [ "$a" = "y" ] || { echo "Отменено."; exit 0; }
  adb shell pm disable-user --user 0 "$pkg"
  echo "disable $pkg" >> "$LOG"
  ;;

anim)
  v="${1:?значение: 0, 0.5 или 1}"
  [ -f "$BK/anim-original.txt" ] || { echo "Сначала выполните: $0 backup"; exit 1; }
  for k in window_animation_scale transition_animation_scale animator_duration_scale; do
    adb shell settings put global $k "$v"
  done
  echo "anim $v" >> "$LOG"
  ;;

restore)
  if [ -f "$LOG" ]; then
    grep '^disable ' "$LOG" | awk '{print $2}' | sort -u | while read -r pkg; do
      echo "Включаю $pkg"
      adb shell pm enable "$pkg" || adb shell cmd package install-existing --user 0 "$pkg"
    done
  fi
  if [ -f "$BK/anim-original.txt" ]; then
    while IFS='=' read -r k v; do
      [ "$v" = "null" ] && adb shell settings delete global "$k" || adb shell settings put global "$k" "$v"
    done < "$BK/anim-original.txt"
  fi
  : > "$LOG"
  echo "Восстановлено. Перезагрузите стик: adb reboot"
  ;;

*)
  sed -n '2,10p' "${BASH_SOURCE[0]}"
  ;;
esac
