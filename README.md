# GitOps-управление GitLab Runners на Debian 13 через SaltStack

Данный репозиторий реализует полную **GitOps-модель** развертывания и управления жизненным циклом GitLab Docker Runners на 3 виртуальных машинах под управлением Debian 13 (Trixie) без использования Kubernetes.

Все конфигурации выполнены **исключительно в виде SaltStack SLS-манифестов и Jinja-шаблонов** (без сторонних Python-скриптов в репозитории).

---

## 1. Архитектурная схема

```
                 GitLab Repository (Source of Truth)
                                │
          ┌─────────────────────┴─────────────────────┐
          ▼                                           ▼
   Merge Request (test=True)                   Merge to 'main'
   • Автоматический Dry-Run                    • Требует обязательный Approve
   • Вывод diff в лог CI/CD                    • Запуск боевого применения
                                                      │
                                                      ▼
                                            Salt Master (Salt-API)
                                                      │ ZeroMQ
                         ┌────────────────────────────┼────────────────────────────┐
                         ▼                            ▼                            ▼
                 Debian 13 (VM 1)             Debian 13 (VM 2)             Debian 13 (VM 3)
                 runner-debian-01             runner-debian-02             runner-debian-03
                 ┌──────────────────┐         ┌──────────────────┐         ┌──────────────────┐
                 │ .runner_auth     │         │ .runner_auth     │         │ .runner_auth     │
                 │ config.toml      │         │ config.toml      │         │ config.toml      │
                 │ docker compose   │         │ docker compose   │         │ docker compose   │
                 └──────────────────┘         └──────────────────┘         └──────────────────┘
```

---

## 2. Структура репозитория

```
.
├── .gitignore
├── .gitlab-ci.yml                      # CI/CD: dry-run в MR, деплой при слиянии в main
├── README.md
├── pillar/
│   ├── top.sls                         # Маппинг хостов к pillar
│   ├── common.sls                      # Общие параметры (URL GitLab, базовый образ раннера)
│   └── runners.sls                     # Конфигурация каждого раннера (теги, описание, concurrency)
└── salt/
    ├── top.sls                         # Маппинг состояний к миньонам
    └── gitlab_runner/
        ├── init.sls                    # Идемпотентное SLS-состояние (регистрация, update, deploy)
        └── templates/
            ├── config.toml.j2          # Шаблон конфигурации gitlab-runner
            └── docker-compose.yml.j2   # Шаблон docker-compose сервиса
```

---

## 3. Выполнение всех требований задачи

| № | Требование | Как реализовано в данном репозитории |
| :--- | :--- | :--- |
| **1** | Развертывание через Docker Compose | Шаблон `docker-compose.yml.j2` + состояние `cmd.run: docker compose up -d`. |
| **2** | Автоматическая регистрация с тегами и описанием | Нативный Salt-модуль `http.query` (POST `/api/v4/user/runners`) с валидацией статуса `201` и сохранением токена в `text_out`. |
| **3** | Применение изменений тегов/описания из репозитория | Файл `/etc/gitlab-runner/.runner_meta` отслеживает diff в Git. При его изменении срабатывает `update_gitlab_runner_metadata` через нативный `http.query` (PUT `/api/v4/runners/{id}`). |
| **4** | `config.toml` хранится в репозитории | Шаблон `salt/gitlab_runner/templates/config.toml.j2` полностью описывает целевой `config.toml`. |
| **5** | Применение изменений `config.toml` на раннере | `file.managed` обновляет `/etc/gitlab-runner/config.toml`. Демон `gitlab-runner` внутри контейнера перечитывает файл на лету каждые 3 секунды. |
| **6** | Изменения только через Approve Merge Request | В `.gitlab-ci.yml` этап `apply_main` запускается **только** на ветке `main`. Ветка `main` защищена (`Protected Branch`), слияние заблокировано до получения Approve. |
| **7** | Однократное создание раннера (идемпотентность) | Директива `unless: test -s /etc/gitlab-runner/.runner_auth` на модуле `http.query` гарантирует, что регистрация раннера вызывается ровно один раз. Токен сохраняется локально. |
| **8** | Без Kubernetes | Работает на чистом Docker Compose и Debian 13. |
| **9** | Тип раннера `docker` | В `config.toml.j2` зафиксирован `executor = "docker"` с монтированием `/var/run/docker.sock`. |
| **10** | GitOps подход | Вся конфигурация раннеров версионируется в Git. Ручные изменения на ВМ перезаписываются SaltStack. |

