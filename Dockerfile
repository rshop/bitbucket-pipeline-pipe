FROM rshop/pipeline:7.4

RUN apk add --no-cache mariadb mariadb-client mariadb-connector-c

WORKDIR /var/www/html
COPY pipe.sh /var/www/html/
RUN chmod +x /var/www/html/pipe.sh

ENTRYPOINT ["/var/www/html/pipe.sh"]