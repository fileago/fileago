FROM nginx:1.14-alpine
COPY fileago.template /tmp/fileago.template
COPY start.sh /bin/start.sh
RUN chmod 755 /bin/start.sh 
RUN set -xe && apk add --no-cache --purge -uU openssl \ 
    && rm -rf /var/cache/apk/*
EXPOSE 443
ENV WEBHOSTNAME fileago.mycompany.com
CMD /bin/sh -c /bin/start.sh
