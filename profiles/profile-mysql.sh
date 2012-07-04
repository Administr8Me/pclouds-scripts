#!/bin/bash -f

# profile-mysql.sh
# Dave McCormick
PROFILE_VERSION="2.3"
PROFILE_URL="http://www.practicalclouds.com/content/guide/mysql-database"
PROFILE_DOWNLOAD="http://files001.practicalclouds.com/profile-mysql.sh"
MINIMUM_BOOTSTRAP_FUNCTIONS="2.0"

# please refer to the instructions on using this profile script at
# http://www.practicalclouds.com/content/guide/mysql

# 1.0 - Initial, copy of mysql profile with modifications.
# 1.1 - Generate a random root password if non is supplied.
# 1.2 - Allow the import file to be an archive file, like
#       those created by the automatic backups.
# 1.3 - check version numbers and updates available and
#       use the fatal_error function.
# 1.4 - Add download of backup-mysql.sh from practical
#       clouds website if not in bootbucket.
# 2.0 - Update to match version 2.0 boot process changes.
# 2.1 - Need to change ownership of /var/lib/mysql to 'mysql'
# 2.2 - Add 'devel' arg which will also install the devel packages.
# 2.3 - Turn off globbing so that backup schedule works.

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
        $logger "I couldn't load the bootstrap-functions2, aborting!"
        exit 1
fi

# Add a function for generating a random password.
function randpass
{
        echo `</dev/urandom tr -dc A-Za-z0-9 | head -c16`
}

# Install MYSQL
$logger "Installing MYSQL."
PACKAGES="mysql-server"
DEVEL=`read_arg -n devel`
if [[ "$DEVEL" == "true" ]]; then
	PACKAGES="$PACKAGES mysql-devel"
fi
yum -y install $PACKAGES

# If we have a DBVOL arg then mount the ebs volume
DBVOL=`read_arg -n dbvol`
if [[ "$DBVOL" != "" ]]; then
	$logger "Mounting ebs database volume $DBVOL"
	mount_ebsvol -n $DBVOL -m /var/lib/mysql
	if [[ "$?" != "0" ]]; then
		fatal_error "No EBS Volume so aborting rest of mysql bootstrap!"
		exit 1
	else
		chown -R mysql:mysql /var/lib/mysql
	fi
fi
	
#start the database
if [ ! -e "/var/lock/subsys/mysqld" ]; then
	/sbin/service mysqld start
	$logger "Started mysqld daemon."
else
	fatal_error "mysqld is already running, and it shouldn't have been - aborting!"
	exit 1
fi

# Check if we want to create a new db and optionally import it from a file...
DBUSER=`read_arg -n dbuser`
DBPASS=`read_arg -n dbpass`
DBNAME=`read_arg -n dbname`
IMPORTFILE=`read_arg -n importfile`
ROOTPASS=`read_arg -n dbrootpass`

if [[ "$ROOTPASS" == "" ]]; then
	ROOTPASS=`randpass`
	$logger "No rootpass was specified, setting a random password of \"$ROOTPASS\" for the root mysql user."
fi

# check root access to mysql
MYSQLCOMMAND="mysql -u root"
$MYSQLCOMMAND -e "show databases \G" 2>&1 >/dev/null
if [[ "$?" != "0" ]]; then
	if [[ "$ROOTPASS" != "" ]]; then
		MYSQLCOMMAND="mysql -u root -p$ROOTPASS"
		$MYSQLCOMMAND -e "show databases \G" 2>&1 >/dev/null
		if [[ "$?" != "0" ]]; then
			fatal_error "I can't access the databases even with the password $ROOTPASS! Aborting!"
			exit 1
		else
			$logger "I can access the databases with the password specified, thanks."
		fi
	else
		fatal_error "I can't access the database as root and no dbrootpass has been specified.  Aborting!"
		exit 1
	fi
else
	$logger "Access to databases has been granted to root without a password!"
	# check and set root password if required
	if [[ "$ROOTPASS" != "" ]]; then
		$logger "Setting root password: mysqladmin -u root password '${ROOTPASS}'"
        	mysqladmin -u root password "${ROOTPASS}"
		if [[ "$?" == "0" ]]; then
			$logger "Successfully set mysql root's password."
			MYSQLCOMMAND="mysql -u root -p$ROOTPASS"
		else
			$logger "Error, I couldn't set mysql root's password!"
		fi
	else
		$logger "WARNING! No dbrootpass specified so I am leaving the databases without password protection!"
	fi
fi			

