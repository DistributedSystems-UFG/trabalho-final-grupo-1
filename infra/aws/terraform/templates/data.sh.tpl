#!/bin/bash
set -euxo pipefail

DB_NAME="${db_name}"
DB_USER="${db_user}"
DB_PASSWORD="${db_password}"
RABBITMQ_USER="${rabbitmq_user}"
RABBITMQ_PASSWORD="${rabbitmq_password}"

dnf install -y docker
systemctl enable --now docker

mkdir -p /opt/collabdocs/postgres-init /opt/collabdocs/pgdata /opt/collabdocs/rabbitmq-data

cat > /opt/collabdocs/postgres-init/01-schema.sql <<'SQLEOF'
${init_sql}
SQLEOF

cat > /opt/collabdocs/postgres-init/02-seed.sql <<'SQLEOF'
${seed_sql}
SQLEOF

cat > /opt/collabdocs/start.sh <<EOS
#!/bin/bash
set -euxo pipefail

docker rm -f collabdocs-postgres collabdocs-rabbitmq collabdocs-redis 2>/dev/null || true

docker run -d --name collabdocs-postgres \\
  --restart unless-stopped \\
  -p 5432:5432 \\
  -e POSTGRES_DB=$DB_NAME \\
  -e POSTGRES_USER=$DB_USER \\
  -e POSTGRES_PASSWORD=$DB_PASSWORD \\
  -v /opt/collabdocs/pgdata:/var/lib/postgresql/data \\
  -v /opt/collabdocs/postgres-init:/docker-entrypoint-initdb.d:ro \\
  postgres:16-alpine

docker run -d --name collabdocs-rabbitmq \\
  --restart unless-stopped \\
  -p 5672:5672 -p 15672:15672 \\
  -e RABBITMQ_DEFAULT_USER=$RABBITMQ_USER \\
  -e RABBITMQ_DEFAULT_PASS=$RABBITMQ_PASSWORD \\
  -v /opt/collabdocs/rabbitmq-data:/var/lib/rabbitmq \\
  rabbitmq:3.13-management-alpine

docker run -d --name collabdocs-redis \\
  --restart unless-stopped \\
  -p 6379:6379 \\
  redis:7-alpine redis-server --appendonly no

sleep 5
docker inspect -f '{{.State.Running}}' collabdocs-postgres
docker inspect -f '{{.State.Running}}' collabdocs-rabbitmq
docker inspect -f '{{.State.Running}}' collabdocs-redis
EOS
chmod +x /opt/collabdocs/start.sh

cat > /etc/systemd/system/collabdocs.service <<'EOS'
[Unit]
Description=CollabDocs data services (postgres, rabbitmq, redis)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/collabdocs/start.sh
Restart=on-failure
RestartSec=15

[Install]
WantedBy=multi-user.target
EOS

systemctl daemon-reload
systemctl enable --now collabdocs.service
