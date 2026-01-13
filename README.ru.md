# Docker-образ для сборки restic и rclone под Windows 7

**[English](README.md) | [Deutsch](README.de.md)**

## Описание

Автономный Docker-образ для кросс-компиляции [restic](https://restic.net/) и [rclone](https://rclone.org/) с поддержкой **Windows 7 / Windows Server 2008 R2**.

### Проблема

Начиная с Go 1.21, официальная поддержка Windows 7 прекращена. Бинарники, собранные стандартным Go 1.21+, не запускаются на Windows 7.

### Решение

Образ использует [XTLS/go-win7](https://github.com/XTLS/go-win7) — форк Go с патчами для восстановления совместимости с Windows 7.

### Особенности

- **Автономность**: можно положить в любую папку, не требует размещения в дереве исходников
- **Автоскачивание**: если исходники не найдены — скачает их сам с GitHub
- **Самодостаточность**: всё необходимое включено в образ
- **Мультипроект**: поддерживает restic и rclone

## Быстрый старт

### Вариант 1: Полностью автоматический (скачает исходники сам)

```bash
# Создать папку для сборки
mkdir win7-build && cd win7-build

# Скопировать Dockerfile и build.sh сюда (или скачать)
# ...

# Собрать образ
docker build -t win7-builder .

# Запустить (скачает исходники и соберёт)
# -v win7-go-cache:/go — сохраняет кэш Go модулей между запусками
docker run --rm \
    -v $(pwd):/workspace \
    -v win7-go-cache:/go \
    win7-builder
```

Результат появится в `./output/`.

### Вариант 2: С готовыми исходниками

```bash
mkdir win7-build && cd win7-build

# Получить исходники
git clone https://github.com/restic/restic.git
git clone https://github.com/rclone/rclone.git

# Собрать образ
docker build -t win7-builder .

# Запустить
docker run --rm -v $(pwd):/workspace win7-builder all:all
```

### Вариант 3: Исходники в другом месте

```bash
docker run --rm \
    -v /путь/к/restic:/workspace/restic:ro \
    -v /путь/к/rclone:/workspace/rclone:ro \
    -v $(pwd)/output:/workspace/output \
    win7-builder all:all
```

## Использование

### Команды (новый формат: проект:архитектура)

| Команда | Описание |
|---------|----------|
| `restic:all` | Собрать restic для Windows 64-bit и 32-bit |
| `restic:amd64` | Собрать restic только для Windows 64-bit |
| `restic:386` | Собрать restic только для Windows 32-bit |
| `rclone:all` | Собрать rclone для Windows 64-bit и 32-bit |
| `rclone:amd64` | Собрать rclone только для Windows 64-bit |
| `rclone:386` | Собрать rclone только для Windows 32-bit |
| `all:all` | Собрать всё (restic + rclone, обе архитектуры) |
| `all:amd64` | Собрать всё только для 64-bit |
| `help` | Показать справку |

### Команды (устаревший формат: только restic)

| Команда | Описание |
|---------|----------|
| `all` | Собрать restic для Windows 64-bit и 32-bit (по умолчанию) |
| `amd64` | Только Windows 64-bit |
| `386` | Только Windows 32-bit |
| `linux` | Linux 64-bit |

### Примеры

```bash
# Собрать restic для обеих архитектур Windows (по умолчанию)
docker run --rm -v $(pwd):/workspace win7-builder

# Собрать restic только 64-bit
docker run --rm -v $(pwd):/workspace win7-builder restic:amd64

# Собрать rclone для обеих архитектур Windows
docker run --rm -v $(pwd):/workspace win7-builder rclone:all

# Собрать всё
docker run --rm -v $(pwd):/workspace win7-builder all:all

# Собрать несколько конкретных целей
docker run --rm -v $(pwd):/workspace win7-builder restic:amd64 rclone:amd64
```

### Интерактивный режим

```bash
docker run --rm -it \
    -v $(pwd):/workspace \
    --entrypoint /bin/bash \
    win7-builder
```

## Логика поиска исходников

Скрипт ищет исходники в следующем порядке:

1. **В корне /workspace** — если смонтированная папка сама является репозиторием проекта
2. **В подпапках** — `restic/`, `rclone/`, `*-master/`, `*-main/`, `src/`, `source/`
3. **Во всех подпапках первого уровня** — если папка называется иначе

### Как определяется проект

- **restic**: наличие `go.mod` с `module github.com/restic/restic`, или `VERSION` + директория `cmd/restic/`
- **rclone**: наличие `go.mod` с `module github.com/rclone/rclone`, или `VERSION` + директория `cmd/rclone/`

### Если исходники не найдены

Скрипт пытается скачать:

1. **git clone** с GitHub
2. **Архив** с GitHub

Если оба способа не сработали — выводится инструкция с объяснением, что делать.

## Структура

```
docker-win7-build/
├── Dockerfile      # Образ на базе debian:bookworm-slim
├── build.sh        # Скрипт сборки с автоскачиванием
└── README.md       # Эта документация

После сборки:
/workspace/
├── restic/         # Исходники restic (скачанные или смонтированные)
├── rclone/         # Исходники rclone (скачанные или смонтированные)
└── output/         # Результаты сборки
    ├── restic-v0.18.1-win7-64.exe
    ├── restic-v0.18.1-win7-32.exe
    ├── rclone-v1.69.0-win7-64.exe
    └── rclone-v1.69.0-win7-32.exe
```

Формат имён файлов: `{проект}-{версия}-win7-{архитектура}.exe`

## Кэширование Go модулей

Для ускорения повторных сборок используйте named volume для Go кэша:

```bash
# Первая сборка (~2-5 минут) — скачивает все зависимости
docker run --rm -v $(pwd):/workspace -v win7-go-cache:/go win7-builder all:all

# Повторные сборки (~6-30 секунд) — использует кэш
docker run --rm -v $(pwd):/workspace -v win7-go-cache:/go win7-builder all:all
```

Без volume `-v win7-go-cache:/go` зависимости будут скачиваться каждый раз.

## Переменные окружения

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `WORKSPACE` | `/workspace` | Рабочая папка |
| `GOPATH` | `/go` | Путь для Go кэша (монтировать volume сюда) |
| `RESTIC_VERSION` | *(последний релиз)* | Версия restic (тег, ветка или коммит) |
| `RCLONE_VERSION` | *(последний релиз)* | Версия rclone (тег, ветка или коммит) |
| `RESTIC_GIT_URL` | `https://github.com/restic/restic.git` | URL для git clone (restic) |
| `RCLONE_GIT_URL` | `https://github.com/rclone/rclone.git` | URL для git clone (rclone) |
| `CGO_ENABLED` | `0` | Статическая линковка |

## Сборка конкретной версии/тега

### Через переменные окружения (рекомендуется)

```bash
# Собрать конкретные версии
docker run --rm \
    -v $(pwd):/workspace \
    -v win7-go-cache:/go \
    -e RESTIC_VERSION=v0.17.3 \
    -e RCLONE_VERSION=v1.68.2 \
    win7-builder all:all

# Собрать из определённого коммита
docker run --rm \
    -v $(pwd):/workspace \
    -e RESTIC_VERSION=abc1234 \
    win7-builder restic:amd64

# Собрать последние версии (поведение по умолчанию)
docker run --rm -v $(pwd):/workspace win7-builder all:all
```

### Через локальные исходники

```bash
# Клонировать с определённым тегом
git clone --branch v0.17.3 --depth 1 https://github.com/restic/restic.git
git clone --branch v1.68.2 --depth 1 https://github.com/rclone/rclone.git

# Собрать
docker run --rm -v $(pwd):/workspace win7-builder all:all
```

## Проверка совместимости

Собранные бинарники помечены как совместимые с Windows 6.01 (Windows 7):

```bash
file output/restic-v0.18.1-win7-64.exe
# PE32+ executable for MS Windows 6.01 (console), x86-64

file output/rclone-v1.69.0-win7-64.exe
# PE32+ executable for MS Windows 6.01 (console), x86-64
```

## Обновление Go SDK

Для использования другой версии патченного Go:

```bash
docker build \
    --build-arg GO_WIN7_VERSION=1.25.5 \
    --build-arg GO_WIN7_TAG=patched-1.25.5 \
    -t win7-builder .
```

Доступные версии: https://github.com/XTLS/go-win7/releases

## Технические детали

- **Базовый образ**: `debian:bookworm-slim`
- **Go версия**: 1.25.5 (патченный для Windows 7)
- **Размер образа**: ~350 MB
- **Выходные файлы**: совместимы с Windows 7 (PE для Windows 6.01)

## Решение проблем

### "Не удалось найти или скачать исходники"

1. Проверьте доступ к интернету в контейнере
2. Скачайте исходники вручную:
   ```bash
   git clone https://github.com/restic/restic.git
   git clone https://github.com/rclone/rclone.git
   ```
3. Смонтируйте папку с исходниками

### "Permission denied" при записи результатов

Убедитесь, что папка `/workspace/output` доступна для записи:
```bash
mkdir -p output && chmod 777 output
```

## Ссылки

- [restic](https://restic.net/) — программа резервного копирования
- [rclone](https://rclone.org/) — синхронизация с облачными хранилищами
- [XTLS/go-win7](https://github.com/XTLS/go-win7) — патченный Go для Windows 7
- [Обсуждение прекращения поддержки Win7 в Go](https://github.com/golang/go/issues/57003)
