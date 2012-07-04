#!/bin/bash -f

# profile-webserver.sh
# Dave McCormick
PROFILE_VERSION="2.10"
PROFILE_URL="http://www.practicalclouds.com/content/guide/apache-webserver"
PROFILE_DOWNLOAD="http://files001.practicalclouds.com/profile-apache.sh"
MINIMUM_BOOTSTRAP_FUNCTIONS="2.0"

# please refer to the instructions on using this profile script at
# http://www.practicalclouds.com/content/guide/apache-webserver

# 1.0 -  initial, install httpd and download of configs
# 1.1 -  better download of configs using tags, also allow download 
#        of html data from file or S3 copy using load_data function
# 1.2 -  added mount of ebs volume for the web content if required.
# 1.3 -  the webconfigs file deploy is now expected to include
#        everything below /etc/httpd and not just conf and conf.d
# 1.4 -  Support bootstrap-functions v1.11 with command line style args
# 1.5 -  allow us to download and install a php.ini file.
# 1.6 -  add optional automatic backups of configs and content to an archive
#        uploaded to S3
# 1.7 -  For backups - use the credentials in this order: backup, webserver,
#        root.
# 1.8 -  Enable apc upload progress by default.
# 1.9 -  Name the backups after the configs and contents archives used 
#        to load the data.
#        Added s3webbucket option for mounting the web content from an S3 bucket.
# 1.10 - Only install php if the withphp tag has been set
#        Automatically enable apc.rfc1867 with php.
# 1.11 - Add mysql support into php by default
# 1.12 - Correct content load error message
# 1.13 - Remove the previous archive extensions when creating new backups
# 1.14 - Rename to profile "apache"
# 1.15 - Enable version checking and use fatal_error function.
# 1.16 - Do not re-append the platform as a prefix if it is already there.
#        Remove any existing time/date stamp from backup file names.
# 1.17 - Download backup2s3 from website if not in bootbucket.
# 1.18 - Enable compression by default.
# 2.0  - Convert to use the version 2.0 format functions.
#	 Turn on KeepAlive, improve caching and Etags for performance.
# 2.1  - Install php-xml by default so we can use dom
# 2.2. - Fix issue where s3fs mount and backups try to use an .s3cfg file instead of .awssecret.
# 2.3  - Another s3sf fix, /root/.awssecret, not /etc/bootstrap.d/.awssecret
# 2.4  - Remove caching of php by default - it does not work well with Joomla
#        Update compression to use smart filters.
# 2.5  - Change location where backup script is sourced from.
# 2.6  - Update default cacheing to include Expires headers as well as Cache-Control.
# 2.7  - Add "devel" option for installing headers and development files.
# 2.8  - Add "nostart" option to not start up apache once installed.
# 2.9  - Add extra information about choice of backups files.
# 2.10 - Turn off 'globbing' so that the backup schedule works properly
#      - Add instance name to the default backup file names,

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

# load the bootstrap-functions
if [ -s "/etc/bootstrap.d/bootstrap-functions2" ]; then
        . /etc/bootstrap.d/bootstrap-functions2
else
        $logger "I couldn't load the bootstrap-fuctions2, aborting!"
        exit 1
fi

# Install Apache

INSTALL_PACKS="httpd mod_ssl mod_security"
DEVEL=`read_arg -n devel`
if [[ "$DEVEL" == "true" ]]; then
	INSTALL_PACKS="${INSTALL_PACKS} httpd-devel"
fi

$logger "Installing apache httpd server."
yum -y install ${INSTALL_PACKS} || { fatal_error "I failed to install apache!"; exit 1; }
/sbin/chkconfig httpd on

