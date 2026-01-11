# PHP Docker Images
[![Build and Push to Registry](https://github.com/mdprotacio/docker-php/actions/workflows/dockerhub.yml/badge.svg)](https://github.com/mdprotacio/docker-php/actions/workflows/dockerhub.yml)

PHP container images preinstalled with commonly used extensions for web development.

Base images derived from the following:

- [PHP images](https://github.com/docker-library/php)
- [PIE Image](https://github.com/php/pie)
- [Composer Image](https://github.com/composer/docker)

Most extensions are installed via [PIE/packagist](https://packagist.org/extensions). If not available as PIE extension, they are installed traditionally through [PECL](https://pecl.php.net/).

Preinstalled extensions apart from the ones provided by the official PHP images:
- amqp
- apcu
- ast
- bcmath
- dba
- ev
- gettext
- igbinary
- imagick
- intl
- jsonpath
- mcrypt
- memcached
- mongodb
- msgpack
- mysqli
- pcntl
- pcov
- pdo
- pdo_mysql
- pdo_sqlite
- pdo_sqlsrv
- redis
- sockets
- swoole
- timezonedb
- xdebug
- xhprof
- xsl
- zip

---
Copyright (C) 2025 Melvin D. Protacio

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.

