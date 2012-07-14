#!/bin/bash

# profile-joomla.sh
# Dave McCormick
PROFILE_VERSION="2.1"
PROFILE_URL="http://www.practicalclouds.com/content/guide/joomla-web-cms"
PROFILE_DOWNLOAD="http://files001.practicalclouds.com/profile-joomla.sh"
MINIMUM_BOOTSTRAP_FUNCTIONS="2.0"

# please refer to the instructions on using this profile script at
# http://www.practicalclouds.com/content/guide/joomla-web-cms

# 1.0  - initial, load mysql and webserver profiles with correct
#      - settings and install latest joomla if not found at
#      - /var/www/html/joomla
# 1.1  - Fix automatic installer, patch pachage was being downloaded instead of the full one.
# 2.0  - Update in line with version 2.0 of the boot process.
# 2.1  - Prevent Alphas and Betas being downloaded.

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

# Note: if your database is going to run locally on an EC2 instance then
# you might want it to import a database file each time it is loaded, but
# if you plan to persist your database by running it on an ebs volume then
# only import a file the first time you run the profile or select to install
# joomla from scratch.

prog=$(basename $0)
logger="logger -t $prog"

# load the bootstrap-functions
if [ -s "/etc/bootstrap.d/bootstrap-functions2" ]; then
        . /etc/bootstrap.d/bootstrap-functions2
else
        $logger "I couldn't load the bootstrap-fuctions2, aborting!"
        exit 1
fi

# Add a function for generating a random passwords etc
# $1 is the number of characters to generate.
function rand
{
	echo `</dev/urandom tr -dc A-Za-z0-9 | head -c$1`
}

# READ TAGS AND SETUP OUR OPTIONS....

# DATABASE
# Note: the DBVOL name will be prefixed with "your platform arg"-
DBVOL=`read_arg -n dbvol`
DBNAME=`read_arg -n dbname`
if [[ "$DBNAME" == "" ]]; then
	$logger "Using the default joomla database name, joomladb"
	DBNAME="joomladb"
fi
DBUSER=`read_arg -n dbuser`
if [[ "$DBUSER" == "" ]]; then
	$logger "Using the default database user, joomla"
	DBUSER="joomla"
fi
DBPASS=`read_arg -n dbpass`
if [[ "$DBPASS" == "" ]]; then
	DBPASS=`rand 16`
	$logger "I've generated the random password \"$DBPASS\" for the database user $DBUSER"
fi
# Only import a file the first time you create a database on an ebs volume as
# it will persist database contents over reboots.  If you want to start from 
# scratch then do not import an import file.
IMPORTFILE=`read_arg -n importfile`

# WEBSERVER
#WEBVOL=""
WEBVOL=`read_arg -n webvol`
S3WEBBUCKET=`read_arg -n s3webbucket`
WEBCREDENTIALS=`read_arg -n webcredentials`
WEBCONFIGS=`read_arg -n webconfigs`
WEBCONTENT=`read_arg -n webcontent`
PHPINI=`read_arg -n phpini`

# BACKUPS
BACKUPPATH=`read_arg -n backuppath`
BACKUPSCHEDULE=`read_arg -n backupschedule`
BACKUPCREDENTIALS=`read_arg -n backupcredentials`
KEEPBACKUPS=`read_arg -n keepbackups`

# Auto Install:  Install joomla from source with database details.
# Joomla will be installed from a specified installer or downloaded
# from joomla.org when /var/www/html/joomla does not exist.
INSTALL=`read_arg -n install`
# minimal - install just the basic site, not the sample data
MINIMAL=`read_arg -n minimal`

# Load the webserver and mysql profiles...

# Only add the options which have been included at top of script...
DBPROFILE="mysql"
[[ "$DBVOL" != "" ]] && DBPROFILE="$DBPROFILE dbvol=$DBVOL"
[[ "$DBUSER" != "" ]] && DBPROFILE="$DBPROFILE dbuser=$DBUSER"
[[ "$DBPASS" != "" ]] && DBPROFILE="$DBPROFILE dbpass=$DBPASS"
[[ "$DBNAME" != "" ]] && DBPROFILE="$DBPROFILE dbname=$DBNAME"
[[ "$IMPORTFILE" != "" ]] && DBPROFILE="$DBPROFILE importfile=$IMPORTFILE"
[[ "$BACKUPPATH" != "" ]] && DBPROFILE="$DBPROFILE dbbackup dbbackups3path=$BACKUPPATH"
[[ "$BACKUPSCHEDULE" != "" ]] && DBPROFILE="$DBPROFILE dbbackupschedule=$BACKUPSCHEDULE"
[[ "$BACKUPCREDENTIALS" != "" ]] && DBPROFILE="$DBPROFILE dbbackupcredentials=$BACKUPCREDENTIALS"
[[ "$KEEPBACKUPS" != "" ]] && DBPROFILE="$DBPROFILE dbbackupkeep=$KEEPBACKUPS"

