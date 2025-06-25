#!/bin/bash

# Скрипт для установки и настройки Blackbox Exporter
# с Basic Auth и SSL-сертификатом от Let's Encrypt (HTTP-01, без email).
# Включает опцию для чистой переустановки с принудительным обновлением сертификата.

# --- BEGIN USER CONFIGURATION ---
# Пожалуйста, заполните эти переменные перед запуском скрипта.

BLACKBOX_EXPORTER_VERSION="0.26.0"            # Желаемая версия Blackbox Exporter (например, "0.25.0")
                                              # Проверьте последнюю стабильную версию на GitHub.
BLACKBOX_EXPORTER_PORT="9115"                 # Порт, на котором будет слушать Blackbox Exporter (например, "9115")
BLACKBOX_EXPORTER_CONFIG_DIR="/etc/blackbox_exporter" # Директория для конфигурационных файлов
                                              # (blackbox.yml, web-config.yml, tls)
                                              # Должен быть абсолютным путем.

DNS_NAME="example.com"           # Полное DNS-имя, для которого будет выпущен сертификат
                                              # (например, "blackbox.example.com").
                                              # Убедитесь, что A-запись указывает на этот сервер.

BASIC_AUTH_USER="black_user"          # Имя пользователя для Basic Authentication
BASIC_AUTH_PASSWORD="your_very_hard_pass" # Пароль для Basic Authentication (ОБЯЗАТЕЛЬНО ИЗМЕНИТЕ!)

CLEAN_INSTALL="false"                         # Установить в "true" для удаления предыдущей установки Blackbox Exporter
                                              # и принудительного перевыпуска сертификата Let's Encrypt.
                                              # ВНИМАНИЕ: Это приведет к удалению существующих конфигураций blackbox_exporter!
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
if [ -z "$BLACKBOX_EXPORTER_VERSION" ]; then
    error_exit "Переменная BLACKBOX_EXPORTER_VERSION не установлена."
fi
if ! [[ "$BLACKBOX_EXPORTER_PORT" =~ ^[0-9]+$ ]] || [ "$BLACKBOX_EXPORTER_PORT" -lt 1 ] || [ "$BLACKBOX_EXPORTER_PORT" -gt 65535 ]; then
    error_exit "Переменная BLACKBOX_EXPORTER_PORT должна быть числом от 1 до 65535."
fi
if [[ -z "$BLACKBOX_EXPORTER_CONFIG_DIR" ]] || [[ "${BLACKBOX_EXPORTER_CONFIG_DIR:0:1}" != "/" ]]; then
    error_exit "Переменная BLACKBOX_EXPORTER_CONFIG_DIR должна быть установлена и являться абсолютным путем (начинаться с '/')."
fi
if [ -z "$DNS_NAME" ] || [[ "$DNS_NAME" != *"."* ]]; then
    error_exit "Переменная DNS_NAME не установлена или выглядит некорректно. Укажите полное доменное имя."
fi
if [ "$DNS_NAME" == "blackbox.your-domain.com" ] && [ "$CLEAN_INSTALL" == "false" ]; then
    read -p "DNS_NAME все еще установлен как 'blackbox.your-domain.com'. Вы уверены, что хотите продолжить с этим значением? (yes/NO): " confirm_dns
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
echo "Blackbox Exporter будет слушать на порту: $BLACKBOX_EXPORTER_PORT"
echo "Конфигурационные файлы Blackbox Exporter будут размещены в: $BLACKBOX_EXPORTER_CONFIG_DIR"
if [ "$CLEAN_INSTALL" == "true" ]; then
    echo "РЕЖИМ ЧИСТОЙ УСТАНОВКИ: АКТИВИРОВАН (с принудительным обновлением сертификата)"
fi
echo "-----------------------------------------"


