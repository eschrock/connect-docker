#!/bin/bash
set -e

custom_extension_count=`ls -1 /opt/connect/custom-extensions/*.zip 2>/dev/null | wc -l`
if [ $custom_extension_count != 0 ]; then
	echo "Found ${custom_extension_count} custom extensions."
	for extension in $(ls -1 /opt/connect/custom-extensions/*.zip); do
		unzip -o -q $extension -d /opt/connect/extensions
	done
fi
cp mcserver_base.vmoptions mcserver.vmoptions

# Address reflective access by Jackson
echo "--add-opens=java.desktop/java.awt.color=ALL-UNNAMED" >> mcserver.vmoptions

# Copy secret mirth properties over
if [ -f /opt/connect/secrets/mirth.properties ]; then
	cat /opt/connect/secrets/mirth.properties > /opt/connect/conf/mirth.properties
fi

# merge the user's secret vmoptions
# takes a whole mcserver.vmoptions file and merges line by line with /opt/connect/mcserver.vmoptions
if [ -f /run/secrets/mcserver_vmoptions ]; then
    (cat /run/secrets/mcserver_vmoptions ; echo "") >> /opt/connect/mcserver.vmoptions
fi

# if delay is set as an environment variable then wait that long in seconds
if ! [ -z "${DELAY+x}" ]; then
	sleep $DELAY
fi

# check if DB is up
# use the db type to attempt to connect to the db before starting connect to prevent connect from trying to start before the db is up
# get the database properties from mirth.properties
db=$(grep "^database\s*=" /opt/connect/conf/mirth.properties | sed -e 's/[^=]*=\s*\(.*\)/\1/')
dbusername=$(grep "^database.username" /opt/connect/conf/mirth.properties | sed -e 's/[^=]*=\s*\(.*\)/\1/')
dbpassword=$(grep "^database.password" /opt/connect/conf/mirth.properties | sed -e 's/[^=]*=\s*\(.*\)/\1/')
dburl=$(grep "^database.url" /opt/connect/conf/mirth.properties | sed -e 's/[^=]*=\s*\(.*\)/\1/')

if [ $db == "postgres" ] || [ $db == "mysql" ]; then
	# parse host, port, and name
	dbhost=$(echo $dburl | sed -e 's/.*\/\/\(.*\):.*/\1/')
	dbport=$(echo $dburl | sed -e "s/.*${dbhost}:\(.*\)\/.*/\1/")
	if [[ $dburl =~ "?" ]]; then
		dbname=$(echo "${dburl}" | sed -e "s/.*${dbport}\/\(.*\)?.*/\1/")
	else
		dbname=$(echo "${dburl}" | sed -e "s/.*${dbport}\///")
	fi
fi

count=0
case "$db" in
	"postgres" )
		until echo $dbpassword | psql -h "$dbhost" -p "$dbport" -U "$dbusername" -d "$dbname" -c '\l' >/dev/null 2>&1; do
			let count=count+1
			if [ $count -gt 30 ]; then
				echo "Postgres is unavailable. Aborting."
				exit 1
			fi
			sleep 1
		done
		;;
	"mysql" )
        echo "trying to connect to mysql"
		until echo $dbpassword | mysql -h "$dbhost" -p -P "$dbport" -u "$dbusername" -e 'SHOW DATABASES' >/dev/null 2>&1; do
			let count=count+1
			if [ $count -gt 50 ]; then
				echo "MySQL is unavailable. Aborting."
				exit 1
			fi
			sleep 1
		done
		;;
	*)
        sleep 1
		;;
esac

exec "$@"
