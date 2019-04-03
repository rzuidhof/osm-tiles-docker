FROM ubuntu:16.04
LABEL maintainer='Davey Witter <Davey.witter@kpn.com>'

# Set the version numbers for each component
ENV POSTGRES_VERSION 9.6
ENV POSTGIS_VERSION 2.5
ENV OSM2PGSQL 0.96.0
ENV GIT_CARTO 3.0.1
ENV CARTO 0.18.0
ENV LIBLUA 5.2

# Set the locale. This affects the encoding of the Postgresql template
# databases.
ENV LC_ALL C.UTF-8 
ENV LANG C.UTF-8
ENV LANGUAGE C.UTF-8

# Ensure `add-apt-repository` is present
RUN apt-get update && apt-get install -y dos2unix sudo
RUN apt-get install -y software-properties-common python-software-properties

RUN apt-get install -y libboost-dev libboost-filesystem-dev libboost-program-options-dev libboost-python-dev libboost-regex-dev libboost-system-dev libboost-thread-dev

# Install remaining dependencies
RUN apt-get install -y subversion git-core tar unzip wget bzip2 build-essential autoconf libtool libxml2-dev libgeos-dev libpq-dev libbz2-dev munin-node munin libprotobuf-c0-dev protobuf-c-compiler libfreetype6-dev libpng12-dev libtiff5-dev libicu-dev libgdal-dev libcairo-dev libcairomm-1.0-dev apache2 apache2-dev libagg-dev liblua${LIBLUA}-dev ttf-unifont

RUN apt-get install -y autoconf apache2-dev libtool libxml2-dev libbz2-dev libgeos-dev libgeos++-dev libproj-dev gdal-bin libgdal1-dev mapnik-utils python-mapnik libmapnik-dev

# Install postgresql and postgis
RUN echo "deb http://apt.postgresql.org/pub/repos/apt xenial-pgdg main" >> \
      /etc/apt/sources.list && \
    wget --quiet -O - http://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc | \
      apt-key add -
RUN apt-get -qq update

RUN apt-get install -y postgresql-${POSTGRES_VERSION}-postgis-${POSTGIS_VERSION} postgresql-contrib-${POSTGRES_VERSION} postgresql-server-dev-${POSTGRES_VERSION}

RUN apt-get install -y make cmake g++ libboost-dev libboost-system-dev libboost-filesystem-dev libexpat1-dev zlib1g-dev libbz2-dev libpq-dev libproj-dev lua5.2 liblua${LIBLUA}-dev

RUN apt-get install -y git libgdal-dev mapnik-utils python-mapnik upstart-sysv runit

# Install osm2pgsql
RUN cd /tmp && git clone git://github.com/openstreetmap/osm2pgsql.git && \
    cd /tmp/osm2pgsql && \
    git checkout ${OSM2PGSQL} && \
    mkdir build && cd build && \
    cmake .. && \
    make && \
    make install && \
    cd ../.. && \
    rm -rf osm2pgsql

# Install mod_tile and renderd
RUN cd /tmp && git clone git://github.com/openstreetmap/mod_tile.git && \
    cd /tmp/mod_tile && \
    ./autogen.sh && \
    ./configure && \
    make && \
    make install && \
    make install-mod_tile && \
    ldconfig && \
    cp /tmp/mod_tile/debian/renderd.init /etc/init.d/renderd && \
    cd /tmp && rm -rf /tmp/mod_tile

RUN cd /tmp && git clone https://github.com/gravitystorm/openstreetmap-carto.git && \
    cd openstreetmap-carto && apt-get install -y fonts-noto-cjk fonts-noto-hinted fonts-noto-unhinted fonts-hanazono ttf-unifont && \
	cd /tmp
RUN cd /tmp/openstreetmap-carto 
RUN apt-get install -y fonts-dejavu-core && \
	/tmp/openstreetmap-carto/scripts/get-shapefiles.py && \
    cd /tmp/openstreetmap-carto && apt-get install -y nodejs-legacy npm && \
    npm install -g carto@${CARTO} && \
    carto -a "3.0.0" project.mml > style.xml && \

	cp -r /tmp/openstreetmap-carto /home/openstreetmap-carto && \ 
	cd /tmp

# Install the Mapnik stylesheet
RUN cd /usr/local/src && svn co http://svn.openstreetmap.org/applications/rendering/mapnik mapnik-style

# Install the coastline data
RUN cd /usr/local/src/mapnik-style && ./get-coastlines.sh /usr/local/share

