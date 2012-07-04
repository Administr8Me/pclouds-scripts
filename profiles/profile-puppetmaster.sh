#!/bin/bash -f

# profile-drupal.sh
# Dave McCormick
PROFILE_VERSION="1.20"
PROFILE_URL="http://www.practicalclouds.com/content/guide/puppet-deployment"
PROFILE_DOWNLOAD="http://files001.practicalclouds.com/profile-puppet.sh"
MINIMUM_BOOTSTRAP_FUNCTIONS="2.0"

# please refer to the instructions on using this profile script at
# http://www.practicalclouds.com/content/guide/puppet-deployment

# 1.0  - initial, load puppet client or as puppet master, if requested.
#	 Install via rubygems so that we get the lastest available versions.
# 1.1  - Add options for apache and passenger
# 1.2  - More configuration changes to enable apache/passenger
# 1.3  - Update Apache install to include optional arguments.  Add MySQL.
#        Add puppetvol ebs volume for /etc/puppet (we really should do this to
#        keep generated certs etc).
# 1.4  - More work to store configs in mysql and play nice with rails3.
# 1.5  - Redesign - make use of the puppet labs yum repository and less use
#        of ruby gem installs.  Minimize the number of calls to yum and 
#        gem install by collating lists to install.
# 1.6  - Optionally install and configure the puppet dashboard, add server argument
# 1.7  - more work on the dashboard, also configure the agent and start it.
# 1.8  - Add optional installation of MCollective
#      - Allow user to change puppetmaster port and dashboard port
#      - If no server is specifed and is a master use amazon internal hostname
#        not the boxes hostname which will be localhost.localdomain.
#      - Add instructions on the options required for any clients at the
#        end of a puppet master install.
# 1.9  - Add a simple username and password to the dashboard
# 1.10 - Install dashboard and mcollective default, replace args with 
#        'nodashboard' and 'nomcollective'.
# 1.11 - Turn on autosign for our puppetmaster, allow people to switch
#        it off with 'noautosign'.
# 1.12 - Don't auto-generate the /etc/puppet/puppet.conf, let it use the defaults, they
#        are better. E.g. ssl ca should be in /var/lib/puppet, not /etc/puppet.
# 1.13 - Continue to install the client even if a server has not been specified.
#        Add libffi-devel for build of Ruby gems.
#        Handle the backing up of /etc/puppet and /var/lib/puppet.
# 1.14 - Prevent globbing of the backup schedule by -f at top of script.
#        Allow the database to be on another host by specifying dbhost=
# 1.15 - Change dashboard.conf so that we allow the IP address of the 
#        server instead of the hostname (reverse will not be set up)
# 1.16 - Set the puppetserver to the fqdn regardless whether it is 
#        resolvable in dns or not.
# 1.17 - Allow access to dashboard to ::1 ipv6
# 1.18 - Change puppetvol to puppetetcvol and puppetvarvol so we can store all the
#        puppet data on persistent storage if we desire.
# 1.19 - Add cases for CentOS install instead of Fedora
# 1.20 - Attempted fix for empty hostname on CentOS.

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

# Add a function for generating a random password.
# used to create a random database password if none supplied.
function randpass
{
        echo `</dev/urandom tr -dc A-Za-z0-9 | head -c16`
}

$logger "******************************************"
$logger "     Welcome to the Puppet Installer"
$logger "******************************************"

NAME=""
DOMAIN=""
MYPLATFORM=`cat /etc/AWS-PLATFORM`

# Read in the Name and domain argument
# If we have a domain then we'll use that for 
# auto-signing certs.
NAME=`read_arg -n Name`
DOMAIN=`read_arg -n domain`