# --- БЛОК ЧИСТОЙ УСТАНОВКИ (если CLEAN_INSTALL="true") ---
if [ "$CLEAN_INSTALL" == "true" ]; then
    echo ""
    echo "--- ВНИМАНИЕ: Активирован режим ЧИСТОЙ УСТАНОВКИ ---"
    echo "Будут предприняты попытки удалить существующие компоненты Blackbox Exporter,"
    echo "конфигурации из '${BLACKBOX_EXPORTER_CONFIG_DIR}'. Сертификат Let's Encrypt для '${DNS_NAME}' будет принудительно обновлен."
    read -p "Вы АБСОЛЮТНО уверены, что хотите продолжить? Это действие необратимо для конфигурации Blackbox Exporter! (введите 'yes' для подтверждения): " confirm_clean
    if [[ "$confirm_clean" != "yes" ]]; then
        error_exit "Чистая установка отменена пользователем."
    fi

    echo "Остановка и отключение сервиса blackbox_exporter..."
    systemctl stop blackbox_exporter.service >/dev/null 2>&1
    systemctl disable blackbox_exporter.service >/dev/null 2>&1
    
    echo "Удаление файла сервиса blackbox_exporter..."
    rm -f /etc/systemd/system/blackbox_exporter.service
    systemctl daemon-reload >/dev/null 2>&1 

    echo "Удаление бинарного файла blackbox_exporter (/usr/local/bin/blackbox_exporter)..."
    rm -f /usr/local/bin/blackbox_exporter

    echo "Удаление конфигурационной директории ${BLACKBOX_EXPORTER_CONFIG_DIR}..."
    rm -rf "${BLACKBOX_EXPORTER_CONFIG_DIR}"
    
    # Удаление deploy-hook скрипта, если он специфичен для этого DNS_NAME
    if command -v certbot &> /dev/null; then
        POTENTIAL_DEPLOY_HOOK_SCRIPT="/etc/letsencrypt/renewal-hooks/deploy/blackbox_exporter_deploy_hook.sh"
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

    echo "--- Процесс очистки конфигурации Blackbox Exporter завершен ---"
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

# 2. Скачивание и установка Blackbox Exporter
echo "--- Установка Blackbox Exporter v${BLACKBOX_EXPORTER_VERSION} ---"
echo "Скачивание Blackbox Exporter..."
cd /tmp || error_exit "Не удалось перейти в директорию /tmp"
wget -q "https://github.com/prometheus/blackbox_exporter/releases/download/v${BLACKBOX_EXPORTER_VERSION}/blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-amd64.tar.gz" -O blackbox_exporter.tar.gz || error_exit "Не удалось скачать Blackbox Exporter."

echo "Извлечение Blackbox Exporter..."
tar xvfz blackbox_exporter.tar.gz || error_exit "Не удалось извлечь Blackbox Exporter."

echo "Установка бинарного файла Blackbox Exporter..."
mv "blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-amd64/blackbox_exporter" /usr/local/bin/ || error_exit "Не удалось переместить бинарный файл Blackbox Exporter."

echo "Очистка загруженных файлов..."
rm -rf "blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-amd64" blackbox_exporter.tar.gz
echo "-----------------------------------------"

# 3. Создание пользователя и директорий
echo "--- Настройка пользователя и директорий ---"
echo "Создание системного пользователя 'blackbox_exporter'..."
if ! id "blackbox_exporter" &>/dev/null; then
    useradd --system --no-create-home --shell /bin/false blackbox_exporter || error_exit "Не удалось создать пользователя blackbox_exporter."
else
    echo "Пользователь 'blackbox_exporter' уже существует."
fi

BLACKBOX_EXPORTER_TLS_DIR="${BLACKBOX_EXPORTER_CONFIG_DIR}/tls"
echo "Создание конфигурационных директорий в ${BLACKBOX_EXPORTER_CONFIG_DIR}..."
mkdir -p "${BLACKBOX_EXPORTER_TLS_DIR}" || error_exit "Не удалось создать директорию ${BLACKBOX_EXPORTER_TLS_DIR}."
# Права будут установлены позже, после создания всех файлов
echo "-----------------------------------------"

# 4. Получение SSL-сертификата от Let's Encrypt
echo "--- Получение/Обновление SSL-сертификата от Let's Encrypt для ${DNS_NAME} ---"

if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null ; then
    error_exit "Порт 80 занят. Certbot в режиме standalone не сможет получить/обновить сертификат. Освободите порт 80."
fi
echo "Порт 80 свободен, продолжаем с certbot standalone."

DEPLOY_HOOK_SCRIPT="/etc/letsencrypt/renewal-hooks/deploy/blackbox_exporter_deploy_hook.sh"
mkdir -p "$(dirname "$DEPLOY_HOOK_SCRIPT")"
cat <<EOF > "$DEPLOY_HOOK_SCRIPT"
#!/bin/bash
# Deploy hook для Blackbox Exporter

LE_DOMAIN="${DNS_NAME}"
BB_TLS_DIR="${BLACKBOX_EXPORTER_TLS_DIR}"
BB_USER="blackbox_exporter"

cp "/etc/letsencrypt/live/\${LE_DOMAIN}/fullchain.pem" "\${BB_TLS_DIR}/cert.pem"
cp "/etc/letsencrypt/live/\${LE_DOMAIN}/privkey.pem" "\${BB_TLS_DIR}/key.pem"

