FROM centos:7.6.1810
MAINTAINER support@fileago.com
RUN set -eux \
  && yum install httpd php php-gd fontconfig git -y \
  && yum clean all && rm -rf /var/cache/yum \
  && cd /tmp && git clone https://github.com/CADViewer/cadviewer7-script-library-php-linux.git \
  && chown -R apache:apache cadviewer7-script-library-php-linux \
  && rm -f cadviewer7-script-library-php-linux/php/CADViewer_config.php \
  && mv cadviewer7-script-library-php-linux/php/CADViewer_config_docker.php cadviewer7-script-library-php-linux/php/CADViewer_config.php \
  && mv /tmp/cadviewer7-script-library-php-linux /var/www/html
COPY php.ini /etc/php.ini
COPY cad.conf /etc/httpd/conf.d/
COPY httpd-foreground /bin/
RUN chmod 755 /bin/httpd-foreground
EXPOSE 80
CMD ["httpd-foreground"]
