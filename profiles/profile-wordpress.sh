#!/bin/bash

# profile-wordpress.sh
# Dave McCormick
PROFILE_VERSION="2.1"
PROFILE_URL="http://www.practicalclouds.com/content/guide/wordpress-web-cms"
PROFILE_DOWNLOAD="http://files001.practicalclouds.com/profile-wordpress.sh"
MINIMUM_BOOTSTRAP_FUNCTIONS="2.0"

# please refer to the instructions on using this profile script at
# http://www.practicalclouds.com/content/guide/wordpress-web-cms

# 1.0  - initial, load mysql and webserver profiles with correct
#      - settings and install latest wordpress if not found at
#      - /var/www/html/wordpress
# 1.1 - Enable version checking and use the fatal_error function.
# 2.0 - Update for version 2.0 boot process
# 2.1 - Switch curl to wget for compatibility with CentOS

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
# wordpress from scratch.

prog=$(basename $0)
logger="logger -t $prog"

# load the bootstrap-functions
if [ -s "/etc/bootstrap.d/bootstrap-functions2" ]; then
        . /etc/bootstrap.d/bootstrap-functions2
else
        $logger "I couldn't load the bootstrap-fuctions2, aborting!"
        exit 1
fi

# Add a function for generating a random password.
function randpass
{
	echo `</dev/urandom tr -dc A-Za-z0-9 | head -c16`
}

function randsalt
{
	echo `</dev/urandom tr -dc [:alnum:] | head -c64`
}

# READ TAGS AND SETUP OUR OPTIONS....

# DATABASE
# Note: the DBVOL name will be prefixed with "your platform arg"-
DBVOL=`read_arg -n dbvol`
DBNAME=`read_arg -n dbname`
if [[ "$DBNAME" == "" ]]; then
	$logger "Using the default wordpress database name, wordpressdb"
	DBNAME="wordpressdb"
fi
DBUSER=`read_arg -n dbuser`
if [[ "$DBUSER" == "" ]]; then
	$logger "Using the default database user, wordpress"
	DBUSER="wordpress"
fi
DBPASS=`read_arg -n dbpass`
if [[ "$DBPASS" == "" ]]; then
	DBPASS=`randpass`
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

# Auto Install:  Install wordpress from source with database details.
# Wordpress will be installed from a specified installer or downloaded
# from wordpress.org when /var/www/html/wordpress does not exist.
INSTALL=`read_arg -n install`

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

# Set some php parameters for wordpress...
sed -e 's/^memory_limit.*$/memory_limit = 250M/' -i /etc/php.ini
sed -e 's/^max_execution_time*$/max_execution_time = 120/' -i /etc/php.ini
sed -e 's/^post_max_size.*$/post_max_size = 20M/' -i /etc/php.ini
sed -e 's/^upload_max_filesize.*$/upload_max_filesize = 10M/' -i /etc/php.ini

