FROM nginx:alpine
COPY fileago.template /tmp/fileago.template
COPY start.sh /bin/start.sh
COPY config_parts /tmp/config_parts
COPY internal_cert.key /etc/nginx/internal_cert.key
COPY internal_cert.crt /etc/nginx/internal_cert.crt
RUN chmod 755 /bin/start.sh 
RUN set -xe && apk add --no-cache --purge -uU openssl \ 
    && rm -rf /var/cache/apk/*
EXPOSE 443
EXPOSE 5555
ENV WEBHOSTNAME fileago.mycompany.com
CMD /bin/sh -c /bin/start.sh
