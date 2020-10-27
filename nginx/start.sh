#! /bin/sh

CHAT=${CHAT_ENABLED:-false}
CAD=${CAD_ENABLED:-false}

if [ -f /tmp/certs/cert.key ] && [ -f /tmp/certs/cert.crt ];
then
  cp -f /tmp/certs/cert.key /etc/nginx/cert.key
  cp -f /tmp/certs/cert.crt /etc/nginx/cert.crt
else
  openssl req -x509 -nodes -days 9131 -newkey rsa:2048 \
    -keyout /etc/nginx/cert.key -out /etc/nginx/cert.crt \
    -subj "/C=US/ST=World/L=Earth/O=FileAgo/OU=Web/CN=${WEBHOSTNAME}/emailAddress=admin@${WEBHOSTNAME}"
fi

## configure backup stream block in main nginx.conf
grep "FILEAGO BACKUP SERVICE" /etc/nginx/nginx.conf > /dev/null || {
cat /tmp/config_parts/backup_block.conf >> /etc/nginx/nginx.conf
openssl req -x509 -nodes -days 9131 -newkey rsa:2048  -keyout /etc/nginx/backup_service.key -out /etc/nginx/backup_service.crt -subj "/C=US/ST=World/L=Earth/O=FileAgo/OU=BackupCentral/CN=${WEBHOSTNAME}/emailAddress=admin@${WEBHOSTNAME}"
}

## configure chat endpoints
if $CHAT; then
  awk '/##__CHAT_UPSTREAM_PLACEHOLDER__##/{system("cat /tmp/config_parts/chat_upstream.conf");next}1' /tmp/fileago.template > /tmp/fileago.template.1 && rm -f /tmp/fileago.template && mv /tmp/fileago.template.1 /tmp/fileago.template
  awk '/##__CHAT_BLOCK_PLACEHOLDER__##/{system("cat /tmp/config_parts/chat_block.conf");next}1' /tmp/fileago.template > /tmp/fileago.template.1 && rm -f /tmp/fileago.template && mv /tmp/fileago.template.1 /tmp/fileago.template
fi

## configure cad endpoints
if $CAD; then
  awk '/##__CAD_BLOCK_PLACEHOLDER__##/{system("cat /tmp/config_parts/cad_block.conf");next}1' /tmp/fileago.template > /tmp/fileago.template.1 && rm -f /tmp/fileago.template && mv /tmp/fileago.template.1 /tmp/fileago.template
fi

envsubst '${WEBHOSTNAME}' < /tmp/fileago.template > /etc/nginx/conf.d/default.conf
exec nginx -g 'daemon off;'