---

## 4. Как это работает (Детальный цикл жизни)

### А. Первичная инициализация (первый запуск)
1. Salt запускает состояние `gitlab_runner/init.sls`.
2. Проверяется условие `creates: /etc/gitlab-runner/.runner_auth`. Так как файла еще нет, выполняется `POST /api/v4/user/runners` в GitLab API.
3. GitLab создает раннер с указанными тегами и описанием и возвращает JSON с `id` и `token` (`glrt-...`).
4. Токен и ID сохраняются в `/etc/gitlab-runner/.runner_auth` с правами `0600`.
5. Salt рендерит `config.toml` через Jinja. Фильтр `load_json` читает токен из `.runner_auth` и подставляет в строку `token = "glrt-..."`.
6. Salt рендерит `docker-compose.yml` и запускает `docker compose up -d`.

### Б. Изменение тегов или описания раннера
1. Инженер открывает Merge Request и правит теги в `pillar/runners.sls`:
   ```yaml
   runner-debian-01:
     tags:
       - docker
       - debian13
       - new-custom-tag  # <--- Добавлен новый тег
   ```
2. В MR автоматически отрабатывает джоба `plan_mr` с `test=True`. В логе видно, какие изменения планируются.
3. Лид делает **Approve** и нажимает **Merge**.
4. Запускается джоба `apply_main`:
   - Salt Master применяет состояние к `runner-debian-01`.
   - Salt видит, что содержимое файла `/etc/gitlab-runner/.runner_meta` изменилось.
   - Триггер `onchanges` запускает `PUT /api/v4/runners/{id}` в API GitLab.
   - **Результат:** Теги в GitLab обновлены мгновенно. Раннер не пересоздавался, контейнер не перезапускался.

### В. Изменение параметров `config.toml` (например, `concurrency`)
1. Инженер правит `concurrency: 8` в `pillar/runners.sls`.
2. После Approve и Merge Salt перерендеривает `/etc/gitlab-runner/config.toml`.
3. Контейнер `gitlab-runner` подхватывает новое значение `concurrency` на лету в течение 3 секунд.

---

## 5. Настройка окружения

### На стороне GitLab:
1. **Protected Branches:**
   - Перейти в **Settings -> Repository -> Protected Branches**.
   - Для ветки `main`: `Allowed to merge: Developers + Maintainers`, `Allowed to push: No one`.
2. **Merge Request Approvals:**
   - Перейти в **Settings -> Merge requests -> Merge request approvals**.
   - Включить `Require approval` (указать минимум 1 аппрувера).
   - Включить опции `Prevent approval by author` и `Reset approvals on push`.
3. **CI/CD Variables (Settings -> CI/CD -> Variables):**
   - `SALT_MASTER_URL`: URL вашего Salt-API (например, `https://salt-master.internal:8000`).
   - `SALT_API_USER`: пользователь с правами вызова Salt-API.
   - `SALT_API_PASSWORD`: пароль пользователя Salt-API (Masked).

### На стороне Salt Master:
Включить и настроить `salt-api` (модуль `rest_cherrypy`):
```yaml
# /etc/salt/master.d/api.conf
rest_cherrypy:
  port: 8000
  ssl_crt: /etc/pki/tls/certs/saltapi.crt
  ssl_key: /etc/pki/tls/certs/saltapi.key

external_auth:
  pam:
    gitlab-ci:
      - 'runner-*':
        - state.apply
        - fileserver.update
```
