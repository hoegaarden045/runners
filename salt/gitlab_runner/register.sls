{% from 'gitlab_runner/map.jinja' import settings with context %}
{% set auth_file = '/opt/runner/config/.runner_auth' %}
{% set registration_params = dict(settings.api, **settings.registration) %}

gitlab_runner_existing_config:
  test.fail_without_changes:
    - name: Existing config.toml without local registration; refusing to create another runner.
    - onlyif:
      - fun: file.file_exists
        path: /opt/runner/config/config.toml
    - unless:
      - fun: file.file_exists
        path: {{ auth_file }}

gitlab_runner_registration:
  http.query:
    - name: {{ (settings.gitlab_url.rstrip('/') ~ '/api/v4/user/runners') | json }}
    - method: POST
    - header_dict:
        PRIVATE-TOKEN: {{ pillar.get('gitlab_api_token', '') | json }}
        Content-Type: application/json
    - data: {{ registration_params | json | json }}
    - status: 201
    - text_out: {{ auth_file }}
    - ca_bundle: /opt/runner/certs/rootca.crt
    - unless:
      - fun: file.file_exists
        path: {{ auth_file }}
    - require:
      - test: gitlab_runner_existing_config
      - file: gitlab_runner_dirs
      - file: gitlab_runner_ca

gitlab_runner_auth_permissions:
  file.managed:
    - name: {{ auth_file }}
    - replace: false
    - user: root
    - group: root
    - mode: '0600'
    - show_changes: false
    - require:
      - http: gitlab_runner_registration
