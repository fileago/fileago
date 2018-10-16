#! /bin/sh

if [ -f /tmp/certs/cert.key ] && [ -f /tmp/certs/cert.crt ];
then
  cp -f /tmp/certs/cert.key /etc/nginx/cert.key
  cp -f /tmp/certs/cert.crt /etc/nginx/cert.crt
else
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/cert.key -out /etc/nginx/cert.crt \
    -subj "/C=US/ST=World/L=Earth/O=FileAgo/OU=Web/CN=${WEBHOSTNAME}/emailAddress=admin@${WEBHOSTNAME}"
fi

envsubst '${WEBHOSTNAME}' < /tmp/fileago.template > /etc/nginx/conf.d/default.conf
exec nginx -g 'daemon off;'
