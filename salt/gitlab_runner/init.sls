# SaltStack State: GitLab Docker Runner Deployment & GitOps Reconciliation
# Pure SLS & Native Salt Modules (http.query, file.managed, file.directory)
# No Python scripts in repo, no cmd.run for HTTP/API

{% set my_id = grains['id'] %}
{% set runners = pillar.get('gitlab_runners', {}) %}

{% if my_id in runners %}
{% set runner = runners[my_id] %}
{% set gitlab_url = pillar.get('gitlab_url') %}
{% set gitlab_api_token = pillar.get('gitlab_api_token') %}
{% set auth_file = '/etc/gitlab-runner/.runner_auth' %}

# Подготовка JSON-пейлоада для создания раннера
{% set register_payload = {
    'runner_type': runner.get('runner_type', 'instance_type'),
    'description': runner.description,
    'tag_list': runner.tags,
    'run_untagged': runner.get('run_untagged', false),
    'locked': runner.get('locked', true)
} %}

# 1. Убеждаемся в наличии необходимых директорий
gitlab_runner_dirs:
  file.directory:
    - names:
        - /etc/gitlab-runner
        - /opt/gitlab-runner
    - user: root
    - group: root
    - mode: '0750'
    - makedirs: True

# 2. Нативный HTTP POST-запрос к GitLab API через state http.query
# Выполняется ровно один раз: unless проверяет наличие непустого .runner_auth
# Ответ API (id и токен glrt-...) сохраняется прямо в text_out
register_gitlab_runner:
  http.query:
    - name: '{{ gitlab_url }}/api/v4/user/runners'
    - method: POST
    - header_dict:
        PRIVATE-TOKEN: '{{ gitlab_api_token }}'
        Content-Type: 'application/json'
    - data: '{{ register_payload | json }}'
    - status: 201
    - text_out: {{ auth_file }}
    - unless: test -s {{ auth_file }}
    - require:
      - file: gitlab_runner_dirs

# 3. Фиксация прав на сохраненный файл авторизации (chmod 0600)
{{ auth_file }}:
  file.managed:
    - replace: False
    - user: root
    - group: root
    - mode: '0600'
    - require:
      - http: register_gitlab_runner

# 4. Отслеживание изменений метаданных в Git (Pillar)
# Файл .runner_meta меняется только если в Git изменены теги или описание
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

# 5. Нативное обновление метаданных в GitLab API через http.query (PUT)
# Срабатывает только при наличии изменений в Git через onchanges
{% if salt['file.file_exists'](auth_file) %}
{% set auth = salt['file.read'](auth_file) | load_json %}
{% set runner_id = auth.get('id') %}
{% if runner_id %}
{% set update_payload = {
    'description': runner.description,
    'tag_list': runner.tags,
    'run_untagged': runner.get('run_untagged', false),
    'locked': runner.get('locked', true)
} %}
update_gitlab_runner_metadata:
  http.query:
    - name: '{{ gitlab_url }}/api/v4/runners/{{ runner_id }}'
    - method: PUT
    - header_dict:
        PRIVATE-TOKEN: '{{ gitlab_api_token }}'
        Content-Type: 'application/json'
    - data: '{{ update_payload | json }}'
    - status: 200
    - onchanges:
      - file: /etc/gitlab-runner/.runner_meta
{% endif %}
{% endif %}

# 6. Декларативное управление config.toml из Jinja-шаблона
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
      - http: register_gitlab_runner

# 7. Декларативное управление docker-compose.yml
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

# 8. Запуск и поддержание контейнера через Docker Compose CLI
gitlab_runner_service:
  cmd.run:
    - name: docker compose -f /opt/gitlab-runner/docker-compose.yml up -d --remove-orphans
    - require:
      - file: /opt/gitlab-runner/docker-compose.yml
      - file: /etc/gitlab-runner/config.toml
    - onchanges:
      - file: /opt/gitlab-runner/docker-compose.yml

{% else %}

unconfigured_minion_notice:
  test.configurable_test_state:
    - name: "Хост {{ my_id }} не сконфигурирован в pillar/runners.sls"
    - result: True
    - comment: "Пропуск настройки раннера."

{% endif %}
