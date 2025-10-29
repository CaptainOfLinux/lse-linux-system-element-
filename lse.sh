#!/usr/bin/env bash
# neofetch-lite.sh
# Basit, dayanıklı bir neofetch-benzeri betik
# İhtiyaç: coreutils, awk, sed, lsblk, df, uname, whoami, hostnamectl (isteğe bağlı),
#          sensors (lm-sensors), dmidecode (root), smartctl (smartmontools), lspci (pciutils), nvidia-smi (NVIDIA)

set -euo pipefail

# ---------- Helpers ----------
info() { printf "%-18s %s\n" "$1:" "$2"; }
sep() { printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' -; }

# Try command quietly
run_quiet() {
  command -v "$1" >/dev/null 2>&1
}

# ---------- ASCII ART (örnek küçük) ----------
ascii_art() {
cat <<'EOF'
            .-"""-.
           '       \
          |,.  ,-.  |
          |()L( ()| |
          |,'  `".| |
          |.___.',| `
         .j `--"' `  `.
        / '        '   \
       / /          `   `.
      / /            `    .
     / /              l   |
    . ,               |   |
    ,"`.             .|   |
 _.'   ``.          | `..-'l
|       `.`,        |      `.
|         `.    __.j         )
|__        |--""___|      ,-'
   `"--...,+""""   `._,.-'

EOF
}

# ---------- Basic identity ----------
USER_NAME=$(whoami 2>/dev/null || echo "Unknown")
HOSTNAME=$(hostname 2>/dev/null || echo "Unknown")

# OS & kernel
OS=""
if run_quiet hostnamectl; then
  OS=$(hostnamectl --pretty 2>/dev/null || hostnamectl 2>/dev/null | grep "Operating System" || true)
fi
# fallback to lsb_release or /etc/os-release
if [ -z "$OS" ] || [[ "$OS" == "" ]]; then
  if run_quiet lsb_release; then
    OS=$(lsb_release -ds 2>/dev/null || true)
  else
    if [ -f /etc/os-release ]; then
      . /etc/os-release
      OS="$PRETTY_NAME"
    fi
  fi
fi
OS=${OS:-"Unknown"}

KERNEL=$(uname -s 2>/dev/null || echo "Unknown")
KERNEL_VER=$(uname -r 2>/dev/null || echo "Unknown")
DISTRO_VER="${OS}"

# ---------- CPU ----------
CPU_MODEL=""
if run_quiet lscpu; then
  CPU_MODEL=$(lscpu 2>/dev/null | awk -F: '/Model name|Model name|Processor/{print $2; exit}' | sed 's/^ *//;s/ *$//')
fi
if [ -z "$CPU_MODEL" ]; then
  CPU_MODEL=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//;s/ *$//' || true)
fi
CPU_MODEL=${CPU_MODEL:-"Unknown"}

# ---------- CPU temp ----------
CPU_TEMP="Unknown"
if run_quiet sensors; then
  # prefer "Package id 0" or "CPU Temp"
  CPU_TEMP=$(sensors 2>/dev/null | awk '/Package id 0|Core 0|CPU Temperature|Physical id 0/ { gsub(/\+|°C/,""); print $2; exit }' || true)
fi
# fallback to /sys/class/thermal
if [[ -z "$CPU_TEMP" || "$CPU_TEMP" == "Unknown" ]]; then
  for f in /sys/class/thermal/thermal_zone*/temp; do
    if [ -f "$f" ]; then
      val=$(cat "$f" 2>/dev/null)
      # some are in millidegree
      if [ "$val" -gt 1000 ] 2>/dev/null; then
        CPU_TEMP=$(awk "BEGIN {printf \"%.1f C\", $val/1000}")
      else
        CPU_TEMP="$val C"
      fi
      break
    fi
  done
fi

# ---------- GPU ----------
GPU_MODEL="Unknown"
if run_quiet lspci; then
  GPU_MODEL=$(lspci 2>/dev/null | awk -F: '/VGA compatible controller|3D controller|Display controller/ { $1=""; sub(/^ /,""); print substr($0,1) ; exit }' | sed 's/^\s*//')
fi
# NVIDIA specific
if run_quiet nvidia-smi; then
  gpu_line=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || true)
  if [ -n "$gpu_line" ]; then GPU_MODEL="$gpu_line"; fi
fi
GPU_MODEL=${GPU_MODEL:-"Unknown"}

# ---------- GPU temp ----------
GPU_TEMP="Unknown"
if run_quiet nvidia-smi; then
  GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | awk '{print $1 " C"}' | head -n1 || true)
fi
# sensors fallback
if [[ -z "$GPU_TEMP" || "$GPU_TEMP" == "Unknown" ]]; then
  if run_quiet sensors; then
    GPU_TEMP=$(sensors 2>/dev/null | awk '/GPU|gpu/ {gsub(/\+|°C/,""); print $2; exit}' || true)
  fi
fi

# ---------- Fan speed / temp ----------
FAN_INFO="Unknown"
if run_quiet sensors; then
  FAN_INFO=$(sensors 2>/dev/null | awk '/fan[0-9]+:|Fan|RPM/ {print $0; exit}' || true)
