#!/bin/bash

# Скрипт для установки и настройки Node Exporter
# с Basic Auth и SSL-сертификатом от Let's Encrypt (HTTP-01, без email).
# Включает опцию для чистой переустановки с принудительным обновлением сертификата.

# --- BEGIN USER CONFIGURATION ---
# Пожалуйста, заполните эти переменные перед запуском скрипта.

NODE_EXPORTER_VERSION="1.9.1"                 # Желаемая версия Node Exporter (например, "1.8.1")
                                              # Проверьте последнюю стабильную версию на GitHub.
NODE_EXPORTER_PORT="9100"                     # Порт, на котором будет слушать Node Exporter (например, "9100")
NODE_EXPORTER_CONFIG_DIR="/etc/node_exporter" # Директория для конфигурационных файлов Node Exporter (tls, web-config.yml)
                                              # Должен быть абсолютным путем.

DNS_NAME="node-exporter.your-domain.com"      # Полное DNS-имя, для которого будет выпущен сертификат
                                              # (например, "node-exporter.example.com").
                                              # Убедитесь, что A-запись указывает на этот сервер.

BASIC_AUTH_USER="prom_node_user"              # Имя пользователя для Basic Authentication
BASIC_AUTH_PASSWORD="ЗАМЕНИТЕ_НА_НАДЕЖНЫЙ_ПАРОЛЬ" # Пароль для Basic Authentication (ОБЯЗАТЕЛЬНО ИЗМЕНИТЕ!)

CLEAN_INSTALL="false"                         # Установить в "true" для удаления предыдущей установки Node Exporter
                                              # и принудительного перевыпуска сертификата Let's Encrypt.
                                              # ВНИМАНИЕ: Это приведет к удалению существующих конфигураций node_exporter!
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
if [ -z "$DNS_NAME" ] || [[ "$DNS_NAME" != *"."* ]]; then
    error_exit "Переменная DNS_NAME не установлена или выглядит некорректно. Укажите полное доменное имя."
fi
if [ "$DNS_NAME" == "node-exporter.your-domain.com" ] && [ "$CLEAN_INSTALL" == "false" ]; then
    read -p "DNS_NAME все еще установлен как 'node-exporter.your-domain.com'. Вы уверены, что хотите продолжить с этим значением? (yes/NO): " confirm_dns
    if [[ ! "$confirm_dns" =~ ^[Yy][Ee][Ss]$ ]]; then
        error_exit "Пожалуйста, измените значение по умолчанию для DNS_NAME."
    fi
fi
if [ -z "$BASIC_AUTH_USER" ]; then
    error_exit "Переменная BASIC_AUTH_USER не установлена."
fi
if [ "$BASIC_AUTH_PASSWORD" == "ЗАМЕНИТЕ_НА_НАДЕЖНЫЙ_ПАРОЛЬ" ] || [ -z "$BASIC_AUTH_PASSWORD" ]; then
    error_exit "Переменная BASIC_AUTH_PASSWORD не установлена или все еще является значением по умолчанию. Пожалуйста, установите надежный пароль."
fi
if [[ "$CLEAN_INSTALL" != "true" ]] && [[ "$CLEAN_INSTALL" != "false" ]]; then
    error_exit "Переменная CLEAN_INSTALL должна быть 'true' или 'false'."
fi

echo "Используемое DNS-имя: $DNS_NAME"
echo "Node Exporter будет слушать на порту: $NODE_EXPORTER_PORT"
echo "Конфигурационные файлы Node Exporter будут размещены в: $NODE_EXPORTER_CONFIG_DIR"
if [ "$CLEAN_INSTALL" == "true" ]; then
    echo "РЕЖИМ ЧИСТОЙ УСТАНОВКИ: АКТИВИРОВАН (с принудительным обновлением сертификата)"
fi
echo "-----------------------------------------"


