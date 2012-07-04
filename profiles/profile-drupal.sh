#!/bin/bash

# profile-drupal.sh
# Dave McCormick
PROFILE_VERSION="2.1"
PROFILE_URL="http://www.practicalclouds.com/content/guide/drupal-web-cms"
PROFILE_DOWNLOAD="http://files001.practicalclouds.com/profile-drupal.sh"
MINIMUM_BOOTSTRAP_FUNCTIONS="2.0"

# please refer to the instructions on using this profile script at
# http://www.practicalclouds.com/content/guide/drupal

# 1.0  - initial, load postgres and webserver profiles with correct
#        settings using load_profile.
# 1.1  - mount s3 for storage of user content.
# 1.2  - look for the drupal database volume which matched our platform
# 1.3  - add download of the php.ini file
#        also added uid:gid to mount s3fs volume as
# 1.4  - Added automatic backups for webserver and postgres (implemented
#        within new versions of these profiles).
# 1.5  - Automatically set up Drupal's crontab
# 1.6  - You need to request webserver "withphp" now.       
# 1.7  - Incorporate mysql as a choice of database and set all of the options
#        at the top of the script rather than hard coding them.  This profile
#        isn't as simple as it was when it was first written.
# 1.8  - Automatically install drupal source tar and insert database details.
#        Rename to profile-drupal.sh, it's a lot less simple than it was.
# 1.9  - Use tags like all the other profiles, not variables you need to edit.
# 1.10 - Do not rely on the platform tag as having been set.
# 1.11 - Disable mod_security for default installs, it interfers with normal
#        site operation.
# 1.12 - Install: You can not upload modules unless /var/www/html/drupal/sites/all/default
#        is owned by apache.
# 1.13 - profile "webserver" is now called "apache" in line with other profiles.
# 1.14 - Automatically install if /var/www/html/drupal does not exist and
#	 download the latest version from the drupal website if no "install" tag
# 1.15 - Enable version checking and use fatal_error function.
# 2.0  - Convert to the 2.0 boot process.
# 2.1  - Fix, not using correct awssecret location for s3fs mounts.

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
# drupal from scratch.

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

# READ TAGS AND SETUP OUR OPTIONS....

# Work out what our hostname is...
MYHOSTNAME=`hostname -f`

# DATABASE
# Set DBTYPE to either "postgres" or "mysql"
DBTYPE=`read_arg -n dbtype`
if [[ "$DBTYPE" == "" ]]; then
	$logger "Using the default database type of postgres"
	DBTYPE="postgres"
fi
# Note: the DBVOL name will be prefixed with "your platform arg"-
DBVOL=`read_arg -n dbvol`
DBHOST=`read_arg -n dbhost`
[[ "$DBHOST" == "" ]] && DBHOST="$MYHOSTNAME"
DBNAME=`read_arg -n dbname`
if [[ "$DBNAME" == "" ]]; then
	$logger "Using the default drupal database name, drupaldb"
	DBNAME="drupaldb"
fi
DBUSER=`read_arg -n dbuser`
if [[ "$DBUSER" == "" ]]; then
	$logger "Using the default database user, drupal"
	DBUSER="drupal"
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

# DRUPAL Specific
# These variables allow you to mount an area from an S3 bucket.
# You might choose to mount the whole of the webserver content
# from an S3 bucket using the S3WEBBUCKET parameter but this allows
# you to mount just a sub directory such as the user content directory.
# That's what I want - local files for the drupal install but user 
# content on S3 so it can be shared between multiple webservers.
DRUPALCONTENTMOUNT=`read_arg -n drupalcontentmount`
DRUPALCONTENTBUCKET=`read_arg -n drupalcontentbucket`
DRUPALCONTENTCRED=`read_arg -n drupalcontentcred`

# Auto Install:  Install drupal from source with database details.
# You will need a drupal source file saved to the bootbucket or in 
# /etc/boostrap-default. Only do this once - after you have installed
# you should save your database and webcontent and use these next time
# (or use that latest backups of each)
INSTALL=`read_arg -t install`

# Load the database as specified in the parameters at the top of this script.
if [[ "$DBTYPE" != "postgres" && "$DBTYPE" != "mysql" ]]; then
	fatal_error "You need to specify a dbtype of either \"postgres\" or \"mysql\" so I know which database I need to load!"
	exit 1
fi

# only load the database profile if the dbhost is instance...

if [[ "$DBHOST" == "$MYHOSTNAME" ]]; then
	# Only add the options which have been included at top of script...
	DBPROFILE="$DBTYPE"
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
else
	$logger "The database is located on $DBHOST, installing for tools and comamnds. "
	load_profile $DBTYPE
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

