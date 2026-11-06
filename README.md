# GitLab project runners managed by Salt

Target: Debian 13 minions, Salt 3008 and GitLab 17.x.
The configuration has not been validated on a live installation.

## Configuration layout

```text
salt/gitlab_runner/
  init.sls
  map.jinja
  prepare.sls
  register.sls
  configure.sls
  service.sls
  certs/rootca.crt
  files/
    compose.yaml
    gitlab-runner-compose.service
  runners/
    runner-minon1/settings.yaml
    runner-minon1/config.toml.j2
    runner-minon2/settings.yaml
    runner-minon2/config.toml.j2
    runner-minon3/settings.yaml
    runner-minon3/config.toml.j2
```

Directory names must match minion IDs. Both top files and CI target
`runner-minon*`. To add a runner, copy a directory and submit a merge request.

- `settings.yaml`: GitLab URL, creation-only fields under `registration`, and
  shared runner API parameters under `api`. Move creation-only keys into
  `registration` in custom configs.
- `config.toml.j2`: per-runner process configuration. Edit concurrency and
  Docker executor settings directly in this file. ID/token are read locally.
- `files/compose.yaml`: shared Compose configuration using Runner v17.5.1.
- `certs/rootca.crt`: replace the existing placeholder with the real PEM CA.

Files under `salt/` are not a secret store: other minions may access them.
Supply `gitlab_api_token` through private Pillar outside this repository,
targeted to the intended minions. Check token permissions against the installed
GitLab release. The token is required for registration and API updates. Use the
`manage_runner` scope and an appropriate project role for updates.

## Registration

The minion registers through the native `http.query` state. There are no custom
Salt states, `cmd.*` states, shell scripts, curl or jq dependencies on the minion.

SLS files use `unless`/`onlyif` for local file checks and `require`/`require_in`
for dependencies. Jinja loads settings and supplies values, without selecting
state branches. The native `test.*` states are configuration checks, not a
separate automated test suite. Missing settings block dependent states; the API
token check is skipped when local registration already exists.

1. If `/opt/runner/config/.runner_auth` exists, skip creation.
2. Without that file, refuse creation if config.toml already exists.
3. Otherwise POST /api/v4/user/runners with the merged `api` and `registration`
   blocks, using the private API token. If a key occurs in both blocks,
   `registration` takes precedence for POST.
4. Save the response, including ID/token, in `.runner_auth` through `text_out`.
   Require HTTP 201 and enforce file permissions 0600.
5. Render config.toml and manage the Compose service.

If GitLab creates the runner but the response is not saved, another run can create
a duplicate. Investigate interrupted creation before retrying. Salt runs must not
be started concurrently; the file checks are not an atomic distributed lock.

Existence of `.runner_auth` prevents another POST; it does not validate credentials
with GitLab. A malformed file will fail TOML rendering rather than recreate the
runner. Existing config.toml without .runner_auth is not imported automatically.

Set `registration.runner_type` to `project_type`, `group_type`, or
`instance_type`. Supply `project_id` for a project runner or `group_id` for a
group runner in the same block. For an instance runner, omit both IDs.
GitLab validates the scope-specific fields when it receives the POST.

## Runner API updates

Add or edit parameters under `api` in `settings.yaml` using fields supported by
both GitLab endpoints. The minion writes the entire `api` block, the GitLab URL,
and the runner ID to `/opt/runner/config/.api_params` with mode 0600. Creating or
changing this file triggers a PUT whose body is the `api` block. Keep credentials
in private Pillar.

On initial registration, the POST supplies the settings and the first later
apply creates `.api_params` and sends a PUT. Project ID and runner type are used
for registration.

TODO: Record successfully applied parameters only after HTTP 200 and retry a
failed update. Currently the file changes before the request. Salt reports a
failed PUT, and the next apply skips the request if the file does not change.

The HTTP state may return the registration response in Salt results. CI prints
only state names and result flags, but result.json and Salt job caches may still
contain the token. Full result handling is deferred as agreed; restrict access
to these files and do not publish them as CI artifacts.

## Runner configuration and Compose

The managed VM layout is:

```text
/opt/runner/
  compose.yaml
  config/
    config.toml
    .runner_auth
    .api_params
  certs/
    rootca.crt
```

Directories have mode 0700; config.toml and .runner_auth have mode 0600.
TOML diffs are suppressed. The template reads ID/token after registration; its
placeholder values are for first-run dry-runs only, not a valid runner identity.

Docker Engine, the Docker Compose plugin and systemd must already be available.
The unit assumes the Docker CLI is installed at /usr/bin/docker.
Salt installs a systemd unit and uses `service.running` to enable/start it.
The unit runs Compose up -d on start/reload and Compose stop on stop.
Compose/unit changes trigger a reload; TOML changes rely on Runner's own reload.
This is a oneshot service: its active status does not prove the container is
healthy or recover a manually removed container on every Salt run.
The container retains the Compose restart policy unless-stopped.

The default job configuration retains the Docker socket mount, allowing jobs
to control the host Docker daemon.
Automatic authentication-token rotation is not reconciled with .runner_auth;
resolve token ownership before applying these templates if rotation is enabled.

## CI and Salt Master

Required CI variables:

- `SALT_MASTER_URL`: HTTPS Salt API endpoint.
- `SALT_API_USER` and `SALT_API_PASSWORD`: restricted Salt API credentials.
- `SALT_API_CA`: GitLab File variable containing the Salt API CA certificate.

CI still uses curl/jq inside its job image to call Salt API; these are not Salt
cmd modules or minion dependencies. Credentials must be scoped to trusted
pipelines. Configure protected main and merge approvals in GitLab itself.
Use a management CI runner independent of the managed runner fleet.

The Salt API identity needs fileserver.update runner access and state.apply on
the intended minions. Configure GitFS with salt/ as root and main mapped to base.
Expose MR source branches as environments. Both plan and apply use base Pillar
for private data. These are existing Master prerequisites, not configured here.

MR pipelines run YAML linting and Salt test=True against the source branch.
Main pipelines apply base. Apply jobs are serialized. Empty responses, missing
minions and failed Salt states fail the job.
Branch environments are mutable: deployment is not pinned to an immutable SHA.
Dry-run does not register a runner or validate the real API response.

## Validation and rollback

No tests were written or run. Syntax checks, Salt rendering, API requests,
package installation and deployment have not been executed during authoring.

Validate registration, repeat application, TOML edits and failed registration
on a non-production minion before rollout.
Rollback: restore the previous repository configuration and apply it while
preserving .runner_auth. No GitLab object should be deleted as part of rollback.
The added systemd unit must be accounted for when returning to another service
management method; stopping it stops the Compose project.
