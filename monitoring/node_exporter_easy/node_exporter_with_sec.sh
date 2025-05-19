#!/bin/bash

# Скрипт для установки и настройки Node Exporter
# с Basic Auth и самоподписанным SSL-сертификатом (с SAN)

# --- BEGIN USER CONFIGURATION ---
# Пожалуйста, заполните эти переменные перед запуском скрипта.

NODE_EXPORTER_VERSION="1.9.1"                 # Желаемая версия Node Exporter (например, "1.8.1")
                                              # Проверьте последнюю стабильную версию на GitHub.
NODE_EXPORTER_PORT="9100"                     # Порт, на котором будет слушать Node Exporter (например, "9100")
NODE_EXPORTER_CONFIG_DIR="/etc/node_exporter" # Директория для конфигурационных файлов Node Exporter (tls, web-config.yml)
                                              # Должен быть абсолютным путем.

HOSTNAME_JOB_NAME="node_exporter_$(hostname -s)" # Уникальное имя для этого экземпляра экспортера
                                              # (например, "node_exporter_server_A").
                                              # По умолчанию используется короткое имя хоста.
                                              # Это имя будет использовано в CN/SAN сертификата и в имени job'а Prometheus.
SERVER_IP=""                                  # IP-адрес этого сервера (например, "192.168.1.100").
                                              # Оставьте пустым для попытки автоопределения (требуется команда 'ip').
BASIC_AUTH_USER="prom_node_user"              # Имя пользователя для Basic Authentication
BASIC_AUTH_PASSWORD="ЗАМЕНИТЕ_НА_НАДЕЖНЫЙ_ПАРОЛЬ" # Пароль для Basic Authentication (ОБЯЗАТЕЛЬНО ИЗМЕНИТЕ!)

# --- END USER CONFIGURATION ---

# --- Начало выполнения скрипта ---

# Функция для вывода сообщений об ошибках и выхода
error_exit() {
    echo "ОШИБКА: $1" >&2
    exit 1
}

# Проверка, запущен ли скрипт от имени root
if [ "$(id -u)" -ne 0 ]; then
    error_exit "Этот скрипт должен быть запущен от имени root. Пожалуйста, используйте sudo."
fi

# Валидация пользовательских вводов
echo "--- Проверка конфигурации пользователя ---"
if [ -z "$NODE_EXPORTER_VERSION" ]; then
    error_exit "Переменная NODE_EXPORTER_VERSION не установлена."
fi
if ! [[ "$NODE_EXPORTER_PORT" =~ ^[0-9]+$ ]] || [ "$NODE_EXPORTER_PORT" -lt 1 ] || [ "$NODE_EXPORTER_PORT" -gt 65535 ]; then
    error_exit "Переменная NODE_EXPORTER_PORT должна быть числом от 1 до 65535."
fi
if [[ -z "$NODE_EXPORTER_CONFIG_DIR" ]] || [[ "${NODE_EXPORTER_CONFIG_DIR:0:1}" != "/" ]]; then
    error_exit "Переменная NODE_EXPORTER_CONFIG_DIR должна быть установлена и являться абсолютным путем (начинаться с '/')."
fi
if [ -z "$HOSTNAME_JOB_NAME" ]; then
    error_exit "Переменная HOSTNAME_JOB_NAME не установлена."
fi
if [ -z "$BASIC_AUTH_USER" ]; then
    error_exit "Переменная BASIC_AUTH_USER не установлена."
fi
if [ "$BASIC_AUTH_PASSWORD" == "ЗАМЕНИТЕ_НА_НАДЕЖНЫЙ_ПАРОЛЬ" ] || [ -z "$BASIC_AUTH_PASSWORD" ]; then
    error_exit "Переменная BASIC_AUTH_PASSWORD не установлена или все еще является значением по умолчанию. Пожалуйста, установите надежный пароль."
fi

# Автоопределение IP, если не установлен
if [ -z "$SERVER_IP" ]; then
    echo "Попытка автоопределения IP-адреса сервера..."
    SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(ip -4 addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -n 1)
    fi

    if [ -z "$SERVER_IP" ]; then
        error_exit "Не удалось автоматически определить SERVER_IP. Пожалуйста, установите его вручную в скрипте."
    else
        echo "Автоматически определенный SERVER_IP: $SERVER_IP"
        read -p "Это корректный IP-адрес? (y/N): " confirm_ip
        if [[ ! "$confirm_ip" =~ ^[Yy]$ ]]; then
            error_exit "IP-адрес не подтвержден. Пожалуйста, установите SERVER_IP вручную и перезапустите скрипт."
        fi
    fi
fi
echo "Используемый SERVER_IP: $SERVER_IP"
echo "Используемое имя для CN/SAN/Job: $HOSTNAME_JOB_NAME"
echo "Node Exporter будет слушать на порту: $NODE_EXPORTER_PORT"
echo "Конфигурационные файлы Node Exporter будут размещены в: $NODE_EXPORTER_CONFIG_DIR"
echo "-----------------------------------------"