#load the database profile
load_profile $DBPROFILE
if [[ "$?" != "0" ]]; then
	fatal_error "The database could't be loaded!  Please fix the issue and then start this profile again."
	exit 1
fi

# Now load the webserver profile from the options given above
WEBPROFILE="apache withphp"
[[ "$WEBVOL" != "" ]] && WEBPROFILE="$WEBPROFILE webvol=$WEBVOL"
[[ "$S3WEBBUCKET" != "" ]] && WEBPROFILE="$WEBPROFILE s3webbucket=$S3WEBBUCKET"
[[ "$WEBCREDENTIALS" != "" ]] && WEBPROFILE="$WEBPROFILE webcredentials=$WEBCREDENTIALS"
[[ "$WEBCONFIGS" != "" ]] && WEBPROFILE="$WEBPROFILE webconfigs=$WEBCONFIGS"
[[ "$WEBCONTENT" != "" ]] && WEBPROFILE="$WEBPROFILE webcontent=$WEBCONTENT"
[[ "$PHPINI" != "" ]] && WEBPROFILE="$WEBPROFILE phpini=$PHPINI"
[[ "$BACKUPPATH" != "" ]] && WEBPROFILE="$WEBPROFILE webbackup webbackups3path=$BACKUPPATH"
[[ "$BACKUPSCHEDULE" != "" ]] && WEBPROFILE="$WEBPROFILE webbackupschedule=$BACKUPSCHEDULE"
[[ "$KEEPBACKUPS" != "" ]] && WEBPROFILE="$WEBPROFILE webbackupkeep=$KEEPBACKUPS"

load_profile $WEBPROFILE
if [[ "$?" != "0" ]]; then
	fatal_error "The webserver couldn't be loaded!  Please fix the issue and then start this profile again."
	exit 1
fi

# Set some php parameters for joomla...
sed -e 's/^memory_limit.*$/memory_limit = 250M/' -i /etc/php.ini
sed -e 's/^max_execution_time*$/max_execution_time = 120/' -i /etc/php.ini
sed -e 's/^post_max_size.*$/post_max_size = 20M/' -i /etc/php.ini
sed -e 's/^upload_max_filesize.*$/upload_max_filesize = 10M/' -i /etc/php.ini

