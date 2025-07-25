FROM alpine:3.18
WORKDIR /app
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    openssl \
    coreutils

RUN curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | \
    bash -s -- -a && \
    mv /root/yandex-cloud/bin/yc /usr/local/bin/ && \
    rm -rf /root/yandex-cloud
!!! change email
RUN curl https://get.acme.sh | sh -s email=your_mail@example.com
RUN mkdir -p /etc/ssl/yandex /var/log /home/www/key

COPY acme.sh script.sh
COPY key.json /home/www/key/key.json
RUN chmod +x /app/script.sh
!!! domen: example.com
ENV PRIMARY_DOMAIN="example.com" \  
    WILDCARD_DOMAIN="*.example.com" \
    CERT_DIR="/etc/ssl/yandex" \
    LOG_FILE="/var/log/yandex_cert_renewal.log" \
    ACME_SERVER="letsencrypt" \
    EMAIL="your_mail@example.com" \
    YC_KEY_FILE="/home/www/key/key.json"


ENTRYPOINT ["./script.sh"]