chown \${BB_USER}:\${BB_USER} "\${BB_TLS_DIR}/cert.pem" "\${BB_TLS_DIR}/key.pem"
chmod 600 "\${BB_TLS_DIR}/cert.pem" 
chmod 400 "\${BB_TLS_DIR}/key.pem"

if systemctl is-active --quiet blackbox_exporter.service; then
  echo "Перезапуск Blackbox Exporter после обновления сертификата для \${LE_DOMAIN}..."
  systemctl restart blackbox_exporter.service
else
  echo "Blackbox Exporter не активен, перезапуск не требуется для \${LE_DOMAIN}."
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

if [ ! -f "${BLACKBOX_EXPORTER_TLS_DIR}/cert.pem" ] || [ ! -f "${BLACKBOX_EXPORTER_TLS_DIR}/key.pem" ]; then
    error_exit "Сертификаты не были скопированы в ${BLACKBOX_EXPORTER_TLS_DIR}. Проверьте вывод certbot и deploy-hook."
fi
echo "SSL-сертификат получен/обновлен и скопирован в ${BLACKBOX_EXPORTER_TLS_DIR}/"
echo "-----------------------------------------"

# 5. Создание blackbox.yml
BLACKBOX_YML_PATH="${BLACKBOX_EXPORTER_CONFIG_DIR}/blackbox.yml"
echo "Создание файла ${BLACKBOX_YML_PATH}..."
cat <<EOF > "${BLACKBOX_YML_PATH}"
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [] # Defaults to 2xx
      method: GET
      preferred_ip_protocol: "ip4" # или "ip6"
  
  # Пример модуля для проверки SSL сертификата (срок действия)
  # Prometheus будет обращаться к этому модулю, указывая target=https://your-service-to-check.com
  ssl_expiry_check:
    prober: http
    timeout: 15s
    http:
      method: GET
      preferred_ip_protocol: "ip4"
      # Для проверки SSL сертификатов, если они самоподписанные или требуют особого CA:
      # tls_config:
      #   insecure_skip_verify: false # Установить в true только если вы понимаете риски
      #   ca_file: "/path/to/ca.pem"
      #   cert_file: "/path/to/client-cert.pem"
      #   key_file: "/path/to/client-key.pem"

  tcp_connect:
    prober: tcp
    timeout: 5s

  icmp:
    prober: icmp
    timeout: 5s
    icmp:
      preferred_ip_protocol: "ip4" # или "ip6"
EOF
echo "Файл ${BLACKBOX_YML_PATH} создан с базовыми модулями."
echo "-----------------------------------------"


# 6. Генерация хеша Basic Auth и создание web-config.yml
echo "--- Настройка Basic Authentication ---"
BLACKBOX_EXPORTER_USER_HASH=$(printf "%s\n" "$BASIC_AUTH_PASSWORD" | htpasswd -nBC 12 -i "$BASIC_AUTH_USER" 2>/dev/null | cut -d ':' -f2)
if [ -z "$BLACKBOX_EXPORTER_USER_HASH" ]; then
    error_exit "Не удалось сгенерировать хеш пароля."
fi

WEB_CONFIG_FILE_PATH="${BLACKBOX_EXPORTER_CONFIG_DIR}/web-config.yml"
echo "Создание файла ${WEB_CONFIG_FILE_PATH}..."
cat <<EOF > "${WEB_CONFIG_FILE_PATH}"
tls_server_config:
  cert_file: "${BLACKBOX_EXPORTER_TLS_DIR}/cert.pem"
  key_file: "${BLACKBOX_EXPORTER_TLS_DIR}/key.pem"

basic_auth_users:
  ${BASIC_AUTH_USER}: "${BLACKBOX_EXPORTER_USER_HASH}"
EOF
echo "Файл ${WEB_CONFIG_FILE_PATH} создан."
echo "-----------------------------------------"

# 7. Установка прав на конфигурационные файлы
echo "--- Установка прав доступа ---"
chown -R blackbox_exporter:blackbox_exporter "${BLACKBOX_EXPORTER_CONFIG_DIR}"
chmod 750 "${BLACKBOX_EXPORTER_CONFIG_DIR}" 
chmod 700 "${BLACKBOX_EXPORTER_TLS_DIR}"    
chmod 640 "${BLACKBOX_YML_PATH}"
chmod 640 "${WEB_CONFIG_FILE_PATH}"     
if [ -f "${BLACKBOX_EXPORTER_TLS_DIR}/cert.pem" ]; then
    chmod 600 "${BLACKBOX_EXPORTER_TLS_DIR}/cert.pem"
    chown blackbox_exporter:blackbox_exporter "${BLACKBOX_EXPORTER_TLS_DIR}/cert.pem"
