# AP Local Development Environment
# Run `just` to see all available commands

set dotenv-load
set shell := ["bash", "-euo", "pipefail", "-c"]

export COMPOSE_FILE := justfile_directory() / "compose.yml"
code_dir := env("CODE_DIR", home_directory() / "code")
ap_repos := "beanworksapi beanauth beanworksui service-haproxy cdk"
api_dir := code_dir / "beanworksapi"
ui_dir := code_dir / "beanworksui"

# ---------------------------------------------------------------------------
# Repo registry: name → bitbucket repo
# ---------------------------------------------------------------------------
[private]
clone name url branch="master":
    #!/usr/bin/env bash
    dir="{{ code_dir }}/{{ name }}"
    if [[ -d "$dir" ]]; then
      echo "Skipping {{ name }} — already at $dir"
    else
      echo "Cloning {{ name }} → $dir ..."
      git clone "{{ url }}" "$dir"
      git -C "$dir" checkout "{{ branch }}"
    fi

# Clone repos, generate certs, install UI deps
setup:
    just clone beanworksapi    git@bitbucket.org:beanworks/beanworksapi.git      master
    just clone beanauth        git@bitbucket.org:beanworks/beanauth.git          master
    just clone beanworksui     git@bitbucket.org:beanworks/beanworksui.git       master
    just clone service-haproxy git@bitbucket.org:beanworks/service-haproxy.git   master
    just clone cdk             git@bitbucket.org:beanworks/cdk.git               master
    just _certs
    just _ensure-env-local
    just ui-install
    @echo "Done. Repos cloned to {{ code_dir }}/, UI deps installed."

# Zero to working app: clone → build → up → seed
bootstrap: setup build up db-reset ui-dev
    @echo ""
    @echo "Ready at https://localhost"
    @echo "Login with any username (e.g. 's') and password 'pwd'"

# Generate local SSL certs for cloudfront (if missing)
[private]
_certs:
    #!/usr/bin/env bash
    cert_dir="{{ justfile_directory() }}/certs"
    mkdir -p "$cert_dir"
    if [[ ! -f "$cert_dir/cert.pem" ]]; then
      echo "Generating local SSL certs ..."
      mkcert -cert-file "$cert_dir/cert.pem" -key-file "$cert_dir/key.pem" localhost 127.0.0.1
    fi

# Ensure .env.local has ENVIRONMENT=local for AWS stub
[private]
_ensure-env-local:
    #!/usr/bin/env bash
    env_local="{{ api_dir }}/.env.local"
    if [[ ! -f "$env_local" ]]; then
      echo "ENVIRONMENT=local" > "$env_local"
      echo "Created $env_local with ENVIRONMENT=local"
    elif ! grep -q '^ENVIRONMENT=local' "$env_local"; then
      echo "" >> "$env_local"
      echo "ENVIRONMENT=local" >> "$env_local"
      echo "Added ENVIRONMENT=local to $env_local"
    fi

# ---------------------------------------------------------------------------
# Docker compose
# ---------------------------------------------------------------------------

# Start everything (pre-init → up -d → init → post-up fixes)
up *args="":
    just _hook pre_init
    @echo "Bringing up AP local env ..."
    docker compose up -d --force-recreate {{ args }}
    just _hook init
    just _post-up

# Stop and remove containers
down *args="":
    docker compose down {{ args }}

# Build/rebuild docker images
build *args="":
    docker compose build {{ args }}

# Restart services
restart *args="":
    docker compose restart {{ args }}

# View logs (e.g. just logs -f api)
logs *args="":
    docker compose logs {{ args }}

# Show running containers
status *args="":
    docker compose ps {{ args }}

# Open bash in a running container
shell svc *cmd="bash":
    docker compose exec {{ svc }} {{ cmd }}

# Open interactive bash in the API container (aliases available)
api:
    docker compose exec api bash -ic "cd /var/www/html && exec bash"

# List all compose services
list:
    @docker compose config --services 2>/dev/null | sort

# Pull latest docker images for all services
pull *args="":
    docker compose pull {{ args }}

# Tear down (images|containers|all)
purge what="containers":
    #!/usr/bin/env bash
    case "{{ what }}" in
      images)     docker compose down --rmi all ;;
      containers) docker compose down -v ;;
      all)        docker compose down --rmi all -v --remove-orphans ;;
      *)          echo "Usage: just purge [images|containers|all]"; exit 1 ;;
    esac

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

