FROM collabora/code:4.0.4.3
MAINTAINER support@fileago.com
COPY start-libreoffice.sh /start-libreoffice.sh
COPY loolwsd.xml /etc/loolwsd/loolwsd.xml 
COPY fileago.crt /usr/share/ca-certificates/fileago.crt 
RUN chmod 755 /start-libreoffice.sh
EXPOSE 9980
