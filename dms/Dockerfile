FROM fileago/fileago:3.0.1
MAINTAINER support@fileago.com
RUN set -xe \ 
    && apk add --no-cache --purge -uU \ 
       openldap-clients wget sqlite \
    && rm -rf /var/cache/apk/* /tmp/*
RUN wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/bin/mc && chmod 755 /usr/bin/mc
COPY start.sh /bin/start.sh 
RUN chmod 755 /bin/start.sh
EXPOSE 8080
ENV SECRETCOOKIE mysecretcookie
VOLUME ["/dms/priv/data", "/dms/priv/dblogs", "/dms/priv/mnesia", "/dms/priv/web/images/avatars", "/tmp/fonts"]
ENTRYPOINT ["/sbin/tini", "--"]
CMD /bin/sh -c /bin/start.sh