# Load demo fixtures (drops existing data, creates fresh demo org)
db-reset:
    #!/usr/bin/env bash
    echo "Preparing API container ..."
    just _stub-clamdscan
    just _fix-cache-perms
    echo ""
    echo "Warming Symfony cache ..."
    docker compose exec api bash -c "php /var/www/html/bin/console cache:warmup --env=prod"
    just _fix-cache-perms
    echo ""
    echo "Running setupdemo (this takes a few minutes) ..."
    docker compose exec api bash -ic "source /root/.commonrc && setupdemo"
    echo ""
    echo "Resetting all passwords to 'pwd' ..."
    docker compose exec api bash -ic "source /root/.commonrc && pwdpwd"
    echo ""
    echo "Done. Login at https://localhost with any user and password 'pwd'"

# Reset all user passwords to 'pwd'
db-pwdreset:
    docker compose exec api bash -ic "source /root/.commonrc && pwdpwd"

# Run a Symfony console command (e.g. just console bean:bcm)
console *args="":
    docker compose exec api bash -c "php /var/www/html/bin/console --env=prod {{ args }}"

# ---------------------------------------------------------------------------
# UI (beanworksui — classic + espresso)
# ---------------------------------------------------------------------------

# Install UI dependencies (yarn in classic + espresso)
ui-install:
    make -C "{{ ui_dir }}" prerequisites

# Build UI for local dev (classic + espresso → build/)
ui-dev theme="beanworks":
    NODE_OPTIONS=--openssl-legacy-provider make -C "{{ ui_dir }}" dev theme={{ theme }}

# Build UI with espresso live reload (rebuilds on file change)
ui-live theme="beanworks":
    NODE_OPTIONS=--openssl-legacy-provider make -C "{{ ui_dir }}" dev-live theme={{ theme }}

# Build UI with espresso hot module replacement on :4443
ui-hot theme="beanworks":
    NODE_OPTIONS=--openssl-legacy-provider make -C "{{ ui_dir }}" dev-hot theme={{ theme }}

# Run UI tests (classic karma + espresso jest)
ui-test:
    make -C "{{ ui_dir }}" espresso-tests
    make -C "{{ ui_dir }}" classic-tests

# Run UI linters
ui-lint:
    make -C "{{ ui_dir }}" run-lint

# Clean UI build output
ui-clean:
    make -C "{{ ui_dir }}" clean

# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

# Show git branches for AP repos
branch repo="":
    #!/usr/bin/env bash
    repos="{{ repo }}"
    [[ -z "$repos" ]] && repos="{{ ap_repos }}"
    for name in $repos; do
      dir="{{ code_dir }}/${name}"
      printf "%-20s " "${name}:"
      if [[ -d "$dir/.git" ]]; then
        git -C "$dir" rev-parse --abbrev-ref HEAD
      else
        echo "(not cloned)"
      fi
    done

# Git pull for AP repos (or just one: just update beanworksapi)
update repo="":
    #!/usr/bin/env bash
    repos="{{ repo }}"
    [[ -z "$repos" ]] && repos="{{ ap_repos }}"
    for name in $repos; do
      dir="{{ code_dir }}/${name}"
      if [[ ! -d "$dir/.git" ]]; then
        echo "${name}: not cloned, skipping."
        continue
      fi
      branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD)
      echo "${name}: pulling ${branch} ..."
      git -C "$dir" pull
    done

# Git pull repos + docker pull images + rebuild
refresh:
    @echo "Updating git repos ..."
    just update
    @echo ""
    @echo "Pulling latest docker images ..."
    just pull
    @echo ""
    @echo "Rebuilding local images ..."
    just build

# ---------------------------------------------------------------------------
# Coder workspace (remote — DCM handles orchestration, just handles the rest)
# ---------------------------------------------------------------------------

# Default Coder workspace name
coder_ws := env("CODER_WS", "sajeev-ap-local")
coder_api := "bean-api-1"

# Show Coder workspace status
coder-status:
    coder show {{ coder_ws }}

# SSH into the Coder workspace
coder-ssh:
    coder ssh {{ coder_ws }}

# SSH into the API container on Coder
coder-api:
    ssh coder.{{ coder_ws }} -t 'docker exec -it {{ coder_api }} bash -ic "cd /var/www/html && exec bash"'