fi
# /sys/class/hwmon fallback
if [[ -z "$FAN_INFO" || "$FAN_INFO" == "Unknown" ]]; then
  if compgen -G "/sys/class/hwmon/hwmon*/fan*_input" >/dev/null; then
    FAN_INFO=$(for f in /sys/class/hwmon/hwmon*/fan*_input; do echo "$(basename $(dirname $f)) $(basename $f): $(cat $f 2>/dev/null) RPM"; done | head -n1)
  fi
fi
FAN_INFO=${FAN_INFO:-"Unknown"}

# ---------- RAM ----------
TOTAL_RAM="Unknown"
USED_RAM="Unknown"
if run_quiet free; then
  read -r total used _ <<<$(free -m | awk '/Mem:/ {print $2, $3, $4}')
  if [ -n "$total" ]; then
    TOTAL_RAM="${total} MB"
    USED_RAM="${used} MB"
  fi
fi

# RAM model (requires dmidecode, root)
RAM_MODEL="Unknown (dmidecode required)"
if run_quiet dmidecode; then
  # try to get manufacturer+part number for first memory device
  if [ "$(id -u)" -eq 0 ]; then
    RAM_MODEL=$(dmidecode -t memory 2>/dev/null | awk -F: '/Manufacturer|Part Number|Size/ {printf "%s ", $2} /Locator/ {print "";}' | sed 's/  */ /g' | sed 's/^ *//; s/ *$//' | head -n1)
    RAM_MODEL=${RAM_MODEL:-"Unknown"}
  else
    RAM_MODEL="Run as root to get RAM model (dmidecode)"
  fi
fi

# ---------- Disks & partitions ----------
# List block devices with model
DISKS=$(lsblk -dn -o NAME,MODEL,SIZE 2>/dev/null | awk '{$1=$1;print}' || true)
# Disk usage per mount
DISK_USAGE=$(df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs | sed 1,1d)

# Try to get disk brand/model via lsblk & /sys
DISK_MODELS=""
while read -r name model size; do
  if [ -n "$name" ]; then
    DISK_MODELS+="$name: ${model:-Unknown} (${size})"$'\n'
  fi
done < <(lsblk -dn -o NAME,MODEL,SIZE 2>/dev/null | awk '{$1=$1;print}')
DISK_MODELS=${DISK_MODELS:-"Unknown (install lsblk)"}

# smartctl provides model info too (may require root)
SMART_HINT=""
if ! run_quiet smartctl; then
  SMART_HINT="Install smartmontools for detailed disk model/health info (sudo apt install smartmontools / pacman -S smartmontools)"
fi

# ---------- Username (who uses the machine) ----------
ACTIVE_USER="$USER_NAME"

# ---------- Internet connectivity ----------
PING_HOST="1.1.1.1"
NET_STATUS="Down"
if ping -c 1 -W 2 $PING_HOST >/dev/null 2>&1; then
  NET_STATUS="Up (can reach $PING_HOST)"
else
  NET_STATUS="Down (could not ping $PING_HOST)"
fi

# ---------- HDD free total ----------
TOTAL_FREE=$(df -h --total -x tmpfs -x devtmpfs | awk '/total/ {print $4 " free of " $2; exit}')
TOTAL_FREE=${TOTAL_FREE:-"Unknown"}

# ---------- Disk vendor/model via /sys/block (optional, root not required for vendor) ----------
DISK_SYS=""
for dev in /sys/block/*; do
  devname=$(basename "$dev")
  if [ -f "$dev/device/model" ]; then
    model=$(cat "$dev/device/model" 2>/dev/null | sed 's/^ *//;s/ *$//')
  else
    model=""
  fi
  if [ -f "$dev/device/vendor" ]; then
    vendor=$(cat "$dev/device/vendor" 2>/dev/null | sed 's/^ *//;s/ *$//')
  else
    vendor=""
  fi
  if [ -n "$model" ] || [ -n "$vendor" ]; then
    size=$(lsblk -dn -o SIZE /dev/$devname 2>/dev/null || echo "")
    DISK_SYS+="$devname: ${vendor} ${model} ${size}\n"
  fi
done
DISK_SYS=${DISK_SYS:-""}

# ---------- Output ----------
clear
ascii_art
sep
info "User" "$ACTIVE_USER"
info "Host" "$HOSTNAME"
info "OS" "$OS"
info "Distro version" "$DISTRO_VER"
info "Kernel" "$KERNEL $KERNEL_VER"
sep
info "CPU" "$CPU_MODEL"
info "CPU Temp" "$CPU_TEMP"
info "GPU" "$GPU_MODEL"
info "GPU Temp" "$GPU_TEMP"
info "Fan" "$FAN_INFO"
sep
info "RAM (total)" "$TOTAL_RAM"
info "RAM (used)" "$USED_RAM"
info "RAM Model" "$RAM_MODEL"
sep
echo "Disks (model & size):"
echo -e "$DISK_MODELS"
sep
echo "Partition / Mount usage:"
echo "$DISK_USAGE"
sep
info "Total disk free" "$TOTAL_FREE"
if [ -n "$DISK_SYS" ]; then
  echo
  echo "Disks (from /sys):"
  echo -e "$DISK_SYS"
fi
if [ -n "$SMART_HINT" ]; then
  echo
  echo "Note: $SMART_HINT"
fi
sep
info "Internet" "$NET_STATUS"
sep
echo "Hints:"
echo "- For more accurate temps/fans install and run lm-sensors (sudo sensors-detect) and smartmontools (smartctl)."
echo "- For RAM/disk models run as root to allow dmidecode / smartctl to access hardware."
echo
