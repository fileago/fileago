FROM fileago/fileago:1.4.1
MAINTAINER support@fileago.com
RUN set -xe \ 
    && apk add --no-cache --purge -uU \ 
       fontconfig libreoffice ttf-freefont openldap-clients \ 
       ttf-opensans ttf-dejavu ttf-ubuntu-font-family \
    && rm -rf /var/cache/apk/* /tmp/*
COPY start.sh /bin/start.sh 
RUN chmod 755 /bin/start.sh
EXPOSE 8080
ENV SECRETCOOKIE mysecretcookie
VOLUME ["/dms/priv/data", "/dms/priv/dblogs", "/dms/priv/mnesia", "/dms/priv/web/images/avatars", "/tmp/fonts"]
ENTRYPOINT ["/sbin/tini", "--"]
CMD /bin/sh -c /bin/start.sh
