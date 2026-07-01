#!/bin/bash
set -euxo pipefail

REGION="${region}"
ACCOUNT_ID="${account_id}"
FRONTEND_IMAGE="${frontend_image}"

dnf install -y docker unzip
systemctl enable --now docker

if ! command -v aws >/dev/null 2>&1; then
  curl -sS "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install
fi

mkdir -p /opt/collabdocs

cat > /opt/collabdocs/nginx.aws.conf <<'CONFEOF'
${nginx_conf}
CONFEOF

cat > /opt/collabdocs/envoy.aws.yaml <<'CONFEOF'
${envoy_yaml}
CONFEOF

cat > /opt/collabdocs/start.sh <<EOS
#!/bin/bash
set -euxo pipefail

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

docker rm -f collabdocs-frontend collabdocs-grpc-web 2>/dev/null || true
docker pull $FRONTEND_IMAGE

docker run -d --name collabdocs-grpc-web \\
  --restart unless-stopped \\
  -p 8082:8082 \\
  -v /opt/collabdocs/envoy.aws.yaml:/etc/envoy/envoy.yaml:ro \\
  envoyproxy/envoy:v1.30-latest

docker run -d --name collabdocs-frontend \\
  --restart unless-stopped \\
  -p 80:80 \\
  -v /opt/collabdocs/nginx.aws.conf:/etc/nginx/conf.d/default.conf:ro \\
  $FRONTEND_IMAGE

sleep 5
docker inspect -f '{{.State.Running}}' collabdocs-grpc-web
docker inspect -f '{{.State.Running}}' collabdocs-frontend
EOS
chmod +x /opt/collabdocs/start.sh

cat > /etc/systemd/system/collabdocs.service <<'EOS'
[Unit]
Description=CollabDocs edge (frontend + grpc-web)
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
