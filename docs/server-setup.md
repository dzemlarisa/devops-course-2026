```markdown
# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Наименование | devops-vm |
| Тип и версия гостевой системы | Linux / Ubuntu (64-bit) |
| Версия ОС | Ubuntu Server 24.04 LTS |
| Объём оперативной памяти | 2048 МБ |
| Количество ядер процессора | 2 |
| Объём дискового накопителя | 25 ГБ, динамически расширяемый |
| Разметка дискового накопителя | Use an entire disk |
| Тип установки | Ubuntu Server |
| Язык интерфейса и раскладка | English |
| Набор Featured snaps | не выбирается |

## 2. Сетевые интерфейсы

| Адаптер | Тип подключения | IP-адрес | Назначение |
|---|---|---|---|
| Адаптер 1 | NAT | 10.0.2.15/24 | Выход в интернет, обновление пакетов |
| Адаптер 2 | Виртуальный адаптер хоста (Host-only) | 192.168.56.102/24 | Связь с хостовой системой, доступ по SSH |

Параметры Host-only сети:

- Имя адаптера в VirtualBox: `VirtualBox Host-Only Ethernet Adapter #2`
- IP-адрес хостовой системы в этой сети: `192.168.56.1`
- Маска подсети: `255.255.255.0`
- DHCP: отключён, IP на гостевой машине задан статически через netplan

Файл конфигурации netplan: `/etc/netplan/00-installer-config.yaml`

Содержимое файла:

```yaml
network:
  ethernets:
    enp0s3:
      dhcp4: true
      dhcp6: true
      match:
        macaddress: 08:00:27:e0:8d:bc
      set-name: enp0s3
    enp0s8:
      dhcp4: no
      dhcp6: no
      accept-ra: no
      addresses:
        - 192.168.56.102/24
  version: 2
```

Команда проверки: `ip -brief address`

## 3. Правило проброса портов

| Параметр | Значение |
|---|---|
| Наименование правила | ssh |
| Протокол | TCP |
| Адрес хостовой системы | 127.0.0.1 |
| Порт хостовой системы | 2222 |
| Адрес гостевой системы | не заполняется |
| Порт гостевой системы | 22 |

Правило задано для Адаптера 1 (NAT).

Команда подключения с хостовой системы: `ssh student@127.0.0.1 -p 2222`

## 4. Учётные записи

| Имя | Группы | Способ аутентификации |
|---|---|---|
| student | student, adm, cdrom, dip, plugdev, lxd, sudo | Пароль (для sudo и входа) |
| devops | devops, sudo | Пароль |
| root | root | Вход запрещён (PermitRootLogin no) |

Команда проверки: `id student && id devops`

## 5. Служба SSH

- **Порт**: 2222 (изменён с 22)
- **Основной конфиг**: `/etc/ssh/sshd_config`
- **Drop-in конфиг**: `/etc/ssh/sshd_config.d/99-hardening.conf`
- **Служба**: `ssh.service` (классический режим, socket-активация отключена)

Изменённые директивы:

| Директива | Значение | Примечание |
|---|---|---|
| Port | 2222 | изменено с 22 |
| PermitRootLogin | no | вход от имени root запрещён |
| PasswordAuthentication | yes | парольная аутентификация включена |
| MaxAuthTries | 3 | изменено с 6 |

Команды проверки:

```bash
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|maxauthtries)'
sudo systemctl status ssh --no-pager
```

## 6. Правила межсетевого экрана

- **Служба**: ufw
- **Статус**: active
- **Политики по умолчанию**: `deny (incoming)`, `allow (outgoing)`, `disabled (routed)`
- **Логирование**: medium

Правила:

| Порт | Действие | Комментарий |
|---|---|---|
| 2222/tcp | LIMIT IN | SSH rate-limited |
| 80/tcp | ALLOW IN | HTTP |
| 443/tcp | ALLOW IN | HTTPS |

Команда проверки: `sudo ufw status verbose`

## 7. Снимки состояния

| Наименование | Момент создания |
|---|---|
| 01-clean-install | после установки Ubuntu и обновления системы (11.10.2026 17:58) |
| 02-keys-configured | после настройки SSH-ключей (11.10.2026 18:29) |
| 03-ssh-hardened | после изменения порта, PermitRootLogin, MaxAuthTries 11.10.2026 18:54|  

## 8. Веб-сервер

- **Устанавливаемый пакет**: `nginx` (версия 1.28.3)
- **Служба**: `nginx.service` (главный процесс от `root`, рабочие от `www-data`)
- **Путь к конфигурации ресурса**: `/etc/nginx/sites-available/devops-site`
- **Символическая ссылка**: `/etc/nginx/sites-enabled/devops-site`
- **Каталог ресурса**: `/var/www/devops-site`, владелец `devops:devops`, права `755` для каталога и `644` для файлов.

### Сертификаты TLS

- **Путь к сертификату**: `/etc/ssl/certs/devops.crt` (права `644`, владелец `root`)
- **Путь к приватному ключу**: `/etc/ssl/private/devops.key` (права `600`, владелец `root`)
- **Команда формирования сертификата**: 
  `sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt -subj "/CN=devops.local" -addext "subjectAltName=DNS:devops.local"`
- **Срок действия**: 365 дней.

## 9. Контейнеризация

- **Способ установки Docker Engine**: Официальный репозиторий Docker (пакет `docker-ce`). Версия: 29.9.2.
- **Участники группы docker**: пользователь `devops`.
- **Расположение проекта на сервере**: `~/app`
- **Расположение файла `.env`**: `~/app/.env`, права доступа `600`.
- **Публикуемые порты и адреса**: приложение опубликовано только на `127.0.0.1:5000`. Порт СУБД (5432) не публикуется.
- **Именованные тома**: `app_db_data` (для хранения данных PostgreSQL).
- **Конфигурация обратного прокси-сервера**: Nginx проксирует запросы по пути `/app/` на `http://127.0.0.1:5000/`.
