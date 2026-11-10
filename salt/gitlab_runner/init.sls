{% from 'gitlab_runner/map.jinja' import settings with context %}

include:
  - gitlab_runner.prepare
  - gitlab_runner.register
  - gitlab_runner.update_api
  - gitlab_runner.configure
  - gitlab_runner.run

gitlab_runner_settings_required:
  test.configurable_test_state:
    - name: Set gitlab_url and registration.runner_type in this runner's settings.yaml.
    - result: {{ (settings.registration.runner_type and settings.gitlab_url != 'https://gitlab.example.com') | default(false, true) | json }}
    - changes: false
    - allow_test_mode_failure: true
    - require_in:
      - sls: gitlab_runner.prepare
      - sls: gitlab_runner.register
      - sls: gitlab_runner.update_api
      - sls: gitlab_runner.configure
      - sls: gitlab_runner.run

gitlab_runner_token_required:
  test.configurable_test_state:
    - name: Supply gitlab_api_token through a private Pillar outside this repository.
    - result: {{ ((pillar.get('gitlab_api_token') or '') | length > 0) | json }}
    - changes: false
    - allow_test_mode_failure: true
    - unless:
      - fun: file.file_exists
        path: /opt/runner/config/.runner_auth
    - require_in:
      - sls: gitlab_runner.prepare
      - sls: gitlab_runner.register
      - sls: gitlab_runner.configure
      - sls: gitlab_runner.run