# 1. Установка зависимостей (htpasswd, openssl)
echo "--- Установка зависимостей ---"
if command -v apt-get &> /dev/null; then
    if ! dpkg -s apache2-utils &> /dev/null || ! dpkg -s openssl &> /dev/null; then
        echo "Установка apache2-utils и openssl с помощью apt-get..."
        apt-get update > /dev/null
        apt-get install -y apache2-utils openssl || error_exit "Не удалось установить зависимости с помощью apt-get."
    else
        echo "Зависимости apache2-utils и openssl уже установлены (Debian/Ubuntu)."
    fi
elif command -v yum &> /dev/null; then
    if ! rpm -q httpd-tools &> /dev/null || ! rpm -q openssl &> /dev/null; then
        echo "Установка httpd-tools и openssl с помощью yum..."
        yum install -y httpd-tools openssl || error_exit "Не удалось установить зависимости с помощью yum."
    else
        echo "Зависимости httpd-tools и openssl уже установлены (RHEL/CentOS)."
    fi
elif command -v dnf &> /dev/null; then
     if ! rpm -q httpd-tools &> /dev/null || ! rpm -q openssl &> /dev/null; then
        echo "Установка httpd-tools и openssl с помощью dnf..."
        dnf install -y httpd-tools openssl || error_exit "Не удалось установить зависимости с помощью dnf."
    else
        echo "Зависимости httpd-tools и openssl уже установлены (Fedora)."
    fi
else
    echo "Предупреждение: Не удалось определить менеджер пакетов. Убедитесь, что apache2-utils (или httpd-tools) и openssl установлены."
fi
echo "-----------------------------------------"

# 2. Скачивание и установка Node Exporter
echo "--- Установка Node Exporter v${NODE_EXPORTER_VERSION} ---"
echo "Скачивание Node Exporter..."
cd /tmp || error_exit "Не удалось перейти в директорию /tmp"
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" -O node_exporter.tar.gz || error_exit "Не удалось скачать Node Exporter."

echo "Извлечение Node Exporter..."
tar xvfz node_exporter.tar.gz || error_exit "Не удалось извлечь Node Exporter."

echo "Установка бинарного файла Node Exporter..."
mv "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/ || error_exit "Не удалось переместить бинарный файл Node Exporter."

echo "Очистка загруженных файлов..."
rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64" node_exporter.tar.gz
echo "-----------------------------------------"

# 3. Создание пользователя и директорий
echo "--- Настройка пользователя и директорий ---"
echo "Создание системного пользователя 'node_exporter'..."
if ! id "node_exporter" &>/dev/null; then
    useradd --system --no-create-home --shell /bin/false node_exporter || error_exit "Не удалось создать пользователя node_exporter."
else
    echo "Пользователь 'node_exporter' уже существует."
fi

NODE_EXPORTER_TLS_DIR="${NODE_EXPORTER_CONFIG_DIR}/tls"
echo "Создание конфигурационных директорий в ${NODE_EXPORTER_CONFIG_DIR}..."
mkdir -p "${NODE_EXPORTER_TLS_DIR}" || error_exit "Не удалось создать директорию ${NODE_EXPORTER_TLS_DIR}."
echo "-----------------------------------------"

# 4. Генерация самоподписанного SSL-сертификата с SAN
echo "--- Генерация SSL-сертификата ---"
echo "Генерация самоподписанного SSL-сертификата с SANs..."
cd "${NODE_EXPORTER_TLS_DIR}" || error_exit "Не удалось перейти в ${NODE_EXPORTER_TLS_DIR}"

openssl req -x509 -newkey rsa:4096 \
    -keyout key.pem -out cert.pem \
    -days 3650 -nodes \
    -subj "/CN=${HOSTNAME_JOB_NAME}" \
    -addext "subjectAltName = DNS:${HOSTNAME_JOB_NAME},IP:${SERVER_IP}" || error_exit "Не удалось сгенерировать SSL-сертификат."
echo "SSL-сертификат и ключ сгенерированы в ${NODE_EXPORTER_TLS_DIR}/"
echo "-----------------------------------------"

# 5. Генерация хеша Basic Auth и создание web-config.yml
echo "--- Настройка Basic Authentication ---"
echo "Генерация хеша пароля для Basic Auth..."
NODE_EXPORTER_USER_HASH=$(printf "%s\n" "$BASIC_AUTH_PASSWORD" | htpasswd -nBC 12 -i "$BASIC_AUTH_USER" 2>/dev/null | cut -d ':' -f2)
if [ -z "$NODE_EXPORTER_USER_HASH" ]; then
    error_exit "Не удалось сгенерировать хеш пароля. Убедитесь, что htpasswd установлен и работает корректно."
fi

