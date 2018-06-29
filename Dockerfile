FROM wordpress:4-apache

# install the PHP extensions we need
RUN set -ex; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libjpeg-dev \
		libpng-dev \
		autoconf \
		gzip \
		make \
		zip \
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

RUN a2enmod rewrite expires

#VOLUME /var/www/html
VOLUME /var/www/html/wordpress

#removing wordpress gettin', as it's in the image, maybe
ENV WORDPRESS_VERSION 4.9.6
ENV WORDPRESS_SHA1 40616b40d120c97205e5852c03096115c2fca537

RUN set -ex; \
	curl -o wordpress.tar.gz -fSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz"; \
	echo "$WORDPRESS_SHA1 *wordpress.tar.gz" | sha1sum -c -; \
	tar -xzf wordpress.tar.gz -C /var/www/html; \
	rm wordpress.tar.gz; \
	#chown -R www-data:www-data /usr/src/wordpress
	chown -R root:root /var/www/html/wordpress


# copy site content
#WORKDIR /usr/src/wordpress
#COPY . /var/www/html/
#RUN mv /usr/src/wordpress/* /var/www/html
#RUN ls /usr/src/wordpress -la
#RUN cp -rp /usr/src/wordpress/* /var/www/html/
#WORKDIR /var/www/html

#WORKDIR /usr/src/wordpress
#COPY . /usr/src/wordpress
#RUN ln -sf /usr/src/wordpress /var/www/html

# Section that sets up Apache and Cosign to run as non-root user.
EXPOSE 8080
EXPOSE 8443

#
COPY . /var/www/html
RUN chown -R root:root /var/www
RUN chmod -R g+rw /var/www

#COPY . /usr/src/wordpress
#RUN chown -R root:root /usr/src/wordpress
#RUN chmod -R g+rw /usr/src/wordpress

### change directory owner, as openshift user is in root group.
RUN chown -R root:root /etc/apache2 \
	/etc/ssl/certs /etc/ssl/private \
	/usr/local/etc/php /usr/local/lib/php \
	/var/lib/apache2/module/enabled_by_admin \
	/var/lib/apache2/site/enabled_by_admin \
	/usr/src/wordpress \
	/var/lock/apache2 /var/log/apache2 /var/run/apache2 \
	/var/www/html

### Modify perms for the openshift user, who is not root, but part of root group.
RUN chmod -R g+rw /etc/apache2 \
	/etc/ssl/certs /etc/ssl/private \
	/usr/local/etc/php /usr/local/lib/php \
	/usr/src/wordpress \
	/var/lib/apache2/module/enabled_by_admin \
	/var/lib/apache2/site/enabled_by_admin \
	/var/lock/apache2 /var/log/apache2 /var/run/apache2 \
	/var/www/html

RUN chmod g+x /etc/ssl/private

COPY start.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/start.sh
CMD /usr/local/bin/start.sh
