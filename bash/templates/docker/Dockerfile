ARG PHP_VERSION=8.3
FROM php:${PHP_VERSION}-fpm-alpine3.19

ARG CLIENT_ID
ARG CLIENT_UID=2000
ARG CLIENT_GID=2000

LABEL maintainer="FreeCP"
LABEL client.id="${CLIENT_ID}"

# System dependencies
RUN apk add --no-cache \
    bash curl unzip nginx supervisor \
    libpng-dev libwebp-dev libjpeg-turbo-dev \
    freetype-dev libxml2-dev oniguruma-dev \
    libzip-dev icu-dev $PHPIZE_DEPS \
    && rm -rf /var/cache/apk/*

# PHP extensions
RUN docker-php-ext-configure gd \
        --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) \
        pdo_mysql mbstring xml zip gd bcmath intl opcache pcntl \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && rm -rf /tmp/pear

# OPcache config
RUN echo "opcache.enable=1"                    >> /usr/local/etc/php/conf.d/opcache.ini \
    && echo "opcache.memory_consumption=128"   >> /usr/local/etc/php/conf.d/opcache.ini \
    && echo "opcache.interned_strings_buffer=8" >> /usr/local/etc/php/conf.d/opcache.ini \
    && echo "opcache.max_accelerated_files=10000" >> /usr/local/etc/php/conf.d/opcache.ini \
    && echo "opcache.validate_timestamps=0"    >> /usr/local/etc/php/conf.d/opcache.ini

# PHP-FPM config
RUN sed -i \
    -e "s|listen = 127.0.0.1:9000|listen = /var/run/php-fpm.sock|" \
    -e "s|;listen.owner = nobody|listen.owner = nginx|" \
    -e "s|;listen.group = nobody|listen.group = nginx|" \
    /usr/local/etc/php-fpm.d/www.conf

# Composer
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer

# Dedicated client user
RUN addgroup -g ${CLIENT_GID} client_${CLIENT_ID} \
    && adduser -u ${CLIENT_UID} -G client_${CLIENT_ID} \
               -h /var/www/app -s /sbin/nologin \
               -D client_${CLIENT_ID}

WORKDIR /var/www/app

# Install PHP deps (layer cache)
COPY --chown=client_${CLIENT_ID}:client_${CLIENT_ID} \
    composer.json composer.lock* ./

RUN composer install \
    --no-dev --no-scripts --no-autoloader \
    --prefer-dist --quiet \
    && composer clear-cache

# Copy app
COPY --chown=client_${CLIENT_ID}:client_${CLIENT_ID} . .

RUN composer dump-autoload --optimize --no-dev \
    && chown -R client_${CLIENT_ID}:client_${CLIENT_ID} \
       storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

# Nginx config
COPY nginx.conf /etc/nginx/http.d/default.conf

# Supervisor config
COPY supervisord.conf /etc/supervisord.conf

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]