# Workout the shortname and possibly domain from Name
if [[ "$NAME" =~ \. ]]; then
        SHORTNAME=${NAME%%.*}
	[[ "$DOMAIN" == "" ]] && DOMAIN=${NAME#*.}
else
	SHORTNAME="$NAME"
fi

# Are we a puppetmaster?
MASTER="true"

# Read in the server argument - this will be the servername for the master
# and clients will be configured to connect to it.
PUPPETSERVER=`read_arg -n puppetserver`
if [[ "$PUPPETSERVER" == "" ]]; then
	if [[ "$MASTER" == "true" ]]; then
		PUPPETSERVER=`hostname -f`
		while [[ "$PUPPETSERVER" == "" ]]; do
			$logger "Could not get a hostname, sleeping 10 seconds and trying again..."
			sleep 10
			PUPPETSERVER=`hostname -f`
		done
                $logger "Setting the puppet server to '$PUPPETSERVER' as no 'puppetserver' argument was provided and this is a puppetmaster."
	else
		PUPPETSERVER="puppet"
                $logger "Setting the puppet server to 'puppet' as no 'puppetserver' argument was provided."
	fi
fi

# Allow for a non-standard port to selected
PUPPETPORT=`read_arg -n puppetport`
if [[ "$PUPPETPORT" == "" ]]; then
	$logger "Setting puppet master port to default: 8140"
	PUPPETPORT="8140"	
fi

# Read in the mcollective arguments.  These tell us to add the mcollective
# software to our instance
NOMCOLLECTIVE=`read_arg -n nomcollective`
if [[ "$NOMCOLLECTIVE" != "true" ]]; then
	STOMPSERVER=`read_arg -n stomphost`
	if [[ "$STOMPSERVER" == "" ]]; then
		$logger "Setting Stomp host to the puppetmaster: $PUPPETSERVER"
		STOMPSERVER="$PUPPETSERVER"
	fi
	STOMPPORT=`read_arg -n stompport`
	if [[ "$STOMPPORT" == "" ]]; then
		$logger "Setting Stomp port to default: 61613"
		STOMPPORT=61613
	fi
	STOMPUSER=`read_arg -n stompuser`
	if [[ "$STOMPUSER" == "" ]]; then
		$logger "Setting Stomp user to default: mcollective"
		STOMPUSER="mcollective"
	fi
	STOMPPASS=`read_arg -n stomppass`
	if [[ "$STOMPPASS" == "" ]]; then
		if [[ "$MASTER" == "true" ]]; then
			STOMPPASS=`randpass`
			$logger "Warning: Randomly generated stomp password : $STOMPPASS"
		else
			$logger "Sorry, I can't install MCollective without a valid 'stomppassword' unless the instance is a puppetmaster."
			NOMCOLLECTIVE="true"
		fi
	fi
	STOMPPSK=`read_arg -n stomppsk`
	if [[ "$STOMPPSK" == "" ]]; then
		if [[ "$MASTER" == "true" ]]; then
			STOMPPSK=`randpass`
			$logger "Warning: Randomly generated stomppsk : $STOMPPSK"
		else
			$logger "Sorry, I can't install MCollective without a valid 'stomppsk' unless the instance is a puppetmaster."
			NOMCOLLECTIVE="true"
		fi
	fi
fi

# Mount an EBS volume or load puppet configs from an archive
PUPETCVOL=`read_arg -n puppetetcvol`
PUPVARVOL=`read_arg -n puppetvarvol`
PUPPETCONFIG=`read_arg -n puppetconfig`
PUPPETDATA=`read_arg -n puppetdata`

# Read in more arguments if we are a puppetmaster.
if [[ "$MASTER" == "true" ]]; then
	# Read in the dashboard settings
	NODASHBOARD=`read_arg -n nodashboard`
	if [[ "$NODASHBOARD" != "true" ]]; then
        	DASHPORT=`read_arg -n dashport`
        	if [[ "$DASHPORT" == "" ]]; then
                	$logger "Installing Puppet Dashboard on detault port : 3000"
                	DASHPORT="3000"
        	fi
        	DASHUSER=`read_arg -n dashuser`
        	if [[ "$DASHUSER" == "" ]]; then
                	$logger "Setting Puppet Dashboard to default : admin"
                	DASHUSER="admin"
        	fi
        	DASHPASS=`read_arg -n dashpass`
        	if [[ "$DASHPASS" == "" ]]; then
                	DASHPASS=`randpass`
                	$logger "Generating random password for $DASHUSER  : $DASHPASS"
        	fi
	fi

	# Allow people to choose not to enable autosign - which we will enable by default
	NOAUTOSIGN=`read_arg -n noautosign`
	AUTOSIGNDOMAIN=`read_arg -n autosigndomain`

        # BACKUPS - pass these options to both Apache and MySQL profiles.
        BACKUPPATH=`read_arg -n backuppath`
        BACKUPSCHEDULE=`read_arg -n backupschedule`
	[[ "$BACKUPSCHEDULE" == "" ]] && BACKUPSCHEDULE="0 2 * * *"
	$logger "The backup schedule is : $BACKUPSCHEDULE"
        BACKUPCREDENTIALS=`read_arg -n backupcredentials`
        KEEPBACKUPS=`read_arg -n keepbackups`
	[[ "$KEEPBACKUPS" == "" ]] && KEEPBACKUPS="7"

        # We need Apache for scalability, allow all apache arguments
        WEBVOL=`read_arg -n webvol`
        S3WEBBUCKET=`read_arg -n s3webbucket`
        WEBCREDENTIALS=`read_arg -n webcredentials`
        WEBCONFIGS=`read_arg -n webconfigs`
        WEBCONTENT=`read_arg -n webcontent`
        WITHPHP=`read_arg -n withphp`
        PHPINI=`read_arg -n phpini`

	DBHOST=`read_arg -n dbhost`
	[[ "$DBHOST" == "" ]] && DBHOST="localhost.localdomain"
        DBVOL=`read_arg -n dbvol`
        DBNAME=`read_arg -n dbname`
        if [[ "$DBNAME" == "" ]]; then
                $logger "Using the default drupal database name, puppetdb"
                DBNAME="puppetdb"
        fi
        DBUSER=`read_arg -n dbuser`
        if [[ "$DBUSER" == "" ]]; then
                $logger "Using the default database user, puppet"
                DBUSER="puppet"
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

	$logger "Loading required profiles..."

        # load apache and configure passenger for scalability
	$logger "Installing Apache for scalability with Phusion Passenger"
        WEBPROFILE="apache nostart"
        [[ "$WEBVOL" != "" ]] && WEBPROFILE="$WEBPROFILE webvol=$WEBVOL"
        [[ "$S3WEBBUCKET" != "" ]] && WEBPROFILE="$WEBPROFILE s3webbucket=$S3WEBBUCKET"
        [[ "$WEBCREDENTIALS" != "" ]] && WEBPROFILE="$WEBPROFILE webcredentials=$WEBCREDENTIALS"
        [[ "$WEBCONFIGS" != "" ]] && WEBPROFILE="$WEBPROFILE webconfigs=$WEBCONFIGS"
        [[ "$WEBCONTENT" != "" ]] && WEBPROFILE="$WEBPROFILE webcontent=$WEBCONTENT"
        [[ "$WITHPHP" != "" ]] && WEBPROFILE="$WEBPROFILE withphp"
        [[ "$PHPINI" != "" ]] && WEBPROFILE="$WEBPROFILE phpini=$PHPINI"
        [[ "$BACKUPPATH" != "" ]] && WEBPROFILE="$WEBPROFILE webbackup webbackups3path=$BACKUPPATH"
        [[ "$BACKUPSCHEDULE" != "" ]] && WEBPROFILE="$WEBPROFILE webbackupschedule=\"$BACKUPSCHEDULE\""
        [[ "$KEEPBACKUPS" != "" ]] && WEBPROFILE="$WEBPROFILE webbackupkeep=$KEEPBACKUPS"

        load_profile $WEBPROFILE
        if [[ "$?" != "0" ]]; then
                fatal_error "The webserver couldn't be loaded!  Please fix the issue and then start this profile again."
                exit 1
        fi

        # disable mod_security
        if [ -f "/etc/httpd/conf.d/mod_security.conf" ]; then
                mv /etc/httpd/conf.d/mod_security.conf /etc/httpd/conf.d/mod_security.conf.disabled
        fi

	# We need a database for exported resources and integration with the puppet
        # console application.  Installing MYSQL for this purpose.
        $logger "Installing MySQL for exported and stored configurations..."

	if [[ "$DBHOST" == "localhost.localdomain" ]]; then
        	DBPROFILE="mysql devel" 
        	[[ "$DBVOL" != "" ]] && DBPROFILE="$DBPROFILE dbvol=$DBVOL"
        	[[ "$DBUSER" != "" ]] && DBPROFILE="$DBPROFILE dbuser=$DBUSER"
        	[[ "$DBPASS" != "" ]] && DBPROFILE="$DBPROFILE dbpass=$DBPASS"
        	[[ "$DBNAME" != "" ]] && DBPROFILE="$DBPROFILE dbname=$DBNAME"
        	[[ "$IMPORTFILE" != "" ]] && DBPROFILE="$DBPROFILE importfile=$IMPORTFILE"
        	[[ "$BACKUPPATH" != "" ]] && DBPROFILE="$DBPROFILE dbbackup dbbackups3path=$BACKUPPATH"
        	[[ "$BACKUPSCHEDULE" != "" ]] && DBPROFILE="$DBPROFILE dbbackupschedule=\"$BACKUPSCHEDULE\""
        	[[ "$BACKUPCREDENTIALS" != "" ]] && DBPROFILE="$DBPROFILE dbbackupcredentials=$BACKUPCREDENTIALS"
        	[[ "$KEEPBACKUPS" != "" ]] && DBPROFILE="$DBPROFILE dbbackupkeep=$KEEPBACKUPS"

        	#load the database profile
        	load_profile $DBPROFILE
        	if [[ "$?" != "0" ]]; then
                	fatal_error "The database could't be loaded!  Please fix the issue and then start this profile again."
                	exit 1
        	fi
	else
		$logger "The database is not located on this instance."
	fi
fi

# Collect information about ourselves
OSTYPE=`cat /etc/redhat-release | awk '{print $1}'`
OSNAME=`echo $OSTYPE | tr [A-Z] [a-z]`
OSRELEASE=`rpm -qi $OSNAME-release | grep "^Version" | awk '{print $3}'`
ARCH=`uname -i`

$logger "******************************************"
$logger "   The ACTUAL Puppet Software Install!"
$logger "******************************************"

# both client and puppet master will need the puppet labs repositories.
$logger "Adding Puppet Labs Repository..."
rpm --import http://yum.puppetlabs.com/RPM-GPG-KEY-puppetlabs
case $OSTYPE in
	Fedora) yum -y install http://yum.puppetlabs.com/fedora/f${OSRELEASE}/products/${ARCH}/puppetlabs-release-${OSRELEASE}-1.noarch.rpm
		;;
	CentOS) yum -y install http://yum.puppetlabs.com/el/${OSRELEASE}/products/${ARCH}/puppetlabs-release-${OSRELEASE}-1.noarch.rpm 	
		;;
esac
	
$logger "Working out which packages to install..."

# Start with the client packages..."
$logger "Adding default Ruby, Puppet and Facter packages."
YUMPACKAGES="ruby ruby-rdoc ruby-ri ruby-libs ruby-shadow rubygems rubygem-rake rubygem-diff-lcs facter puppet"
GEMS=""

# Update the list of packages with those needed for a puppetmaster
if [[ "$MASTER" == "true" ]]; then
        # add phusion passenger yum repository
        $logger "Adding Puppetmaster packages."
        rpm --import http://passenger.stealthymonkeys.com/RPM-GPG-KEY-stealthymonkeys.asc
	case $OSTYPE in
		Fedora) yum -y install http://passenger.stealthymonkeys.com/fedora/${OSRELEASE}/passenger-release.noarch.rpm
			;;
		CentOS) yum -y install http://passenger.stealthymonkeys.com/rhel/${OSRELEASE}/passenger-release.noarch.rpm 	
			$logger "Adding Fedora EPEL Repository..."
			case ${OSRELEASE} in
				6) yum -y install http://dl.fedoraproject.org/pub/epel/6/${ARCH}/epel-release-6-5.noarch.rpm 
					;;
				5) yum -y install http://dl.fedoraproject.org/pub/epel/5/${ARCH}/epel-release-5-4.noarch.rpm 
					;;
			esac
			;;
	esac

	YUMPACKAGES="$YUMPACKAGES ruby-devel libffi-devel rubygem-rails rubygem-activerecord libxml2 libxml2-devel libxslt libxslt-devel libxslt libxslt-devel gcc make mod_passenger ruby-mysql puppet-server"
	if [[ "$NODASHBOARD" != "true" ]]; then
		$logger "Adding Puppet Dashboard packages"
		YUMPACKAGES="$YUMPACKAGES puppet-dashboard"
	fi
	$logger "Adding AWS Ruby SDK and Puppet Module Ruby gems."
	GEMS="aws-sdk puppet-module fog guid"
	
	# we need to install active MQ if the server is a puppet master
	# and an alternative stompserver has not been requested.
	if [[ "$NOMCOLLECTIVE" != "true" ]]; then
		$logger "Adding MCollective Client (only available on the puppetmaster)..."
		YUMPACKAGES="$YUMPACKAGES mcollective-client"
		# Also add active MQ, unless another stomp server has been specified
		# This would allow you to connect to a seperate ActiveMQ server if you wish.
		# By default, the puppetmaster will also host the activemq broker.
 		if [[ "$STOMPSERVER" == "$PUPPETSERVER" ]]; then
			$logger "Adding ActiveMQ package."
			YUMPACKAGES="$YUMPACKAGES activemq"
		else
			$logger "\"$STOMPSERVER\" is not the same as \"$PUPPETSERVER\" so not installing ActiveMQ!"
		fi
	fi
fi

# Add additional packages for mcollective
if [[ "$NOMCOLLECTIVE" != "true" ]]; then
	$logger "Adding MCollective Agent Package."
	YUMPACKAGES="$YUMPACKAGES mcollective"
	# net-ping and sys-proctable are for mcollective plugins.
	GEMS="$GEMS stomp net-ping sys-proctable"
fi

