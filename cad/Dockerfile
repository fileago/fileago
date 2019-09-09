FROM centos:latest
MAINTAINER support@fileago.com
RUN set -eux \
  && yum install httpd php php-gd wget -y \
  && yum clean all && rm -rf /var/cache/yum \
  && wget http://cadviewerjs.com/downloads/cadviewer_4_1_0/php_linux_tar/cadviewer.tar.gz -O /tmp/cadviewer.tar.gz \
  && cd /tmp && tar zxf cadviewer.tar.gz && chown -R apache:apache /tmp/cadviewer && mv /tmp/cadviewer /var/www/html \
  && rm -rf /tmp/cadviewer.tar.gz
COPY php.ini /etc/php.ini
COPY cad.conf /etc/httpd/conf.d/
COPY httpd-foreground /bin/
EXPOSE 80
CMD ["httpd-foreground"]
