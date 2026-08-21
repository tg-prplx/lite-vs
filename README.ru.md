# lite-vs

[English README](README.md)

Независимый мультиплатформенный workbench-слой для Lite XL 2.1.8 и новее:
компактный borderless toolbar, адаптивные вкладки, анимированные сайдбары и
нижняя панель, палитра команд, поиск файлов, интегрированный терминал, Git,
менеджер плагинов и согласованная тёмная подсветка кода.

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
репозитории.

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

Удаление затрагивает только шесть файлов lite-vs. Общие LPM-зависимости и
каталог `lite-vs-backups` сохраняются специально.

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

## Что не публикуется

В Git нет чужих логотипов и продуктовых иконок, скриншотов, шрифтов, DLL/EXE,
сессий, истории файлов, логов и пользовательских настроек. Метка `<>` и Lua-код
интерфейса созданы для этого проекта. Зависимости скачиваются из официальных
источников через LPM и сохраняют собственные лицензии.

Код проекта распространяется по [лицензии MIT](LICENSE), подробности о границе
зависимостей находятся в [THIRD_PARTY.md](THIRD_PARTY.md).