$logger "Installing all required packages - this will take some time for a puppetmaster! ..."
yum -y install $YUMPACKAGES 2>&1 | tee -a /var/log/messages
if [[ "$?" != "0" ]]; then
	fatal_error "Sorry! I couldn't install all of the rpms, see syslog for details."
	exit 1
fi
$logger "RPM Packages installed - ok"
if [[ "$GEMS" != "" ]]; then
	$logger "Installing required Ruby Gems..."
	gem install --no-rdoc --no-ri $GEMS 2>&1 | tee -a /var/log/messages
	if [[ "$?" != "0" ]]; then
		fatal_error "Sorry! I couldn't install all of the Ruby GEMS, see syslog for details."
		exit 1
	fi
fi
$logger "Ruby GEMS installed - ok"

# Now lets do some configuration
# Allow the puppet config to be stored on an ebs volume
if [[ "$PUPETCVOL" != "" ]]; then
	$logger "Mounting ebs database volume $PUPETCVOL"
        mount_ebsvol -n $PUPETCVOL -m /etc/puppet
	if [[ "$?" != "0" ]]; then
        	fatal_error "Could not mount $PUPETCVOL, so aborting rest of puppet bootstrap!"
                exit 1
        fi
fi

# allow storage of puppet data on an ebs vol too...
if [[ "$PUPVARVOL" != "" ]]; then
        $logger "Mounting ebs database volume $PUPVARVOL"
        mount_ebsvol -n $PUPVARVOL -m /var/lib/puppet
        if [[ "$?" != "0" ]]; then
                fatal_error "Could not mount $PUPVARVOL, so aborting rest of puppet bootstrap!"
                exit 1
        fi
fi

if [[ "$PUPPETCONFIG" == "" ]]; then
	$logger "Creating a default puppet config"
	#puppetmasterd --genconfig >/etc/puppet/puppet.conf
	echo "[master]" >/etc/puppet/puppet.conf
	if [[ "$PUPPETSERVER" != "" ]]; then
		$logger "This puppet agent will connect to server: $PUPPETSERVER"
		echo "    server = $PUPPETSERVER" >>/etc/puppet/puppet.conf
	else
		$logger "This puppet agent will connect to the default puppet server."
	fi
	echo "    puppetport = $PUPPETPORT" >>/etc/puppet/puppet.conf
else
	load_data -s $PUPPETCONFIG -d /etc/puppet
fi

if [[ "$PUPPETDATA" != "" ]]; then
	$logger "Loading /var/lib/puppet from $PUPPETDATA..."
	load_data -s $PUPPETDATA -d /var/lib/puppet
fi

# Configure the puppet master, if requested.

if [[ "$MASTER" == "true" ]]; then
	$logger "******************************************"
	$logger "       Configuring Puppet Master"
	$logger "******************************************"

	$logger "Puppet Master Configuration: - "

	if [[ "$PUPPETCONFIG" == "" ]]; then
        	$logger "Creating a default puppet config"
        	#puppetmasterd --genconfig >/etc/puppet/puppet.conf

	        # correct some of the dumb non-default values
        	#sed -e 's/^\s*pluginsource\s*=.*$/pluginsource = puppet:\/\/\$server\/plugins/' -i /etc/puppet/puppet.conf
        	#sed -e 's/^\s*reportserver\s*=.*$/reportserver = \$server/' -i /etc/puppet/puppet.conf
        	#sed -e 's/^\s*report_server\s*=.*$/report_server = \$server/' -i /etc/puppet/puppet.conf
        	#sed -e 's/^\s*inventory_server\s*=.*$/inventory_server = \$server/' -i /etc/puppet/puppet.conf
        	#sed -e 's/^\s*ca_server\s*=.*$/ca_server = \$server/' -i /etc/puppet/puppet.conf
		#sed -e 's/^\s*pidfile\s*=.*/pidfile = \/var\/run\/puppet\/agent.pid/' -i /etc/puppet/puppet.conf

        	if [[ "$PUPPETSERVER" != "" ]]; then
                	$logger "This puppet agent will connect to server: $PUPPETSERVER"
                	echo "    server = $PUPPETSERVER" >>/etc/puppet/puppet.conf
        	else
                	$logger "This puppet agent will connect to the default puppet server."
        	fi
        	echo "    puppetport = $PUPPETPORT" >>/etc/puppet/puppet.conf

                echo "    pluginsync = true" >>/etc/puppet/puppet.conf
                echo "    pluginsource = puppet://\$server/plugins/" >>/etc/puppet/puppet.conf
                echo "    reportserver = \$server " >>/etc/puppet/puppet.conf
                echo "    report_server = \$server " >>/etc/puppet/puppet.conf
                echo "    inventory_server = \$server " >>/etc/puppet/puppet.conf
                echo "    ca_server = \$server " >>/etc/puppet/puppet.conf
                echo "    pidfile = /var/run/puppet/agent.pid" >>/etc/puppet/puppet.conf

		# correct facter issue with passenger
		#sed -e 's/^\s*factdest.*$/# factdest = \/var\/puppet\/facts\//' -i /etc/puppet/puppet.conf
		#sed -e 's/^\s*factsource.*$/# factsource = puppet:\/\/puppet\/facts\//' -i /etc/puppet/puppet.conf

		$logger "Setting certificate DN to $PUPPETSERVER"
		echo "    certname = $PUPPETSERVER" >>/etc/puppet/puppet.conf
		
		if [[ ! -f "/etc/puppet/manifests/site.pp" ]]; then
			mkdir -p /etc/puppet/manifests
			if [[ "$NOMCOLLECTIVE" == "true" ]]; then
				$logger "Creating an empty site.pp manifest"
				touch /etc/puppet/manifests/site.pp
			else
				# Add a file on each host which gets generated from puppets facts.
				$logger "Creating a default site.pp manifest which saves facts for mcollective."
				cat <<EOT >/etc/puppet/manifests/site.pp
# Default, update a list of facts for mcollective to use.
\$content = inline_template("<%= facts = {}; scope.to_hash.each_pair{|k,v| facts[k.to_s] = v.to_s};facts.to_yaml %>")

exec { "generate_facts_yaml":
        loglevel => debug,
        logoutput => false,
        cwd => "/tmp",
        command => "/bin/false",
        unless => "/bin/echo '\$content' >/etc/mcollective/facts.yaml",
}

# Default, save files back to the puppet master (so that they can be viewed/diffed
filebucket { "main":
  server => "$PUPPETSERVER",
  path => false,
}

File { backup => "main" }
EOT
			fi
		else
			$logger "/etc/puppet/manifests/site.pp already exists."
		fi
	fi

	# Work out the number of CPU cores available
	# used in configuring rack and the delayed_message handler if dashboard is installed.
	CORES=`cat /proc/cpuinfo | grep ^processor.*: | wc -l`

	CONFIGURED=`grep "practicalclouds Recommended Passenger Configuration" /etc/httpd/conf.d/passenger.conf`
	if [[ "$CONFIGURED" != "" ]]; then
		$logger "Passenger is already configured..."
	else
		# Automatically calculate the pool size as 1.5x the number of cores rounded up to 
		# nearest int
		POOL=`echo "$CORES * 1.5" | bc`
		POOLINT=`echo "($POOL+0.5)/1" | bc`

		$logger "Configuring mod_passenger (/etc/httpd/conf.d/passenger.conf)..."
		cat >>/etc/httpd/conf.d/passenger.conf <<EOT
# practicalclouds Recommended Passenger Configuration
PassengerHighPerformance on
PassengerUseGlobalQueue on
# PassengerMaxPoolSize control number of application instances
# typically 1.5x number of cores
PassengerMaxPoolSize $POOLINT
# Restart ruby process after handling specifc number of requests
PassengerMaxRequests 4000
# Shutdown idle Passenger instances after 30 min.
PassengerPoolIdleTime 1800
# End of practicalclouds Passenger settings.
EOT
	fi
	$logger "Configuring SSL vhost (/etc/httpd/conf.d/puppetmaster.conf)..."
	if [[ ! -s "/etc/httpd/conf.d/puppetmaster.conf" ]]; then
		#curl -s -o /etc/httpd/conf.d/puppetmaster.conf http://files001.practicalclouds.com/puppetmaster.conf
		#if [[ "$?" != "0" ]]; then
		#	fatal_error "I can't load apache configuration file for puppetmaster.conf!"
		#	exit 1
		#fi
		cat >/etc/httpd/conf.d/puppetmaster.conf <<EOT
#
# This is the Apache server configuration file providing SSL support.
# It contains the configuration directives to instruct the server how to
# serve pages over an https connection. For detailing information about these 
# directives see <URL:http://httpd.apache.org/docs/2.2/mod/mod_ssl.html>
# 
# Do NOT simply read the instructions in here without understanding
# what they do.  They're here only as hints or reminders.  If you are unsure
# consult the online docs. You have been warned.  
#

<IfModule !mod_ssl.c>
        LoadModule ssl_module modules/mod_ssl.so
</IfModule>

#
# When we also provide SSL we have to listen to the 
# the HTTPS port in addition.
#
Listen $PUPPETPORT

