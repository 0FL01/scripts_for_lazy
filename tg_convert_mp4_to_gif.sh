#!/bin/bash

#
# Оптимизированный скрипт для пакетной конвертации видео из поддиректории 'mp4' в GIF.
# Использует многопоточную обработку, снижение FPS и постобработку gifsicle.
#
# Ожидаемая структура папок:
# .
# ├── convert_mp4_to_gif.sh  (этот скрипт)
# └── mp4/
#     ├── video1.mp4
#     └── ...
#
# Использование:
#   ./convert_mp4_to_gif.sh           # (ширина 500px, 15 FPS)
#   ./convert_mp4_to_gif.sh 640       # (ширина 640px, 15 FPS)
#   ./convert_mp4_to_gif.sh 640 12    # (ширина 640px, 12 FPS)
#   ./convert_mp4_to_gif.sh 640 12 4  # (ширина 640px, 12 FPS, 4 потока)
#

# --- Конфигурация ---
SOURCE_DIR="mp4"
OUTPUT_DIR="."
WIDTH=${1:-400}
FPS=${2:-24}
MAX_JOBS=${3:-$(nproc)}

# --- Проверка перед запуском ---
if [ ! -d "$SOURCE_DIR" ]; then
  echo "Ошибка: Директория с видео '$SOURCE_DIR/' не найдена."
  exit 1
fi

if ! command -v gifsicle &> /dev/null; then
  echo "Предупреждение: утилита 'gifsicle' не найдена."
  echo "Она крайне рекомендуется для финальной оптимизации размера GIF."
  echo "Установка: sudo dnf install gifsicle"
fi

# --- Функция конвертации одного файла ---
convert_file() {
  local input_file_path="$1"
  local width="$2"
  local fps="$3"
  local output_dir="$4"
  
  local base_filename
  base_filename=$(basename "$input_file_path")
  local stem="${base_filename%.mp4}"
  local output_gif_path="$output_dir/${stem}.gif"
  local temp_gif_path="$output_dir/${stem}_temp.gif"

  if [ -f "$output_gif_path" ]; then
    echo "-> Пропускаю '$base_filename', так как '$output_gif_path' уже существует."
    return 2 # 2 = пропуск (уже существует)
  fi

  echo "=> Конвертирую '$input_file_path' -> '$output_gif_path' (W: ${width}px, FPS: ${fps})..."

  local palette_temp
  palette_temp=$(mktemp --suffix=.png)
  
  # Опция для ускорения через GPU (AMD VA-API). Раскомментируйте, если нужно.
  # local hw_opts="-hwaccel vaapi -vaapi_device /dev/dri/renderD128"
  # local scale_filter="scale_vaapi=$width:-1"
  local hw_opts=""
  local scale_filter="scale=$width:-1:flags=lanczos"

  # Комплексный фильтр: снижение FPS, масштабирование, разделение потока для палитры и использования
  local complex_filter="fps=$fps,$scale_filter,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle"

  # Создаем GIF с помощью ffmpeg
  ffmpeg -v error -i "$input_file_path" -filter_complex "$complex_filter" -y "$temp_gif_path"

  if [ $? -ne 0 ]; then
    echo "   Ошибка при конвертации '$base_filename' с помощью ffmpeg."
    rm -f "$palette_temp" "$temp_gif_path"
    return 1 # Ошибка
  fi
  
  rm -f "$palette_temp"

  # Оптимизируем созданный GIF с помощью gifsicle, если утилита доступна
  if command -v gifsicle &> /dev/null; then
    gifsicle -O3 --lossy=80 "$temp_gif_path" -o "$output_gif_path"
    rm -f "$temp_gif_path"
  else
    mv "$temp_gif_path" "$output_gif_path"
  fi

  echo "   Готово: $base_filename"
  return 0 
}

export -f convert_file
export WIDTH FPS OUTPUT_DIR

# --- Основной процесс ---
echo "Начинаю поиск .mp4 в './${SOURCE_DIR}/' для конвертации..."
echo "Параметры: Ширина=${WIDTH}px, FPS=${FPS}, Потоков=${MAX_JOBS}"
echo "----------------------------------------------------------------"

mapfile -t files_to_process < <(find "$SOURCE_DIR" -maxdepth 1 -name "*.mp4" -type f)

if [ ${#files_to_process[@]} -eq 0 ]; then
  echo "Файлов .mp4 для конвертации не найдено."
  exit 0
fi

COUNTER=0
if command -v parallel &> /dev/null; then
  echo "Используется GNU Parallel для оптимальной загрузки CPU..."
  # `convert_file` возвращает 0 только когда создан новый GIF.
  # Печатаем маркер __NEW__ для таких случаев и считаем их.
  COUNTER=$(printf '%s\n' "${files_to_process[@]}" | \
    parallel -j "$MAX_JOBS" --bar --line-buffer "convert_file {} $WIDTH $FPS $OUTPUT_DIR; rc=\$?; if [ \$rc -eq 0 ]; then echo __NEW__; fi" | \
    grep -c '^__NEW__$')
else
  echo "GNU Parallel не найден, использую фоновые задачи..."
  
  processed_files=0
  pids=()
  
  for input_file_path in "${files_to_process[@]}"; do
    convert_file "$input_file_path" "$WIDTH" "$FPS" "$OUTPUT_DIR" &
    pids+=("$!")
    # Держим не более MAX_JOBS одновременно
    while [ "${#pids[@]}" -ge "$MAX_JOBS" ]; do
      wait "${pids[0]}"
      rc=$?
      if [ "$rc" -eq 0 ]; then
        ((processed_files++))
      fi
      pids=("${pids[@]:1}")
    done
  done
  
  # Дожидаемся оставшиеся задачи
  for pid in "${pids[@]}"; do
    wait "$pid"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      ((processed_files++))
    fi
  done
  
  COUNTER=$processed_files
fi

echo "----------------------------------------------------------------"

if [ "$COUNTER" -eq 0 ]; then
    echo "Новых видео для конвертации не найдено (все уже существуют)."
else
    echo "Завершено. Обработано новых файлов: $COUNTER."
fi
