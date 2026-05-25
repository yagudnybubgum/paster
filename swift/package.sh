#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Paster.app"
STAGE="$ROOT/build/dmg-stage"
DMG="$ROOT/build/Paster.dmg"

if [[ ! -d "$APP" ]]; then
    echo "App not built. Run ./build.sh first."
    exit 1
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/Прочти меня.txt" << 'EOF'
Paster — история буфера обмена для macOS

УСТАНОВКА (важно — прочти!)

Шаг 1. Перетащи Paster.app в папку Applications

Шаг 2. Сними блок Gatekeeper (нужно один раз)
   macOS блокирует приложения без платной Apple-подписи. Чтобы
   разблокировать Paster, открой Terminal (Cmd+Space → "Terminal")
   и вставь команду:

       xattr -dr com.apple.quarantine /Applications/Paster.app

   Нажми Enter. Готово — больше команда не понадобится.

Шаг 3. Открой Paster.app из Applications обычным двойным кликом.
   В строке меню (наверху экрана) появится иконка.

ИСПОЛЬЗОВАНИЕ
- Клик по иконке в menu bar → открывается история
- Глобальный хоткей: ⌘⇧V (Cmd + Shift + V) — работает откуда угодно
- Поиск работает прямо в открытой панели — просто начни печатать
- Enter в поиске = вставить первый результат
- Клик по записи = вернуть её в буфер обмена

ХРАНЕНИЕ
- История лежит в ~/.paster/history.db (зашифрована AES-256-GCM)
- Ключ шифрования — в macOS Keychain
- Лимиты: 14 дней или 30 МБ (что наступит раньше)
- Всё локально, никаких облаков и серверов

ЕСЛИ НЕ ХОЧЕШЬ ИСПОЛЬЗОВАТЬ TERMINAL
Альтернативный путь без команды:
1. Перетащи Paster.app в Applications
2. Двойной клик → появится диалог "can't be opened"
3. Открой System Settings → Privacy & Security
4. Прокрути вниз, найди строку про Paster → "Open Anyway"
5. Подтверди паролем

УДАЛЕНИЕ
1. Quit из меню Paster
2. Удалить Paster.app из Applications
3. (опционально) Удалить папку ~/.paster и ключ "com.paster.clipboard.dbkey"
   из Keychain Access
EOF

echo "==> Building DMG…"
hdiutil create \
    -volname "Paster" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG" >/dev/null

rm -rf "$STAGE"

echo "==> Done"
ls -lh "$DMG"
