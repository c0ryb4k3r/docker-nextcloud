ARG NEXTCLOUD_VERSION
FROM c0ryb4k3r/nginx-php:7.4

ARG NEXTCLOUD_VERSION
ARG GPG_nextcloud="2880 6A87 8AE4 23A2 8372  792E D758 99B9 A724 937A"

ENV UID=991 GID=991 \
    UPLOAD_MAX_SIZE=10G \
    APC_SHM_SIZE=128M \
    OPCACHE_MEM_SIZE=128 \
    MEMORY_LIMIT=512M \
    CRON_PERIOD=5m \
    CRON_MEMORY_LIMIT=1g \
    TZ=Etc/UTC \
    DB_TYPE=sqlite3 \
    DOMAIN=localhost

RUN echo '********************* Beginning RUN *********************' \
 && echo '********************* START NextCloud SECTION *********************' \
 && if [ "x$NEXTCLOUD_VERSION" = "x" ] ; then \
	echo 'Detecting latest NextCloud Release'; \
	wget https://nextcloud.com/changelog/ -O /tmp/nextcloud_releases; \
	NEXTCLOUD_VERSION=$(cat /tmp/nextcloud_releases | grep "name=\"latest20\"" -A 2 | grep -io 'id=['"'"'"][^"'"'"']*['"'"'"]' | sed -e 's/^id=["'"'"']//i' -e 's/"//' | awk -F '-' '{print $1 "." $2 "." $3}'); \
	echo Using NextCloud version [${NEXTCLOUD_VERSION}]; \
	rm -rf /tmp/nextcloud_releases; \
 fi \
 && echo '********************* End NextCloud SECTION *********************' \
 && apk -U upgrade \
 && apk add -t build-dependencies \
    gnupg \
    tar \
    build-base \
    autoconf \
    automake \
    pcre-dev \
    libtool \
    samba-dev \
    imagemagick-dev \
 && apk add \
    libressl \
    ca-certificates \
    libsmbclient \
    tzdata \
    imagemagick \
    ffmpeg \
 && pecl install \
    smbclient \
    apcu \
    redis \
    imagick \
 && echo "extension=smbclient.so" > /php/conf.d/smbclient.ini \
 && echo "extension=redis.so" > /php/conf.d/redis.ini \
 && echo "extension=imagick.so" > /php/conf.d/imagick.ini \
 && mkdir /nextcloud \
 && cd /tmp \
 && NEXTCLOUD_TARBALL="nextcloud-${NEXTCLOUD_VERSION}.tar.bz2" \
 && wget -q https://download.nextcloud.com/server/releases/${NEXTCLOUD_TARBALL} \
 && wget -q https://download.nextcloud.com/server/releases/${NEXTCLOUD_TARBALL}.sha512 \
 && wget -q https://download.nextcloud.com/server/releases/${NEXTCLOUD_TARBALL}.asc \
 && wget -q https://nextcloud.com/nextcloud.asc \
 && echo "Verifying both integrity and authenticity of ${NEXTCLOUD_TARBALL}..." \
 && CHECKSUM_STATE=$(echo -n $(sha512sum -c ${NEXTCLOUD_TARBALL}.sha512) | tail -c 2) \
 && if [ "${CHECKSUM_STATE}" != "OK" ]; then echo "Warning! Checksum does not match!" && exit 1; fi \
 && gpg --import nextcloud.asc \
 && FINGERPRINT="$(LANG=C gpg --verify ${NEXTCLOUD_TARBALL}.asc ${NEXTCLOUD_TARBALL} 2>&1 \
  | sed -n "s#Primary key fingerprint: \(.*\)#\1#p")" \
 && if [ -z "${FINGERPRINT}" ]; then echo "Warning! Invalid GPG signature!" && exit 1; fi \
 && if [ "${FINGERPRINT}" != "${GPG_nextcloud}" ]; then echo "Warning! Wrong GPG fingerprint!" && exit 1; fi \
 && echo "All seems good, now unpacking ${NEXTCLOUD_TARBALL}..." \
 && tar xjf ${NEXTCLOUD_TARBALL} --strip 1 -C /nextcloud \
 && update-ca-certificates \
 && apk del build-dependencies \
 && rm -rf /var/cache/apk/* /tmp/* /root/.gnupg

COPY rootfs /

RUN chmod +x /usr/local/bin/* /etc/s6.d/*/* /etc/s6.d/.s6-svscan/*

VOLUME /data /config /apps2 /nextcloud/themes

EXPOSE 8888

LABEL description="A server software for creating file hosting services" \
      nextcloud="Nextcloud v${NEXTCLOUD_VERSION}" \
      maintainer="Cory Baker <C0ry.B4k3r@gmail.com> forked from Wonderfall <wonderfall@targaryen.house>"

CMD ["run.sh"]
