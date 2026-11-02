gitlab_runner_unit:
  file.managed:
    - name: /etc/systemd/system/gitlab-runner-compose.service
    - source: salt://gitlab_runner/files/gitlab-runner-compose.service
    - user: root
    - group: root
    - mode: '0644'

gitlab_runner_systemd_reload:
  module.run:
    - service.systemctl_reload: []
    - onchanges:
      - file: gitlab_runner_unit

gitlab_runner_service:
  service.running:
    - name: gitlab-runner-compose
    - enable: true
    - reload: true
    - require:
      - module: gitlab_runner_systemd_reload
      - file: gitlab_runner_config
      - file: gitlab_runner_ca
      - file: gitlab_runner_unit
    - watch:
      - file: gitlab_runner_compose
      - file: gitlab_runner_unit
