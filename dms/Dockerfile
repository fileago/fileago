FROM fileago/fileago:3.0.5
MAINTAINER support@fileago.com
RUN set -xe \ 
    && apk add --no-cache --purge -uU \ 
       openldap-clients wget sqlite \
    && rm -rf /var/cache/apk/* /tmp/*
RUN cd /tmp && wget --no-check-certificate https://raw.githubusercontent.com/fileago/resources/refs/heads/main/mc.RELEASE.2025-04-16T18-13-26Z.tar.gz \ 
    && tar zxf mc.RELEASE.2025-04-16T18-13-26Z.tar.gz && chmod 755 mc.RELEASE.2025-04-16T18-13-26Z && mv mc.RELEASE.2025-04-16T18-13-26Z /usr/bin/mc \ 
    && rm -f mc.RELEASE.2025-04-16T18-13-26Z.tar.gz
COPY start.sh /bin/start.sh 
RUN chmod 755 /bin/start.sh
EXPOSE 8080
ENV SECRETCOOKIE mysecretcookie
VOLUME ["/dms/priv/data", "/dms/priv/dblogs", "/dms/priv/mnesia", "/dms/priv/web/images/avatars"]
ENTRYPOINT ["/sbin/tini", "--"]
CMD /bin/sh -c /bin/start.sh