##
##  SSL Global Context
##
##  All SSL configuration in this context applies both to
##  the main server and all SSL-enabled virtual hosts.
##

#   Pass Phrase Dialog:
#   Configure the pass phrase gathering process.
#   The filtering dialog program (\`builtin' is a internal
#   terminal dialog) has to provide the pass phrase on stdout.
SSLPassPhraseDialog exec:/usr/libexec/httpd-ssl-pass-dialog

#   Inter-Process Session Cache:
#   Configure the SSL Session Cache: First the mechanism 
#   to use and second the expiring timeout (in seconds).
#SSLSessionCache        dc:UNIX:/var/cache/mod_ssl/distcache
SSLSessionCache         shmcb:/var/cache/mod_ssl/scache(512000)
SSLSessionCacheTimeout  300

#   Semaphore:
#   Configure the path to the mutual exclusion semaphore the
#   SSL engine uses internally for inter-process synchronization. 
SSLMutex default

#   Pseudo Random Number Generator (PRNG):
#   Configure one or more sources to seed the PRNG of the 
#   SSL library. The seed data should be of good random quality.
#   WARNING! On some platforms /dev/random blocks if not enough entropy
#   is available. This means you then cannot use the /dev/random device
#   because it would lead to very long connection times (as long as
#   it requires to make more entropy available). But usually those
#   platforms additionally provide a /dev/urandom device which doesn't
#   block. So, if available, use this one instead. Read the mod_ssl User
#   Manual for more details.
SSLRandomSeed startup file:/dev/urandom  256
SSLRandomSeed connect builtin
#SSLRandomSeed startup file:/dev/random  512
#SSLRandomSeed connect file:/dev/random  512
#SSLRandomSeed connect file:/dev/urandom 512

#
# Use "SSLCryptoDevice" to enable any supported hardware
# accelerators. Use "openssl engine -v" to list supported
# engine names.  NOTE: If you enable an accelerator and the
# server does not start, consult the error logs and ensure
# your accelerator is functioning properly. 
#
SSLCryptoDevice builtin
#SSLCryptoDevice ubsec

##
## SSL Virtual Host Context
##

<VirtualHost _default_:$PUPPETPORT>

# General setup for the virtual host, inherited from global configuration
#DocumentRoot "/var/www/html"
#ServerName www.example.com:443

# Use separate log files for the SSL virtual host; note that LogLevel
# is not inherited from httpd.conf.
ErrorLog logs/ssl_error_log
TransferLog logs/ssl_access_log
LogLevel warn

#   SSL Engine Switch:
#   Enable/Disable SSL for this virtual host.
SSLEngine on

#   SSL Protocol support:
# List the enable protocol levels with which clients will be able to
# connect.  Disable SSLv2 access by default:
SSLProtocol -ALL +SSLv3 +TLSv1

#   SSL Cipher Suite:
#   List the ciphers that the client is permitted to negotiate.
#   See the mod_ssl documentation for a complete list.
SSLCipherSuite RC4-SHA:AES128-SHA:ALL:!ADH:!EXP:!LOW:!MD5:!SSLV2:!NULL

#   SSL Cipher Honor Order:
#   On a busy HTTPS server you may want to enable this directive
#   to force clients to use one of the faster ciphers like RC4-SHA
#   or AES128-SHA in the order defined by SSLCipherSuite.
#SSLHonorCipherOrder on 

#   Server Certificate:
# Point SSLCertificateFile at a PEM encoded certificate.  If
# the certificate is encrypted, then you will be prompted for a
# pass phrase.  Note that a kill -HUP will prompt again.  A new
# certificate can be generated using the genkey(1) command.
# 
# The puppet master will create this cert the first time it starts
# up
SSLCertificateFile /etc/puppet/ssl/certs/${PUPPETSERVER}.pem

#   Server Private Key:
#   If the key is not combined with the certificate, use this
#   directive to point at the key file.  Keep in mind that if
#   you've both a RSA and a DSA private key you can configure
#   both in parallel (to also allow the use of DSA ciphers, etc.)
SSLCertificateKeyFile /etc/puppet/ssl/private_keys/${PUPPETSERVER}.pem

#   Server Certificate Chain:
#   Point SSLCertificateChainFile at a file containing the
#   concatenation of PEM encoded CA certificates which form the
#   certificate chain for the server certificate. Alternatively
#   the referenced file can be the same as SSLCertificateFile
#   when the CA certificates are directly appended to the server
#   certificate for convinience.
SSLCertificateChainFile /etc/puppet/ssl/certs/ca.pem

#   Certificate Authority (CA):
#   Set the CA certificate verification path where to find CA
#   certificates for client authentication or alternatively one
#   huge file containing all of them (file must be PEM encoded)
SSLCACertificateFile /etc/puppet/ssl/certs/ca.pem
SSLCARevocationFile /etc/puppet/ssl/crl.pem

#   Client Authentication (Type):
#   Client certificate verification type and depth.  Types are
#   none, optional, require and optional_no_ca.  Depth is a
#   number which specifies how deeply to verify the certificate
#   issuer chain before deciding the certificate is not valid.
SSLVerifyClient optional
SSLVerifyDepth  1

#   Access Control:
#   With SSLRequire you can do per-directory access control based
#   on arbitrary complex boolean expressions containing server
#   variable checks and other lookup directives.  The syntax is a
#   mixture between C and Perl.  See the mod_ssl documentation
#   for more details.
#<Location />
#SSLRequire (    %{SSL_CIPHER} !~ m/^(EXP|NULL)/ \\
#            and %{SSL_CLIENT_S_DN_O} eq "Snake Oil, Ltd." \\
#            and %{SSL_CLIENT_S_DN_OU} in {"Staff", "CA", "Dev"} \\
#            and %{TIME_WDAY} >= 1 and %{TIME_WDAY} <= 5 \\
#            and %{TIME_HOUR} >= 8 and %{TIME_HOUR} <= 20       ) \\
#           or %{REMOTE_ADDR} =~ m/^192\\.76\\.162\\.[0-9]+\$/
#</Location>

#   SSL Engine Options:
#   Set various options for the SSL engine.
#   o FakeBasicAuth:
#     Translate the client X.509 into a Basic Authorisation.  This means that
#     the standard Auth/DBMAuth methods can be used for access control.  The
#     user name is the \`one line' version of the client's X.509 certificate.
#     Note that no password is obtained from the user. Every entry in the user
#     file needs this password: \`xxj31ZMTZzkVA'.
#   o ExportCertData:
#     This exports two additional environment variables: SSL_CLIENT_CERT and
#     SSL_SERVER_CERT. These contain the PEM-encoded certificates of the
#     server (always existing) and the client (only existing when client
#     authentication is used). This can be used to import the certificates
#     into CGI scripts.
#   o StdEnvVars:
#     This exports the standard SSL/TLS related \`SSL_*' environment variables.
#     Per default this exportation is switched off for performance reasons,
#     because the extraction step is an expensive operation and is usually
#     useless for serving static content. So one usually enables the
#     exportation for CGI and SSI requests only.
#   o StrictRequire:
#     This denies access when "SSLRequireSSL" or "SSLRequire" applied even
#     under a "Satisfy any" situation, i.e. when it applies access is denied
#     and no other module can change it.
#   o OptRenegotiate:
#     This enables optimized SSL connection renegotiation handling when SSL
#     directives are used in per-directory context. 
#SSLOptions +FakeBasicAuth +ExportCertData +StrictRequire
SSLOptions +StdEnvVars

# The following client headers record authentication information for down stream
# workers.

RequestHeader set X-SSL-Subject %{SSL_CLIENT_S_DN}e
RequestHeader set X-Client-DN %{SSL_CLIENT_S_DN}e
RequestHeader set X-Client-Verify %{SSL_CLIENT_VERIFY}e

#   SSL Protocol Adjustments:
#   The safe and default but still SSL/TLS standard compliant shutdown
#   approach is that mod_ssl sends the close notify alert but doesn't wait for
#   the close notify alert from client. When you need a different shutdown
#   approach you can use one of the following variables:
#   o ssl-unclean-shutdown:
#     This forces an unclean shutdown when the connection is closed, i.e. no
#     SSL close notify alert is send or allowed to received.  This violates
#     the SSL/TLS standard but is needed for some brain-dead browsers. Use
#     this when you receive I/O errors because of the standard approach where
#     mod_ssl sends the close notify alert.
#   o ssl-accurate-shutdown:
#     This forces an accurate shutdown when the connection is closed, i.e. a
#     SSL close notify alert is send and mod_ssl waits for the close notify
#     alert of the client. This is 100% SSL/TLS standard compliant, but in
#     practice often causes hanging connections with brain-dead browsers. Use
#     this only for browsers where you know that their SSL implementation
#     works correctly. 
#   Notice: Most problems of broken clients are also related to the HTTP
#   keep-alive facility, so you usually additionally want to disable
#   keep-alive for those clients, too. Use variable "nokeepalive" for this.
#   Similarly, one has to force some clients to use HTTP/1.0 to workaround
#   their broken HTTP/1.1 implementation. Use variables "downgrade-1.0" and
#   "force-response-1.0" for this.
SetEnvIf User-Agent ".*MSIE.*" \\
         nokeepalive ssl-unclean-shutdown \\
         downgrade-1.0 force-response-1.0