# --- БЛОК ЧИСТОЙ УСТАНОВКИ (если CLEAN_INSTALL="true") ---
if [ "$CLEAN_INSTALL" == "true" ]; then
    echo ""
    echo "--- ВНИМАНИЕ: Активирован режим ЧИСТОЙ УСТАНОВКИ ---"
    echo "Будут предприняты попытки удалить существующие компоненты Node Exporter,"
    echo "конфигурации из '${NODE_EXPORTER_CONFIG_DIR}'. Сертификат Let's Encrypt для '${DNS_NAME}' будет принудительно обновлен."
    read -p "Вы АБСОЛЮТНО уверены, что хотите продолжить? Это действие необратимо для конфигурации Node Exporter! (введите 'yes' для подтверждения): " confirm_clean
    if [[ "$confirm_clean" != "yes" ]]; then
        error_exit "Чистая установка отменена пользователем."
    fi

    echo "Остановка и отключение сервиса node_exporter..."
    systemctl stop node_exporter.service >/dev/null 2>&1
    systemctl disable node_exporter.service >/dev/null 2>&1
    
    echo "Удаление файла сервиса node_exporter..."
    rm -f /etc/systemd/system/node_exporter.service
    systemctl daemon-reload >/dev/null 2>&1 

    echo "Удаление бинарного файла node_exporter (/usr/local/bin/node_exporter)..."
    rm -f /usr/local/bin/node_exporter

    echo "Удаление конфигурационной директории ${NODE_EXPORTER_CONFIG_DIR}..."
    rm -rf "${NODE_EXPORTER_CONFIG_DIR}"
    
    # Удаление deploy-hook скрипта, если он специфичен для этого DNS_NAME
    if command -v certbot &> /dev/null; then
        POTENTIAL_DEPLOY_HOOK_SCRIPT="/etc/letsencrypt/renewal-hooks/deploy/node_exporter_deploy_hook.sh"
        if [ -f "$POTENTIAL_DEPLOY_HOOK_SCRIPT" ]; then
            if grep -q "LE_DOMAIN=\"${DNS_NAME}\"" "$POTENTIAL_DEPLOY_HOOK_SCRIPT"; then
                 echo "Удаление deploy-hook скрипта: ${POTENTIAL_DEPLOY_HOOK_SCRIPT}"
                 rm -f "$POTENTIAL_DEPLOY_HOOK_SCRIPT"
            else
                echo "Предупреждение: Deploy-hook скрипт ${POTENTIAL_DEPLOY_HOOK_SCRIPT} не содержит упоминания ${DNS_NAME} в LE_DOMAIN. Пропускаем удаление хука."
            fi
        fi
    else
        echo "Certbot не найден, пропускаем удаление deploy-hook."
    fi

    echo "--- Процесс очистки конфигурации Node Exporter завершен ---"
    echo ""
fi
# --- КОНЕЦ БЛОКА ЧИСТОЙ УСТАНОВКИ ---


# 1. Установка зависимостей (htpasswd, curl, certbot)
echo "--- Установка зависимостей ---"
PKG_MANAGER=""
if command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt-get"
    PKG_UPDATE_CMD="apt-get update -qq"
    PKG_INSTALL_CMD="apt-get install -y -qq"
    APACHE_UTILS_PKG="apache2-utils"
    CURL_PKG="curl"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
    PKG_INSTALL_CMD="yum install -y -q"
    APACHE_UTILS_PKG="httpd-tools"
    CURL_PKG="curl"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
    PKG_INSTALL_CMD="dnf install -y -q"
    APACHE_UTILS_PKG="httpd-tools"
    CURL_PKG="curl"
else
    error_exit "Не удалось определить менеджер пакетов (apt, yum, dnf). Установите зависимости вручную."
fi

echo "Установка ${APACHE_UTILS_PKG} и ${CURL_PKG}..."
if [ -n "$PKG_UPDATE_CMD" ]; then
    $PKG_UPDATE_CMD
fi
$PKG_INSTALL_CMD $APACHE_UTILS_PKG $CURL_PKG || error_exit "Не удалось установить ${APACHE_UTILS_PKG} или ${CURL_PKG}."

echo "Установка Certbot..."
if ! command -v certbot &> /dev/null; then
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        $PKG_INSTALL_CMD software-properties-common || echo "Не удалось установить software-properties-common, продолжаем..."
        $PKG_INSTALL_CMD certbot || error_exit "Не удалось установить certbot через apt. Попробуйте установить его вручную (например, через snap: sudo snap install --classic certbot)."
    elif [[ "$PKG_MANAGER" == "yum" ]]; then
        $PKG_INSTALL_CMD epel-release || echo "Не удалось установить epel-release, продолжаем..."
        $PKG_INSTALL_CMD certbot || error_exit "Не удалось установить certbot через yum. Попробуйте установить его вручную."
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
        $PKG_INSTALL_CMD certbot || error_exit "Не удалось установить certbot через dnf. Попробуйте установить его вручную."
    fi
    if ! command -v certbot &> /dev/null; then
        error_exit "Certbot не был установлен. Пожалуйста, установите его вручную и перезапустите скрипт."
    fi
