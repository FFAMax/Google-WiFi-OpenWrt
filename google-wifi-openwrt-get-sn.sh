#!/bin/sh

BIN="/tmp/vpd_block.bin"
TMP_BIN="/tmp/vpd_block_trimmed.bin"
TMP_HEX="/tmp/vpd_hex.txt"
TMP_POS="/tmp/positions.txt"


MTD_DEVICE=/dev/mtd0
START_MARKER="gVpdInfo"
END_MARKER="wifi_base64_calibration1"

start_offset=$(strings -tx $MTD_DEVICE | grep -m1 "$START_MARKER" | awk '{print $1}')
end_offset=$(strings -tx $MTD_DEVICE | grep -m1 "$END_MARKER" | awk '{print $1}')

if [ -z "$start_offset" ] || [ -z "$end_offset" ]; then
  echo "Ошибка: не найдены маркеры"
  exit 1
fi

length=$(( 0x$end_offset + 0x20 - 0x$start_offset ))

dd if=$MTD_DEVICE bs=1 skip=$((0x$start_offset)) count=$length of="$BIN" 2>/dev/null


# Убираем первые 8 байт (метка gVpdInfo)
dd if="$BIN" of="$TMP_BIN" bs=1 skip=8 2>/dev/null

# Получаем HEX байт по одному в строке
hexdump -v -e '1/1 "%02X\n"' "$TMP_BIN" > "$TMP_HEX"

# Находим позиции всех разделителей 0x01
i=0
> "$TMP_POS"
while read -r byte; do
  if [ "$byte" = "01" ]; then
    echo "$i" >> "$TMP_POS"
  fi
  i=$((i + 1))
done < "$TMP_HEX"

# Идем по позициям, чередуем ключ-значение
set -- $(cat "$TMP_POS")
prev=0
idx=0

for pos in "$@"; do
  if [ $((idx % 2)) -eq 0 ]; then
    key_start=$prev
    key_len=$((pos - prev))
  else
    val_start=$((prev + 1))
    val_len=$((pos - val_start))

    key=$(dd if="$TMP_BIN" bs=1 skip=$key_start count=$key_len 2>/dev/null | tr '\017' '=' | tr '\014' '=' | tr '\013' '=' | tr '\012' '=' | tr '\011' '=' | tr '\002' '=' | tr '\006' '=' | tr '\015' ';' | tr '\021\' ';' | tr '\001' ';' | tr -d '\n' | sed 's/^=//g' | sed 's/^=//g' | sed 's/^=//g' | sed 's/^;//g' | sed 's/^;//g'  | sed 's/^; //g' | sed 's/^=//g')
    val=$(dd if="$TMP_BIN" bs=1 skip=$val_start count=$val_len 2>/dev/null | tr '\017' '=' | tr '\014' '=' | tr '\013' '=' | tr '\012' '=' | tr '\011' '=' | tr '\002' '=' | tr '\006' '=' | tr '\015' ';' | tr '\021\' ';' | tr '\001' ';' | tr -d '\n' | sed 's/^=//g' | sed 's/^=//g' | sed 's/^=//g' | sed 's/^;//g' | sed 's/^;//g'  | sed 's/^; //g' | sed 's/^=//g')
    echo $key
    echo $val
  fi
  prev=$pos
  idx=$((idx + 1))
done