# Set some php parameters for Drupal...
sed -e 's/^memory_limit.*$/memory_limit = 250M/' -i /etc/php.ini
sed -e 's/^max_execution_time*$/max_execution_time = 120/' -i /etc/php.ini
sed -e 's/^post_max_size.*$/post_max_size = 20M/' -i /etc/php.ini
sed -e 's/^upload_max_filesize.*$/upload_max_filesize = 10M/' -i /etc/php.ini

# now lets do something really not simple, lets install drupal automatically from a drupal source file
# and set up the database config and add some default configs.
# we need to work out whether to install drupal.
if [[ ! -e "/var/www/html/drupal" ]]; then
        $logger "Drupal isn't installed at /var/www/html/drupal"
        if [[ "$INSTALL" != "" ]]; then
                $logger "Installing from $INSTALL"
                get_file -f $INSTALL
        else
                $logger "Installing the latest version from drupal.org..."
                cd /etc/bootstrap.d
		INSTALL=`curl -s http://drupal.org/project/drupal | grep "http://ftp.drupal.org/files/projects/drupal-[0-9.]*\.tar\.gz" | head -1 | sed -e 's/^[^"]*"//' | sed -e 's/".*$//'`
		if [[ "$INSTALL" != "" ]]; then
			$logger "Downloading latest version, $INSTALL..."
			SHORTDP=`basename $INSTALL`
			curl -s -o $SHORTDP $INSTALL
		else
			fatal_error "I couldn't work out the latest installer for Drupal!  Sorry, please download it yourself, place in your bootbucket and then use the \"install\" tag."
			exit 1
		fi
        fi

	INSTALL=`basename $INSTALL`
	if [[ -s "/etc/bootstrap.d/$INSTALL" ]]; then
		DRUPALDIR=${INSTALL%.tar.gz}
		cd /var/www/html
		tar xfpz /etc/bootstrap.d/$INSTALL
		chown -R root:root /var/www/html/$DRUPALDIR
		chown -R apache:apache /var/www/html/$DRUPALDIR/sites/all
		if [[ ! -e "/var/www/html/drupal" ]]; then
			ln -s /var/www/html/$DRUPALDIR /var/www/html/drupal
		fi

		if [[ "$DBNAME" != "" && "$DBUSER" != "" && $DBPASS != "" ]]; then
			cp /var/www/html/drupal/sites/default/default.settings.php /var/www/html/drupal/sites/default/settings.php
			chown apache:apache /var/www/html/drupal/sites/default/settings.php
			# Lets be nice and write all the database settings into the config file
			case "$DBTYPE" in 
				postgres)	DRIVER="pgsql"
						;;
				mysql)		DRIVER="mysql"
						;;
			esac
			sed -e "s/^\$databases = array();/\$databases = array (\n  'default' => array (\n    'default' => array (\n      'database' => '$DBNAME',\n      'username' => '$DBUSER',\n      'password' => '$DBPASS',\n      'host' => 'localhost',\n      'port' => '',\n      'driver' => '$DRIVER',\n      'prefix' => ''\n    )\n  )\n);/" -i /var/www/html/drupal/sites/default/settings.php
		fi

		# change the sites docroot to /var/www/html/drupal if configs were not loaded from a tar
		# and automatically add the rewrite for clean urls
		if [[ "$WEBCONFIGS" == "" ]]; then
			sed -e 's/^DocumentRoot.*$/DocumentRoot "\/var\/www\/html\/drupal"/' -i /etc/httpd/conf/httpd.conf
			$logger "Set DocumentRoot to /var/www/html/drupal in default httpd configs"
			cat >/etc/httpd/conf.d/clean-urls.conf <<EOT
RewriteEngine on

<Directory "/var/www/html/drupal">
   RewriteEngine on
   RewriteBase /
   RewriteCond %{REQUEST_FILENAME} !-f
   RewriteCond %{REQUEST_FILENAME} !-d
   RewriteRule ^(.*)\$ index.php?q=\$1 [L,QSA]
