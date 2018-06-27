FROM php:7.1-fpm

# install the PHP extensions we need
RUN set -ex; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		apt-utils \
		autoconf \
		gzip \
		libaio1 \
		libaio-dev \
		libxml2-dev \
		make \
		zip \
		mysql-client \		
		libjpeg-dev \
		libpng-dev \
	; \
	\
	docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr; \
	docker-php-ext-install gd mysqli opcache zip; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
		| awk '/=>/ { print $3 }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
		echo 'opcache.memory_consumption=128'; \
		echo 'opcache.interned_strings_buffer=8'; \
		echo 'opcache.max_accelerated_files=4000'; \
		echo 'opcache.revalidate_freq=2'; \
		echo 'opcache.fast_shutdown=1'; \
		echo 'opcache.enable_cli=1'; \
	} > /usr/local/etc/php/conf.d/opcache-recommended.ini

VOLUME /var/www/html

ENV WORDPRESS_VERSION 4.9.6
ENV WORDPRESS_SHA1 40616b40d120c97205e5852c03096115c2fca537

RUN set -ex; \
	curl -o wordpress.tar.gz -fSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz"; \
	echo "$WORDPRESS_SHA1 *wordpress.tar.gz" | sha1sum -c -; \
# upstream tarballs include ./wordpress/ so this gives us /usr/src/wordpress
	tar -xzf wordpress.tar.gz -C /usr/src/; \
	rm wordpress.tar.gz; \
	chown -R www-data:www-data /usr/src/wordpress

COPY . /var/www/html/

# Section that sets up Apache and Cosign to run as non-root user.
EXPOSE 8080
EXPOSE 8443

### change directory owner, as openshift user is in root group.
RUN chown -R root:root /etc/apache2 \
	/etc/ssl/certs /etc/ssl/private \
	/usr/local/etc/php /usr/local/lib/php \
	/var/lib/apache2/module/enabled_by_admin \ 
	/var/lib/apache2/site/enabled_by_admin \
	/var/lock/apache2 /var/log/apache2 /var/run/apache2\
	/var/www/html

### Modify perms for the openshift user, who is not root, but part of root group.
RUN chmod -R g+rw /etc/apache2 \
	/etc/ssl/certs /etc/ssl/private \
	/usr/local/etc/php /usr/local/lib/php \
	/var/lib/apache2/module/enabled_by_admin \ 
	/var/lib/apache2/site/enabled_by_admin \
	/var/lock/apache2 /var/log/apache2 /var/run/apache2\
	/var/www/html

RUN chmod g+x /etc/ssl/private

COPY start.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin
CMD /usr/local/bin/start.sh

#ENTRYPOINT ["start.sh"]
#CMD ["start.sh"]
