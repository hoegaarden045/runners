{% from 'gitlab_runner/map.jinja' import settings with context %}
{% set auth_file = '/opt/runner/config/.runner_auth' %}

{% if not salt['file.file_exists'](auth_file) %}
gitlab_runner_api_update_deferred:
  test.nop:
    - name: Runner API updates start on the first apply after registration.
{% else %}
{% set runner_id = (salt['file.read'](auth_file) | load_json).get('id') %}
{% set gitlab_url = settings.gitlab_url.rstrip('/') %}
{% set api_params = settings.api %}

gitlab_runner_api_params:
  file.managed:
    - name: /opt/runner/config/.api_params
    - contents: {{ {'runner_id': runner_id, 'gitlab_url': gitlab_url, 'api': api_params} | json | json }}
    - user: root
    - group: root
    - mode: '0600'
    - require:
      - file: gitlab_runner_auth_permissions

gitlab_runner_update_api:
  http.query:
    - name: {{ (gitlab_url ~ '/api/v4/runners/' ~ runner_id) | json }}
    - method: PUT
    - header_dict:
        PRIVATE-TOKEN: {{ pillar.get('gitlab_api_token', '') | json }}
        Content-Type: application/json
    - data: {{ api_params | json | json }}
    - status: 200
    - ca_bundle: /opt/runner/certs/rootca.crt
    - require:
      - file: gitlab_runner_ca
    - onchanges:
      - file: gitlab_runner_api_params
{% endif %}
