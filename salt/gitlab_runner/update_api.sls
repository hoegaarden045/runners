{% from 'gitlab_runner/map.jinja' import settings with context %}
{% set auth_file = '/opt/runner/config/.runner_auth' %}

{% if not salt['file.file_exists'](auth_file) %}
gitlab_runner_api_update_deferred:
  test.nop:
    - name: Runner API updates start on the first apply after registration.
{% else %}
{% set runner_id = (salt['file.read'](auth_file) | load_json).get('id') %}
{% if runner_id is integer and runner_id > 0 %}
{% set gitlab_url = settings.gitlab_url.rstrip('/') %}
{% set api_params = {
    'description': settings.api.description,
    'tag_list': settings.api.tag_list,
    'locked': settings.api.locked,
    'run_untagged': settings.api.run_untagged,
} %}

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
    # TODO: Save the applied parameters after HTTP 200 so a failed PUT is retried.
    # Currently the file changes before the request, so the next apply skips it.
    - onchanges:
      - file: gitlab_runner_api_params
{% else %}
gitlab_runner_invalid_api_id:
  test.fail_without_changes:
    - name: Expected a positive integer runner ID in .runner_auth.
{% endif %}
{% endif %}
