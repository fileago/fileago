# ClamAV + ICAP Container
FROM ubuntu:latest

ARG VERSION=0.5.14
ARG PLUGINS_VERSION=0.5.7

RUN cd /root && \
    apt-get update && \
    apt-get install -y git build-essential clamav clamav-daemon curl zip pkg-config wget libtool libtool-bin && \
    cd /root && git clone https://github.com/Microsoft/vcpkg.git && cd vcpkg && \
    ./bootstrap-vcpkg.sh && ./vcpkg integrate install && ./vcpkg install brotli && cd /root && \
    wget -O c-icap.tar.gz https://sourceforge.net/projects/c-icap/files/c-icap/0.5.x/c_icap-${VERSION}.tar.gz/download && \
    tar zxfv c-icap.tar.gz && cd c_icap-${VERSION} && ./configure --prefix=/usr/local/c-icap && make && make install && cd /root && \
    wget -O c-icap-plugins.tar.gz https://sourceforge.net/projects/c-icap/files/c-icap-modules/0.5.x/c_icap_modules-${PLUGINS_VERSION}.tar.gz/download && \
    tar zxfv c-icap-plugins.tar.gz && cd c_icap_modules-${PLUGINS_VERSION} && \
    ./configure --with-c-icap=/usr/local/c-icap --prefix=/usr/local/c-icap && make && make install

COPY clamd.conf /etc/clamav/
COPY freshclam.conf /etc/clamav/
COPY c-icap.conf /usr/local/c-icap/etc/
COPY virus_scan.conf /usr/local/c-icap/etc/
COPY clamd_mod.conf /usr/local/c-icap/etc/
COPY entrypoint.sh /usr/bin/

RUN chmod 755 /usr/bin/entrypoint.sh && mkdir /run/clamav && chmod 0770 /run/clamav && chown -R clamav:clamav /run/clamav

EXPOSE 1344

ENTRYPOINT ["entrypoint.sh"]