# Configure mapnik style-sheets
RUN cd /usr/local/src/mapnik-style/inc && cp fontset-settings.xml.inc.template fontset-settings.xml.inc
ADD bin/datasource-settings.sed /tmp/
RUN cd /usr/local/src/mapnik-style/inc && sed --file /tmp/datasource-settings.sed  datasource-settings.xml.inc.template > datasource-settings.xml.inc
ADD bin/settings.sed /tmp/
RUN cd /usr/local/src/mapnik-style/inc && sed --file /tmp/settings.sed  settings.xml.inc.template > settings.xml.inc

# Configure renderd
RUN cp -p /usr/local/etc/renderd.conf /usr/local/etc/renderd.conf.orig
COPY bin/renderd.conf /usr/local/etc/

# Create the files required for the mod_tile system to run
RUN mkdir /var/run/renderd && chown www-data: /var/run/renderd
RUN mkdir /var/lib/mod_tile && chown www-data /var/lib/mod_tile

# Replace default apache index page with OpenLayers demo
ADD index.html /var/www/html/index.html

# Add OpenLayers.js to the apache index page such that the index.html calls this instead.
ADD OpenLayers.js /var/www/html/OpenLayers.js

COPY bin/000-default.conf /etc/apache2/sites-available/
COPY bin/rewrite.conf /etc/apache2/mods-available/

# Configure mod_tile
ADD bin/mod_tile.load /etc/apache2/mods-available/
ADD bin/mod_tile.conf /etc/apache2/mods-available/
RUN a2enmod mod_tile

# Ensure the webserver user can connect to the gis database
RUN sed -i -e 's/local   all             all                                     peer/local gis www-data peer/' /etc/postgresql/${POSTGRES_VERSION}/main/pg_hba.conf && \
	mkdir -p /var/run/postgresql/${POSTGRES_VERSION}-main.pg_stat_tmp && \
	chown postgres:postgres /var/run/postgresql/${POSTGRES_VERSION}-main.pg_stat_tmp -R

# Tune postgresql
ADD bin/postgresql.conf.sed /tmp/
RUN sed --file /tmp/postgresql.conf.sed --in-place /etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf

# Define the application logging logic
ADD bin/syslog-ng.conf /etc/syslog-ng/conf.d/local.conf
RUN rm -rf /var/log/postgresql

# Create a `postgresql` `runit` service
ADD postgresql /etc/sv/postgresql
RUN update-service --add /etc/sv/postgresql

# Create an `apache2` `runit` service
ADD apache2 /etc/sv/apache2
RUN update-service --add /etc/sv/apache2

# Create a `renderd` `runit` service
ADD renderd /etc/sv/renderd
RUN update-service --add /etc/sv/renderd

#Add the perl script to render only an extract of the map
COPY bin/render_list_geo.pl /opt/
ADD bin/drop_indexes.sql /home/openstreetmap-carto/drop_indexes.sql
RUN chmod +x /opt/render_list_geo.pl

# Expose the webserver and database ports
EXPOSE 80 5432

# Set the osm2pgsql import cache size in MB. Used in `run import`.
ENV OSM_IMPORT_CACHE 40

# Add the README
ADD README.md /usr/local/share/doc/

# Add the help file
RUN mkdir -p /usr/local/share/doc/run && \
    rm -rf /var/lib/apt/lists/*
ADD bin/help.txt /usr/local/share/doc/run/help.txt


RUN mv /etc/apache2/conf-available/security.conf /etc/apache2/conf-available/security.conf.orig && \
	cd /etc/apache2/conf-available && \
	wget https://raw.githubusercontent.com/virtadpt/ubuntu-hardening/master/16.04-lts/apache2/conf-available/security.conf && \
	mv /etc/apache2/conf-available/security.conf /etc/apache2/conf-available/security.conf.hard && \
	cd /tmp/



# Add the entrypoint
ADD bin/my_init /sbin/my_init
ADD bin/setuser /sbin/setuser
ADD bin/install_clean /sbin/install_clean
ADD bin/run.sh /usr/local/sbin/run
RUN chmod a+x /sbin/my_init && \
	chmod a+x /usr/local/sbin/run && \
	chmod a+x /sbin/setuser && \
	chmod a+x /sbin/install_clean
RUN dos2unix /sbin/setuser && \
    dos2unix /usr/local/sbin/run && \
    dos2unix /sbin/install_clean && \
    dos2unix /sbin/my_init && \
    dos2unix /etc/sv/postgresql/* && \
    dos2unix /etc/sv/renderd/* && \
    dos2unix /etc/sv/apache2/*
ENTRYPOINT ["/sbin/my_init", "--", "/usr/local/sbin/run"]

RUN chmod a+x /var/lib/mod_tile

# Default to showing the usage text
CMD ["help"]

# Clean up APT
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
