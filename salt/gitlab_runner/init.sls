# SaltStack State: GitLab Docker Runner Deployment & GitOps Reconciliation
# Isolated runner layout in /opt/runner with ./config and ./certs
# Pure SLS & Native Salt Modules (http.query, file.managed, file.directory)

{% set my_id = grains['id'] %}
{% set runners = pillar.get('gitlab_runners', {}) %}

{% if my_id in runners %}
{% set runner = runners[my_id] %}
{% set gitlab_url = pillar.get('gitlab_url') %}
{% set gitlab_api_token = pillar.get('gitlab_api_token') %}

{% set runner_base_dir = '/opt/runner' %}
{% set config_dir = runner_base_dir ~ '/config' %}
{% set certs_dir = runner_base_dir ~ '/certs' %}
{% set auth_file = config_dir ~ '/.runner_auth' %}
{% set meta_file = config_dir ~ '/.runner_meta' %}
{% set root_ca_file = certs_dir ~ '/rootca.crt' %}

# Подготовка JSON-пейлоада для создания раннера
{% set register_payload = {
    'runner_type': runner.get('runner_type', 'instance_type'),
    'description': runner.description,
    'tag_list': runner.tags,
    'run_untagged': runner.get('run_untagged', false),
    'locked': runner.get('locked', true)
} %}

# 1. Создание целевой структуры директорий в /opt/runner
gitlab_runner_dirs:
  file.directory:
    - names:
        - {{ runner_base_dir }}
        - {{ config_dir }}
        - {{ certs_dir }}
    - user: root
    - group: root
    - mode: '0750'
    - makedirs: True

# 2. Доставка корневого сертификата rootca.crt в /opt/runner/certs/
{{ root_ca_file }}:
  file.managed:
    {% if pillar.get('gitlab_root_ca') %}
    - contents: {{ pillar.get('gitlab_root_ca') | json }}
    {% else %}
    - source: salt://gitlab_runner/certs/rootca.crt
    {% endif %}
    - user: root
    - group: root
    - mode: '0644'
    - require:
      - file: gitlab_runner_dirs

# 3. Нативная регистрация раннера в GitLab API через http.query
# Выполняется ровно ОДИН раз (unless проверяет наличие сохраненного токена)
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
    - ca_bundle: {{ root_ca_file }}
    - unless: test -s {{ auth_file }}
    - require:
      - file: gitlab_runner_dirs
      - file: {{ root_ca_file }}

# 4. Фиксация прав на сохраненный файл авторизации (chmod 0600)
{{ auth_file }}:
  file.managed:
    - replace: False
    - user: root
    - group: root
    - mode: '0600'
    - require:
      - http: register_gitlab_runner

# 5. Отслеживание изменений метаданных в Git (теги, описание)
{{ meta_file }}:
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

# 6. Обновление метаданных в GitLab API (PUT) при наличии изменений в Git
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
    - ca_bundle: {{ root_ca_file }}
    - onchanges:
      - file: {{ meta_file }}
{% endif %}
{% endif %}

# 7. Декларативное управление config.toml в папке /opt/runner/config/
{{ config_dir }}/config.toml:
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
      - file: {{ root_ca_file }}

# 8. Декларативное управление compose.yaml в папке /opt/runner/
{{ runner_base_dir }}/compose.yaml:
  file.managed:
    - source: salt://gitlab_runner/templates/compose.yaml.j2
    - template: jinja
    - user: root
    - group: root
    - mode: '0644'
    - context:
        runner_image: {{ pillar.get('gitlab_runner_image', 'gitlab/gitlab-runner:v17.5.1') | json }}
    - require:
      - file: gitlab_runner_dirs

# 9. Запуск и поддержание сервиса через Docker Compose CLI в /opt/runner
gitlab_runner_service:
  cmd.run:
    - name: docker compose -f {{ runner_base_dir }}/compose.yaml up -d --remove-orphans
    - cwd: {{ runner_base_dir }}
    - require:
      - file: {{ runner_base_dir }}/compose.yaml
      - file: {{ config_dir }}/config.toml
      - file: {{ root_ca_file }}
    - onchanges:
      - file: {{ runner_base_dir }}/compose.yaml

{% else %}

unconfigured_minion_notice:
  test.configurable_test_state:
    - name: "Хост {{ my_id }} не сконфигурирован в pillar/runners.sls"
    - result: True
    - comment: "Пропуск настройки раннера."

{% endif %}