WITHPHP=`read_arg -n withphp`
if [[ "$WITHPHP" != "" ]]; then
	# Install PHP

	$logger "Installing PHP."
	yum -y install php php-pdo php-pecl-apc php-xml php-domxml-php4-php5 php-gd php-mbstring php-pgsql php-mysql || { fatal_error "I failed to install php!"; exit 1; }
	# Enable apc upload progress
	sed -e 's/apc.rfc1867=0/apc.rfc1867=1/' -i /etc/php.d/apc.ini

	PHPINI=`read_arg -n phpini`
	if [[ "$PHPINI" != "" ]]; then
        	get_file -f $PHPINI
        	PHPFILE=`basename $PHPINI`
        	if [[ -s /etc/bootstrap.d/$PHPFILE ]]; then
                	cp /etc/bootstrap.d/$PHPFILE /etc/php.ini
                	$logger "New /etc/php.ini file has been installed."
        	fi
	fi
fi

MYBOOTBUCKET=`cat /etc/AWS-BOOTBUCKET`
MYPLATFORM=`cat /etc/AWS-PLATFORM`
#GOTCONFIGS="no"
#GOTHTMLDATA="no"

# optionally add additional IAM user credentials for accessing EC2 or S3
APACHEACCESS=`read_arg -n webcredentials`
if [[ "$APACHEACCESS" != "" ]]; then
        set_access -f $APACHEACCESS -a webserver
fi

# get apache configs
# 1. from a arg webconfigs - fail if arg set but file not found
# 2. if there is a platform set then try ${MYPLATFORM}-webserver-configs.tar.gz
#    continue to 3 if not found
# 3. look for a generic webserver-configs.tar.gz file.

CONFIGSFILE=`read_arg -n webconfigs`
echo "configsfile=\"$CONFIGSFILE\""
if [[ "$CONFIGSFILE" != "" ]]; then
	rm -rf /etc/httpd
	load_data -s $CONFIGSFILE -d /etc/httpd
	if [[ "$?" != "0" ]]; then
		fatal_error "I couldn't download the specified webserver configs file!"
		exit 1
	fi		 
else
	$logger "No webserver configs were specified, I'm a default install!"
	$logger "Enabling Compression."
	cat >/etc/httpd/conf.d/compress.conf <<EOT
# Load the filter module
<IfModule !mod_filter.so>
  LoadModule filter_module modules/mod_filter.so
</IfModule>

SetEnv filter-errordocs true
FilterDeclare comp-resp
# Compress everything except for images, audio and video
FilterProvider comp-resp DEFLATE resp=Content-Type !/^(image|audio|video)//
FilterProtocol comp-resp change=yes
FilterChain comp-resp
EOT
	$logger "Enabling KeepAlive by Default"
	sed -e 's/^KeepAlive Off$/KeepAlive On/' -i /etc/httpd/conf/httpd.conf
	$logger "Enabling Caching of Javascript, css and Fonts by default..."
	if [ -d "/data" ]; then
		mkdir -p /data/apache/cache
		chown apache:apache /data/apache/cache
		CACHE="/data/apache/cache"
	else
		mkdir -p /var/www/cache
		chown apache:apache /var/www/cache
		CACHE="/var/www/cache"
	fi
	cat >/etc/httpd/conf.d/cache.conf <<EOT
# Default practicalclouds caching options...

# cache static content in local disk cache for performance..
<IfModule !cache_module>
        LoadModule cache_module modules/mod_cache.so
</IfModule> 
<IfModule cache_module>
	<IfModule !disk_cache_module>
        	LoadModule disk_cache_module modules/mod_disk_cache.so
        </IfModule>
        CacheRoot $CACHE
        CacheEnable disk /
        CacheDirLevels 5
        CacheDirLength 3
	CacheIgnoreHeaders Set-Cookie
	CacheIgnoreQueryString On
	CacheLock on
	CacheLockPath /tmp/mod_cache-lock
	CacheLockMaxAge 5
</IfModule> 

# some resonable default caching rules based on filetypes..

# Cache CSS and JavaScript for 1 day.
<FilesMatch "\.(js|JS|css|CSS)$">
        Header set Cache-Control "max-age=86400, private, must-revalidate"
</FilesMatch>