else
    echo "Certbot уже установлен."
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
chown -R node_exporter:node_exporter "${NODE_EXPORTER_CONFIG_DIR}"
chmod 750 "${NODE_EXPORTER_CONFIG_DIR}"
chmod 700 "${NODE_EXPORTER_TLS_DIR}"
echo "-----------------------------------------"

# 4. Получение SSL-сертификата от Let's Encrypt
echo "--- Получение/Обновление SSL-сертификата от Let's Encrypt для ${DNS_NAME} ---"

if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null ; then
    error_exit "Порт 80 занят. Certbot в режиме standalone не сможет получить/обновить сертификат. Освободите порт 80."
fi
echo "Порт 80 свободен, продолжаем с certbot standalone."

DEPLOY_HOOK_SCRIPT="/etc/letsencrypt/renewal-hooks/deploy/node_exporter_deploy_hook.sh"
mkdir -p "$(dirname "$DEPLOY_HOOK_SCRIPT")"
cat <<EOF > "$DEPLOY_HOOK_SCRIPT"
#!/bin/bash
# Deploy hook для Node Exporter

LE_DOMAIN="${DNS_NAME}"
NE_TLS_DIR="${NODE_EXPORTER_TLS_DIR}"
NE_USER="node_exporter"

cp "/etc/letsencrypt/live/\${LE_DOMAIN}/fullchain.pem" "\${NE_TLS_DIR}/cert.pem"
cp "/etc/letsencrypt/live/\${LE_DOMAIN}/privkey.pem" "\${NE_TLS_DIR}/key.pem"

chown \${NE_USER}:\${NE_USER} "\${NE_TLS_DIR}/cert.pem" "\${NE_TLS_DIR}/key.pem"
chmod 600 "\${NE_TLS_DIR}/cert.pem" 
chmod 400 "\${NE_TLS_DIR}/key.pem"

if systemctl is-active --quiet node_exporter.service; then
  echo "Перезапуск Node Exporter после обновления сертификата для \${LE_DOMAIN}..."
  systemctl restart node_exporter.service
else
  echo "Node Exporter не активен, перезапуск не требуется для \${LE_DOMAIN}."
fi
exit 0
EOF
chmod +x "$DEPLOY_HOOK_SCRIPT"
echo "Deploy hook создан/обновлен: $DEPLOY_HOOK_SCRIPT"

certbot_args=(
    certonly
    --standalone
    -d "${DNS_NAME}"
    --agree-tos
    --register-unsafely-without-email
    --non-interactive
    --deploy-hook "$DEPLOY_HOOK_SCRIPT"
    --preferred-challenges http
)

if [ "$CLEAN_INSTALL" == "true" ]; then
    certbot_args+=(--force-renewal)
    echo "INFO: Флаг --force-renewal будет использован для certbot из-за CLEAN_INSTALL=true."
fi

echo "Запрос/обновление сертификата с помощью Certbot..."
certbot "${certbot_args[@]}" || error_exit "Не удалось получить/обновить SSL-сертификат от Let's Encrypt."

echo "Первоначальный/повторный запуск deploy-hook для копирования сертификатов..."
if [ -f "$DEPLOY_HOOK_SCRIPT" ]; then
    bash "$DEPLOY_HOOK_SCRIPT" || echo "Предупреждение: Запуск deploy-hook завершился с ошибкой, проверьте логи."
else
    error_exit "Deploy hook скрипт не найден по пути $DEPLOY_HOOK_SCRIPT."
fi

if [ ! -f "${NODE_EXPORTER_TLS_DIR}/cert.pem" ] || [ ! -f "${NODE_EXPORTER_TLS_DIR}/key.pem" ]; then
    error_exit "Сертификаты не были скопированы в ${NODE_EXPORTER_TLS_DIR}. Проверьте вывод certbot и deploy-hook."
fi
echo "SSL-сертификат получен/обновлен и скопирован в ${NODE_EXPORTER_TLS_DIR}/"
echo "-----------------------------------------"

# 5. Генерация хеша Basic Auth и создание web-config.yml
echo "--- Настройка Basic Authentication ---"
NODE_EXPORTER_USER_HASH=$(printf "%s\n" "$BASIC_AUTH_PASSWORD" | htpasswd -nBC 12 -i "$BASIC_AUTH_USER" 2>/dev/null | cut -d ':' -f2)
if [ -z "$NODE_EXPORTER_USER_HASH" ]; then
    error_exit "Не удалось сгенерировать хеш пароля."
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
chown node_exporter:node_exporter "${WEB_CONFIG_FILE_PATH}"
chmod 640 "${WEB_CONFIG_FILE_PATH}"
echo "Файл ${WEB_CONFIG_FILE_PATH} создан."
echo "-----------------------------------------"

