#!/bin/sh

sed -i -e "s/<APC_SHM_SIZE>/$APC_SHM_SIZE/g" /php/conf.d/apcu.ini \
       -e "s/<OPCACHE_MEM_SIZE>/$OPCACHE_MEM_SIZE/g" /php/conf.d/opcache.ini \
       -e "s/<CRON_MEMORY_LIMIT>/$CRON_MEMORY_LIMIT/g" /etc/s6.d/cron/run \
       -e "s/<CRON_PERIOD>/$CRON_PERIOD/g" /etc/s6.d/cron/run \
       -e "s/<MEMORY_LIMIT>/$MEMORY_LIMIT/g" /usr/local/bin/occ \
       -e "s/<UPLOAD_MAX_SIZE>/$UPLOAD_MAX_SIZE/g" /nginx/conf/nginx.conf /php/etc/php-fpm.conf \
       -e "s/<MEMORY_LIMIT>/$MEMORY_LIMIT/g" /php/etc/php-fpm.conf

# Put the configuration and apps into volumes
ln -sf /config/config.php /nextcloud/config/config.php &>/dev/null
ln -sf /apps2 /nextcloud &>/dev/null

echo "Check for existing UID - [${UID}]"
getent passwd $UID > /dev/null 2&>1
if [ $? -ne 0 ]; then
   echo "Creating user nextcloud with UID=${UID} and GID=${GID}"
   /usr/sbin/addgroup -g ${GID} nextcloud
   /usr/sbin/adduser -G nextcloud -u ${UID} -D -H -g "" nextcloud
else
   echo "Existing user with UID=${UID} was found"
fi
chown -h $UID:$GID /nextcloud/config/config.php /nextcloud/apps2

# Create folder for php sessions if not exists
if [ ! -d /data/session ]; then
  mkdir -p /data/session;
fi

echo "Updating permissions..."
for dir in /nextcloud /config /apps2 /var/log /php /nginx /tmp /etc/s6.d; do
if $(find $dir ! -user $UID -o ! -group $GID|egrep '.' -q); then
  echo "Updating permissions in $dir..."
  chown -R $UID:$GID $dir
else
  echo "Permissions in $dir are correct."
fi
done

#Only update /data permissions when requested. Or on first run.
if [ "$PERMISSION_RESET" = "1" ] || [ ! -f /config/config.php ] ; then
  echo "Updating permissions in /data..."
  chown -R $UID:$GID /data
else
  echo "Not updating /data since \$PERMISSION_RESET was not '1' and this was not our first run"
fi
echo "Done updating permissions."

if [ -f /data/nextcloud.log ]; then
	echo "Rotating Logs"
	timestamp=`date +%Y%m%d-%H%M%S`
	mv /data/nextcloud.log "/data/nextcloud.log.$timestamp"
	touch /data/nextcloud.log

	if [ "${LOGRETENTIONDAYS:-null}" = null ]; then
		LOGRETENTIONDAYS=7
	fi
	echo "Removing logs older than ${LOGRETENTIONDAYS} days"
	find /data -mindepth 1 -name "nexcloud.log.*" -type f -mtime +${LOGRETENTIONDAYS} -delete
fi

if [ ! -f /config/config.php ]; then
    # New installation, run the setup
    echo "No config file detected; running setup"
    /usr/local/bin/setup.sh
else

    # Run upgrade if applicable
    echo "Running OCC Upgrade"
    occ upgrade -vvv

	# Add missing columns
	echo "Adding any missing DB columns"
	occ db:add-missing-columns

    # Add missing indexes
    echo "Adding any missing DB indexes"
    occ db:add-missing-indices

    # Convert filecache fields
    echo "Converting filecache fields"
    occ db:convert-filecache-bigint

    # Update DB schema as needed
    echo "Update the DB Schema if needed"
    occ db:convert-mysql-charset
fi

# Run auto update
if [ "$APP_AUTO_UPDATE" = "1" ] ; then
  echo "Updating nextcloud applications."
  occ app:update --all
fi

echo "Startup complete; launching server"
exec su-exec $UID:$GID /bin/s6-svscan /etc/s6.d