# check if a database has been specified and also an import file for it...
if [[ "$DBNAME" != "" ]]; then
	if [[ "$IMPORTFILE" != "" ]]; then
		# we are importing the db from a backup file
		get_file -f $IMPORTFILE
		if [[ "$?" != "0" ]]; then
			$logger "I couldn't retreive the database import file : $IMPORTFILE"
		else
			# check whether db exists and drop it,,,
			DBEXISTS=`$MYSQLCOMMAND -e "show databases \G" | grep ^Database | awk "(\\\$2 == \"$DBNAME\"){print}"`
			if [[ "$DBEXISTS" != "" ]]; then
				$logger "Database $DBNAME already exists, dropping it."
				$MYSQLCOMMAND -e "DROP DATABASE $DBNAME;"
			fi
			#create it again
			$logger "Creating database $DBNAME..."
			$MYSQLCOMMAND -e "CREATE DATABASE $DBNAME;"
			if [[ "$?" != "0" ]]; then 
				fatal_error "Error, I couldn't create $DBNAME!"
				exit 1
			fi

                        #import the db import file
                        LOCALFILE=`basename $IMPORTFILE`
                        #automatically work out what to do with compressed files and tar archives.
                        case "$LOCALFILE" in
                                *.tar.gz)       CONTAINEDFILE=`tar -tf /etc/bootstrap.d/$LOCALFILE | head -1`
                                                cd /etc/bootstrap.d
                                                tar xfpz /etc/bootstrap.d/$LOCALFILE
                                                LOCALFILE="$CONTAINEDFILE"
                                                ;;
                                *.tgz)          CONTAINEDFILE=`tar -tf /etc/bootstrap.d/$LOCALFILE | head -1`
                                                cd /etc/bootstrap.d
                                                tar xfpz /etc/bootstrap.d/$LOCALFILE
                                                LOCALFILE="$CONTAINEDFILE"
                                                ;;
                                *.tar.bz2)      CONTAINEDFILE=`tar -tf /etc/bootstrap.d/$LOCALFILE | head -1`
                                                cd /etc/bootstrap.d
                                                tar xfpj /etc/bootstrap.d/$LOCALFILE
                                                LOCALFILE="$CONTAINEDFILE"
                                                ;;
                                *.gz)           if [[ -f "${LOCALFILE%.gz}" ]]; then
                                                        rm -f ${LOCALFILE%.gz}
                                                fi
                                                gzip -d /etc/bootstrap.d/$LOCALFILE
                                                LOCALFILE=${LOCALFILE%.gz}
                                                ;;
                                *.bz2)          if [[ -f "${LOCALFILE%.bz2}" ]]; then
                                                        rm -f ${LOCALFILE%.bz2}
                                                fi
                                                bzip2 -d /etc/bootstrap.d/$LOCALFILE
                                                LOCALFILE=${LOCALFILE%.bz2}
                                                ;;
                        esac

			$logger "Running import command, $MYSQLCOMMAND </etc/bootstrap.d/$LOCALFILE 2>&1"
			RESULT=`$MYSQLCOMMAND </etc/bootstrap.d/$LOCALFILE 2>&1`			
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
		DBEXISTS=`$MYSQLCOMMAND -e "show databases \G" | grep ^Database | awk "(\\\$2 == \"$DBNAME\"){print}"`
		if [[ "$DBEXISTS" == "" ]]; then
			RESULT=`$MYSQLCOMMAND -e "CREATE DATABASE $DBNAME;"`
			if [[ "$?" != "0" ]]; then 
				fatal_error "Error, I couldn't create $DBNAME!" "Error: $RESULT"
				exit 1
			else
				$logger "Successfully created database $DNAME"
			fi
		else
			$logger "The Database $DBNAME already exists."
		fi
	fi

	# If we have a db name and a user account - make sure the user is created and given access to the database...
	if [[ "$DBUSER" != "" ]]; then
        	# check that the user already exists
        	UEXISTS=`$MYSQLCOMMAND -e "SELECT User FROM mysql.user WHERE user='$DBUSER';"`
        	if [[ "$UEXISTS" == "" ]]; then
                	$logger "Creating mysql user $DBUSER..."
                	if [[ "$DBPASS" != "" ]]; then
                        	$MYSQLCOMMAND -e "GRANT ALL on ${DBNAME}.* to '${DBUSER}'@'localhost' IDENTIFIED BY '$DBPASS';"
                        	$MYSQLCOMMAND -e "GRANT ALL on ${DBNAME}.* to '${DBUSER}'@'%' IDENTIFIED BY '$DBPASS';"
               	 	else
                        	$logger "WARNING: Creating $DBUSER with no password!"
                        	$MYSQLCOMMAND -e "GRANT ALL on ${DBNAME}.* to '$DBUSER'@'localhost';"
                        	$MYSQLCOMMAND -e "GRANT ALL on ${DBNAME}.* to '$DBUSER'@'%';"
                	fi
                	UEXISTS=`$MYSQLCOMMAND -e "SELECT User FROM mysql.user WHERE user='$DBUSER';"`
                	if [[ "$UEXISTS" == "" ]]; then
                        	fatal_error "I couldn't create the user $DBUSER!!"
                        	exit 1
			else
				$logger "The dbuser $DBUSER has been created and allowed ALL access to $DBNAME."
                	fi
        	fi
	else
        	$logger "I can't set any database user access without a database name and username."
	fi
fi

# Install an automatic backup script if requested
BACKUPS=`read_arg -n dbbackup`
if [[ "$BACKUPS" == "true" ]]; then
        $logger "MYSQL backups requested"
	
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
                	SCHEDULE=`read_arg -t dbbackupschedule`
                	if [[ "$SCHEDULE" == "" ]]; then
                        	SCHEDULE="30 2 * * *"
                	fi

                	# make sure we have the mysql specific backup script...
                	get_file -f backup-mysql.sh -d /usr/local/bin
			if [[ ! -s "/usr/local/bin/backup-mysql.sh" ]]; then
				curl -s -o /usr/local/bin/backup-mysql.sh http://files001.practicalclouds.com/backup-mysql.sh
			fi
                	if [[ -s "/usr/local/bin/backup-mysql.sh" ]]; then
                        	chmod +x /usr/local/bin/backup-mysql.sh

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
                        		BACKUPCOMMAND="${BACKUPCOMMAND} /usr/local/bin/backup-mysql.sh -f ${PREFIX}mysql_backup_${ADATABASE} -t $DEST -k $KEEP -d ${ADATABASE} -u $DBUSER -w $DBPASS $SCFG;"
				done
				BACKUPCOMMAND=${BACKUPCOMMAND%;}
				echo "${BACKUPCOMMAND}" >>/var/spool/cron/root
				$logger "Added automatic backups of mysql to cron"
                	else
                        	$logger "I could not find the backup script backup-mysql.sh so I can't enable automatic backups!"
                	fi
        	fi
	fi
else
        $logger "Automatic backups of mysql have not been requested."
fi