# we need to work out whether to install joomla.
if [[ ! -e "/var/www/html/joomla" ]]; then
	$logger "Joomla isn't installed at /var/www/html/joomla"
	if [[ "$INSTALL" != "" ]]; then
		$logger "Installing from $INSTALL"
		get_file -f $INSTALL
	else
		$logger "Installing the latest version from joomlacode.org..."
		cd /etc/bootstrap.d
		#INSTALL=`curl -s http://joomlacode.org/gf/project/joomla/frs | grep -i "Stable-Full" | grep tar.gz | head -1 | sed -r -e 's/^.*href="([^"]+).*$/\1/'`
		INSTALL=`curl -s http://joomlacode.org/gf/project/joomla/frs | grep -v -i "alpha" | grep -v -i "beta" | grep -i "Stable-Full" | grep tar.gz | head -1 | sed -r -e 's/^.*href="([^"]+).*$/\1/'`
		if [[ "$INSTALL" != "" ]]; then
                	$logger "Downloading latest version, $INSTALL..."
			# -L tells it to follow redirects
			SAVEFILE=`basename $INSTALL`
                        curl -L -s -o $SAVEFILE http://joomlacode.org$INSTALL
                else
                        fatal_error "I couldn't work out the latest installer for Joomla!  Sorry, please download it yourself, place in your bootbucket and then use the \"install\" tag."
                        exit 1
                fi
	fi
	INSTALL=`basename $INSTALL`
	if [[ -s "/etc/bootstrap.d/$INSTALL" ]]; then
		# Extract the install
		JSHORT=`echo $INSTALL | sed -r -e 's/^.*([Jj][Oo][Oo][Mm][Ll][Aa][._0-9-]+[0-9]).*/\1/'`
		$logger "Installing $JSHORT ($INSTALL)"
		cd /var/www/html
		if [[ ! -d "$JSHORT" ]]; then
			mkdir $JSHORT
			tar xfpz /etc/bootstrap.d/$INSTALL -C $JSHORT
		else
			$logger "Joomla $JSHORT already apprears to be installed!"
		fi
		# create link /var/www/html/joomla to downloaded version
		ln -s $JSHORT joomla
		chown -R apache:apache /var/www/html/joomla/.

		#$logger "Configuring Joomla"
		cp -p /var/www/html/joomla/installation/configuration.php-dist /var/www/html/joomla/configuration.php

		# set database, user and pw
		sed -e "s/public *\$user *= *'' *;/public \$user = '$DBUSER';/" -i /var/www/html/joomla/configuration.php
		sed -e "s/public *\$password *= *'' *;/public \$password = '$DBPASS';/" -i /var/www/html/joomla/configuration.php
		sed -e "s/public *\$db *= *'' *;/public \$db = '$DBNAME';/" -i /var/www/html/joomla/configuration.php
		SALT=`rand 16`
		sed -e "s/public *\$secret *= *'[a-zA-Z0-9]*' *;/public \$secret = '$SALT';/" -i /var/www/html/joomla/configuration.php
		DBPREFIX=`rand 6`
		sed -e "s/public *\$dbprefix *= *'[a-zA-Z0-9_]*' *;/public \$dbprefix = '${DBPREFIX}_';/" -i /var/www/html/joomla/configuration.php
		sed -e "s/public *\$root_user *= *'[0-9]*' *;/\/* public \$root_user = '42'; *\//" -i /var/www/html/joomla/configuration.php
		# turn off output buffering.
		sed -e 's/ *output_buffering *=.*/output_buffering = off/' -i /etc/php.ini

		$logger "Loading basic Joomla MYSQL Data."
		sed -e "s/#_/$DBPREFIX/g" -i /var/www/html/joomla/installation/sql/mysql/joomla.sql
		RESULT=`mysql -u$DBUSER -p$DBPASS $DBNAME </var/www/html/joomla/installation/sql/mysql/joomla.sql 2>&1`
		if [[ "$?" != "0" ]]; then
			$logger "ERROR!!! I couldn't load the Joomla SQL Data!!!"
			$logger "ERROR: $RESULT"
		fi
		if [[ "$MINIMAL" == "" ]]; then
			$logger "Loading the Joomla sample website."
			sed -e "s/#_/$DBPREFIX/g" -i /var/www/html/joomla/installation/sql/mysql/sample_data.sql
			RESULT=`mysql -u$DBUSER -p$DBPASS $DBNAME </var/www/html/joomla/installation/sql/mysql/sample_data.sql 2>&1`
			if [[ "$?" != "0" ]]; then
				$logger "ERROR!!! I couldn't load the Joomla sample website!"
				$logger "ERROR: $RESULT"
			fi
		fi

		$logger "Adding an admin user with default password, please change!"
		mysql -u$DBUSER -p$DBPASS $DBNAME <<EOT
INSERT INTO \`${DBPREFIX}_users\` VALUES
(42, 'Super User', 'admin', 'email@dot.com', 'c3a7f3b22068a79c8ded2248c22a90a9:kbcOu1cpEjVphxJMkB5PcuDBLYfLvtz6', 'deprecated', 0, 1, '2011-01-13 12:09:00', '2011-01-14 08:43:24', '', '');
INSERT INTO \`${DBPREFIX}_user_usergroup_map\` VALUES (42,8);
EOT

		#if [[ "$?" != "0" ]]; then
		#	$logger "ERROR!!! I Failed to create the admin user!"
		#fi
		
		# remove the installation directory
		rm -rf /var/www/html/joomla/installation

        	# change the sites docroot to /var/www/html/joomla if configs were not loaded from a tar
        	# and automatically add the rewrite for clean urls
        	if [[ "$WEBCONFIGS" == "" ]]; then
                	sed -e 's/^DocumentRoot.*$/DocumentRoot "\/var\/www\/html\/joomla"/' -i /etc/httpd/conf/httpd.conf
                	$logger "Set DocumentRoot to /var/www/html/joomla in default httpd configs"
                	mv /etc/httpd/conf.d/mod_security.conf /etc/httpd/conf.d/mod_security.conf.disabled
        	fi

        	# restart apache
        	$logger "Restarting Apache..."
        	RESULT=`service httpd restart`
        	if [[ "$?" != "0" ]]; then
                	$logger "Apache failed to restart!"
                	$logger "Error: $RESULT"
        	fi
        	$logger "$JSHORT Installed"

	else
		fatal_error "I failed to download the joomla install file, aborting!"
		exit 1
	fi
else
	$logger "Joomla was installed with the webserver profile, not installing..."
fi

$logger "Self contained Joomla is ready."
MYEXTERNALNAME=`curl -s --fail http://169.254.169.254/latest/meta-data/public-hostname`
$logger "Please browse to http://$MYEXTERNALNAME/administrator with 'admin' 'admin' and change your password!"
$logger "You can also associate your instance with an elasticip and assign it a proper DNS domain name."