# Cache these files for a day...
<FilesMatch "\.(pdf|PDF|swf|SWF|txt|TXT|sh|SH|ksh|KSH|pp|PP|rb|RB|pl|PL)$">
        Header set Cache-Control "max-age=86400, public"
        ExpiresActive On
        ExpiresDefault "access plus 1 day"
</FilesMatch>

# Cache icons and shockwave flash for 1 month.
<FilesMatch "\.(flv|FLV|ico|ICO)$">
	Header set Cache-Control "max-age=2678400, public"
        ExpiresActive On
        ExpiresDefault "access plus 1 month"
</FilesMatch>

# Cache images for a month...
<FilesMatch "\.(jpg|JPG|jpeg|JPEG|png|PNG|gif|GIF|svg|SVG)$">
	Header set Cache-Control "max-age=2678400, public"
        ExpiresActive On
        ExpiresDefault "access plus 1 month"
</FilesMatch>

# Cache fonts for a month
<FilesMatch "\.(eot|EOT|woff|WOFF|ttf|TTF|otf|OTF)$">
	Header set Cache-Control "max-age=2678400, public"
        ExpiresActive On
        ExpiresDefault "access plus 1 month"
</FilesMatch>

# Use a simple ETag without inode in it
FileETag MTime Size
EOT

fi

# If we have a webvol arg then mount the ebs volume to /var/www
WEBVOL=`read_arg -n webvol`
if [[ "$WEBVOL" != "" ]]; then
	$logger "Mounting ebs webcontent volume $WEBVOL"
	mount_ebsvol -n $WEBVOL -m /var/www
	if [[ "$?" != "0" ]]; then
		fatal_error "I couldn't attach my web data volume, $WEBVOL - aborting...!"
		exit 1
	fi
else
	$logger "We have not been requested to mount an EBS volume for the webcontent"
fi
	
# If we can mount the web content from S3, if requested.
WEBSBKT=`read_arg -n s3webbucket`
if [[ "$WEBSBKT" != "" ]]; then
	$logger "Mounting an S3 bucket for webcontent $WEBSBKT"
	if [[ -f "/root/.awssecret-webserver" ]]; then
		mount_s3fs -b $WEBSBKT -m /var/www -a /root/.awssecret-webserver -u 49:49
	else
		mount_s3fs -b $WEBSBKT -m /var/www -u 49:49
	fi
	if [[ "$?" != "0" ]]; then
		fatal_error "I couldn't attach my web data bucket, $WEBSBKT - aborting...!"
		exit 1
	fi
else
	$logger "We have not been requested to mount an S3 bucket for the webcontent"
fi
	
# get html data
# This can either be a tar/gzip file as with the configs or it can simply be an s3 directory tree
# note: if this is not supplied via an arg then we will not search everywhere for it like we 
WEBCONTENT=`read_arg -n webcontent`
if [[ "$WEBCONTENT" != "" ]]; then
        rm -rf /var/www
        load_data -s $WEBCONTENT -d /var/www
        if [[ "$?" != "0" ]]; then
                fatal_error "I couldn't download the specified webserver content file!"
        #        exit 1
        fi
else
	$logger "No webserver content was specified, leaving the default files!"
fi