#   Per-Server Logging:
#   The home of a custom SSL log file. Use this when you want a
#   compact non-error SSL logfile on a virtual host basis.
#CustomLog logs/ssl_request_log \\
#          "%t %h %{SSL_PROTOCOL}x %{SSL_CIPHER}x \\"%r\\" %b"

# Configure virtual host to use rack/passenger/ruby...
RackAutoDetect On
DocumentRoot /etc/puppet/rack/puppetmaster/public/
<Directory /etc/puppet/rack/puppetmaster/>
	Options None
	AllowOverride None
	Order allow,deny
	allow from all
</Directory>
</VirtualHost>   
EOT
	else
		$logger "/etc/httpd/conf.d/puppetmaster.conf already exists, skipping."
	fi

        # check the certs and generate if we don't have any...
        MYCERT=$(puppet config print hostcert)
        $logger "Checking that my ssl certificate exists at $MYCERT."
        if [ ! -f "$MYCERT" ]; then
                $logger "My certificate does not exist - generating a new one..."
                $logger "Generating certificate for host $PUPPETSERVER"
		#removed - the correct values are now  written as the file is created...
                #sed -e "s/^SSLCertificateFile.*\$/SSLCertificateFile \/etc\/puppet\/ssl\/certs\/${PUPPETSERVER}.pem/" -i /etc/httpd/conf.d/puppetmaster.conf
                #sed -e "s/^SSLCertificateKeyFile.*\$/SSLCertificateKeyFile \/etc\/puppet\/ssl\/private_keys\/${PUPPETSERVER}.pem/" -i /etc/httpd/conf.d/puppetmaster.conf
                puppet cert --generate $PUPPETSERVER
                if [[ "$?" != "0" ]]; then
                        fatal_error "I couldn't generate my certificates for SSL using: puppet cert --generate $PUPPETSERVER"
                        exit 1
                fi
        else
                $logger "My certificate already exists, ok."
        fi
		
	if [[ ! -d "/etc/puppet/rack/puppetmaster/public" ]]; then
		$logger "Configuring Rack (/etc/puppet/rack/puppetmaster/config.ru)..."
		mkdir -p /etc/puppet/rack/puppetmaster/{public,tmp}
		cat >/etc/puppet/rack/puppetmaster/config.ru <<EOT
# /etc/puppet/rack/puppetmaster/config.ru
# a config.ru, for use with every rack-compatible webserver
\$0 = "master"
# if you want debugging:
# ARGV << "--debug"
ARGV << "--rack"
require 'puppet/application/master'
run Puppet::Application[:master].run
# EOF /etc/puppet/rack/puppetmaster/config.ru
EOT
		chown puppet:puppet /etc/puppet/rack/puppetmaster/config.ru
	else
		$logger "Rack is already configured, skipping."
	fi

	$logger "Configuring Puppet Master to store configs in MySQL..."
	CONFIGURED=`cat /etc/puppet/puppet.conf | grep -v "^\s*#" | grep "dbadapter"`
	if [[ "$CONFIGURED" == "" ]]; then
		cat >>/etc/puppet/puppet.conf <<EOT
    storeconfigs = true
    dbadapter = mysql
    dbname = $DBNAME
    dbuser = $DBUSER
    dbpassword = $DBPASS
    dbserver = $DBHOST
    dbsocket = /var/lib/mysql/mysql.sock
