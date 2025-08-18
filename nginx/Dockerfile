FROM openresty/openresty:alpine-fat

# FileAgo configs
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY fileago.template /tmp/fileago.template
COPY config_parts /tmp/config_parts
COPY lua /tmp/lua
COPY start.sh /bin/start.sh

# Commands
RUN chmod 755 /bin/start.sh && \ 
    set -xe && apk add --no-cache --purge -uU logrotate openssl && rm -rf /var/cache/apk/* && \ 
    /usr/local/openresty/luajit/bin/luarocks install luasocket && \ 
    /usr/local/openresty/luajit/bin/luarocks install lua-resty-http && \ 
    /usr/local/openresty/luajit/bin/luarocks install lua-resty-upload && \ 
    /usr/local/openresty/luajit/bin/luarocks install lua-resty-openssl && \ 
    mv /tmp/lua /usr/local/openresty/lualib/fileago

# Certs
COPY internal_cert.key /etc/nginx/internal_cert.key
COPY internal_cert.crt /etc/nginx/internal_cert.crt

# Logrotate
COPY logrotate-nginx.conf /etc/logrotate.d/nginx

EXPOSE 443
ENV WEBHOSTNAME fileago.mycompany.com
CMD /bin/sh -c /bin/start.sh
