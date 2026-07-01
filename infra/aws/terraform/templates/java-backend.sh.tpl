#!/bin/bash
set -euxo pipefail

REGION="${region}"
ACCOUNT_ID="${account_id}"
IMAGE="${image}"
DOMAIN="${internal_domain}"
DB_NAME="${db_name}"
DB_USER="${db_user}"
DB_PASSWORD="${db_password}"
RABBITMQ_USER="${rabbitmq_user}"
RABBITMQ_PASSWORD="${rabbitmq_password}"
JWT_SECRET="${jwt_secret}"

dnf install -y docker unzip
systemctl enable --now docker

if ! command -v aws >/dev/null 2>&1; then
  curl -sS "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
fi

mkdir -p /opt/collabdocs

cat > /opt/collabdocs/start.sh <<EOS
#!/bin/bash
set -euxo pipefail

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

docker rm -f collabdocs-java-backend 2>/dev/null || true
docker pull $IMAGE

docker run -d --name collabdocs-java-backend \\
  --restart unless-stopped \\
  -p 8081:8081 -p 9090:9090 \\
  -e SERVER_PORT=8081 \\
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://postgres.$DOMAIN:5432/$DB_NAME \\
  -e SPRING_DATASOURCE_USERNAME=$DB_USER \\
  -e SPRING_DATASOURCE_PASSWORD=$DB_PASSWORD \\
  -e SPRING_RABBITMQ_HOST=rabbitmq.$DOMAIN \\
  -e SPRING_RABBITMQ_PORT=5672 \\
  -e SPRING_RABBITMQ_USERNAME=$RABBITMQ_USER \\
  -e SPRING_RABBITMQ_PASSWORD=$RABBITMQ_PASSWORD \\
  -e JWT_SECRET=$JWT_SECRET \\
  -e GRPC_SERVER_PORT=9090 \\
  $IMAGE

sleep 5
docker inspect -f '{{.State.Running}}' collabdocs-java-backend
EOS
chmod +x /opt/collabdocs/start.sh

cat > /etc/systemd/system/collabdocs.service <<'EOS'
[Unit]
Description=CollabDocs java-backend
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

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
