#!/bin/bash

# Скрипт настройки ZSH с Oh-My-Zsh, плагинами и автоподключением ssh-agent
# Избегает конфликтов с уже установленными компонентами
# Не дублирует блоки в .zshrc и не удаляет старые ssh-agent из других сессий

set -e

echo "🚀 Начинаем настройку ZSH..."

# Функции для вывода цветного текста
print_status() {
    echo -e "\033[1;32m[INFO]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

# Установка базовых пакетов
print_status "Обновление пакетов и установка зависимостей..."
sudo apt update && sudo apt install zsh git curl openssh-client -y

# Проверка установки zsh
if ! command -v zsh >/dev/null 2>&1; then
    print_error "ZSH не установлен!"
    exit 1
fi

ZSH_BIN="$(command -v zsh)"
print_status "ZSH успешно установлен: $(zsh --version)"

# Установка Oh-My-Zsh (если не установлен)
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    print_status "Устанавливаем Oh-My-Zsh..."
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    print_warning "Oh-My-Zsh уже установлен, пропускаем..."
fi

# Установка переменной ZSH_CUSTOM, если не установлена
if [ -z "${ZSH_CUSTOM:-}" ]; then
    export ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
fi

# Создание директории для плагинов
mkdir -p "$ZSH_CUSTOM/plugins"

install_or_update_plugin() {
    local repo_url="$1"
    local plugin_dir="$2"
    local plugin_name="$3"

    if [ ! -d "$plugin_dir/.git" ]; then
        print_status "Клонируем $plugin_name..."
        git clone "$repo_url" "$plugin_dir"
    else
        print_warning "$plugin_name уже существует, обновляем..."
        (cd "$plugin_dir" && git pull --ff-only) || print_warning "Не удалось обновить $plugin_name"
    fi
}

print_status "Устанавливаем плагины..."

install_or_update_plugin \
    "https://github.com/zsh-users/zsh-syntax-highlighting.git" \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" \
    "zsh-syntax-highlighting"

install_or_update_plugin \
    "https://github.com/zsh-users/zsh-autosuggestions.git" \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions" \
    "zsh-autosuggestions"

install_or_update_plugin \
    "https://github.com/zsh-users/zsh-completions.git" \
    "$ZSH_CUSTOM/plugins/zsh-completions" \
    "zsh-completions"

# Создание backup файла .zshrc
ZSHRC_FILE="$HOME/.zshrc"

if [ -f "$ZSHRC_FILE" ]; then
    cp "$ZSHRC_FILE" "$ZSHRC_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    print_status "Создан backup файла .zshrc"
else
    touch "$ZSHRC_FILE"
    print_status "Создан новый файл .zshrc"
fi

print_status "Настраиваем .zshrc..."

# Добавляем настройки автообновления, если их ещё нет
if ! grep -q '^DISABLE_AUTO_UPDATE=' "$ZSHRC_FILE" 2>/dev/null; then
    {
        echo ""
        echo "# Отключить автоматическую проверку обновлений"
        echo 'DISABLE_AUTO_UPDATE="true"'
    } >> "$ZSHRC_FILE"
    print_status "Добавлена настройка DISABLE_AUTO_UPDATE"
fi

if ! grep -q '^DISABLE_UPDATE_PROMPT=' "$ZSHRC_FILE" 2>/dev/null; then
    {
        echo ""
        echo "# Отключить напоминание об обновлении"
        echo 'DISABLE_UPDATE_PROMPT="true"'
    } >> "$ZSHRC_FILE"
    print_status "Добавлена настройка DISABLE_UPDATE_PROMPT"
fi

# Настройка плагинов
DESIRED_PLUGINS="git zsh-syntax-highlighting zsh-autosuggestions zsh-completions"

if grep -q "^plugins=(" "$ZSHRC_FILE" 2>/dev/null; then
    EXISTING_PLUGINS=$(grep "^plugins=(" "$ZSHRC_FILE" | sed 's/plugins=(//' | sed 's/)//' | tr -d '\n' | xargs)
    ALL_PLUGINS=$(echo "$EXISTING_PLUGINS $DESIRED_PLUGINS" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | xargs)
    sed -i "/^plugins=(/c\\plugins=($ALL_PLUGINS)" "$ZSHRC_FILE"
    print_status "Обновлена строка plugins с плагинами: $ALL_PLUGINS"
else
    {
        echo ""
        echo "plugins=($DESIRED_PLUGINS)"
    } >> "$ZSHRC_FILE"
    print_status "Добавлена строка plugins с плагинами: $DESIRED_PLUGINS"
fi

# Удаляем старый управляемый блок ssh-agent, если он уже был
sed -i '/^# >>> SSH AGENT AUTOLOAD >>>$/,/^# <<< SSH AGENT AUTOLOAD <<</d' "$ZSHRC_FILE"

# Добавляем новый управляемый блок ssh-agent
SSH_AGENT_BLOCK=$(cat <<'EOF'
# >>> SSH AGENT AUTOLOAD >>>
# Автоподключение к ssh-agent для ZSH.
# Логика:
# 1. Если в текущей сессии уже есть рабочий ssh-agent — используем его.
# 2. Иначе пробуем подключиться к агенту из ~/.ssh/agent.env.
# 3. Если и он недоступен — запускаем новый ssh-agent.
# Важно: старые агенты из других сессий не удаляются.

export SSH_ENV="$HOME/.ssh/agent.env"

ssh_agent_is_usable() {
  [ -n "${SSH_AUTH_SOCK:-}" ] || return 1
  [ -S "${SSH_AUTH_SOCK}" ] || return 1
  [ -n "${SSH_AGENT_PID:-}" ] || return 1
  kill -0 "${SSH_AGENT_PID}" 2>/dev/null || return 1

  ssh-add -l >/dev/null 2>&1
  local ssh_add_status=$?

  # 0 = есть ключи, 1 = агент доступен, но ключей нет, 2 = агент недоступен
  [ "$ssh_add_status" -eq 0 ] || [ "$ssh_add_status" -eq 1 ]
}

load_ssh_agent_env() {
  [ -f "$SSH_ENV" ] || return 1
  source "$SSH_ENV" >/dev/null 2>&1
  ssh_agent_is_usable
}

start_ssh_agent() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  # Сохраняем переменные окружения агента в файл для следующих сессий.
  # Строку echo комментируем, чтобы при source не было лишнего вывода.
  (umask 077; ssh-agent -s | sed 's/^echo /# echo /' > "$SSH_ENV")

  source "$SSH_ENV" >/dev/null 2>&1
}

if ! ssh_agent_is_usable; then
  load_ssh_agent_env || start_ssh_agent
fi

# Примеры добавления SSH-ключей вручную:
# ssh-add ~/.ssh/id_ed25519
# ssh-add ~/.ssh/id_rsa
# ssh-add ~/.ssh/my_work_key
# ssh-add -t 8h ~/.ssh/id_ed25519   # ключ будет доступен 8 часов
# ssh-add -c ~/.ssh/id_ed25519      # спрашивать подтверждение при каждом использовании

# Посмотреть добавленные ключи:
# ssh-add -l
# <<< SSH AGENT AUTOLOAD <<<
EOF
)

{
    echo ""
    echo "$SSH_AGENT_BLOCK"
} >> "$ZSHRC_FILE"

print_status "Добавлен блок автоподключения ssh-agent в .zshrc"

# Устанавливаем zsh как shell по умолчанию
if [ "$SHELL" != "$ZSH_BIN" ]; then
    print_status "Устанавливаем zsh как shell по умолчанию..."
    chsh -s "$ZSH_BIN"
    print_status "Для применения изменений перезайдите в систему или выполните: exec zsh"
fi

print_status "✅ Настройка ZSH завершена!"
print_status "📝 Backup оригинального .zshrc сохранен"
print_status "🔄 Для применения изменений выполните: source ~/.zshrc"

echo ""
echo "Установленные плагины:"
echo "  - git (базовый)"
echo "  - zsh-syntax-highlighting (подсветка синтаксиса)"
echo "  - zsh-autosuggestions (автоподсказки)"
echo "  - zsh-completions (расширенные дополнения)"
echo ""
echo "SSH agent:"
echo "  - будет переиспользоваться между сессиями через ~/.ssh/agent.env"
echo "  - новый агент запускается только если старый недоступен"
echo "  - старые агенты из других сессий не удаляются"
