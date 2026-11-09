{% from 'gitlab_runner/map.jinja' import runner_dir, settings with context %}

gitlab_runner_config:
  file.managed:
    - name: /opt/runner/config/config.toml
    - source: salt://{{ runner_dir }}/config.toml.j2
    - template: jinja
    - context:
        gitlab_url: {{ settings.gitlab_url | json }}
    - user: root
    - group: root
    - mode: '0600'
    - show_changes: false
    - onlyif:
      - fun: file.file_exists
        path: /opt/runner/config/.runner_auth
    - require:
      - file: gitlab_runner_auth_permissions