# Apply post-DCM fixes on Coder (ENVIRONMENT=local, clamdscan stub, cache perms)
coder-fix:
    #!/usr/bin/env bash
    echo "Applying fixes to Coder workspace {{ coder_ws }} ..."
    ssh coder.{{ coder_ws }} 'docker exec {{ coder_api }} bash -c "
      # Set ENVIRONMENT=local for AWS STS bypass
      env_local=/var/www/html/.env.local
      if ! grep -q \"^ENVIRONMENT=local\" \$env_local 2>/dev/null; then
        echo ENVIRONMENT=local >> \$env_local
        echo \"Added ENVIRONMENT=local\"
      else
        echo \"ENVIRONMENT=local already set\"
      fi

      # Stub clamdscan (not needed on amd64 but keeps parity)
      printf \"#!/bin/bash\ncat > /dev/null\nexit 0\n\" > /usr/local/bin/clamdscan
      chmod +x /usr/local/bin/clamdscan
      echo \"clamdscan stubbed\"

      # Fix cache perms
      chown -R www-data:www-data /var/www/html/var/cache 2>/dev/null
      echo \"Cache perms fixed\"

      # Warm cache
      php /var/www/html/bin/console cache:warmup --env=prod 2>&1 | tail -1
      chown -R www-data:www-data /var/www/html/var/cache 2>/dev/null
      echo \"Done.\"
    "'

# Load demo fixtures on Coder workspace
coder-db-reset:
    #!/usr/bin/env bash
    echo "Resetting database on Coder workspace {{ coder_ws }} ..."
    just coder-fix
    echo ""
    echo "Running setupdemo (this takes a few minutes) ..."
    ssh coder.{{ coder_ws }} 'docker exec {{ coder_api }} bash -ic "source /root/.commonrc && setupdemo"'
    echo ""
    echo "Resetting all passwords to pwd ..."
    ssh coder.{{ coder_ws }} 'docker exec {{ coder_api }} bash -ic "source /root/.commonrc && pwdpwd"'
    echo ""
    echo "Done. Login at the Coder workspace URL with any user and password pwd"

# Reset passwords on Coder workspace
coder-db-pwdreset:
    ssh coder.{{ coder_ws }} 'docker exec {{ coder_api }} bash -ic "source /root/.commonrc && pwdpwd"'

# Run a Symfony console command on Coder (e.g. just coder-console bean:bcm)
coder-console *args="":
    ssh coder.{{ coder_ws }} 'docker exec {{ coder_api }} bash -c "php /var/www/html/bin/console --env=prod {{ args }}"'

# View API logs on Coder
coder-logs *args="-f --tail 50":
    ssh coder.{{ coder_ws }} 'docker logs {{ args }} {{ coder_api }}'

# Run command in Coder API container (e.g. just coder-exec "php -v")
coder-exec *cmd="":
    ssh coder.{{ coder_ws }} 'docker exec {{ coder_api }} bash -c "{{ cmd }}"'

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Stub clamdscan — ClamAV OOM-kills under Rosetta/ARM64 emulation
[private]
_stub-clamdscan:
    #!/usr/bin/env bash
    docker compose exec api bash -c '
      if [[ "$(readlink -f /usr/local/bin/clamdscan 2>/dev/null || file /usr/local/bin/clamdscan)" == *"script"* ]] 2>/dev/null; then
        echo "clamdscan already stubbed"
      else
        printf "#!/bin/bash\ncat > /dev/null\nexit 0\n" > /usr/local/bin/clamdscan
        chmod +x /usr/local/bin/clamdscan
        echo "clamdscan stubbed (ClamAV OOM under ARM64 emulation)"
      fi
    '

# Fix cache dir ownership (cache:clear runs as root, web server is www-data)
[private]
_fix-cache-perms:
    docker compose exec api bash -c "chown -R www-data:www-data /var/www/html/var/cache 2>/dev/null || true"

# Post-up fixes: stub clamdscan, fix cache perms
[private]
_post-up:
    #!/usr/bin/env bash
    echo "Applying post-startup fixes ..."
    # Wait for api container to be ready
    for i in {1..30}; do
      if docker compose exec api bash -c "true" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    just _stub-clamdscan
    just _fix-cache-perms
    echo "Post-startup fixes applied."

# Init hooks (legacy DCM compat)
[private]
_hook phase:
    #!/usr/bin/env bash
    api_dir="{{ code_dir }}/beanworksapi"
    # Legacy DCM env vars — init scripts reference ${DCM_DIR}/srv/${DCM_PROJECT}/api
    export DCM_DIR="{{ code_dir }}/.dcm-compat"
    export DCM_PROJECT="ap"
    compat_link="${DCM_DIR}/srv/${DCM_PROJECT}/api"
    mkdir -p "$(dirname "$compat_link")"
    ln -sfn "$api_dir" "$compat_link"
    case "{{ phase }}" in
      pre_init)
        [[ -f "${api_dir}/docker-compose/pre_init" ]] && {
          echo "Running api pre-init ..."
          cd "$api_dir" && bash docker-compose/pre_init
        } || true ;;
      init)
        [[ -f "${api_dir}/docker-compose/init" ]] && {
          echo "Running api init ..."
          cd "$api_dir" && bash docker-compose/init
        } || true ;;
    esac
