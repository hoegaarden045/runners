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