WEB_CONFIG_FILE_PATH="${NODE_EXPORTER_CONFIG_DIR}/web-config.yml"
echo "Создание файла ${WEB_CONFIG_FILE_PATH}..."
cat <<EOF > "${WEB_CONFIG_FILE_PATH}"
tls_server_config:
  cert_file: "${NODE_EXPORTER_TLS_DIR}/cert.pem"
  key_file: "${NODE_EXPORTER_TLS_DIR}/key.pem"

basic_auth_users:
  ${BASIC_AUTH_USER}: "${NODE_EXPORTER_USER_HASH}"
EOF
if [ $? -ne 0 ]; then
    error_exit "Не удалось создать ${WEB_CONFIG_FILE_PATH}."
fi
echo "Файл ${WEB_CONFIG_FILE_PATH} создан."
echo "-----------------------------------------"

# 6. Установка прав
echo "--- Установка прав доступа ---"
chown -R node_exporter:node_exporter "${NODE_EXPORTER_CONFIG_DIR}" || error_exit "Не удалось изменить владельца ${NODE_EXPORTER_CONFIG_DIR}."
chmod 750 "${NODE_EXPORTER_CONFIG_DIR}"
chmod 640 "${WEB_CONFIG_FILE_PATH}"
chmod 640 "${NODE_EXPORTER_TLS_DIR}/cert.pem"
chmod 400 "${NODE_EXPORTER_TLS_DIR}/key.pem" # Только чтение для владельца (node_exporter)
echo "Права доступа установлены."
echo "-----------------------------------------"

# 7. Создание Systemd сервиса
echo "--- Настройка Systemd сервиса ---"
echo "Создание файла сервиса Systemd для Node Exporter..."
cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter (v${NODE_EXPORTER_VERSION}) for Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
Restart=on-failure
ExecStart=/usr/local/bin/node_exporter \
    --web.listen-address=":${NODE_EXPORTER_PORT}" \
    --web.config.file="${WEB_CONFIG_FILE_PATH}"

[Install]
WantedBy=multi-user.target
EOF
if [ $? -ne 0 ]; then
    error_exit "Не удалось создать файл systemd сервиса."
fi

echo "Перезагрузка демона Systemd, включение и запуск сервиса Node Exporter..."
systemctl daemon-reload || error_exit "Не удалось перезагрузить демон systemd."
systemctl enable node_exporter || error_exit "Не удалось включить сервис node_exporter."
systemctl start node_exporter || error_exit "Не удалось запустить сервис node_exporter."

# Даем немного времени на запуск
sleep 3
echo "Текущий статус сервиса node_exporter:"
systemctl status node_exporter --no-pager
echo "-----------------------------------------"

# 8. Вывод информации
echo ""
echo "--- Установка Node Exporter завершена ---"
echo ""
echo "Node Exporter (версия ${NODE_EXPORTER_VERSION}) установлен и запущен."
echo "Он слушает на https://${SERVER_IP}:${NODE_EXPORTER_PORT}/metrics"
echo ""
echo "Данные для Basic Authentication:"
echo "  Имя пользователя: ${BASIC_AUTH_USER}"
echo "  Пароль: ${BASIC_AUTH_PASSWORD} (Это оригинальный пароль, который вы установили)"
echo ""
echo "Информация о SSL-сертификате:"
echo "  Публичный SSL-сертификат (cert.pem) находится здесь: ${NODE_EXPORTER_TLS_DIR}/cert.pem"
echo "  ВАМ НУЖНО СКОПИРОВАТЬ ЭТОТ ФАЙЛ (cert.pem) на ваш сервер Prometheus"
echo "  и настроить Prometheus доверять ему."
echo "  Пример имени файла на хосте Prometheus: ./prometheus/certs_for_prometheus/${HOSTNAME_JOB_NAME}.pem"
echo ""
echo "Пример конфигурации для сбора метрик в Prometheus (добавьте в prometheus.yml):"
cat <<PROMETHEUS_EOF

  - job_name: '${HOSTNAME_JOB_NAME}'
    scheme: https
    metrics_path: /metrics
    static_configs:
      - targets: ['${SERVER_IP}:${NODE_EXPORTER_PORT}']
    basic_auth:
      username: '${BASIC_AUTH_USER}'
      password: '${BASIC_AUTH_PASSWORD}' # Здесь используется ОРИГИНАЛЬНЫЙ пароль
    tls_config:
      ca_file: '/etc/prometheus/certs_for_exporters/${HOSTNAME_JOB_NAME}.pem' # Путь внутри контейнера Prometheus
      server_name: '${HOSTNAME_JOB_NAME}' # Должен совпадать с CN/DNS SAN в сертификате
PROMETHEUS_EOF
echo ""
echo "Не забудьте заменить '/etc/prometheus/certs_for_exporters/${HOSTNAME_JOB_NAME}.pem' на актуальный"
echo "путь, по которому вы разместите CA-сертификат в вашей конфигурации Prometheus (например, Docker volume mount)."
echo "Значение 'server_name' (${HOSTNAME_JOB_NAME}) должно точно совпадать с CN/DNS SAN, использованным при генерации сертификата."
echo "--- Скрипт завершен ---"
