# Общие параметры для всех GitLab раннеров
gitlab_url: "https://gitlab.example.com"

# Токен доступа GitLab с правами create_runner / manage_runner
# В продакшене рекомендуется шифровать через GPG-Pillar или передавать через Vault
gitlab_api_token: "glpat-xxxxxxxxxxxxxxxxxxxx"

# Базовый Docker-образ контейнера runner
gitlab_runner_image: "gitlab/gitlab-runner:v17.5.1"

# Корневой сертификат удостоверяющего центра (CA) для подключения к GitLab по HTTPS
# Если не задан, используется файл salt://gitlab_runner/certs/rootca.crt
# gitlab_root_ca: |
#   -----BEGIN CERTIFICATE-----
#   ...
#   -----END CERTIFICATE-----
