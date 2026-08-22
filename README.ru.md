# lite-vs

[English README](README.md)

Независимый мультиплатформенный workbench-слой для Lite XL 2.1.8 и новее:
компактный borderless toolbar, адаптивные вкладки, анимированные сайдбары и
нижняя панель, палитра команд, поиск файлов, мультисессионный терминал, Git,
менеджер плагинов, адаптивная страница настроек и согласованная тёмная
подсветка кода.

Проект работает поверх публичного Lua API и не патчит системные файлы Lite XL.

## Установка в один шаг

Перед установкой закройте Lite XL, после завершения снова запустите редактор.
Если одноимённые файлы уже есть, установщик сначала сохранит их резервную
копию.

### Windows

Откройте PowerShell:

```powershell
irm https://raw.githubusercontent.com/tg-prplx/lite-vs/main/scripts/install.ps1 | iex
```

### Linux

```sh
curl -fsSL https://raw.githubusercontent.com/tg-prplx/lite-vs/main/scripts/install.sh | sh
```

### macOS

Команда одинакова для Intel и Apple Silicon:

```sh
curl -fsSL https://raw.githubusercontent.com/tg-prplx/lite-vs/main/scripts/install.sh | sh
```

Если LPM ещё не установлен, скрипт скачает официальный бинарник для вашей ОС и
архитектуры. Через него будут установлены терминал, SCM, менеджер плагинов,
навигация, JSON и библиотека иконок. Бинарники зависимостей не лежат в этом
репозитории. Установщик также скачивает зафиксированную по SHA-256 версию
свободного шрифта Inter и его лицензию SIL OFL, поэтому метрики интерфейса
совпадают на Windows, Linux и macOS.

## Локальная установка после проверки кода

```sh
git clone https://github.com/tg-prplx/lite-vs.git
cd lite-vs
```

Windows:

```powershell
.\scripts\install.ps1
```

Linux/macOS:

```sh
./scripts/install.sh
```

Нестандартный каталог конфигурации:

```powershell
.\scripts\install.ps1 -UserDir 'D:\portable\lite-xl-data'
```

```sh
LITE_USERDIR=/path/to/lite-xl-data ./scripts/install.sh
```

## Удаление и восстановление

```powershell
.\scripts\uninstall.ps1
# Удалить lite-vs и вернуть последнюю резервную копию:
.\scripts\uninstall.ps1 -RestoreLatestBackup
```

```sh
./scripts/uninstall.sh
# Удалить lite-vs и вернуть последнюю резервную копию:
./scripts/uninstall.sh --restore-latest
```

Удаление затрагивает только файлы, принадлежащие или установленные lite-vs.
Общие LPM-зависимости и каталог `lite-vs-backups` сохраняются специально.

## Горячие клавиши

| Действие | Windows / Linux | macOS |
| --- | --- | --- |
| Палитра команд | `Ctrl+Shift+P` | `Cmd+Shift+P` |
| Файлы | `Ctrl+Shift+E` | `Cmd+Shift+E` |
| Поиск | `Ctrl+Shift+F` | `Cmd+Shift+F` |
| Git | `Ctrl+Shift+G` | `Cmd+Shift+G` |
| Запуск и отладка | `Ctrl+Shift+D` | `Cmd+Shift+D` |
| Плагины | `Ctrl+Shift+X` | `Cmd+Shift+X` |
| Сайдбар | `Ctrl+B` | `Cmd+B` |
| Нижняя панель | `Ctrl+J` | `Cmd+J` |
| Новый терминал | `Ctrl+Shift+\`` | `Cmd+Shift+\`` |

## Интегрированный терминал

Терминал работает внутри анимированной нижней панели. Кнопка `+` создаёт
независимую shell-сессию и больше не перезапускает текущую. Переключение между
сессиями выполняется через имя терминала в заголовке, а корзина завершает только
активную сессию. В соседнем меню доступны очистка, перезапуск, завершение и
скрытие панели. Backspace, Enter и `Ctrl+C` передаются непосредственно активной
PTY-сессии, включая настоящее прерывание запущенного процесса.

В Windows lite-vs выбирает Windows PowerShell, если terminal-плагин всё ещё
использует стандартный `COMSPEC` (`cmd.exe`). Чтобы оставить Command Prompt,
добавьте в `init.lua` Lite XL:

```lua
config.plugins.lite_vs_terminal = { prefer_powershell = false }
```

Явно заданные нестандартные shell-команды на всех системах не изменяются.

## Что не публикуется

В Git нет чужих логотипов и продуктовых иконок, скриншотов, DLL/EXE,
сессий, истории файлов, логов и пользовательских настроек. Метка `<>` и Lua-код
интерфейса созданы для этого проекта. Зависимости скачиваются из официальных
источников через LPM и сохраняют собственные лицензии. Inter скачивается из
зафиксированной ревизии Google Fonts по проверяемому SHA-256 и распространяется
по SIL Open Font License; моноширинный JetBrains Mono поставляется самим Lite XL.
Проприетарные системные шрифты не требуются.

Код проекта распространяется по [лицензии MIT](LICENSE), подробности о границе
зависимостей находятся в [THIRD_PARTY.md](THIRD_PARTY.md).