# 6. Установка прав на конфигурационные файлы (повторная проверка)
echo "--- Проверка прав доступа ---"
chown -R node_exporter:node_exporter "${NODE_EXPORTER_CONFIG_DIR}"
chmod 750 "${NODE_EXPORTER_CONFIG_DIR}" 
chmod 700 "${NODE_EXPORTER_TLS_DIR}"    
chmod 640 "${WEB_CONFIG_FILE_PATH}"     
if [ -f "${NODE_EXPORTER_TLS_DIR}/cert.pem" ]; then
    chmod 600 "${NODE_EXPORTER_TLS_DIR}/cert.pem"
    chown node_exporter:node_exporter "${NODE_EXPORTER_TLS_DIR}/cert.pem"
fi
if [ -f "${NODE_EXPORTER_TLS_DIR}/key.pem" ]; then
    chmod 400 "${NODE_EXPORTER_TLS_DIR}/key.pem"
    chown node_exporter:node_exporter "${NODE_EXPORTER_TLS_DIR}/key.pem"
fi
echo "Права доступа проверены/установлены."
echo "-----------------------------------------"

# 7. Создание Systemd сервиса
echo "--- Настройка Systemd сервиса ---"
cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter (v${NODE_EXPORTER_VERSION}) for Prometheus (Let's Encrypt)
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

systemctl daemon-reload || error_exit "Не удалось перезагрузить демон systemd."
systemctl enable node_exporter || error_exit "Не удалось включить сервис node_exporter."
systemctl restart node_exporter || error_exit "Не удалось запустить/перезапустить сервис node_exporter." # restart вместо start

sleep 3
echo "Текущий статус сервиса node_exporter:"
systemctl status node_exporter --no-pager
echo "-----------------------------------------"

# 8. Настройка автоматического обновления сертификата Certbot
echo "--- Настройка автоматического обновления сертификатов Certbot ---"
if ! systemctl list-timers | grep -q 'certbot.timer'; then
    if ! (crontab -l 2>/dev/null | grep -q 'certbot renew'); then
        echo "Добавление cronjob для 'certbot renew'..."
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --deploy-hook \"$DEPLOY_HOOK_SCRIPT\"") | crontab -
        echo "Cronjob для 'certbot renew' добавлен."
    else
        echo "Cronjob для 'certbot renew' уже существует."
        echo "Убедитесь, что он включает --deploy-hook \"$DEPLOY_HOOK_SCRIPT\"."
    fi
else
    echo "Systemd таймер 'certbot.timer' найден."
    echo "Убедитесь, что deploy-hook ($DEPLOY_HOOK_SCRIPT) корректно настроен."
fi
echo "-----------------------------------------"

# 9. Вывод информации
echo ""
echo "--- Установка/Обновление Node Exporter с Let's Encrypt завершена ---"
echo ""
echo "Node Exporter (версия ${NODE_EXPORTER_VERSION}) установлен и запущен."
echo "Он слушает на https://${DNS_NAME}:${NODE_EXPORTER_PORT}/metrics"
echo "Убедитесь, что порт ${NODE_EXPORTER_PORT} открыт в вашем файрволе для доступа Prometheus."
echo ""
echo "Данные для Basic Authentication:"
echo "  Имя пользователя: ${BASIC_AUTH_USER}"
echo "  Пароль: ${BASIC_AUTH_PASSWORD}"
echo ""
echo "SSL-сертификат от Let's Encrypt для ${DNS_NAME} получен/обновлен и настроен."
echo "Автоматическое обновление сертификатов настроено через Certbot."
echo ""
echo "Пример конфигурации для сбора метрик в Prometheus (prometheus.yml):"
cat <<PROMETHEUS_EOF

  - job_name: 'node_exporter_${DNS_NAME//./_}' 
    scheme: https
    metrics_path: /metrics
    static_configs:
      - targets: ['${DNS_NAME}:${NODE_EXPORTER_PORT}']
    basic_auth:
      username: '${BASIC_AUTH_USER}'
      password: '${BASIC_AUTH_PASSWORD}'
    tls_config:
      server_name: '${DNS_NAME}'
PROMETHEUS_EOF
echo ""
echo "--- Скрипт завершен ---"
