# Общие параметры для всех GitLab раннеров
gitlab_url: "https://gitlab.example.com"

# Токен доступа GitLab с правами create_runner / manage_runner
# В продакшене рекомендуется шифровать через GPG-Pillar или передавать через Vault
gitlab_api_token: "glpat-xxxxxxxxxxxxxxxxxxxx"

# Базовый Docker-образ контейнера runner
gitlab_runner_image: "gitlab/gitlab-runner:v17.5.1"
