FROM rshop/pipeline:8.0

WORKDIR /var/www/html
COPY pipe.sh /var/www/html/
RUN chmod +x /var/www/html/pipe.sh

ENTRYPOINT ["/var/www/html/pipe.sh"]