FROM ubuntu:xenial
MAINTAINER Justin Hartman <justin@hartman.me>

ENV DEBIAN_FRONTEND noninteractive
ENV MYSQL_ROOT_PASSWORD RpgCNfRTBpEyBKdk6D

RUN echo mysql-server mysql-server/root_password \
    password $MYSQL_ROOT_PASSWORD | debconf-set-selections
RUN echo mysql-server mysql-server/root_password_again \
    password $MYSQL_ROOT_PASSWORD | debconf-set-selections

# Install apt-utils first so we avoid errors in Docker build.
RUN apt-get update && apt-get -y install apt-utils

# Install Apache, MySQL and PHP along with all the dependencies.
RUN apt-get -y install curl zip unzip libicu55 libmcrypt-dev g++ libicu-dev \
    libmcrypt4 pwgen git mysql-server apache2 libapache2-mod-php7.0 \
    php7.0-mysql php7.0-mcrypt php7.0-opcache php7.0 php7.0-cli php7.0-fpm \
    php7.0-gd php7.0-json php7.0-readline php7.0-common php7.0-curl \
    php7.0-mbstring php7.0-mcrypt php7.0-intl php7.0-simplexml

# Add volumes for MySQL & Apache 2
VOLUME  ["/etc/mysql", "/var/lib/mysql", "/var/www/html"]

# Copy core files across.
ADD database.sql /var/lib/mysql/database.sql
ADD config/app.default.php /var/www/html/config/app.default.php
ADD config/bootstrap.php /var/www/html/config/bootstrap.php
ADD config/env.default /var/www/html/config/env.default

# Restart MySQL.
RUN service mysql restart

# Create the CakePHP live and test databases as well as the database users.
# RUN mysql -u root -pRpgCNfRTBpEyBKdk6D < /var/lib/mysql/database.sql
RUN which mysql

# Open ports 80 and 3306. Port 8765 is for CakePHP's development server should
# you need to use it.
EXPOSE 80 3306 8765

# Remove and purge some previously installed software.
RUN requirementsToRemove="libmcrypt-dev g++ libicu-dev" \
    && apt-get purge --auto-remove -y $requirementsToRemove \
    && rm -rf /var/lib/apt/lists/*

# Default config for vhost.
ADD apache_default /etc/apache2/sites-available/000-default.conf

# Enable mod_rewrite.
RUN a2enmod rewrite

# Setup work directory for Composer and CakePHP installation.
WORKDIR /var/www/html

# Install Composer.
RUN curl -sSL https://getcomposer.org/installer | php \
    && mv composer.phar /usr/local/bin/composer \
    && apt-get update \
    && apt-get install -y zlib1g-dev \
    && apt-get purge -y --auto-remove zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Install latest version of CakePHP to the configured Apache Vhost folder.
RUN /usr/local/bin/composer create-project --prefer-dist cakephp/app \
    /var/www/html/cakephp

# Change to the config directory to prepare for copying files over.
WORKDIR /var/www/html/config

# Copy CakePHP config files to project to enable dotenv and define app defaults
# which include database connection settings.
RUN mv app.default.php /var/www/html/cakephp/config/app.default.php
RUN mv bootstrap.php /var/www/html/cakephp/config/bootstrap.php
RUN mv env.default /var/www/html/cakephp/config/.env

# Apply all the correct permissions on cakephp directory.
WORKDIR /var/www/html/cakephp
RUN usermod -u 1000 www-data

# Now we can restart Apache for everything to kick in.
RUN service apache2 restart

# Test to see if Docker can pick up the cake shell script or not.
RUN /bin/sh ./bin/cake version

# Run the development server just in case. You can access this on port 8765.
# I expect the build to fail right here.
RUN /bin/bash ./bin/cake server -H 0.0.0.0
