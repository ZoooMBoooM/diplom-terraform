### diplom-terraform

Terraform-конфигурация инфраструктуры дипломного проекта
в Yandex Cloud и сценарии первоначального развёртывания.

## Назначение

- Управление сетью, подсетью, security group и виртуальной машиной.
- Первоначальная настройка ВМ через cloud-init.
- Передача актуального внешнего IP в Ansible inventory.
- Запуск Ansible.
- Синхронизация адреса и fingerprint с GitHub Actions secrets.

Рабочая зона: `ru-central1-a`.
Управляющий хост: Debian 13.
Пользователь управляющего хоста в текущих сценариях: `root`.
Пользователь целевой ВМ: `ubuntu`.

## Расположение репозиториев

Сценарии рассчитаны на соседние каталоги:

```text
/root/diplom/
├── app/         # репозиторий diplom
├── terraform/   # репозиторий diplom-terraform
└── ansible/     # репозиторий diplom-ansible
```

## Предварительные условия

На управляющем хосте необходимы:

- Terraform.
- Ansible и коллекции из Ansible requirements.yml.
- Git.
- OpenSSH client.
- curl.
- netcat-openbsd.
- GitHub CLI `gh` для синхронизации secrets.

До запуска должны быть подготовлены:

1. Доступ к Yandex Cloud и параметры Terraform.
2. Доступ к backend Terraform, если он настроен.
3. SSH-ключ `/root/.ssh/github_actions_diplom`
   и соответствующий публичный ключ.
4. Настройка cloud-init для добавления публичного ключа
   пользователю `ubuntu`.
5. Доступный Docker-образ приложения.
6. Клоны трёх репозиториев в указанной структуре.
7. GitHub Actions secrets для Docker Hub и SSH-пользователя.

Фактические входные параметры находятся в `variables.tf`,
настройки провайдера и backend — в Terraform-конфигурации.
Секретные значения в README и исходные файлы не вставляются.

## Подготовка Ansible

```bash
cd /root/diplom/ansible
ansible-galaxy collection install -r requirements.yml
```

## Развёртывание

```bash
/root/diplom/terraform/scripts/deploy.sh
```

Сценарий выполняет:

1. Проверку инструментов и обязательных файлов.
2. Terraform init и validate.
3. Создание и показ Terraform-плана.
4. Запрос подтверждения применения.
5. Применение сохранённого плана.
6. Получение output `vm_external_ip`.
7. Формирование `ansible/inventory/hosts.ini`.
8. Ожидание TCP-порта 22.
9. SSH-подключение и ожидание cloud-init.
10. Запуск Ansible site.yml.
11. Внешнюю HTTP-проверку.
12. Вывод адреса и ECDSA fingerprint.

Перед подтверждением необходимо проверить Terraform-план.

При первом подключении к новой ВМ необходимо проверить предложенный
SSH fingerprint по независимому доверенному источнику,
например через доступную консоль облака.
Не отключать проверку host key.

## Синхронизация GitHub Actions secrets

Необходимо один раз авторизоваться в GitHub CLI:

```bash
gh auth login --hostname github.com --git-protocol https --web
```

После развёртывания:

```bash
/root/diplom/terraform/scripts/sync-github-secrets.sh
```

Сценарий:

- определяет репозиторий приложения по его `origin`;
- получает IP из Terraform output;
- получает ECDSA fingerprint через доверенное SSH-соединение;
- показывает целевой репозиторий и значения;
- запрашивает подтверждение;
- обновляет `VM_HOST` и `VM_HOST_FINGERPRINT`.

Сценарий не изменяет VM_USER, VM_SSH_KEY и Docker Hub credentials.
Сценарий не запускает CI/CD автоматически.
Обновления двух secrets выполняются последовательно, не атомарно.

## Проверка результата

```bash
VM_IP="$(terraform -chdir=/root/diplom/terraform output -raw vm_external_ip)"
curl --fail --connect-timeout 10 --max-time 30 "http://$VM_IP:8080/"
```

После синхронизации secrets необходимо выполнить push изменения приложения
либо вручную запустить CI/CD в репозитории `diplom`.

## Безопасность

Не опубликованы:

- приватные SSH-ключи;
- облачные credentials и GitHub/Docker Hub tokens;
- Terraform state и его резервные копии;
- сохранённые Terraform-планы;
- каталог `.terraform/`;
- tfvars-файлы с секретными значениями.

Файл `.terraform.lock.hcl` сохраняется в Git.

## Статус проверки

Повторное применение на существующей ВМ проверено:
Terraform не предложил изменений, Ansible завершился без ошибок.
Синхронизация GitHub Actions secrets проверена.
