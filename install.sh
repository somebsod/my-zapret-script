#!/bin/bash

# Проверка прав
if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Запустите от имени root (sudo)"
  exit 1
fi

echo "--- Инициализация системы автоподбора Zapret ---"

# 1. Очистка и установка зависимостей
rm -rf /opt/zapret
apt update && apt install -y git make gcc libc-dev libnetfilter-queue-dev libpcap-dev \
libpcre3-dev zlib1g-dev iptables curl whiptail

# 2. Скачивание и сборка
git clone --depth=1 https://github.com/bol-van/zapret.git /opt/zapret
make -C /opt/zapret

# 3. АВТОПОДБОР КОНФИГУРАЦИИ (Fast Mode)
echo "Начинаем автоматический поиск рабочей стратегии для YouTube..."
echo "Это может занять 2-3 минуты. Скрипт проверяет разные методы обхода..."

# Создаем временный файл для результата теста
CHECK_LOG="/tmp/zapret_check.log"
# Запускаем blockcheck только для youtube.com в неинтерактивном режиме
/opt/zapret/blockcheck.sh --quick --domain=googlevideo.com > $CHECK_LOG

# Вырезаем лучшую стратегию из лога
# Ищем строку, которая предлагает параметры для nfqws
BEST_STRATEGY=$(grep -m 1 "nfqws --" $CHECK_LOG | sed 's/.*nfqws --//')

if [ -z "$BEST_STRATEGY" ]; then
    echo "Автоподбор не смог найти идеальную стратегию. Используем универсальную (split2)."
    BEST_STRATEGY="--disorder --ttl=1 --dpi-desync=split2"
else
    echo "Найдена оптимальная стратегия: $BEST_STRATEGY"
fi

# 4. Применение настроек в основной конфиг
cat << EOF > /opt/zapret/config
FWTYPE=iptables
SET_MAXELEM=522288
IPSET_OPT="hashsize 262144 maxelem \$SET_MAXELEM"
NFQWS_OPT_DESYNC="$BEST_STRATEGY"
MODE=nfqws
MODE_HTTP=1
MODE_HTTPS=1
MODE_QUIC=1
DESYNC_MARK=0x40000000
IFACE_LAN=eth0
EOF

# 5. Создание визуального скрипта "Матрица"
CAT_SCRIPT="/usr/local/bin/zapret-matrix.sh"
cat << 'EOF' > $CAT_SCRIPT
#!/bin/bash
clear
tput civis
draw_matrix() {
    for i in {1..20}; do
        tput setaf 2
        printf "\e[$((RANDOM%LINES));$((RANDOM%COLUMNS))f%s" $(printf "\\x$(printf %x $((33 + RANDOM%94)))")
    done
}

while true; do
    draw_matrix
    WIDTH=55; HEIGHT=12
    COL=$(( ( $(tput cols) - $WIDTH ) / 2 )); ROW=$(( ( $(tput lines) - $HEIGHT ) / 2 ))
    tput setaf 7
    tput cup $ROW $COL; printf "┌$(printf '─%.0s' $(seq 1 $WIDTH))┐"
    for i in $(seq 1 $HEIGHT); do tput cup $((ROW + i)) $COL; printf "│%${WIDTH}s│" " "; done
    tput cup $((ROW + HEIGHT)) $COL; printf "└$(printf '─%.0s' $(seq 1 $WIDTH))┘"

    IP=$(hostname -I | awk '{print $1}')
    tput bold; tput setaf 2
    tput cup $((ROW + 2)) $((COL + 15)); echo "ZAPRET SYSTEM CORE"
    tput setaf 7
    tput cup $((ROW + 4)) $((COL + 5)); echo "Status: RUNNING (AUTO-CONFIGURED)"
    tput cup $((ROW + 5)) $((COL + 5)); echo "Gateway IP: $IP"
    tput cup $((ROW + 7)) $((COL + 5)); echo "Target: YouTube (PC & Android TV)"
    tput cup $((ROW + 9)) $((COL + 5)); tput setaf 3; echo "TV Tip: Set DNS to 8.8.8.8 on your TV"
    sleep 0.1
done
EOF
chmod +x $CAT_SCRIPT

# 6. Финальные вопросы
if whiptail --title "Автозагрузка" --yesno "Добавить в автозагрузку наш скрипт?" 10 60; then
    cat << EOF > /etc/systemd/system/zapret-custom.service
[Unit]
Description=Zapret Matrix Launcher
After=network.target

[Service]
Type=simple
ExecStartPre=/opt/zapret/init.d/sysv/zapret start
ExecStart=$CAT_SCRIPT
StandardOutput=tty
TTYPath=/dev/tty1
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable zapret-custom.service
fi

if whiptail --title "Запуск" --yesno "Настройка завершена! Запустить сейчас?" 10 60; then
    /opt/zapret/init.d/sysv/zapret start
    bash $CAT_SCRIPT
fi