# we need to work out whether to install wordpress.
if [[ ! -e "/var/www/html/wordpress" ]]; then
	$logger "Wordpress isn't installed at /var/www/html/wordpress"
	if [[ "$INSTALL" != "" ]]; then
		$logger "Installing from $INSTALL"
		get_file -f $INSTALL
	else
		$logger "Installing the latest version from WordPress.org..."
		cd /etc/bootstrap.d
		wget --content-disposition http://wordpress.org/latest.tar.gz
		INSTALL=/etc/bootstrap.d/wordpress-*.tar.gz
	fi
	INSTALL=`basename $INSTALL`
	if [[ -s "/etc/bootstrap.d/$INSTALL" ]]; then
		# Extract the install
		$logger "Installing $INSTALL"
		cd /var/www/html
		tar xfpz /etc/bootstrap.d/$INSTALL
		WPSHORT=${INSTALL%.tar.gz}
		# rename and link wordpress to the version
		mv /var/www/html/wordpress /var/www/html/$WPSHORT
		ln -s $WPSHORT wordpress
		chown -R apache:apache /var/www/html/wordpress/.

		# create the wp-config.php file
		$logger "Configuring Wordpress"
		cp /var/www/html/wordpress/wp-config-sample.php /var/www/html/wordpress/wp-config.php
		sed -e "s/^ *define *( *'DB_NAME' *, *'database_name_here' *) *; */define('DB_NAME', '$DBNAME');/" -i /var/www/html/wordpress/wp-config.php
		sed -e "s/^ *define *( *'DB_USER' *, *'username_here' *) *; */define('DB_USER', '$DBUSER');/" -i /var/www/html/wordpress/wp-config.php
		sed -e "s/^ *define *( *'DB_PASSWORD' *, *'password_here' *) *; */define('DB_PASSWORD', '$DBPASS');/" -i /var/www/html/wordpress/wp-config.php

		# install some security keys..
		$logger "Generating Random KEYS and SALT for added security..."
		SALT=`randsalt`
		sed -e "s/^ *define *( *'AUTH_KEY' *, *'put your unique phrase here' *) *; */define('AUTH_KEY','$SALT');/" -i /var/www/html/wordpress/wp-config.php	
		SALT=`randsalt`
		sed -e "s/^ *define *( *'SECURE_AUTH_KEY' *, *'put your unique phrase here' *) *; */define('SECURE_AUTH_KEY', '$SALT');/" -i /var/www/html/wordpress/wp-config.php	
		SALT=`randsalt`
		sed -e "s/^ *define *( *'LOGGED_IN_KEY' *, *'put your unique phrase here' *) *; */define('LOGGED_IN_KEY', '$SALT');/" -i /var/www/html/wordpress/wp-config.php	
		SALT=`randsalt`
		sed -e "s/^ *define *( *'NONCE_KEY' *, *'put your unique phrase here' *) *; */define('NONCE_KEY', '$SALT');/" -i /var/www/html/wordpress/wp-config.php	
		SALT=`randsalt`
		sed -e "s/^ *define *( *'AUTH_SALT' *, *'put your unique phrase here' *) *; */define('AUTH_SALT', '$SALT');/" -i /var/www/html/wordpress/wp-config.php	
		SALT=`randsalt`
		sed -e "s/^ *define *( *'SECURE_AUTH_SALT' *, *'put your unique phrase here' *) *; */define('SECURE_AUTH_SALT', '$SALT');/" -i /var/www/html/wordpress/wp-config.php	
		SALT=`randsalt`
		sed -e "s/^ *define *( *'LOGGED_IN_SALT' *, *'put your unique phrase here' *) *; */define('LOGGED_IN_SALT', '$SALT');/" -i /var/www/html/wordpress/wp-config.php	
		SALT=`randsalt`
		sed -e "s/^ *define *( *'NONCE_SALT' *, *'put your unique phrase here' *) *; */define('NONCE_SALT', '$SALT');/" -i /var/www/html/wordpress/wp-config.php	

        	# change the sites docroot to /var/www/html/wordpress if configs were not loaded from a tar
        	# and automatically add the rewrite for clean urls
        	if [[ "$WEBCONFIGS" == "" ]]; then
                	sed -e 's/^DocumentRoot.*$/DocumentRoot "\/var\/www\/html\/wordpress"/' -i /etc/httpd/conf/httpd.conf
                	$logger "Set DocumentRoot to /var/www/html/wordpress in default httpd configs"
                	mv /etc/httpd/conf.d/mod_security.conf /etc/httpd/conf.d/mod_security.conf.disabled
        	fi

        	# restart apache
        	$logger "Restarting Apache..."
        	RESULT=`service httpd restart`
        	if [[ "$?" != "0" ]]; then
                	$logger "Apache failed to restart!"
                	$logger "Error: $RESULT"
        	fi
        	$logger "$WPSHORT Installed"

	else
		fatal_error "I failed to download the wordpress install file, aborting!"
		exit 1
	fi
else
	$logger "Wordpress was installed with the webserver profile, not installing..."
fi

$logger "Self contained WordPress is ready."
MYEXTERNALNAME=`curl -s --fail http://169.254.169.254/latest/meta-data/public-hostname`
$logger "Please browse to http://$MYEXTERNALNAME or associate it with an elasticip and assign it a proper DNS name."
