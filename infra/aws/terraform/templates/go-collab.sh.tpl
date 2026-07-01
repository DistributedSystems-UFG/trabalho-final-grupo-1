#!/bin/bash
set -euxo pipefail

REGION="${region}"
ACCOUNT_ID="${account_id}"
IMAGE="${image}"
DOMAIN="${internal_domain}"
RABBITMQ_USER="${rabbitmq_user}"
RABBITMQ_PASSWORD="${rabbitmq_password}"
JWT_SECRET="${jwt_secret}"
CONTAINER_NAME="${container_name}"

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

docker rm -f $CONTAINER_NAME 2>/dev/null || true
docker pull $IMAGE

docker run -d --name $CONTAINER_NAME \\
  --restart unless-stopped \\
  -p 8080:8080 \\
  -e PORT=8080 \\
  -e JAVA_BACKEND_URL=http://java-backend.$DOMAIN:8081 \\
  -e RABBITMQ_URL=amqp://$RABBITMQ_USER:$RABBITMQ_PASSWORD@rabbitmq.$DOMAIN:5672/ \\
  -e REDIS_URL=redis://redis.$DOMAIN:6379/0 \\
  -e JWT_SECRET=$JWT_SECRET \\
  $IMAGE

sleep 5
docker inspect -f '{{.State.Running}}' $CONTAINER_NAME
EOS
chmod +x /opt/collabdocs/start.sh

cat > /etc/systemd/system/collabdocs.service <<'EOS'
[Unit]
Description=CollabDocs go-collab
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
