#!/bin/bash -f

# profile-postgres.sh
# Dave McCormick
PROFILE_VERSION="2.3"
PROFILE_URL="http://www.practicalclouds.com/content/guide/postgres-database"
PROFILE_DOWNLOAD="http://files001.practicalclouds.com/profile-postgres.sh"
MINIMUM_BOOTSTRAP_FUNCTIONS="2.0"

# please refer to the instructions on using this profile script at
# http://www.practicalclouds.com/content/guide/postgres

# 1.0 - Initial, install postgres, attach an ebs and create or import a db
# 1.1 - Support bootstrap-functions v1.11 with command line style args
# 1.2 - Fix postgres not initialising new db issue (/var/lib/pgsql/data 
#       exists before initdb has been run).
# 1.3 - Add options for automatic backup of databases to S3 according to a 
#       cron schedule and optionally keeping X previous backups.
#       Don't quit if there are errors in the import.
# 1.4 - Fix create of database without import file, needs template argument
# 1.5 - Allow the importfile to be a tar archive containing the actual import
#       file, like those created by the automatic backups. 
# 1.6 - Checks for new versions available and minimum bootstrap-fuctions required.
#       (needs functions v1.24 and above) - uses fatal_error.
# 1.7 - Download backup-postgres.sh from website if not available locally.
# 2.0 - update to version 2.0 of the boot process.
# 2.1 - Make Fedora 16 compatible - "no service postgresql initdb"
#       Use alternative method of looking up users compat with postgres 9
# 2.2 - Turn off globbing for backups.
# 2.3 - Fix mounting an ebsvolume and postgres 9

# Copyright 2011 David McCormick
# 
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
# 
#        http://www.apache.org/licenses/LICENSE-2.0
# 
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

prog=$(basename $0)
logger="logger -t $prog"

MYBOOTBUCKET=`cat /etc/AWS-BOOTBUCKET`
MYPLATFORM=`cat /etc/AWS-PLATFORM`

# load the bootstrap-functions
if [ -s "/etc/bootstrap.d/bootstrap-functions2" ]; then
        . /etc/bootstrap.d/bootstrap-functions2
else
        $logger "I couldn't load the bootstrap-fuctions2, aborting!"
        exit 1
fi

# Install Postgres

$logger "Installing Postgres."
yum -y install postgresql postgresql-server


# If we have a DBVOL arg then mount the ebs volume
DBVOL=`read_arg -n dbvol`
if [[ "$DBVOL" != "" ]]; then
	$logger "Mounting ebs database volume $DBVOL"
	mount_ebsvol -n $DBVOL -m /var/lib/pgsql
	if [[ "$?" != "0" ]]; then
		fatal_error "No EBS Volume so aborting rest of postgres bootstrap!"
		exit 1
	fi
	chown -R postgres:postgres /var/lib/pgsql
fi
	
# check for the existence of a database and install a new one if one not available
if [ ! -d "/var/lib/pgsql/data/base" ]; then
	$logger "Initialising Postgres for the first time..."
	su postgres -c "initdb --encoding=UTF8 -D /var/lib/pgsql/data"

	cat >/var/lib/pgsql/data/pg_hba.conf <<EOT
# TYPE  DATABASE    USER        CIDR-ADDRESS          METHOD

# "local" is for Unix domain socket connections only
local   all         all                               trust
# IPv4 local connections:
host    all         all         127.0.0.1/32          md5
# IPv6 local connections:
host    all         all         ::1/128               md5
EOT
fi

# Lets make sure we can perform anything we want on the databases.  We'll change this back to password
# protected at the end of the script or if we abort
sed -e 's/^local.*/local   all         all                               trust/' -i /var/lib/pgsql/data/pg_hba.conf

#start the database
if [ ! -e "/var/lock/subsys/postgresql" ]; then
	/sbin/service postgresql start
	# leave enough of a wait for the database to have started up!
	$logger "Wait 30 seconds..."
	sleep 30
	$logger "Started postgres daemon."
else
	fatal_error "Postgres is already started, and it shouldn't have been - aborting!"
	exit 1
fi

# Check if we want to create a new db and optionally import it from a file...
DBUSER=`read_arg -n dbuser`
DBPASS=`read_arg -n dbpass`
DBNAME=`read_arg -n dbname`
IMPORTFILE=`read_arg -n importfile`