BACKUPS=`read_arg -n webbackup`
if [[ "$BACKUPS" == "true" ]]; then
	$logger "Webserver backups requested"

	INSTANCENAME=`cat /etc/AWS-NAME`
	DEST=`read_arg -n webbackups3path` 
	if [[ "$DEST" == "" ]]; then
		$logger "I need the webbackups3path arg in order to know where to make automatic backups of the webserver!"
	else
		KEEP=`read_arg -n webbackupkeep`
		if [[ "$KEEP" == "" ]]; then
			KEEP="7"
		fi
		SCHEDULE=`read_arg -n webbackupschedule`
		if [[ "$SCHEDULE" == "" ]]; then
			SCHEDULE="0 2 * * *"
		fi

		# make sure we have the generic backup script backup2s3.sh
		get_file -f backup2s3.sh -d /usr/local/bin
		if [[ ! -s "/usr/local/bin/backup2s3.sh" ]]; then
                	curl -s -o /usr/local/bin/backup2s3.sh http://files001.practicalclouds.com/backup2s3.sh
                fi
		if [[ -s "/usr/local/bin/backup2s3.sh" ]]; then
			chmod +x /usr/local/bin/backup2s3.sh

			# Set access for the backup user (if possible)
			set_access -f backup-user-credentials -a backup

			if [[ -s "/root/.awssecret-backup" ]]; then
				SCFG="-c /root/.awssecret-backup"
			else
				if [[ -s "/root/.awssecret-webserver" ]]; then
					SCFG="-c /root/.awssecret-webserver"
				else
					SCFG=""
				fi
			fi
			
			if [[ "$MYPLATFORM" != "" ]]; then
				
				PREFIX="$MYPLATFORM-"
			else
				PREFIX=""
			fi

			if [[ "$CONFIGSFILE" != "" && "$WEBCONTENT" != "" ]]; then
				# remove any archive extentions and any previous time/date stamps.
				CONFIGSFILE=`echo $CONFIGSFILE | sed -e 's/\.t[ar.]*[gb]z[2]*$//'`
				if [[ "$CONFIGSFILE" =~ _[0-9-_]* ]]; then
					CONFIGSFILE=${CONFIGSFILE%%_[0-9-_]*}
				fi
				$logger "Configs backup file is : $CONFIGSFILE"
				WEBCONTENT=`echo $WEBCONTENT | sed -e 's/\.t[ar.]*[gb]z[2]*$//'`
				if [[ "$WEBCONTENT" =~ _[0-9-_]* ]]; then
					WEBCONTENT=${WEBCONTENT%%_[0-9-_]*}
				fi
				$logger "Content backup file is : $WEBCONTENT"
				if [[ ! "$CONFIGSFILE" =~ ^${PREFIX} ]]; then
					echo "$SCHEDULE /usr/local/bin/backup2s3.sh -f ${PREFIX}${CONFIGSFILE} -p /etc/httpd  -d $DEST -k $KEEP $SCFG" >>/var/spool/cron/root
				else
					echo "$SCHEDULE /usr/local/bin/backup2s3.sh -f ${CONFIGSFILE} -p /etc/httpd  -d $DEST -k $KEEP $SCFG" >>/var/spool/cron/root
				fi
				if [[ ! "$WEBCONTENT" =~ ^${PREFIX} ]]; then
					echo "$SCHEDULE /usr/local/bin/backup2s3.sh -f ${PREFIX}${WEBCONTENT} -p /var/www  -d $DEST -k $KEEP $SCFG" >>/var/spool/cron/root
				else
					echo "$SCHEDULE /usr/local/bin/backup2s3.sh -f ${WEBCONTENT} -p /var/www  -d $DEST -k $KEEP $SCFG" >>/var/spool/cron/root
				fi
			else
				echo "$SCHEDULE /usr/local/bin/backup2s3.sh -f ${PREFIX}${INSTANCENAME}-webserver-configs -p /etc/httpd  -d $DEST -k $KEEP $SCFG" >>/var/spool/cron/root
				echo "$SCHEDULE /usr/local/bin/backup2s3.sh -f ${PREFIX}${INSTANCENAME}-webserver-content -p /var/www  -d $DEST -k $KEEP $SCFG" >>/var/spool/cron/root
			fi
			$logger "Added automatic backups of webserver to cron"
		else 
			$logger "I could not find the backup script backup2s3.sh so I can't enable automatic backups!"
		fi
	fi
else
	$logger "Automatic backups of webserver have not been requested."
fi
	
NOSTART=`read_arg -n nostart`
if [[ "$NOSTART" == "true" ]]; then
	$logger "Skipping apache start up (requested by nostart argument)."
else
	#start the webserver
	service httpd start
	$logger "Started the httpd service."
fi

