gitlab_runner_compose_running:
  cmd.run:
    - name: /usr/bin/docker compose -f /opt/runner/compose.yaml up -d
    - cwd: /opt/runner
    - require:
      - file: gitlab_runner_compose
      - file: gitlab_runner_config
      - file: gitlab_runner_ca