if [[ "$DBUSER" != "" && "$DBNAME" != "" ]]; then
	# first check that the user already exists
	UEXISTS=`psql -d postgres -U postgres --command "\\du $DBUSER"| awk "(\\\$1 == \"$DBUSER\"){print}"`
	if [[ "$UEXISTS" == "" ]]; then 
		$logger "Creating postgres user $DBUSER..."
		if [[ "$DBPASS" != "" ]]; then
			psql -U postgres --command "CREATE USER $DBUSER with PASSWORD '$DBPASS' CREATEDB NOCREATEUSER;"
		else
			$logger "WARNING: Creating $DBUSER with no password!"
			psql -U postgres --command "CREATE USER $DBUSER CREATEDB NOCREATEUSER;"
		fi
		UEXISTS=`psql -d postgres -U postgres --command "\\du $DBUSER"| awk "(\\\$1 == \"$DBUSER\"){print}"`
		if [[ "$UEXISTS" == "" ]]; then
			fatal_error "I couldn't create the user $DBUSER!!"
			sed -e 's/^local.*/local   all         all                               md5/' -i /var/lib/pgsql/data/pg_hba.conf
			service postgresql restart
			exit 1
		fi
	fi

	# check if we need to import the database from a file or create an empty new one...
	if [[ "$IMPORTFILE" != "" ]]; then
		# we are importing the db from a backup file
		get_file -f $IMPORTFILE
		if [[ "$?" != "0" ]]; then
			$logger "I couldn't retreive the database import file : $IMPORTFILE"
		else
			# check whether db exists and drop it,,,
			DBEXISTS=`psql -U postgres --list | grep -e "^\s*$DBNAME"`
			if [[ "$DBEXISTS" != "" ]]; then
				$logger "Database $DBNAME already exists, dropping it."
				dropdb -U postgres $DBNAME
			fi
			#create it again
			$logger "Creating database $DBNAME with owner $DBUSER..."
			createdb -U postgres --encoding=UTF8 --owner=$DBUSER -T template0 $DBNAME			
			if [[ "$?" != "0" ]]; then 
				fatal_error "Error, I couldn't create $DBNAME!"
				sed -e 's/^local.*/local   all         all                               md5/' -i /var/lib/pgsql/data/pg_hba.conf
				service postgresql restart
				exit 1
			fi

			#import the db import file
			LOCALFILE=`basename $IMPORTFILE`
			#automatically work out what to do with compressed files and tar archives.
			case "$LOCALFILE" in
				*.tar.gz)	CONTAINEDFILE=`tar -tf /etc/bootstrap.d/$LOCALFILE | head -1`
						cd /etc/bootstrap.d
						tar xfpz /etc/bootstrap.d/$LOCALFILE
						LOCALFILE="$CONTAINEDFILE"
						;;
				*.tgz)		CONTAINEDFILE=`tar -tf /etc/bootstrap.d/$LOCALFILE | head -1`
						cd /etc/bootstrap.d
						tar xfpz /etc/bootstrap.d/$LOCALFILE
						LOCALFILE="$CONTAINEDFILE"
						;;
				*.tar.bz2)	CONTAINEDFILE=`tar -tf /etc/bootstrap.d/$LOCALFILE | head -1`
						cd /etc/bootstrap.d
						tar xfpj /etc/bootstrap.d/$LOCALFILE
						LOCALFILE="$CONTAINEDFILE"
						;;
				*.gz)		if [[ -f "${LOCALFILE%.gz}" ]]; then
                                        		rm -f ${LOCALFILE%.gz}
                                		fi
						gzip -d /etc/bootstrap.d/$LOCALFILE
						LOCALFILE=${LOCALFILE%.gz}
						;;
				*.bz2)		if [[ -f "${LOCALFILE%.bz2}" ]]; then
                                        		rm -f ${LOCALFILE%.bz2}
                                		fi
						bzip2 -d /etc/bootstrap.d/$LOCALFILE
						LOCALFILE=${LOCALFILE%.bz2}
						;;
				*)		$logger "We didn't match any archive or compressed files."
						;;
			esac

			$logger "Running pg_restore command: pg_restore -O -c -p 5432 -U $DBUSER -d $DBNAME /etc/bootstrap.d/$LOCALFILE"
			RESULT=`pg_restore -O -c -p 5432 -U $DBUSER -d $DBNAME /etc/bootstrap.d/$LOCALFILE 2>&1`			
			if [[ "$?" != "0" ]]; then
				$logger "I couldn't import the database $DBNAME from /etc/bootstrap.d/$LOCALFILE!"
				RESULT=`echo $RESULT | sed -e 's/[^a-zA-Z0-9_-]//g'`
				$logger "ERROR: $RESULT"
			else
				$logger "Successfully imported the database $DBNAME from /etc/bootstrap.d/$LOCALFILE"
			fi
		fi
	else
		# check if database exists and create if not
		DBEXISTS=`psql -U postgres --list | grep -e "^\s*$DBNAME"`
		if [[ "$DBEXISTS" == "" ]]; then
			RESULT=`createdb -U postgres --encoding=UTF8 --owner=$DBUSER -T template0 $DBNAME 2>&1`
			if [[ "$?" != "0" ]]; then 
				fatal_error "Error, I couldn't create $DBNAME!" "Error: $RESULT"
				sed -e 's/^local.*/local   all         all                               md5/' -i /var/lib/pgsql/data/pg_hba.conf
				service postgresql restart
				exit 1
			else
				$logger "Successfully created database $DBNAME"
			fi
		fi
	fi
