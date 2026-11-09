gitlab_runner_dirs:
  file.directory:
    - names:
      - /opt/runner
      - /opt/runner/config
      - /opt/runner/certs
    - user: root
    - group: root
    - mode: '0700'
    - makedirs: true

gitlab_runner_ca:
  file.managed:
    - name: /opt/runner/certs/rootca.crt
    - source: salt://gitlab_runner/certs/rootca.crt
    - user: root
    - group: root
    - mode: '0644'
    - require:
      - file: gitlab_runner_dirs

gitlab_runner_compose:
  file.managed:
    - name: /opt/runner/compose.yaml
    - source: salt://gitlab_runner/files/compose.yaml
    - user: root
    - group: root
    - mode: '0644'
    - require:
      - file: gitlab_runner_dirs
