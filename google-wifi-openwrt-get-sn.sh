#!/bin/sh
# Скрипт извлекает серийный номер устройства Google WiFi из дампа памяти.
# Ниже приведён пример дампа, прочитанного из EEPROM, с комментариями:
# 
# 00000000: ffff ffff ffff ffff ffff ffff ffff ffff  ................
# 00000010: ffff ffff ffff ffff ffff ffff ffff ffff  ................
# 00000020: ffff ffff ffff ffff ffff ffff ffff ffff  ................
# 00000030: ffff ffff ffff ffff ffff ffff ffff ffff  ................
# 00000040: ffff ffff ffff ffff ffff ffff ffff ffff  ................
# 00000050: ffff ffff ffff ffff ffff ffff ffff ffff  ................
# 00000060: ffff ffff ffff fffe 0901 6756 7064 496e  ..........gVpdIn
# 00000070: 666f 040d 7f00 0001 0d65 7468 6572 6e65  fo.......etherne
# 00000080: 745f 6d61 6330 0c34 3430 3730 4232 3230  t_mac0.44070B220
# 00000090: 3141 3401 0d65 7468 6572 6e65 745f 6d61  1A4..ethernet_ma
# 000000a0: 6331 0c34 3430 3730 4232 3230 3141 3501  c1.44070B2201A5.
# 000000b0: 116d 6c62 5f73 6572 6961 6c5f 6e75 6d62  .mlb_serial_numb
# 000000c0: 6572 0f4e 4a4f 4b49 3338 3144 4346 3258  er.NJOKI381DCF2X   <-- MLB серийный номер
# 000000d0: 3031 010a 6d6f 6465 6c5f 6e61 6d65 0641  01..model_name.A
# 000000e0: 4331 3330 3401 0672 6567 696f 6e02 7573  C1304..region.us
# 000000f0: 010d 7365 7269 616c 5f6e 756d 6265 720b  ..serial_number.
# 00000100: 3239 3139 4857 3030 3548 3001 0973 6574  2919HW005H0..set <-- Серийный номер устройства
# 00000110: 7570 5f70 736b 0976 6e62 7167 6874 6e6e  up_psk.vnbqghtnn
# 00000120: 010a 7365 7475 705f 7373 6964 0a73 6574  ..setup_ssid.set
# 00000130: 7570 3031 4142 3001 1877 6966 695f 6261  up01AB0..wifi_ba
# 00000140: 7365 3634 5f63 616c 6962 7261 7469 6f6e  se64_calibration
# 00000150: 31fd 5849 4339 4541 6745 4252 4163 4c49  1.XIC9EAgEBRAcLI
# 00000160: 6747 6e41 4141 6741 4257 6741 4141 4159  gGnAAAgABWgAAAAY
# 00000170: 4141 4146 5163 4141 4141 4141 4141 5641  AAAFQcAAAAAAAAVA
# 00000180: 4141 4f4d 7741 4141 4141 4141 4141 4141  AAOMwAAAAAAAAAAA
#
# Эти данные используются для поиска ключей вроде "serial_number" и "mlb_serial_number",
# за которыми следуют значения — они и извлекаются скриптом.

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