fi
if [ -f "${BLACKBOX_EXPORTER_TLS_DIR}/key.pem" ]; then
    chmod 400 "${BLACKBOX_EXPORTER_TLS_DIR}/key.pem"
    chown blackbox_exporter:blackbox_exporter "${BLACKBOX_EXPORTER_TLS_DIR}/key.pem"
fi
echo "Права доступа установлены/проверены."
echo "-----------------------------------------"

# 8. Создание Systemd сервиса
echo "--- Настройка Systemd сервиса ---"
cat <<EOF > /etc/systemd/system/blackbox_exporter.service
[Unit]
Description=Blackbox Exporter (v${BLACKBOX_EXPORTER_VERSION}) for Prometheus (Let's Encrypt)
Wants=network-online.target
After=network-online.target

[Service]
User=blackbox_exporter
Group=blackbox_exporter
Type=simple
Restart=on-failure
ExecStart=/usr/local/bin/blackbox_exporter \
    --config.file="${BLACKBOX_YML_PATH}" \
    --web.listen-address=":${BLACKBOX_EXPORTER_PORT}" \
    --web.config.file="${WEB_CONFIG_FILE_PATH}"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload || error_exit "Не удалось перезагрузить демон systemd."
systemctl enable blackbox_exporter || error_exit "Не удалось включить сервис blackbox_exporter."
systemctl restart blackbox_exporter || error_exit "Не удалось запустить/перезапустить сервис blackbox_exporter."

sleep 3
echo "Текущий статус сервиса blackbox_exporter:"
systemctl status blackbox_exporter --no-pager
echo "-----------------------------------------"

# 9. Настройка автоматического обновления сертификата Certbot
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

# 10. Вывод информации
echo ""
echo "--- Установка/Обновление Blackbox Exporter с Let's Encrypt завершена ---"
echo ""
echo "Blackbox Exporter (версия ${BLACKBOX_EXPORTER_VERSION}) установлен и запущен."
echo "Он слушает на https://${DNS_NAME}:${BLACKBOX_EXPORTER_PORT}"
echo "  - Метрики самого экспортера: https://${DNS_NAME}:${BLACKBOX_EXPORTER_PORT}/metrics"
echo "  - Эндпоинт для проб: https://${DNS_NAME}:${BLACKBOX_EXPORTER_PORT}/probe?target=<your_target>&module=<module_name>"
echo "Убедитесь, что порт ${BLACKBOX_EXPORTER_PORT} открыт в вашем файрволе для доступа Prometheus."
echo ""
echo "Данные для Basic Authentication:"
echo "  Имя пользователя: ${BASIC_AUTH_USER}"
echo "  Пароль: ${BASIC_AUTH_PASSWORD}"
echo ""
echo "SSL-сертификат от Let's Encrypt для ${DNS_NAME} получен/обновлен и настроен."
echo "Автоматическое обновление сертификатов настроено через Certbot."
echo "Файл конфигурации модулей: ${BLACKBOX_YML_PATH}"
echo ""
echo "Пример конфигурации для сбора метрик через Prometheus (prometheus.yml):"
echo "Предполагается, что вы хотите проверить сайт 'https://prometheus.io' с помощью модуля 'http_2xx'"
cat <<PROMETHEUS_EOF

  - job_name: 'blackbox_http_checks'
    metrics_path: /probe
    params:
      module: [http_2xx]  # Укажите модуль из blackbox.yml
    static_configs:
      - targets:
        - https://prometheus.io   # Цель для проверки
        - http://example.com
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: ${DNS_NAME}:${BLACKBOX_EXPORTER_PORT} # Адрес вашего Blackbox Exporter
    # Basic Auth для доступа к Blackbox Exporter
    basic_auth:
      username: '${BASIC_AUTH_USER}'
      password: '${BASIC_AUTH_PASSWORD}'
    # TLS config для соединения Prometheus -> Blackbox Exporter
    # ca_file не нужен, т.к. используется Let's Encrypt
    scheme: https
    tls_config:
      server_name: '${DNS_NAME}' # Должен совпадать с DNS именем в сертификате Blackbox Exporter
PROMETHEUS_EOF
echo ""
echo "--- Скрипт завершен ---"
