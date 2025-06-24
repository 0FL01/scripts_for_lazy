#!/bin/bash

# Скрипт настройки ZSH с Oh-My-Zsh и плагинами
# Избегает конфликтов с уже установленными компонентами

set -e

echo "🚀 Начинаем настройку ZSH..."

# Функция для вывода цветного текста
print_status() {
    echo -e "\033[1;32m[INFO]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

# Обновление пакетов и установка zsh
print_status "Обновление пакетов и установка zsh..."
sudo apt update && sudo apt install zsh git -y

# Проверка установки zsh
if ! command -v zsh &> /dev/null; then
    print_error "ZSH не установлен!"
    exit 1
fi

print_status "ZSH успешно установлен: $(zsh --version)"

# Установка Oh-My-Zsh (если не установлен)
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    print_status "Устанавливаем Oh-My-Zsh..."
    RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    print_warning "Oh-My-Zsh уже установлен, пропускаем..."
fi

# Установка переменной ZSH_CUSTOM если не установлена
if [ -z "$ZSH_CUSTOM" ]; then
    export ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
fi

# Создание директории для плагинов если не существует
mkdir -p "$ZSH_CUSTOM/plugins"

# Установка плагинов по одному
print_status "Устанавливаем плагины..."

# zsh-syntax-highlighting
PLUGIN_DIR="$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
if [ ! -d "$PLUGIN_DIR" ]; then
    print_status "Клонируем zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$PLUGIN_DIR"
else
    print_warning "zsh-syntax-highlighting уже существует, обновляем..."
    (cd "$PLUGIN_DIR" && git pull origin master) || print_warning "Не удалось обновить zsh-syntax-highlighting"
fi

# zsh-autosuggestions
PLUGIN_DIR="$ZSH_CUSTOM/plugins/zsh-autosuggestions"
if [ ! -d "$PLUGIN_DIR" ]; then
    print_status "Клонируем zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions.git "$PLUGIN_DIR"
else
    print_warning "zsh-autosuggestions уже существует, обновляем..."
    (cd "$PLUGIN_DIR" && git pull origin master) || print_warning "Не удалось обновить zsh-autosuggestions"
fi

# zsh-completions
PLUGIN_DIR="$ZSH_CUSTOM/plugins/zsh-completions"
if [ ! -d "$PLUGIN_DIR" ]; then
    print_status "Клонируем zsh-completions..."
    git clone https://github.com/zsh-users/zsh-completions.git "$PLUGIN_DIR"
else
    print_warning "zsh-completions уже существует, обновляем..."
    (cd "$PLUGIN_DIR" && git pull origin master) || print_warning "Не удалось обновить zsh-completions"
fi

# Создание backup файла .zshrc
if [ -f "$HOME/.zshrc" ]; then
    cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d_%H%M%S)"
    print_status "Создан backup файла .zshrc"
fi

# Настройка .zshrc
print_status "Настраиваем .zshrc..."

# Создание нового .zshrc или обновление существующего
ZSHRC_FILE="$HOME/.zshrc"

# Проверяем и добавляем настройки автообновления
if ! grep -q "DISABLE_AUTO_UPDATE" "$ZSHRC_FILE" 2>/dev/null; then
    echo "" >> "$ZSHRC_FILE"
    echo "# Отключить автоматическую проверку обновлений" >> "$ZSHRC_FILE"
    echo 'DISABLE_AUTO_UPDATE="true"' >> "$ZSHRC_FILE"
    print_status "Добавлена настройка DISABLE_AUTO_UPDATE"
fi

if ! grep -q "DISABLE_UPDATE_PROMPT" "$ZSHRC_FILE" 2>/dev/null; then
    echo "" >> "$ZSHRC_FILE"
    echo "# Отключить напоминание об обновлении" >> "$ZSHRC_FILE"
    echo 'DISABLE_UPDATE_PROMPT="true"' >> "$ZSHRC_FILE"
    print_status "Добавлена настройка DISABLE_UPDATE_PROMPT"
fi

# Настройка плагинов
DESIRED_PLUGINS="git zsh-syntax-highlighting zsh-autosuggestions zsh-completions"

# Проверяем существующую строку plugins
if grep -q "^plugins=(" "$ZSHRC_FILE" 2>/dev/null; then
    # Получаем существующие плагины
    EXISTING_PLUGINS=$(grep "^plugins=(" "$ZSHRC_FILE" | sed 's/plugins=(//' | sed 's/)//' | tr -d '\n' | xargs)
    
    # Объединяем плагины (убираем дубликаты)
    ALL_PLUGINS=$(echo "$EXISTING_PLUGINS $DESIRED_PLUGINS" | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs)
    
    # Заменяем строку plugins
    sed -i "/^plugins=(/c\\plugins=($ALL_PLUGINS)" "$ZSHRC_FILE"
    print_status "Обновлена строка plugins с плагинами: $ALL_PLUGINS"
else
    # Добавляем новую строку plugins
    echo "" >> "$ZSHRC_FILE"
    echo "plugins=($DESIRED_PLUGINS)" >> "$ZSHRC_FILE"
    print_status "Добавлена строка plugins с плагинами: $DESIRED_PLUGINS"
fi

# Устанавливаем zsh как shell по умолчанию (если не установлен)
if [ "$SHELL" != "$(which zsh)" ]; then
    print_status "Устанавливаем zsh как shell по умолчанию..."
    chsh -s $(which zsh)
    print_status "Для применения изменений перезайдите в систему или выполните: exec zsh"
fi

print_status "✅ Настройка ZSH завершена!"
print_status "📝 Backup оригинального .zshrc сохранен"
print_status "🔄 Для применения изменений выполните: source ~/.zshrc"

echo ""
echo "Установленные плагины:"
echo "  - git (базовый)"
echo "  - zsh-syntax-highlighting (подсветка синтаксиса)"
echo "  - zsh-autosuggestions (автодополнение)"
echo "  - zsh-completions (расширенные дополнения)" 