else
	$logger "No import or create of database was requested."
fi

# Install an automatic backup script if requested
BACKUPS=`read_arg -n dbbackup`
if [[ "$BACKUPS" == "true" ]]; then
        $logger "Postgres backups requested"
	DBSTOBACKUP=`read_arg -n dbstobackup`
	if [[ "$DBSTOBACKUP" == "" && "$DBNAME" != "" ]]; then
		DBSTOBACKUP="$DBNAME"
	fi
	if [[ "$DBSTOBACKUP" == "" || "$DBUSER" == "" || "$DBPASS" == "" ]]; then
		$logger "You need to specify dbstobackup (or dbname), dbuser and dbpass args in order to enable backups!"
	else 
	        DEST=`read_arg -n dbbackups3path`
        	if [[ "$DEST" == "" ]]; then
                	$logger "You need to specify dbbackups3path in order to save the backup to S3."
        	else
                	KEEP=`read_arg -n dbbackupkeep`
                	if [[ "$KEEP" == "" ]]; then
                        	KEEP="7"
                	fi
                	SCHEDULE=`read_arg -n dbbackupschedule`
                	if [[ "$SCHEDULE" == "" ]]; then
                        	SCHEDULE="30 2 * * *"
                	fi

                	# make sure we have the postgres specific backup script...
                	get_file -f backup-postgres.sh -d /usr/local/bin
			if [[ ! -s "/usr/local/bin/backup-postgres.sh" ]]; then
                                curl -s -o /usr/local/bin/backup-postgres.sh http://files001.practicalclouds.com/backup-postgres.sh
                        fi
                	if [[ -s "/usr/local/bin/backup-postgres.sh" ]]; then
                        	chmod +x /usr/local/bin/backup-postgres.sh

                        	# Allow the user to pick the backup credentials to use.
                        	BACKUPCRED=`read_arg -n dbbackupcredentials`
                        	if [[ "$BACKUPCRED" != "" ]]; then   
                                	set_access -f $BACKUPCRED -a backup
                        	else
                                	# Try a default backup-user-credentials file...
                                	set_access -f backup-user-credentials -a backup
                        	fi

                        	#write the backup cron entries
                        	if [[ -s "/root/.awssecret-backup" ]]; then
                                	SCFG="-c /root/.awssecret-backup"
                        	else
                                	SCFG=""
                       	 	fi

                        	if [[ "$MYPLATFORM" != "" ]]; then
                                	PREFIX="$MYPLATFORM-"
                        	else
                                	PREFIX=""
                        	fi

				# Backup each selected datanase one after another...
				BACKUPCOMMAND="$SCHEDULE"
				for ADATABASE in $DBSTOBACKUP
				do
                        		BACKUPCOMMAND="${BACKUPCOMMAND} /usr/local/bin/backup-postgres.sh -f ${PREFIX}postgres_backup_${ADATABASE} -t $DEST -k $KEEP -d ${ADATABASE} -u $DBUSER -w $DBPASS $SCFG;"
				done
				BACKUPCOMMAND=${BACKUPCOMMAND%;}
				echo "${BACKUPCOMMAND}" >>/var/spool/cron/root
				$logger "Added automatic backups of postgres to cron"
                	else
                        	$logger "I could not find the backup script backup-postgres.sh so I can't enable automatic backups!"
                	fi
        	fi
	fi
else
        $logger "Automatic backups of postgres have not been requested."
fi

# now restart postgres with more restrictive settings
sed -e 's/^local.*/local   all         all                               md5/' -i /var/lib/pgsql/data/pg_hba.conf
service postgresql restart