</Directory>
EOT
			$logger "Added clean URLs rewrite to default httpd configs"
			$logger "Disable mod_security.. this doesn't work by default yet."
			mv /etc/httpd/conf.d/mod_security.conf /etc/httpd/conf.d/mod_security.conf.disabled	
			service httpd restart
		fi
	
		#add the sites/default/files directory
		$logger "Creating /var/www/html/drupal/sites/default/files"
		mkdir -p /var/www/html/drupal/sites/default/files
		chown -R apache:apache /var/www/html/drupal/sites/default

		# Run the drupal site installer using curl to install the modules and software.
		# We do this because if you configure the database without running the installer
		# and then browse to the site you get a nasty error.  We also need the install to
		# have been done before we can setup the automatic cron.
		RESULT=""
		if [[ -f "/tmp/mysession.$$" ]]; then
			rm -f /tmp/mysession.$$
		fi
		# Repeatedly call the installer until it tells us that it has finished making sure we keep 
		# the same session by using the session cookies.
		$logger "Running the Drupal installer..."
		while [[ "$RESULT" == "" ]]
		do
			echo "Calling install script..."
			RESULT=`curl -s --fail --cookie /tmp/mysession.$$ -c /tmp/mysession.$$ --location "http://127.0.0.1/install.php?profile=standard&locale=en&id=1&op=do_nojs" | grep "id=\"progress\".*class=\"percentage\">100%<"`
		done
		if [[ -f "/tmp/mysession.$$" ]]; then
                	rm -f /tmp/mysession.$$
        	fi
		$logger "Drupal Installed"
	else
		fatal_error "I failed to download the installer!  Aborting!"
		exit 1
	fi
else
	$logger "Drupal is already installed at /var/www/html/drupal."
fi

# Optionally, mount an S3 bucket for drupal user content files... 
# make sure that the directory is empty or s3fs can't mount to it! Easist way it to delete and recreate...
if [[ "$DRUPALCONTENTMOUNT" != "" && "$DRUPALCONTENTBUCKET" != "" ]]; then
	S3FSMOUNTCOMMAND="-b $DRUPALCONTENTBUCKET -m $DRUPALCONTENTMOUNT"

	if [[ -d "$DRUPALCONTENTMOUNT" ]]; then
		rm -rf $DRUPALCONTENTMOUNT
	fi
	mkdir -p $DRUPALCONTENTMOUNT
	chown -R apache:apache $DRUPALCONTENTMOUNT

	if [[ "$DRUPALCONTENTCRED" != "" ]]; then
		# get the s3cfg file for our user-content bucket
		set_access -f $DRUPALCONTENTCRED -a drupal
		S3FSMOUNTCOMMAND="$S3FSMOUNTCOMMAND -a /root/.awssecret-drupal"
	fi

	# Mount the S3 user-content bucket
	$logger "Mounting S3 bucket for drupal content: mount_s3fs $S3FSMOUNTCOMMAND -u 48:48"
	mount_s3fs $S3FSMOUNTCOMMAND -u 48:48
	if [[ "$?" != "0" ]]; then
		fatal_error "I failed to mount the user-content! Aborting and shutting down the webserver!"
		service httpd stop
		exit 1
	fi
else
	$logger "No drupal S3 content mount requested."
fi
	
# Automatically set up Drupal's Crontab, for this we need to get the cron_key from database
if [[ "$DBNAME" != "" && "$DBUSER" != "" && "$DBPASS" != "" ]]; then
	if [[ "$DBTYPE" == "postgres" ]]; then
		$logger "Getting cron_key from postgres database $DBNAME"
		echo "*:*:$DBNAME:$DBUSER:$DBPASS" >/root/.pgpass
		chmod 600 /root/.pgpass
		# Now try and read the cron_key from the database
		CRONKEY=`psql -U $DBUSER -t -w --command "SELECT value FROM variable WHERE name = 'cron_key';" $DBNAME`
	else
		$logger "Getting cron_key from mysql database $DBNAME"
		CRONKEY=`mysql --database=$DBNAME --user=$DBUSER --password=$DBPASS -e "SELECT value FROM variable WHERE name = 'cron_key';"`
	fi
	if [[ "$?" == "0" ]]; then
		CRONKEY=`echo $CRONKEY | sed -e 's/"[^"]*$//' | sed -e 's/^[^"]*"//'`
		$logger "Found Drupal cron_key: $CRONKEY"
		echo "0 * * * * apache wget -O - -q -t 1 http://127.0.0.1/cron.php?cron_key=$CRONKEY" >>/etc/crontab
	else
		$logger "I can't read the cron_key from $DBNAME!"
	fi
	if [[ -f "/root/.pgpass" ]]; then
		rm -f /root/.pgpass
	fi
else
	$logger "I can't set up Drupal's cron without access to the drupal database, sorry!"
fi

$logger "Self contained drupal server now set up!"
if [[ "$INSTALL" != "" ]]; then
	MYEXTERNALNAME=`curl -s --fail http://169.254.169.254/latest/meta-data/public-hostname`
	$logger "Please browse to http://$MYEXTERNALNAME/install.php?profile=standard&locale=en to finish configuring your new drupal website."
fi