EOT
	else
		$logger "A database adapter is already configured in /etc/puppet/puppet.conf, skipping"
	fi

	# Enable autosign by default.  By perference set it to autosigndomain, then the domain
	# worked out from the Name or domain arg, or finally - any ec2 internal name.
	if [[ "$NOAUTOSIGN" != "true" ]]; then
		if [[ "$AUTOSIGNDOMAIN" != "" ]]; then
			$logger "Enabling cert autosign for *.$AUTOSIGNDOMAIN"
			echo "*.$AUTOSIGNDOMAIN" >/etc/puppet/autosign.conf
		else
			if [[ "$DOMAIN" != "" ]]; then
				$logger "Enabling cert autosign for *.$DOMAIN"
				echo "*.$DOMAIN" >/etc/puppet/autosign.conf
			else
				$logger "Enabling cert autosign for *.compute.internal"
				echo "*.compute.internal" >/etc/puppet/autosign.conf
			fi
		fi
	else
		$logger "Autosign left disabled by request."		
	fi

	# make sure that the important puppet directories are properly owned by the puppet user!
	chown -R puppet:puppet /etc/puppet
	chown -R puppet:puppet /var/lib/puppet

	# Configure backing up of /etc/puppet and /var/lib/puppet
	if [[ "$BACKUPPATH" != "" ]]; then
		$logger "Enabling backups of /etc/puppet and /var/lib/puppet..."

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

		if [[ "$PUPPETCONFIG" != "" ]]; then
			CONFIGSFILE="$PUPPETCONFIG"
                        # remove any archive extentions and any previous time/date stamps.
                        CONFIGSFILE=`echo $CONFIGSFILE | sed -e 's/\.t[ar.]*[gb]z[2]*$//'`
                        if [[ "$CONFIGSFILE" =~ _[0-9-_]* ]]; then
                        	CONFIGSFILE=${CONFIGSFILE%%_[0-9-_]*}
                        fi
                        $logger "/etc/puppet backup file is : $CONFIGSFILE"
                        if [[ ! "$CONFIGSFILE" =~ ^${PREFIX} ]]; then
                        	echo "$BACKUPSCHEDULE /usr/local/bin/backup2s3.sh -f ${PREFIX}${CONFIGSFILE} -p /etc/puppet  -d $BACKUPPATH -k $KEEPBACKUPS $SCFG" >>/var/spool/cron/root
                        else
                         	echo "$BACKUPSCHEDULE /usr/local/bin/backup2s3.sh -f ${CONFIGSFILE} -p /etc/puppet  -d $BACKUPPATH -k $KEEPBACKUPS $SCFG" >>/var/spool/cron/root
                        fi
                else
                 	echo "$BACKUPSCHEDULE /usr/local/bin/backup2s3.sh -f ${PREFIX}puppet-configs -p /etc/puppet  -d $BACKUPPATH -k $KEEPBACKUPS $SCFG" >>/var/spool/cron/root
                fi
                if [[ "$PUPPETDATA" != "" ]]; then
                        DATAFILE="$PUPPETDATA"
                        # remove any archive extentions and any previous time/date stamps.
                        DATAFILE=`echo $DATAFILE | sed -e 's/\.t[ar.]*[gb]z[2]*$//'`
                        if [[ "$DATAFILE" =~ _[0-9-_]* ]]; then
                                DATAFILE=${DATAFILE%%_[0-9-_]*}
                        fi
                        $logger "/var/lib/puppet backup file is : $DATAFILE"
                        if [[ ! "$DATAFILE" =~ ^${PREFIX} ]]; then
                                echo "$BACKUPSCHEDULE /usr/local/bin/backup2s3.sh -f ${PREFIX}${DATAFILE} -p /var/lib/puppet  -d $BACKUPPATH -k $KEEPBACKUPS $SCFG" >>/var/spool/cron/root
                        else
                                echo "$BACKUPSCHEDULE /usr/local/bin/backup2s3.sh -f ${DATAFILE} -p /var/lib/puppet  -d $BACKUPPATH -k $KEEPBACKUPS $SCFG" >>/var/spool/cron/root
                        fi
                 else
                        echo "$BACKUPSCHEDULE /usr/local/bin/backup2s3.sh -f ${PREFIX}puppet-data -p /var/lib/puppet  -d $BACKUPPATH -k $KEEPBACKUPS $SCFG" >>/var/spool/cron/root
                 fi
                 $logger "Added automatic backups of puppet configs and puppet data to cron"
        else
                 $logger "Automatic backups have not been requested, you will need another way of backing up /etc/puppet and /var/lib/puppet!"
        fi
	
	# Optionally install the puppetdashboard
	if [[ "$NODASHBOARD" != "true" ]]; then
		$logger "Configuring the Dashboard..."
		sed -e "s/database: dashboard_production/database: ${DBNAME}/g" -i /usr/share/puppet-dashboard/config/database.yml
		sed -e "s/username: dashboard/username: ${DBUSER}/g" -i /usr/share/puppet-dashboard/config/database.yml
		sed -e "s/password:/password: ${DBPASS}/g" -i /usr/share/puppet-dashboard/config/database.yml

		# Cope with a non standard puppetmaster port
		$logger "Configuring Dashboard /usr/share/puppet-dashboard/config/settings.yml "
		cp -p /usr/share/puppet-dashboard/config/settings.yml.example /usr/share/puppet-dashboard/config/settings.yml
		# change the port to the correct one
		sed -e 's/8140/'$PUPPETPORT'/g' -i /usr/share/puppet-dashboard/config/settings.yml
		# change all the default 'puppet' config for the correct server name	
		sed -e 's/_server:\s*.*$/_server: '$PUPPETSERVER'/' -i /usr/share/puppet-dashboard/config/settings.yml

		# Workaround Rack Dependancy Issue
		# Puppet dashboard doesn't seem to expect rails to already be installed.
		sed -e 's/^\s*s.add_dependency.*rack.*$//' -i /usr/share/puppet-dashboard/vendor/rails/actionpack/Rakefile
		sed -e 's/^gem.*rack.*$//' -i /usr/share/puppet-dashboard/vendor/rails/actionpack/lib/action_controller.rb

		$logger "Creating dashboard tables..."
		cd /usr/share/puppet-dashboard
		rake RAILS_ENV=production db:migrate | grep -v "SourceIndex#add_spec" | tee -a /var/log/messages	

		$logger "Starting the delayed job monitor..."
		RAILS_ENV="production" ./script/delayed_job -p dashboard -n $CORES -m start
	
		# set up passenger...
		# if port is 80 remove the listen directive from the httpd.conf
		if [[ "$DASHPORT" == "80" ]]; then
			$logger "Removing Listen 80 from httpd.conf"
			sed -e 's/^Listen/#Listen/g' -i /etc/httpd/conf/httpd.conf
		fi

		# configure a user name and password
		$logger "Creating apache user $DASHUSER with password $DASHPASS."
		htpasswd -bc /etc/httpd/conf/passwd_dashboard $DASHUSER $DASHPASS 2>&1 | tee -a /var/log/messages

		# updated with simple authentication by default
		MYIPADDR=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`
		cat >/etc/httpd/conf.d/dashboard.conf <<EOT
Listen $DASHPORT

<VirtualHost *:$DASHPORT>
        ServerName $PUPPETSERVER
        DocumentRoot /usr/share/puppet-dashboard/public/
        <Location />
		Order allow,deny
                Options None
		Allow from 127.0.0.1 ::1 ${MYIPADDR}
    		Satisfy any
    		AuthType Basic
		#AuthAuthoritative Off
    		AuthName "Puppet Dashboard"
    		# (Following line optional)
    		AuthBasicProvider file
    		AuthUserFile /etc/httpd/conf/passwd_dashboard
    		Require valid-user
        </Location>
	ErrorLog logs/${PUPPETSERVER}_dashboard_error.log
	LogLevel warn
	CustomLog logs/${PUPPETSERVER}_dashboard_access.log combined
	ServerSignature On
</VirtualHost>
EOT

		# configure the external node classifier
		EXTNODES=`cat /etc/puppet/puppet.conf | grep "^\s*node_terminus = exec"`
		if [[ "$EXTNODES" == "" ]]; then
			$logger "Configuring to use the dashboard as external node classifier..."
			echo "    node_terminus = exec" >>/etc/puppet/puppet.conf
			echo "    external_nodes = /usr/share/puppet-dashboard/bin/external_node" >>/etc/puppet/puppet.conf
		fi
		# fix up the default external_node script
		#sed -e "s/^DASHBOARD_URL = .\*\$/DASHBOARD_URL = \"http:\\/\\/localhost:${DASHPORT}\"/" -i /usr/share/puppet-dashboard/bin/external_node
		sed -e 's/^DASHBOARD_URL = .*$/DASHBOARD_URL = "http:\/\/localhost:'${DASHPORT}'"/' -i /usr/share/puppet-dashboard/bin/external_node
		sed -e 's/^CERT_PATH = .*$/CERT_PATH = "\/etc\/puppet\/ssl\/certs\/'${PUPPETSERVER}'.pem"/' -i /usr/share/puppet-dashboard/bin/external_node
		sed -e 's/^PKEY_PATH = .*$/PKEY_PATH = "\/etc\/puppet\/ssl\/private_keys\/'${PUPPETSERVER}'.pem"/' -i /usr/share/puppet-dashboard/bin/external_node
	
		# take care of log rotation.
		cat >/etc/logrotate.d/puppet-dashboard <<EOT
/usr/share/puppet-dashboard/log/*log {
    missingok
    daily
    rotate 3
    compress
    notifempty
    sharedscripts
}
EOT
		# configure the puppetmaster to send reports to the dashboard
	        REPORTSCONFIGURED=`cat /etc/puppet/puppet.conf | grep "^\s*reports = http"`
        	if [[ "$REPORTSCONFIGURED" == "" ]]; then
                	$logger "Configuring reports to go to the dashboard.."
        		echo "    reports = http" >>/etc/puppet/puppet.conf
        		echo "    reporturl = http://${PUPPETSERVER}:${DASHPORT}/reports" >>/etc/puppet/puppet.conf
        	else
        		$logger "Http reporting is already configured."
        	fi

	fi

	$logger "Configuring the \"filebucket\" service in the dashboard..."
	sed -e 's/^use_file_bucket_diffs:.*$/use_file_bucket_diffs: true/' -i /usr/share/puppet-dashboard/config/settings.yml

	$logger "Installing Puppet Cloud Provisioner..."
	mkdir -p /etc/puppet/modules
	cd /etc/puppet/modules	
	puppet-module install puppetlabs/cloud_provisioner
	echo "export RUBYLIB=$(pwd)/cloud_provisioner/lib:$RUBYLIB" >>/etc/profile
	$logger "Configuring FOG with the root users credentials.."
	AWSKEY=`cat /root/.awssecret| head -1`
	SECRETKEY=`cat /root/.awssecret| tail -1`
	cat >/root/.fog <<EOT
:default:
  :aws_access_key_id:     $AWSKEY
  :aws_secret_access_key: $SECRETKEY
EOT

	# configure activemq if needed
	if [[ "$NOMCOLLECTIVE" != "true" && "$STOMPSERVER" == "$PUPPETSERVER" ]]; then
		$logger "Configuring ActiveMQ..."
		cat >/etc/activemq/activemq.xml <<EOT
<!--
         Licensed to the Apache Software Foundation (ASF) under one or more
    contributor license agreements.  See the NOTICE file distributed with
    this work for additional information regarding copyright ownership.
    The ASF licenses this file to You under the Apache License, Version 2.0
    (the "License"); you may not use this file except in compliance with
    the License.  You may obtain a copy of the License at
   
    http://www.apache.org/licenses/LICENSE-2.0
   
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
-->
<beans
  xmlns="http://www.springframework.org/schema/beans"
  xmlns:amq="http://activemq.apache.org/schema/core"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://www.springframework.org/schema/beans http://www.springframework.org/schema/beans/spring-beans-2.0.xsd
    http://activemq.apache.org/schema/core http://activemq.apache.org/schema/core/activemq-core.xsd 
    http://activemq.apache.org/camel/schema/spring http://activemq.apache.org/camel/schema/spring/camel-spring.xsd">

    <!-- Allows us to use system properties as variables in this configuration file -->
    <bean class="org.springframework.beans.factory.config.PropertyPlaceholderConfigurer">
        <property name="locations">
            <value>file:\${activemq.base}/conf/credentials.properties</value>
        </property>      
    </bean>

    <!-- 
                 The <broker> element is used to configure the ActiveMQ broker. 
    -->
    <broker xmlns="http://activemq.apache.org/schema/core" brokerName="localhost" dataDirectory="\${activemq.base}/data" destroyApplicationContextOnStop="true">
 
        <!--
                       For better performances use VM cursor and small memory limit.
          For more information, see:
            
          http://activemq.apache.org/message-cursors.html
            
          Also, if your producer is "hanging", it's probably due to producer 
          flow control.

          For more information, see:
          http://activemq.apache.org/producer-flow-control.html
        -->
              
        <destinationPolicy>
            <policyMap>
              <policyEntries>
                <policyEntry topic=">" producerFlowControl="true" memoryLimit="1mb">
                  <pendingSubscriberPolicy>
                    <vmCursor />
                  </pendingSubscriberPolicy>
                </policyEntry>
                <policyEntry queue=">" producerFlowControl="true" memoryLimit="1mb">
                  <!-- 
                                           Use VM cursor for better latency
                    For more information, see:
                       
                    http://activemq.apache.org/message-cursors.html
                       
                  <pendingQueuePolicy>
                    <vmQueueCursor/>
                  </pendingQueuePolicy>
                  -->
                </policyEntry>
              </policyEntries>
            </policyMap>
        </destinationPolicy> 

        <!-- 
                       The managementContext is used to configure how ActiveMQ is exposed in 
          JMX. By default, ActiveMQ uses the MBean server that is started by 
          the JVM. For more information, see: 
            
          http://activemq.apache.org/jmx.html 
        -->
        <managementContext>
            <managementContext createConnector="false"/>
        </managementContext>

        <!-- 
                       Configure message persistence for the broker. The default persistence
          mechanism is the KahaDB store (identified by the kahaDB tag). 
          For more information, see: 
            
          http://activemq.apache.org/persistence.html 
        -->
        <persistenceAdapter>
            <kahaDB directory="\${activemq.base}/data/kahadb"/>
        </persistenceAdapter>
        
        <plugins>
          <!--
                           Enable the statisticsBrokerPlugin to allow ActiveMQ to collect
            statistics.
          -->
          <statisticsBrokerPlugin/>

          <!--
                           Here we define a default set of users
          -->
          <simpleAuthenticationPlugin>
            <users>
              <authenticationUser username="\${activemq.username}" password="\${activemq.password}" groups="admins,everyone"/>
              <authenticationUser username="$STOMPUSER" password="$STOMPPASS" groups="mcollective,admins,everyone"/>
            </users>
          </simpleAuthenticationPlugin>
          <authorizationPlugin>
            <map>
              <authorizationMap>
                <authorizationEntries>
                  <authorizationEntry queue=">" write="admins" read="admins" admin="admins" />
                  <authorizationEntry topic=">" write="admins" read="admins" admin="admins" />
                  <authorizationEntry topic="mcollective.>" write="$STOMPUSER" read="$STOMPUSER" admin="$STOMPUSER" />
                  <authorizationEntry topic="mcollective.>" write="$STOMPUSER" read="$STOMPUSER" admin="$STOMPUSER" />
                  <authorizationEntry topic="ActiveMQ.Advisory.>" read="everyone" write="everyone" admin="everyone"/>
                </authorizationEntries>
              </authorizationMap>
            </map>
          </authorizationPlugin>
        </plugins>

        
        <!--
                       The systemUsage controls the maximum amount of space the broker will 
          use before slowing down producers. For more information, see:
          
          http://activemq.apache.org/producer-flow-control.html
        -->
        <systemUsage>
            <systemUsage>
                <memoryUsage>
                    <memoryUsage limit="20 mb"/>
                </memoryUsage>
                <storeUsage>
                    <storeUsage limit="1 gb"/>
                </storeUsage>
                <tempUsage>
                    <tempUsage limit="100 mb"/>
                </tempUsage>
            </systemUsage>
        </systemUsage>
		  
        <!-- 
                       The transport connectors expose ActiveMQ over a given protocol to
          clients and other brokers. For more information, see: 
            
          http://activemq.apache.org/configuring-transports.html 
        -->
        <transportConnectors>
            <transportConnector name="openwire" uri="tcp://0.0.0.0:61616"/>
            <transportConnector name="stomp+nio" uri="stomp+nio://0.0.0.0:$STOMPPORT"/>
        </transportConnectors>

    </broker>

    <!-- 
               Enable web consoles, REST and Ajax APIs and demos
      It also includes Camel (with its web console), see \${ACTIVEMQ_HOME}/conf/camel.xml for more info
        
      Take a look at \${ACTIVEMQ_HOME}/conf/jetty.xml for more details 
    -->
    <import resource="jetty.xml"/>
    
</beans>
EOT
		$logger "Starting Active MQ..."
		service activemq start
	fi

	# DO NOT START PUPPET MASTER DIRECTLY...
	# start apache with passenger
	$logger "Starting the Webserver and Puppet Master..."
	service httpd start
	if [[ "$?" != "0" ]]; then
		fatal_error "Sorry, Apache failed to start!"
	fi

	# configure the inventory service AFTER puppet has been started so that we 
	# have access to the puppet CA
	if [[ "$NODASHBOARD" != "true" ]]; then
		$logger "Enabling the \"inventory service\" for the dashboard"
		# Enable sudo to run without a tty
		sed -e 's/^Defaults\s*requiretty.*$/#Defaults	requiretty/' -i /etc/sudoers
		cd /usr/share/puppet-dashboard
		mkdir -p certs
		chown -R puppet-dashboard:puppet-dashboard certs
		sudo -u puppet-dashboard rake cert:create_key_pair 2>&1
		$logger "Requesting dashboard cert..."
		sudo -u puppet-dashboard rake cert:request 2>&1
		$logger "Signing the cert..."
		puppet cert sign dashboard
		sudo -u puppet-dashboard rake cert:retrieve 2>&1
		SERVICECONFIG=`cat /etc/puppet/auth.conf | grep "path /facts"`
		if [[ "$SERVICECONFIG" == "" ]]; then
			$logger "Allowing dashboard access to /facts"
			cat >/etc/puppet/auth.conf <<EOT
# This is an example auth.conf file, it mimics the puppetmasterd defaults
#
# The ACL are checked in order of appearance in this file.
#
# Supported syntax:
# This file supports two different syntax depending on how
# you want to express the ACL.
#
# Path syntax (the one used below):
# ---------------------------------
# path /path/to/resource
# [environment envlist]
# [method methodlist]
# [auth[enthicated] {yes|no|on|off|any}]
# allow [host|ip|*]
# deny [host|ip]
#
# The path is matched as a prefix. That is /file match at
# the same time /file_metadat and /file_content.
#
# Regex syntax:
# -------------
# This one is differenciated from the path one by a '~'
#
# path ~ regex
# [environment envlist]
# [method methodlist]
# [auth[enthicated] {yes|no|on|off|any}]
# allow [host|ip|*]
# deny [host|ip]
#
# The regex syntax is the same as ruby ones.
#
# Ex:
# path ~ .pp\$
# will match every resource ending in .pp (manifests files for instance)
#
# path ~ ^/path/to/resource
# is essentially equivalent to path /path/to/resource
#
# environment:: restrict an ACL to a specific set of environments
# method:: restrict an ACL to a specific set of methods
# auth:: restrict an ACL to an authenticated or unauthenticated request
# the default when unspecified is to restrict the ACL to authenticated requests
# (ie exactly as if auth yes was present).
#

### Authenticated ACL - those applies only when the client
### has a valid certificate and is thus authenticated

# allow nodes to retrieve their own catalog (ie their configuration)
path ~ ^/catalog/([^/]+)\$
method find
allow \$1

# allow nodes to retrieve their own node definition
path ~ ^/node/([^/]+)\$
method find
allow \$1

# allow all nodes to access the certificates services
path /certificate_revocation_list/ca
method find
allow *

# allow all nodes to store their reports
path /report
method save
allow *

# inconditionnally allow access to all files services
# which means in practice that fileserver.conf will
# still be used
path /file
allow *

### Unauthenticated ACL, for clients for which the current master doesn't
### have a valid certificate; we allow authenticated users, too, because
### there isn't a great harm in letting that request through.

# allow access to the master CA
path /certificate/ca
auth any
method find
allow *

path /certificate/
auth any
method find
allow *

path /certificate_request
auth any
method find, save
allow *

path /certificate_status
method save
auth any
allow localhost, 127.0.0.1, $PUPPETSERVER

path /facts
auth any
method find, search
allow *
allow dashboard, localhost, 127.0.0.1, $PUPPETSERVER

path /facts
auth any
method save
allow localhost, 127.0.0.1, $PUPPETSERVER

#
# this one is not stricly necessary, but it has the merit
# to show the default policy which is deny everything else
path /
auth any

EOT
			$logger "Updating puppet to use the database facts_terminus."
			echo "    facts_terminus = inventory_active_record" >>/etc/puppet/puppet.conf
		fi
		# enable the inventory service in the puppet dashboard
		sed -e 's/^enable_inventory_service:.*$/enable_inventory_service: true/' -i /usr/share/puppet-dashboard/config/settings.yml
	fi
else  
	$logger "Creating a default puppet agent config"
        #puppet agent --genconfig >/etc/puppet/puppet.conf
	echo "[agent]" >/etc/puppet/puppet.conf

        # correct some of the dumb non-default values
        #sed -e 's/^\s*pluginsource\s*=.*$/pluginsource = puppet:\/\/\$server\/plugins/' -i /etc/puppet/puppet.conf
        #sed -e 's/^\s*reportserver\s*=.*$/reportserver = \$server/' -i /etc/puppet/puppet.conf
        #sed -e 's/^\s*report_server\s*=.*$/report_server = \$server/' -i /etc/puppet/puppet.conf
        #sed -e 's/^\s*inventory_server\s*=.*$/inventory_server = \$server/' -i /etc/puppet/puppet.conf
        #sed -e 's/^\s*ca_server\s*=.*$/ca_server = \$server/' -i /etc/puppet/puppet.conf
	#sed -e 's/^\s*pidfile\s*=.*/pidfile = \/var\/run\/puppet\/agent.pid/' -i /etc/puppet/puppet.conf

        if [[ "$PUPPETSERVER" != "" ]]; then
		$logger "This puppet agent will connect to server: $PUPPETSERVER"
		echo "    server = $PUPPETSERVER" >>/etc/puppet/puppet.conf
	else
		$logger "This puppet agent will connect to the default puppet server."
        fi
        echo "    puppetport = $PUPPETPORT" >>/etc/puppet/puppet.conf

	echo "    pluginsync = true" >>/etc/puppet/puppet.conf
        echo "    pluginsource = puppet://\$server/plugins/" >>/etc/puppet/puppet.conf
        echo "    reportserver = \$server " >>/etc/puppet/puppet.conf
        echo "    report_server = \$server " >>/etc/puppet/puppet.conf
        echo "    inventory_server = \$server " >>/etc/puppet/puppet.conf
        echo "    ca_server = \$server " >>/etc/puppet/puppet.conf
        echo "    pidfile = /var/run/puppet/agent.pid" >>/etc/puppet/puppet.conf
fi

$logger "Configuring the puppet agent..."
if [[ "$PUPPETSERVER" != "" ]]; then
	SERVERCONFIGURED=`cat /etc/puppet/puppet.conf | grep "^\s*server = "`
	if [[ "$SERVERCONFIGURED" == "" ]]; then
		echo "    server = $PUPPETSERVER" >>/etc/puppet/puppet.conf
	fi

	$logger "Writing /etc/sysconfig/puppet."
	cat >/etc/sysconfig/puppet <<EOT
# The puppetmaster server
PUPPET_SERVER="${PUPPETSERVER}"

# If you wish to specify the port to connect to do so here
PUPPET_PORT=${PUPPETPORT}

# Where to log to. Specify syslog to send log messages to the system log.
PUPPET_LOG="/var/log/puppet/puppet.log"

# You may specify other parameters to the puppet client here
PUPPET_EXTRA_OPTS="--pidfile=/var/run/puppet/agent.pid --waitforcert=500 --verbose"
EOT
	
	SHOWDIFF=`cat /etc/puppet/puppet.conf | grep "^\s*show_diff\s*=\s*true\s*$"`
	if [[ "$SHOWDIFF" == "" ]]; then
		$logger "Enabling diffs to be reported in the logs/reports."
		echo "    show_diff = true" >>/etc/puppet/puppet.conf
	fi
else
	$logger "Warning: I am unable to configure the puppet agent without the \"puppetserver\" argument"
fi

$logger "Starting the puppet agent..."
/sbin/service puppet start
if [[ "$?" != "0" ]]; then
	fatal_error "Sorry, the puppet agent failed to start!"
fi

if [[ "$NOMCOLLECTIVE" != "true" ]]; then
	$logger "Configuring MCollective..."
	for FILE in /etc/mcollective/client.cfg /etc/mcollective/server.cfg
	do
		if [[ -f $FILE ]]; then
			sed -e 's/^plugin.psk\s*=.*$/plugin.psk = '$STOMPPSK'/' -i $FILE
			sed -e 's/^plugin.stomp.host\s*=.*$/plugin.stomp.host = '$STOMPSERVER'/' -i $FILE
			sed -e 's/^plugin.stomp.port\s*=.*$/plugin.stomp.port = '$STOMPPORT'/' -i $FILE
			sed -e 's/^plugin.stomp.user\s*=.*$/plugin.stomp.user = '$STOMPUSER'/' -i $FILE
			sed -e 's/^plugin.stomp.password\s*=.*$/plugin.stomp.password = '$STOMPPASS'/' -i $FILE
		fi
	done

	$logger "Making sure that 'git' is installed..."
	GITINSTALLED=`rpm -qa git`
	if [[ "$GITINSTALLED" == "" ]]; then
		$logger "Installing Git Version control client."
		yum -y install git 2>&1 | tee -a /var/log/messages
	fi
	git clone git://github.com/puppetlabs/mcollective-plugins.git /etc/bootstrap.d/mcollective-plugins	

	# Dave's v2 MCollective Plugin installer.
	# Take each file and work backwards along its path looking at each parent directory
	# until we find a match for a directory in /usr/libexec/mcollective/mcollective or a special case.
	# Special cases: -
	#       'spec' are skipped
	#       'puppet' are copied to /etc/puppet/extras
	#       'util|utilitites|sbin|commander' are copied to /usr/local/sbin

	$logger "Installing MCollective Pluggins..."
	mkdir -p /etc/puppet/extras
	# Get a list of files, excluding .git dierctory and files at the top level.
	FILES=`find /etc/bootstrap.d/mcollective-plugins -type f | grep -v "\.git" | grep "/.*/"`
	for FILE in $FILES; do
        	FPATH=$FILE
        	while [[ "$FPATH" != "/etc/bootstrap.d/mcollective-plugins" ]]; do
                	FPATH=${FPATH%/*}
                	PARENT=`basename $FPATH`
                	case $PARENT in
                        	spec)   break
                                	;;
                        	puppet) cp -p $FILE /etc/puppet/extras
                                	break
                                	;;
                        	util|utilitites|sbin|commander) cp -p $FILE /usr/local/sbin
                                	break
                                	;;
                        	*)      if [[ -d "/usr/libexec/mcollective/mcollective/$PARENT" ]]; then
                                        	echo "copying $FILE to /usr/libexec/mcollective/mcollective/$PARENT"
                                        	cp -p $FILE /usr/libexec/mcollective/mcollective/$PARENT
                                        	break
                                	fi
                                	;;
                	esac
        	done
	done

	# configure the puppetm plugin
	if [[ -f "/usr/libexec/mcollective/mcollective/agent/puppetd.rb" ]]; then
		$logger "Configuring the MCollective puppet agent."
		echo >>/etc/mcollective/server.cfg <<EOT
plugin.puppetd.puppetd = /usr/sbin/puppetd
plugin.puppetd.lockfile = /var/lib/puppet/state/puppetdlock
plugin.puppetd.statefile = /var/lib/puppet/state/state.yaml
plugin.puppet.pidfile = /var/run/puppet/agent.pid
plugin.puppetd.splaytime = 100
plugin.puppet.summary = /var/lib/puppet/state/last_run_summary.yaml
EOT
	fi
	# Enable service and package agents...
	$logger "Enabling the MCollective 'service' plugin."
	[[ -f "/usr/libexec/mcollective/mcollective/agent/puppet-service.rb" ]] && mv /usr/libexec/mcollective/mcollective/agent/puppet-service.rb /usr/libexec/mcollective/mcollective/agent/service.rb
	$logger "Enabling the MCollective 'package' plugin."
	[[ -f "/usr/libexec/mcollective/mcollective/agent/puppet-package.rb" ]] && mv /usr/libexec/mcollective/mcollective/agent/puppet-package.rb /usr/libexec/mcollective/mcollective/agent/package.rb

	$logger "Starting MCollective agent..."
	service mcollective start
        if [[ "$?" != "0" ]]; then
                fatal_error "Sorry, MCollective failed to start!"
        fi
fi

# make sure that the important puppet directories are properly owned by the puppet user!
chown -R puppet:puppet /etc/puppet
chown -R puppet:puppet /var/lib/puppet

$logger "******************************************"
$logger "     Finished installing Puppet!"
$logger "******************************************"
if [[ "$MASTER" == "true" ]]; then
	# Tell us about the dashboard, stupid!
        if [[ "$NODASHBOARD" != "true" ]]; then
                MYEXTERNALNAME=`curl -s --fail http://169.254.169.254/latest/meta-data/public-hostname`
                $logger "The puppet dashboard has been installed and is available here http://$DASHUSER:$DASHPASS@${MYEXTERNALNAME}:${DASHPORT}"
        fi

	# Calculate what options we need to set when we start an agent
	AGENTOPTIONS="profile=puppet puppetserver=$PUPPETSERVER"
	if [[ "$PUPPETPORT" != "8140" ]]; then
		AGENTOPTIONS="$AGENTOPTIONS puppetport=$PUPPETPORT"
	fi
	if [[ "$NOMCOLLECTIVE" != "true" ]]; then
		if [[ "$STOMPSERVER" != "$PUPPETSERVER" ]]; then
			AGENTOPTIONS="$AGENTOPTIONS stomphost=$STOMPSERVER"
		fi
		if [[ "$STOMPPORT" != "61613" ]]; then
			AGENTOPTIONS="$AGENTOPTIONS stompport=$STOMPPORT"
		fi
		if [[ "$STOMPUSER" != "mcollective" ]]; then
			AGENTOPTIONS="$AGENTOPTIONS stompuser=$STOMPUSER"
		fi
		AGENTOPTIONS="$AGENTOPTIONS stomppass=$STOMPPASS stomppsk=$STOMPPSK"
	fi
	$logger "To connect agents to this puppet master please specify the following boot arguments in 'user-data': -"
	$logger "$AGENTOPTIONS"
        if [[ -f "/etc/puppet/autosign.conf" ]]; then
                AUTOSIGN=`cat /etc/puppet/autosign.conf`
                $logger "Your puppet agent certs will be automatically signed if they match this domain: $AUTOSIGN"
        else
                $logger "No puppet agent certs will be automatically signed; you must sign them manually"
        fi
	$logger "It is advisable to create two separate security groups for your 'puppetmaster' and 'puppetagent'."
	if [[ "$NOMCOLLECTIVE" != "true" ]]; then
		$logger "Only allow members of your 'puppetagent' security group to connect to your puppet master port ($PUPPETPORT) or mcollective ($STOMPPORT)."
	else
		$logger "Only allow members of your 'puppetagent' security group to connect to your puppet master port ($PUPPETPORT)."

	fi
	$logger "This way, it should be safe to automatically sign puppet certificates because you can control which servers are allowed to connect."
	$logger "******************************************"
fi

