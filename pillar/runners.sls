# Специфичные настройки для каждого из 3 Debian 13 хостов (по minion id)
gitlab_runners:
  runner-debian-01:
    description: "Debian 13 Worker 01 (General CI/CD)"
    tags:
      - docker
      - debian13
      - worker-01
      - general
    concurrency: 4
    check_interval: 3
    locked: true
    run_untagged: false
    runner_type: "instance_type"
    docker_image: "docker:27-cli"
    privileged: false
    docker_volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "/cache"

  runner-debian-02:
    description: "Debian 13 Worker 02 (High-CPU / Heavy Builds)"
    tags:
      - docker
      - debian13
      - worker-02
      - high-cpu
    concurrency: 8
    check_interval: 3
    locked: true
    run_untagged: false
    runner_type: "instance_type"
    docker_image: "docker:27-cli"
    privileged: false
    docker_volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "/cache"

  runner-debian-03:
    description: "Debian 13 Worker 03 (Frontend / Node.js Builds)"
    tags:
      - docker
      - debian13
      - worker-03
      - frontend
    concurrency: 4
    check_interval: 3
    locked: true
    run_untagged: false
    runner_type: "instance_type"
    docker_image: "docker:27-cli"
    privileged: false
    docker_volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "/cache"
