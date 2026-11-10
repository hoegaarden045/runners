# Управление GitLab Runner через Salt

Репозиторий устанавливает Docker на minion, регистрирует раннеры в GitLab
и запускает их через Docker Compose.

## Принцип работы

1. Salt читает настройки и шаблон конфигурации из `salt/runners/<minion-id>/`.
2. При первом применении Salt регистрирует раннер через POST с полями из `api` и `registration`. При совпадении ключей приоритет у `registration`. Полученные ID и токен сохраняются в `/opt/runner/config/.runner_auth`.
3. При повторном применении Salt пропускает регистрацию, если существует `.runner_auth`. Для существующего раннера Salt записывает поля из `api` в `.api_params` и отправляет PUT по сохранённому ID при создании или изменении этого файла.
4. Salt формирует `config.toml` с сохранёнными ID и токеном и при каждом применении выполняет `docker compose up -d` через `cmd.run`. Compose создаёт отсутствующий контейнер, запускает остановленный или применяет изменения конфигурации. Salt отмечает выполнение команды как изменение даже при уже работающем контейнере.

## Добавление раннера

1. Для нового раннера нужно создать каталог `salt/runners/<minion-id>/`. Имя каталога должно совпадать с ID minion и соответствовать текущему шаблону целей `runner-minon*`.
2. В этот каталог нужно скопировать образцы из `templates/runner/`. [settings.yaml](templates/runner/settings.yaml) · [config.toml.j2](templates/runner/config.toml.j2)
3. В `settings.yaml` нужно указать адрес GitLab в `gitlab_url` и заполнить блок `registration`. Для `project_type` нужен `project_id`, для `group_type` — `group_id`, а для `instance_type` достаточно `runner_type`. Эти параметры используются при создании раннера.
4. В блоке `api` нужно задать описание, теги и остальные параметры, общие для регистрации и обновления раннера.
5. В `config.toml.j2` нужно настроить имя раннера, параллелизм и Docker executor. Описание доступных параметров есть в документации GitLab. [Документация config.toml](https://docs.gitlab.com/runner/configuration/advanced-configuration/)
6. Для первого развёртывания нужно настроить приватный Pillar с `gitlab_api_token`. Токену нужны права `create_runner` и `manage_runner`. Для доступа к GitLab Salt использует CA из `salt/gitlab_runner/certs/rootca.crt`.
7. После заполнения конфигурации нужно открыть merge request в `main`. После слияния CI запускает `validate` с `test=True`, а затем `deploy` с применением конфигурации. Результат выполнения нужно проверить в пайплайне.
