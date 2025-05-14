#!/usr/bin/env bash
#
# update_alternative.sh ─ компактный менеджер версий GCC / Clang
#
# Возможности
#   • «Снести-и-поставить» (поведение по умолчанию)
#   • Сохранить существующие альтернативы  (--keep-existing)
#   • Свой приоритет у каждой версии       gcc-13:120  clang-19:90
#   • Одна группа «cc» переключает cc / c++ / CC / CXX сразу
#
# Лицензия: MIT
set -euo pipefail

# ─────────────────────────────  HELP  ──────────────────────────────────── #
usage() {
cat <<EOF
Использование
  sudo $0 [ОПЦИИ]  gcc-13[:PRIO]  [clang-19[:PRIO]] …

Опции
  -p, --priority N      глобальный приоритет (по умолчанию 100)
  -k, --keep-existing   не очищать старые группы альтернатив
  -l, --list            показать текущую конфигурацию и выйти
  -h, --help            эта справка

После запуска можно переключаться:
  sudo update-alternatives --config cc      # cc, c++, CC, CXX
  sudo update-alternatives --config gcc     # gcc, g++
  sudo update-alternatives --config clang   # clang, clang++

Примеры
  Полная переустановка:
      sudo $0 gcc-13 clang-19
  Добавить clang-18, оставить остальное:
      sudo $0 -k clang-18:110
EOF
}

# ─────────────────────  ARG PARSING  ─────────────────────────── #
PRIO_GLOBAL=100
KEEP_EXISTING=0
LIST_ONLY=0
declare -a COMPILERS=()   # "TYPE VER PRIO"

while (( $# )); do
  case $1 in
    -h|--help) usage; exit 0 ;;
    -l|--list) LIST_ONLY=1; shift ;;
    -k|--keep-existing) KEEP_EXISTING=1; shift ;;
    -p|--priority) PRIO_GLOBAL=$2; shift 2 ;;
    -p*) PRIO_GLOBAL=${1#-p}; shift ;;
    *)
      # gcc-13[:120]  | gcc 13[:120]
      if [[ $1 =~ ^(gcc|clang)-([0-9]+)(:([0-9]+))?$ ]]; then
        COMPILERS+=("${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[4]:-}")
        shift
      elif [[ $1 =~ ^(gcc|clang)$ && $# -ge 2 && $2 =~ ^([0-9]+)(:([0-9]+))?$ ]]; then
        COMPILERS+=("$1 ${BASH_REMATCH[1]} ${BASH_REMATCH[3]:-}")
        shift 2
      else
        echo "Неверный аргумент: $1" >&2; usage; exit 1
      fi
      ;;
  esac
done

list_compilers() {
  for name in gcc clang cc; do
    if update-alternatives --query "$name" &>/dev/null; then
      echo "== $name ==";
      update-alternatives --query "$name" |
        awk '
          BEGIN{alt="";sel="";prio=""}
          /^Value:/      {sel=$2}
          /^Alternative:/{alt=$2}
          /^Priority:/   {prio=$2; gsub(/^.*-/, "", alt);
                          printf "  %-8s (priority %s)%s\n", alt, prio, (alt==sel)?"  ⬅":""
          }'
      echo
    fi
  done
}

if (( LIST_ONLY )); then list_compilers; exit 0; fi
(( ${#COMPILERS[@]} )) || { echo "Нужно указать хотя бы один компилятор!"; exit 1; }

[[ $EUID -eq 0 ]] || { echo "Запускайте через sudo"; exit 1; }

# ─────────── Clean up ─────────── #
if (( KEEP_EXISTING == 0 )); then
  echo "Очистка старых альтернатив…"
  names=(cc c++ CC CXX gcc g++ clang clang++ llvm-config llvm-ar llvm-ranlib \
         llvm-nm llvm-objdump clang-format clang-tidy)
  for n in "${names[@]}"; do
    update-alternatives --remove-all "$n" 2>/dev/null || true
  done
  echo
fi

# ─────────── Register gcc / clang groups ─────────── #
for entry in "${COMPILERS[@]}"; do
  read -r TYPE VER PRI_SPEC <<<"$entry"
  PRIO=${PRI_SPEC:-$PRIO_GLOBAL}
  BIN="/usr/bin/${TYPE}-${VER}"
  [[ -x $BIN ]] || { echo "⚠ $BIN не найден, пропуск"; continue; }

  if [[ $TYPE == gcc ]]; then
    update-alternatives \
      --install /usr/bin/gcc gcc "$BIN" "$PRIO" \
      --slave /usr/bin/g++ g++ "/usr/bin/g++-${VER}"
  else
    update-alternatives \
      --install /usr/bin/clang clang "$BIN" "$PRIO" \
      --slave /usr/bin/clang++ clang++ "/usr/bin/clang++-${VER}" \
      --slave /usr/bin/llvm-config llvm-config "/usr/bin/llvm-config-${VER}" \
      --slave /usr/bin/llvm-ar llvm-ar "/usr/bin/llvm-ar-${VER}" \
      --slave /usr/bin/llvm-ranlib llvm-ranlib "/usr/bin/llvm-ranlib-${VER}" \
      --slave /usr/bin/llvm-nm llvm-nm "/usr/bin/llvm-nm-${VER}" \
      --slave /usr/bin/llvm-objdump llvm-objdump "/usr/bin/llvm-objdump-${VER}" \
      --slave /usr/bin/clang-format clang-format "/usr/bin/clang-format-${VER}" \
      --slave /usr/bin/clang-tidy clang-tidy "/usr/bin/clang-tidy-${VER}"
  fi
  echo "✓ ${TYPE}-${VER} зарегистрирован (priority $PRIO)"
done

# ─────────── Unified cc / c++ / CC / CXX group ─────────── #
for entry in "${COMPILERS[@]}"; do
  read -r TYPE VER PRI_SPEC <<<"$entry"
  PRIO=${PRI_SPEC:-$PRIO_GLOBAL}
  if [[ $TYPE == gcc ]]; then
    BIN="/usr/bin/gcc-${VER}"
    CXX_BIN="/usr/bin/g++-${VER}"
  else
    BIN="/usr/bin/clang-${VER}"
    CXX_BIN="/usr/bin/clang++-${VER}"
  fi
  [[ -x $BIN && -x $CXX_BIN ]] || continue
  update-alternatives \
    --install /usr/bin/cc cc "$BIN" "$PRIO" \
    --slave   /usr/bin/c++ c++ "$CXX_BIN" \
    --slave   /usr/bin/CC  CC  "$BIN" \
    --slave   /usr/bin/CXX CXX "$CXX_BIN"
done

echo -e "\nГотово. Текущая конфигурация:\n"
list_compilers

