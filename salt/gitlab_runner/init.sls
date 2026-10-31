# SaltStack State: GitLab Docker Runner Deployment & GitOps Reconciliation
# Debian 13 (Trixie) - No Python files in repo, pure SLS & Jinja

{% set my_id = grains['id'] %}
{% set runners = pillar.get('gitlab_runners', {}) %}

{% if my_id in runners %}
{% set runner = runners[my_id] %}
{% set gitlab_url = pillar.get('gitlab_url') %}
{% set gitlab_api_token = pillar.get('gitlab_api_token') %}

# 1. Убеждаемся в наличии необходимых директорий на хосте
gitlab_runner_dirs:
  file.directory:
    - names:
        - /etc/gitlab-runner
        - /opt/gitlab-runner
    - user: root
    - group: root
    - mode: '0750'
    - makedirs: True

# 2. Идемпотентная первичная регистрация в GitLab API
# Выполняется ровно ОДИН раз благодаря директиве creates.
# Сохраняет id и glrt-токен в /etc/gitlab-runner/.runner_auth
register_gitlab_runner:
  cmd.run:
    - name: >-
        PAYLOAD='{"runner_type":"{{ runner.get('runner_type', 'instance_type') }}","description":"{{ runner.description }}","tag_list":{{ runner.tags | json }},"run_untagged":{{ runner.get('run_untagged', false) | lower }},"locked":{{ runner.get('locked', true) | lower }}}' &&
        RESP=$(curl -sS --fail -X POST "{{ gitlab_url }}/api/v4/user/runners"
        -H "PRIVATE-TOKEN: {{ gitlab_api_token }}"
        -H "Content-Type: application/json"
        -d "$PAYLOAD") &&
        echo "$RESP" > /etc/gitlab-runner/.runner_auth &&
        chmod 600 /etc/gitlab-runner/.runner_auth
    - creates: /etc/gitlab-runner/.runner_auth
    - require:
      - file: gitlab_runner_dirs

# 3. Отслеживание изменений метаданных раннера в Git (теги, описание, блокировки).
# Файл .runner_meta хранит актуальное желаемое состояние из Pillar.
# Если в Git изменились теги или описание - файл меняется и триггерит onchanges на обновление в GitLab API.
/etc/gitlab-runner/.runner_meta:
  file.managed:
    - contents: |
        description: {{ runner.description }}
        tags: {{ runner.tags | sort | join(',') }}
        run_untagged: {{ runner.get('run_untagged', false) }}
        locked: {{ runner.get('locked', true) }}
    - user: root
    - group: root
    - mode: '0600'
    - require:
      - file: gitlab_runner_dirs

# 4. Обновление метаданных в GitLab API при изменении тегов/описания в репозитории
update_gitlab_runner_metadata:
  cmd.run:
    - name: >-
        RUNNER_ID=$(sed -n 's/.*"id": *\([0-9]*\).*/\1/p' /etc/gitlab-runner/.runner_auth) &&
        PAYLOAD='{"description":"{{ runner.description }}","tag_list":{{ runner.tags | json }},"run_untagged":{{ runner.get('run_untagged', false) | lower }},"locked":{{ runner.get('locked', true) | lower }}}' &&
        curl -sS --fail -X PUT "{{ gitlab_url }}/api/v4/runners/${RUNNER_ID}"
        -H "PRIVATE-TOKEN: {{ gitlab_api_token }}"
        -H "Content-Type: application/json"
        -d "$PAYLOAD"
    - onlyif: test -f /etc/gitlab-runner/.runner_auth
    - onchanges:
      - file: /etc/gitlab-runner/.runner_meta
    - require:
      - cmd: register_gitlab_runner

# 5. Декларативное управление config.toml из Jinja-шаблона
# Подставляет токен и ID из локального .runner_auth
/etc/gitlab-runner/config.toml:
  file.managed:
    - source: salt://gitlab_runner/templates/config.toml.j2
    - template: jinja
    - user: root
    - group: root
    - mode: '0600'
    - context:
        runner: {{ runner | json }}
        gitlab_url: {{ gitlab_url | json }}
    - require:
      - cmd: register_gitlab_runner

# 6. Декларативное управление docker-compose.yml
/opt/gitlab-runner/docker-compose.yml:
  file.managed:
    - source: salt://gitlab_runner/templates/docker-compose.yml.j2
    - template: jinja
    - user: root
    - group: root
    - mode: '0644'
    - context:
        runner_image: {{ pillar.get('gitlab_runner_image', 'gitlab/gitlab-runner:v17.5.1') | json }}
    - require:
      - file: gitlab_runner_dirs

# 7. Запуск и поддержание сервиса через Docker Compose
# При изменении docker-compose.yml контейнер автоматически пересоздается
gitlab_runner_service:
  cmd.run:
    - name: docker compose -f /opt/gitlab-runner/docker-compose.yml up -d --remove-orphans
    - require:
      - file: /opt/gitlab-runner/docker-compose.yml
      - file: /etc/gitlab-runner/config.toml
    - onchanges:
      - file: /opt/gitlab-runner/docker-compose.yml

{% else %}

# Если данный хост не описан в pillar/runners.sls, выводим информационное сообщение
unconfigured_minion_notice:
  test.configurable_test_state:
    - name: "Хост {{ my_id }} не сконфигурирован как gitlab-runner в pillar/runners.sls"
    - result: True
    - comment: "Пропуск настройки раннера для данного хоста."

{% endif %}
