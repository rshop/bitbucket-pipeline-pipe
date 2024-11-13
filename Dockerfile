FROM rshop/pipeline:7.3

WORKDIR /var/www/html
COPY pipe.sh /var/www/html/
RUN chmod +x /var/www/html/pipe.sh

RUN git config --global --add safe.directory /root/.composer/

ENTRYPOINT ["/var/www/html/pipe.sh"]