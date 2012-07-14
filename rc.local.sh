#!/bin/bash
#
# 2011 Dave McCormick

PROFILE_NAME="rc.local"
PROFILE_VERSION="2.19"
PROFILE_URL="http://www.practicalclouds.com/content/guide/extended-cloud-boot-rclocal"
PROFILE_DOWNLOAD="files001.practicalclouds.com/rc.local.sh"
MINIMUM_BOOTSTRAP_FUNCTIONS="2.0"

WEBPROFILES="files001.practicalclouds.com"
AWSDOWNLOAD="https://raw.github.com/timkay/aws/master/aws http://files001.practicalclouds.com/aws"

# 1.0  - initial version
# 1.1  - add bootstrap profiles and motd status
# 1.2  - add ssh keys from user-data
# 1.3  - allow default files for tags and files
# 1.4  - use bootstrap-functions
# 1.5  - restrict root user after boot and clean up bootstrap files.
# 1.6  - add colour to the motd
# 1.7  - allow setting default bootbucket, access_key and secret_key based
#        on platform.
# 1.8  - add 'args' tag support
# 1.9  - Change to support bootstrap functions with command style arguments.
# 1.10 - Tags are now case sensitive! Try and set the "Name" and platform tags as
#        real tags if they have been set in the args tag or by a file.
# 1.11 - Allow selecting profiles with "profiles" or "profile" tag
# 1.12 - Add delete of tags at the end of the bootstrap process - needs
#        bootstrap-functions version 1.23 or above.
# 1.13 - correct typo - should be tags2delete, not tag2delete.
# 1.14 - Add version checking and printing motd at end of the bootstrap.
# 1.15 - Correct broken explode of args tag and also look in user-data just like
#        the bootstrap-functions.  Tags can be entered anywhere!
# 1.16 - Look on www.practicalclouds.com website when you can't find a profile.
#        This allows you to boot any profile on the website without having a
#        bootbucket or having saved it into /etc/bootstrap-default.
# 1.17 - Look on www.practicalclouds.com for the boostrap functions if you can't
#        find them in bootbucket or /etc/bootstrap-default.
# 1.18 - Carry on even if we can't read tags!  That means all arguments need
#        to be passed as "args: " in the user-data.
# 1.19 - Minor clean up of messages and automatically write the motd file.
# 1.20 - If no profile is specifically specified but the ami manifest ends
#        in __profile=xyz then automatically load the profile xyz.  This is to
#        allow us to register AMIs which load profiles without the user having to 
#        know that they are supposed to enter the profile (e.g. Special drupal AMI).
#
# 2.0  - SIMPLER, EASIER and FASTER
#        * Convert to using 'aws' by Tim Kay, http://timkay.com/aws/
#        * Automatically install 'aws script' for making ec2 api and s3cmd calls.
#          EC2-API-Tools, JAVA and s3cmd are no longer needed by the boot process
#          and there will be no need of configuring certs, just the access_key and 
#          secret_key are needed.
#	 * No more arguments as tags (and no args tag)!  All args must be passed 
#          in user-data or in args- files. args in user-data are not prefixed with
#          'args:'.
# 2.1  - Look for instance "Name" as a tag if it is not specified as an argument.
# 2.2  - Download all profiles and files from files001.practicalclouds.com instead
#        of the website.  This URL is accellerated via CloudFront and backed by S3
#        so is more resilient to failure than www.practicalclouds.com, and will 
#        perform better for users with slow connection to Ireland. 
# 2.3  - Source /etc/profile so script works with systemd and Fedora 16
# 2.4  - Lookup Fedora Version from /etc/fedora-release
#        Keep re-reading INSTID at start of script until the network is available.
# 2.5  - Set the hostname to the ec2 internal hostname.
# 2.6  - Allow a Route53 domain to be added to the "Name" argument (or separate 'domain'
#        arg).  Try and add the hostname to the domain and then set the server hostname to
#        this.  This uses the python tool - 'boto'.
# 2.7  - Patching of systemd 'reboot', 'halt', 'poweroff' and 'shutdown' services so that
#        they first /usr/local/bin/deregister_dns.sh to deallocate their IP address from Route53
#        (if one was added, see 2.6).
# 2.8  - Lowercase the Name argument - capitals in hostnames make no sense.
# 2.9  - Emergency fix for broken AMIs.  Added setting of an external DNS record using
#        the exthostname argument.
# 2.10 - Restart sshd after setting the hostname
# 2.11 - First pass at allowing Centos rather than Fedora.
# 2.12 - Clean up the Route53 code and fix so that DNS removal works on CentOS as well
#        as Fedora (code moved into the function add_Route53).
# 2.13 - Load the puppet profile by default!  We want all instances to boot with the puppet
#        client.  This is to start the migration from shell scripts to puppet.
# 2.14 - Integrate Puppet into core.  It is expect to be a part of the AMI. 
#        There is a choice on how to apply puppet data.  Either load up the modules and then
#        apply a manifest or manifests or point the puppet agent at a puppet server.  You could
#        do a combination of the two if you so desire.
#	   * puppet modules can be loaded by adding the "modules" argument
#	     which can download them from bootbucket, pclouds-cloudfront or PuppetForge
#	   * when a manifest is included with "---puppet" delimiters n the user-date then it is applied.	
#          * apply manifests (from bootbucket) specified with the manifest= argument.
#          * when puppetserver is specified then a puppet agent is started
# 2.15 - Change the DNS clean up mechanism.  Multliple scripts can be added to 
#          /etc/rc.d/init.d/pclouds-cleanup
#          and they will be run before the rest of the shutdown proceeds.
# 2.16 - Finally, I see the light at the end of the tunnel.  Created a systemd service
#        called cleanup.service, (much like centos) which is tied to the network and so 
#        runs at shutdown before the network stops.
# 2.16.1 - Add the - back into the appended number for Route53 DNS domains that clash
#        It needs something to distinguish between the apended number and the name.
# 2.17 - Add support for loading a puppet module from the practicalclouds website before
#        trying to download it from puppetforge. Fix puppet apply command.
# 2.18 - Copy aws to /usr/bin before running install!  Prevent all of the symlinks 
#        to /etc/bootstrap.d
# 2.19 - Add /root/.fog credentials by default if we have an access key and 
#        secret key

# The www.practicalclouds.com bootstrap process
# for futher details please visit the website
# 
# This script will be executed *after* all the other init scripts.
# You can put your own initialization stuff in here if you don't
# want to do the full Sys V style init stuff.
#
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

. /etc/profile

touch /var/lock/subsys/local

prog=$(basename $0)
logger="logger -t $prog"

# Create bootstrap.d directory
mkdir -p /etc/bootstrap.d
chmod 700 /etc/bootstrap.d

# set up root's shell environment
if [[ ! -f "/root/.bash_profile" ]]; then
	cat >/root/.bash_profile <<EOT
# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
	. ~/.bashrc
fi

# User specific environment and startup programs

PATH=\$PATH:\$HOME/bin

export PATH
EOT
fi 
chmod 600 /root/.bash_profile

if [[ ! -f "/root/.bashrc" ]]; then
	cat >/root/.bashrc <<EOT
# .bashrc

# User specific aliases and functions

alias syslog="tail -f /var/log/messages"

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi
EOT
fi
chmod 600 /root/.bashrc

SYSLOG=`grep "alias syslog=\"tail -f /var/log/messages\"" /root/.bashrc`
if [[ "$SYSLOG" == "" ]]; then
	echo "alias syslog=\"tail -f /var/log/messages\"" >>/root/.bashrc
fi

if [[ -f "/etc/fedora-release" ]]; then
	OS_NAME="Fedora"
	OS_VERSION=`cat /etc/fedora-release | head -1 | awk '{print $3}'` 
elif [[ -f "/etc/centos-release" ]]; then
	OS_NAME="CentOS"
	OS_VERSION=`cat /etc/centos-release | head -1 | awk '{print $3}'` 
fi
ARCH=`uname -i`

$logger "This is $OS_NAME $OS_VERSION"
$logger "Running rc.local version $PROFILE_VERSION"

echo "" >/etc/motd
echo -e "\033[0;34mPractical Clouds\033[0;38m - \033[0;35m$OS_NAME $OS_VERSION $ARCH AMI\033[0;38m" >>/etc/motd
echo "" >>/etc/motd
echo -e "\033[0;31mWarning:  This EC2 instance is still booting, or the boot process\033[0;38m" >>/etc/motd
echo -e "\033[0;31mhas failed.  Certain features and software are unavailabe.\033[0;38m" >>/etc/motd
echo -e "\033[0;31mType 'syslog' to follow the progress (/var/log/messages).\033[0;38m" >>/etc/motd
echo "" >>/etc/motd
echo -e "\033[0;38mWe recommend that you log out and back in again, once the boot completes.\033[0;38m" >>/etc/motd
echo "" >>/etc/motd
echo -e "\033[0;38mBoot Progress:\033[0;38m" >>/etc/motd
echo -e "\033[0;34m0. System Boot\033[0;38m" >>/etc/motd

# remove any old files
for INFO in /etc/AWS-NAME /etc/AWS-PLATFORM /etc/AWS-INSTID /etc/AWS-AVZONE /etc/AWS-PROFILES
do
        if [ -f "$INFO" ]
        then
                rm -f $INFO
        fi
done

# Check/wait for the network is available and find out essential information...

INSTID=`curl -s -m 5 --fail http://169.254.169.254/latest/meta-data/instance-id|tr '[A-Z]' '[a-z]'`
while [[ "$INSTID" == "" ]]; do
	$logger "Network is not available yet.":q!
	sleep 5
	INSTID=`curl -s -m 5 --fail http://169.254.169.254/latest/meta-data/instance-id|tr '[A-Z]' '[a-z]'`
done
echo $INSTID >/etc/AWS-INSTID
$logger "I'm Instance $INSTID"

AVZONE=`curl -s --fail http://169.254.169.254/latest/meta-data/placement/availability-zone|tr '[A-Z]' '[a-z]'`
if [[ "$AVZONE" != "" ]]; then
        echo $AVZONE >/etc/AWS-AVZONE
        $logger "I'm in $AVZONE"
fi

#  Now set up the ssh keys...

$logger "Configuring SSH Key-Pair"
echo -e "\033[0;34m1. Configuring SSH Key-Pair\033[0;38m" >>/etc/motd

public_key_url=http://169.254.169.254/1.0/meta-data/public-keys/0/openssh-key
public_key_file=/tmp/openssh_id.pub
public_key_ephemeral=/mnt/openssh_id.pub
authorized_keys=/root/.ssh/authorized_keys

# Try to get the ssh public key from instance data.
curl --silent --fail -o $public_key_file $public_key_url
test -d /root/.ssh || mkdir -p -m 700 /root/.ssh
if [ $? -eq 0 -a -e $public_key_file ] ; then
  if ! grep -s -q -f $public_key_file $authorized_keys
  then
    cat $public_key_file >> $authorized_keys
    $logger "New ssh key added to $authorized_keys from $public_key_url"
  fi
  chmod 600 $authorized_keys
  rm -f $public_key_file

# Try to get the ssh public key from ephemeral storage
elif [ -e $public_key_ephemeral ] ; then
  if ! grep -s -q -f $public_key_ephemeral $authorized_keys
  then 
    cat $public_key_ephemeral >> $authorized_keys
    $logger "New ssh key added to $authorized_keys from $public_key_ephemeral"
  fi
  chmod 600 $authorized_keys
  chmod 600 $public_key_ephemeral
fi

$logger "Configuring AWS Script"
echo -e "\033[0;34m2. Configuring AWS Script\033[0;38m" >>/etc/motd

# Make sure that the AWS Script is installed
#check aws is installed
if [[ ! -s "/usr/bin/aws" ]]; then
        for ATTEMPT in $AWSDOWNLOAD; do
                $logger "Downloading Tim Kay's AWS from $ATTEMPT..."
                curl -s -m 20 -o /etc/bootstrap.d/aws $ATTEMPT
                if [[ -s "/etc/bootstrap.d/aws" ]]; then
                        $logger "Installing AWS."
			cp /etc/bootstrap.d/aws /usr/bin
                        perl /usr/bin/aws --install
                        break
                fi
        done
fi

# a helper function that reads a string and creates a bunch of 
# files in /etc/bootstrap.d which will be read when requested.
function explode_args {
        while [[ "$1" != "" ]]; do
                if [[ "$1" =~ .*= ]]; then
                        VARNAME=${1%%=*}
                        VARVAL=${1#*=}
                else
                        VARNAME=$1
                        VARVAL="true"
                fi
		echo "$VARVAL" >/etc/bootstrap.d/arg-$VARNAME
                shift
        done
}

# first check for the main args we need in the user-data, ignore everything from a line starting ---
UDARGS=`curl -s http://169.254.169.254/latest/user-data | sed -e 's/^args[ ]*:[ ]*//' | awk 'BEGIN{printit=1}($1 ~ /^---/){printit=0;getline} (printit == 1){print}'`
if [[ "$UDARGS" != "" ]]; then
        $logger "I found the following args in user-data: $UDARGS"
        eval explode_args $UDARGS
fi

AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
PLATFORM=""

[[ -s "/etc/bootstrap.d/arg-access_key" ]] && AWS_ACCESS_KEY_ID=`cat /etc/bootstrap.d/arg-access_key`
[[ -s "/etc/bootstrap.d/arg-secret_key" ]] && AWS_SECRET_ACCESS_KEY=`cat /etc/bootstrap.d/arg-secret_key`
[[ -s "/etc/bootstrap.d/arg-platform" ]] && PLATFORM=`cat /etc/bootstrap.d/arg-platform`

# Try and get the access keys from files in /etc/bootstap-default if not set in user-data.
if [[ "$AWS_ACCESS_KEY_ID" == "" ]]; then
	if [[ "$PLATFORM" != "" ]]; then
      		[[ -s "/etc/bootstrap-default/arg-${PLATFORM}-access_key" ]] && AWS_ACCESS_KEY_ID=`cat /etc/bootstrap-default/arg-${PLATFORM}-access_key`
	fi
        if [[ "$AWS_ACCESS_KEY_ID" == "" ]]; then
        	[[ -s "/etc/bootstrap-default/arg-access_key" ]] && AWS_ACCESS_KEY_ID=`cat /etc/bootstrap-default/arg-access_key`
        fi
fi

if [[ "$AWS_ACCESS_KEY_ID" != "" ]]; then
        $logger "access_key obtained"
else
        $logger "No access_key"
fi

if [[ "$AWS_SECRET_ACCESS_KEY" == "" ]]; then
        if [[ "$PLATFORM" != "" ]]; then
                [[ -s "/etc/bootstrap-default/arg-${PLATFORM}-secret_key" ]] && AWS_SECRET_ACCESS_KEY=`cat /etc/bootstrap-default/arg-${PLATFORM}-secret_key`
	fi
        if [[ "$AWS_SECRET_ACCESS_KEY" == "" ]]; then
         	[[ -s "/etc/bootstrap-default/arg-secret_key" ]] && AWS_SECRET_ACCESS_KEY=`cat /etc/bootstrap-default/arg-secret_key`
        fi
fi

if [[ "$AWS_SECRET_ACCESS_KEY" != "" ]]; then
        $logger "secret_key obtained"
else
        $logger "No secret_key"
fi

if [[ "$AWS_ACCESS_KEY_ID"  == "" || "$AWS_SECRET_ACCESS_KEY" == "" ]]; then
	$logger "I can't access AWS API functions or S3 without access keys!"
else 
	# Here we are setting up credentials files for the three different
	# AWS APIs/Command line tools, aws, boto and fog
	# We should try to phase others out in favour of just one.
	# FOG seems to most likely candidate to me at present.

	# Write the .awsecret file
	echo "$AWS_ACCESS_KEY_ID" >/root/.awssecret
	echo "$AWS_SECRET_ACCESS_KEY" >>/root/.awssecret
	chmod 600 /root/.awssecret
	# Write the .fog file
	cat >/root/.fog <<EOT
:default:
  :aws_access_key_id: $AWS_ACCESS_KEY_ID
  :aws_secret_access_key: $AWS_SECRET_ACCESS_KEY
EOT
	chmod 600 /root/.fog
	# export these for use with boto (for Route53)
	export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
fi

$logger "Configuring Bootbucket"
echo -e "\033[0;34m3. Configuring Bootbucket\033[0;38m" >>/etc/motd

BOOTBUCKET=""
[[ -s "/etc/bootstrap.d/arg-bootbucket" ]] && BOOTBUCKET=`cat /etc/bootstrap.d/arg-bootbucket`

if [[ "$BOOTBUCKET" == "" ]]; then
	if [[ "$PLATFORM" != "" ]]; then	
                [[ -s "/etc/bootstrap-default/arg-${PLATFORM}-bootbucket" ]] && BOOTBUCKET=`cat /etc/bootstrap-default/arg-${PLATFORM}-bootbucket`
	fi
        if [[ "$BOOTBUCKET" == "" ]]; then
        	[[ -s "/etc/bootstrap-default/arg-bootbucket" ]] && BOOTBUCKET=`cat /etc/bootstrap-default/arg-bootbucket`
        fi
	if [[ "$BOOTBUCKET" == "" ]]; then
		$logger "No bootbucket specified, I can't look in S3 for boot files and profiles"
	fi
fi

# check if S3 access actually works!
SOK=""
if [[ "$BOOTBUCKET" != "" && "$AWS_ACCESS_KEY_ID" != "" && "$AWS_SECRET_ACCESS_KEY" != "" ]]; then
	$logger "Checking Access to bootbucket..."
	RESULT=`aws --simple ls $BOOTBUCKET`
	if [[ "$?" == "0" ]]; then
		SOK="ok"
		$logger "Bootbucket ok"
		echo "$BOOTBUCKET" >/etc/AWS-BOOTBUCKET
	else
		SOK=""
		$logger "ERROR: Bootbucket not available"
		$logger "ERROR: $RESULT"
	fi
fi

# load the bootstrap-functions2

$logger "Loading the bootstrap-functions2"
echo -e "\033[0;34m4. Loading the bootstrap-functions2\033[0;38m" >>/etc/motd

if [[ "$SOK" == "ok" ]]; then
	$logger "Looking for bootstrap-functions2 in \"$BOOTBUCKET\"..."
	RESULT=`aws get $BOOTBUCKET/bootstrap-functions2 /etc/bootstrap.d 2>&1`
	if [[ "$?" == "0" ]]; then
		$logger "bootstrap-functions2 loaded from $BOOTBUCKET ok"
	else
		$logger "I couldn't download the bootstrap-functions2 from $BOOTBUCKET!"
		$logger "ERROR: $RESULT"
	fi
else
	$logger "Do not look in s3 for bootstrap-functions2"
fi
if [ ! -s "/etc/bootstrap.d/bootstrap-functions2" ]; then
        if [ -e "/etc/bootstrap-default/bootstrap-functions2" ]; then
                cp /etc/bootstrap-default/bootstrap-functions2 /etc/bootstrap.d
                $logger "Copied default bootstrap-functions2 from /etc/bootstrap-default/bootstrap-functions2"
        else
                $logger "Still no bootstrap-functions2, try to download from web..."
                cd /etc/bootstrap.d
                curl -s -o /etc/bootstrap.d/bootstrap-functions2 --fail http://$WEBPROFILES/bootstrap-functions2
        	if [ ! -s "/etc/bootstrap.d/bootstrap-functions2" ]; then
                	$logger "SERIOUS PROBLEM: I can't find any bootstrap-functions2 anywhere!  Sorry, I can't continue without them."
                	echo "SERIOUS PROBLEM: I can't find any bootstrap-functions2 anywhere!  Sorry, I can't continue without them." >>/etc/motd
                	exit 1
		fi
        fi
fi

#link to /etc/bootstrap-functions for old profiles
ln -s /etc/bootstrap.d/bootstrap-functions2 /etc/bootstrap.d/bootstrap-functions

# Load the functions so we can use them
. /etc/bootstrap.d/bootstrap-functions2

# Now that we have loaded the bootstrap fuctions we can start using its functions.
# We want to first explode any arguments which are set in a file using the argsfile
# argument.  This is only possible if S3 access is available.  

ARGSFILE=`read_arg -n argsfile`
if [[ "$ARGSFILE" != "" ]]; then
	if [[ "$SOK" == "ok" ]]; then
                $logger "Retrieving arguments file: $ARGSFILE"
                get_file -f $ARGSFILE
                LOCALFILE=`basename $ARGSFILE`
                if [ -s "/etc/bootstrap.d/$LOCALFILE" ]; then
                        AFARGS=`cat /etc/bootstrap.d/$LOCALFILE`
                        eval explode_args $AFARGS
                else
                        $logger "I couldn't retrieve the arguments file, sorry!"
                fi
        else
                $logger "ERROR: Sorry, I can't load argsfile \"$ARGSFILE\" without access to S3!"
        fi
else
	$logger "No \"argsfile\" has been requested."
fi

# Now we can find out about our name and platform and set a decent prompt

$logger "Setting up system prompt"
echo -e "\033[0;34m5. Setting up system name and prompts\033[0;38m" >>/etc/motd

# Read a Name for our instance and work out a domain if possible
NAME=`read_arg -n Name -set|tr '[A-Z]' '[a-z]'`
DOMAIN=""
if [[ "$NAME" != "" ]]; then
	# Workout the shortname and domain
	if [[ "$NAME" =~ \. ]]; then
        	SHORTNAME=${NAME%%.*}
        	DOMAIN=${NAME#*.}
	else
        	SHORTNAME="$NAME"
        	DOMAIN=`read_arg -n domain`
	fi
fi
EXTHOSTNAME=`read_arg -n externaldns`

# Lookup the internal ip address of the instance
INTIP=`curl -s --fail http://169.254.169.254/latest/meta-data/local-ipv4`
EXTIP=`curl http://169.254.169.254/latest/meta-data/public-ipv4`
AWSHOSTNAME=`curl -s --fail http://169.254.169.254/latest/meta-data/hostname`
EXTAWSNAME=`curl http://169.254.169.254/latest/meta-data/public-hostname`

$logger "Adding the run_cleanup service to perform tasks at shutdown, power-off etc.."
mkdir -p /etc/rc.d/init.d/pclouds-cleanup
# create the clean up service...
if [[ ! -s "/etc/rc.d/init.d/run_cleanup" ]]; then
	cat >/etc/rc.d/init.d/run_cleanup <<EOT
#!/bin/bash
#
# run_cleanup
#
# chkconfig: 345 99 01 
# description: Runs at shutdown or power off and executes any
# clean up scripts it finds in /etc/rc.d/init.d/pclouds-cleanup  
# in parrallel and then wait 10 seconds before finishing.
# processname: run_cleanup
# 
prog=\$(basename \$0)
logger="logger -t \$prog"

case \$1 in
	start)	\$logger "run_cleanup stub start... noop"
		;;
	stop)  if [[ -d "/etc/rc.d/init.d/pclouds-cleanup" ]]; then
        		for SCRIPT in /etc/rc.d/init.d/pclouds-cleanup/*
        		do
                		if [[ -x "\$SCRIPT" ]]; then
                        		\$logger "Running cleanup script: \$SCRIPT"              
                        		\$SCRIPT &
                		else
                        		\$logger "cleanup: \$SCRIPT is not executable"
                		fi
        		done
		else
        		\$logger "No cleanup scripts found."
		fi

		# wait for children to complete
		\$logger "Waiting for children to complete"
		wait
		\$logger "Waiting 10 seconds"
		sleep 10
		\$logger "Finished the cleanup"
		;;
	*)	\$logger "Sorry! I don't know how to \\"\$1\\""
	   	exit 1
		;;
esac

EOT
	chmod 700 /etc/rc.d/init.d/run_cleanup
fi
# Make sure it runs at power off, reboot, shutdown...
# Add lock file so that a kill is attempted.
mkdir -p /var/lock/subsys
touch /var/lock/subsys/run_cleanup

# make compat with Fedora and CentOS
# Fedora16 uses systemd whereas CentOS uses regular Sysinit V5.
case $OS_NAME in
	Fedora)         # Create and execute the clean up service in systemd
			$logger "Creating the systemd cleanup.service."
			cat >/etc/systemd/system/cleanup.service <<EOT
#  This file is part of systemd.
#
#  systemd is free software; you can redistribute it and/or modify it
#  under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.

[Unit]
Description=Practical Clouds CleanUp Service
DefaultDependencies=yes
Requires=network.target
After=network.target

[Service]
Type=forking
RemainAfterExit=yes
TimeoutSec=0
ExecStart=/etc/rc.d/init.d/run_cleanup start
ExecStop=/etc/rc.d/init.d/run_cleanup stop
EOT
			
                        systemctl daemon-reload
                        systemctl start cleanup.service
                        ;;
	CentOS)         chkconfig --add run_cleanup
                        ;;
esac
# DONE - now add scripts to /etc/rc.d/init.d/pclouds-cleanup that you want to run at shutdown, poweroff etc..

# Function: add_Route53 FQDN IP
# This function tries to add a FQDN to a Route53 managed DNS Zone.
function add_Route53 {
	local FQDN="$1"
	local IP="$2"
	local SETHOSTNAME="$3"
	local SHORTNAME=""
	local DOMAIN=""
	local APPEND=""
	local INUSE=""
	local TEMPS=""
	local SHUTSERVICE=""
	
	# Work out shortname and domain from the FQDN
	DOMAIN=${FQDN#*.}
	SHORTNAME=${FQDN%%.*}

        # check that we have access to Route 53 by looking up the ZoneID
        local ZONEID=`/usr/bin/route53 ls | awk '($2 == "ID:"){printf "%s ",$3;getline;printf "%s\n",$3}' | grep $DOMAIN | awk '{print $1}'`
        if [[ "$ZONEID" != "" ]]; then
                # add our new host record to the zone
                # first, make sure that our hostname isn't already taken.
                # find next available name by appending a number 
                # eg web1, web2, web3 etc.
                APPEND=0
                INUSE=`host $FQDN`
                while [[ "$?" == "0" ]]
                do
                        APPEND=$((APPEND + 1))
                        INUSE=`host ${SHORTNAME}${APPEND}.${DOMAIN}`
                done
                if [[ "$APPEND" != "0" ]]; then
                        # set the new fqdn hostname and shortname
                        FQDN="${SHORTNAME}-${APPEND}.${DOMAIN}"
                        SHORTNAME="${SHORTNAME}-${APPEND}"
                fi

                # Add the DNS record
                RESULT=`/usr/bin/route53 add_record $ZONEID $FQDN A $IP | grep "PENDING"`
                if [[ "$RESULT" == "" ]]; then
                        fatal_error "Sorry, I could add my hostname to Route53 : $FQDN IN A $IP"
			return 1
                else
                        $logger "I successfully added DNS record $FQDN IN A $IP"

                        # add a shutdown script to remove the dns entry on shutdown
			cat >/etc/rc.d/init.d/pclouds-cleanup/remove_${FQDN} <<EOT
#!/bin/bash
#
# remove_$FQDN

/usr/bin/wall "Removing DNS $FQDN..."
logger -t remove_$FQDN "Removing DNS $FQDN..."
export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
/usr/bin/route53 del_record $ZONEID $FQDN A $IP
EOT
                        chmod 700 /etc/rc.d/init.d/pclouds-cleanup/remove_${FQDN}

			# update the DNS search path in resolv.conf and dhcp
			TEMPS=`cat /etc/resolv.conf | grep "search.*$DOMAIN"`
			if [[ "$TEMPS" == "" ]]; then
				sed -e 's/^search/search '$DOMAIN' /' -i /etc/resolv.conf
			fi
			# update dhcp in case we update our lease
			# check if there is a supersede line in dhclient.conf
			TEMPS=`grep "supersede domain-name" /etc/dhclient.conf`
			if [[ "$TEMPS" == "" ]]; then
				echo "supersede domain-name \"${DOMAIN}\" ;" >>/etc/dhclient.conf
			else
				# only add to existing line if not already present.
				TEMPS=`grep "supersede domain-name.*$DOMAIN"`
				if [[ "$TEMPS" == "" ]]; then
					sed -e 's/^supersede domain-name "\(.*\)"\s*;/supersede domain-name "\1 '$DOMAIN'" ;/' -i /etc/dhclient.conf
				fi
			fi

			if [[ "$SETHOSTNAME" == "sethostname" ]]; then
		                hostname $SHORTNAME.$DOMAIN
                		service sshd restart

                		# update the DNS search path in resolv.conf and dhcp
                		sed -e 's/^domain.*/domain '$DOMAIN'/' -i /etc/resolv.conf
                	fi
		fi
        else
                fatal_error "Sorry, I can't find/access the zone $DOMAIN"
		return 1
        fi
}

# Lets try to add our internal hostname to Route53
if [[ "$SHORTNAME" == "" || "$DOMAIN" == "" || "$INTIP" == "" ]]; then
	$logger "We need a hostname and domain in order to create a Route53 DNS Record"
else
	add_Route53 "$SHORTNAME.$DOMAIN" $INTIP sethostname
fi

# also add an external hostname to Route53 if one has been provided.
if [[ "$EXTHOSTNAME" != "" && "$EXTIP" != "" ]]; then
	add_Route53 $EXTHOSTNAME $EXTIP
fi

# Set the name for the system prompt.
if [[ "$SHORTNAME" != "" ]]; then
	echo $SHORTNAME >/etc/AWS-NAME
fi

# if still default hostname, set it to the AWS hostname
CHECKHOSTNAME=`hostname`
if [[ "$CHECKHOSTNAME" == "localhost.localdomain" ]]; then
	$logger "Setting the hostname to the amazon aws hostname: $AWSHOSTNAME"
	hostname $AWSHOSTNAME
	service sshd restart
fi	

# Try and read the platform from the arguments...
if [[ "$PLATFORM" == "" ]]; then
	PLATFORM=`read_arg -n platform -set`
fi
if [[ "$PLATFORM" != "" ]]; then
       	echo $PLATFORM >/etc/AWS-PLATFORM
fi

cat >/etc/profile.d/aws-prompt.sh  <<EOT
#Set colour prompt using the name, platform or instance id and avzone

if [ -f "/etc/AWS-INSTID" ]; then
	export INSTID=\`cat /etc/AWS-INSTID\`
else
	export INSTID=\`curl -s --fail http://169.254.169.254/latest/meta-data/instance-id\`
fi
if [ -f "/etc/AWS-AVZONE" ]; then
	export AVZONE=\`cat /etc/AWS-AVZONE\`
else
	export AVZONE=\`curl -s --fail http://169.254.169.254/latest/meta-data/placement/availability-zone\`
fi
PLATFORM=""
if [ -f "/etc/AWS-PLATFORM" ]; then
	PLATFORM=\`cat /etc/AWS-PLATFORM\`
fi
NAME=""
if [ -f "/etc/AWS-NAME" ]; then
	NAME=\`cat /etc/AWS-NAME\`
fi

# Define colours
RED=31
GREEN=32
ORANGE=33
BLUE=34
PURPLE=35
CYAN=36

# Use NAME and PLATFORM if defined - otherwise use the instance ID
# or the availability zone.  Set the platform colour according to the
# platform.

if [[ "\$NAME" == "" ]]; then
	NAME=\$INSTID
fi
export NAME

if [[ "\$PLATFORM" != "" ]]; then
	PLAT=\`echo \$PLATFORM | tr '[a-z]' '[A-Z]'\`
	case \$PLAT in
		TEST*|STAGE*)	PLATCOL=\$GREEN
			NAMECOL=\$CYAN
			;;
		UAT*|PREPROD*)	PLATCOL=\$ORANGE
			NAMECOL=\$PURPLE
			;;
		LIVE*|PROD*)	PLATCOL=\$RED
			NAMECOL=\$BLUE
			;;
		*)	PLATCOL=\$BLUE
			NAMECOL=\$GREEN
			;;
	esac
else
	PLAT=\$AVZONE
	PLATCOL=\$CYAN
	NAMECOL=\$ORANGE
fi
export PLAT
export PLATCOL
export NAMECOL

case \$TERM in
    vt100)
      PS1="\\[\\033]0;\$PLAT-\$NAME\\007\\]\\[\\033[0;\${PLATCOL}m\\]\$PLAT\\[\\033[0;38m\\]-\\[\\033[0;\${NAMECOL}m\\]\$NAME\\[\\033[0;38m\\] [\\u:\\W]\$ "
      ;;
    xtermc)
      export TERM=xterm
      PS1="\\[\\033]0;\$PLAT-\$NAME\\007\\]\\[\\033[0;\${PLATCOL}m\\]\$PLAT\\[\\033[0;38m\\]-\\[\\033[0;\${NAMECOL}m\\]\$NAME\\[\\033[0;38m\\] [\\u:\\W]\$ "
      ;;
    xterm*)
      PS1="\\[\\033]0;\$PLAT-\$NAME\\007\\]\\[\\033[0;\${PLATCOL}m\\]\$PLAT\\[\\033[0;38m\\]-\\[\\033[0;\${NAMECOL}m\\]\$NAME\\[\\033[0;38m\\] [\\u:\\W]\$ "
      ;;
    *)
      PS1="[\\u@$INSTID \\W]\$ "
      ;;
esac
shopt -s checkwinsize
[ "\$PS1" = "\\\\s-\\\\v\\\\\\\$ " ] && PS1="[\\u@\\h \\W]\\\\\$ "
export PS1
EOT

# Let's run some bootstrap scripts to customise the instance with choices made when launching.
# Each server will attempt to load in this order
#	* common.sh - commands common to every instance
#	* $PLATFORM.sh - a script corresponding to the name of the platform
#	* ($PROFILES).sh - the list of profiles as supplied by the 'profiles' arg when starting the instance
#
# The profiles can be loaded from the bootbucket in s3 or from /etc/default-bootstrap

$logger "Loading Profiles: -"
echo -e "\033[0;34m6. Loading Profiles\033[0;38m" >>/etc/motd

PROFILES=`read_arg -n profiles`
if [[ "$PROFILES" != "" ]]; then
        echo $PROFILES >/etc/AWS-PROFILES
        $logger "Looking for the following profiles: common $PLATFORM $PROFILES"
else
	PROFILES=`read_arg -n profile`
	if [[ "$PROFILES" != "" ]]; then
        	echo $PROFILES >/etc/AWS-PROFILES
        	$logger "Looking for the following profiles: common $PLATFORM $PROFILES"
	else
		# Auto profile.
		# we still don't have a profile - look at the name of the manifest
		# if the last part of the manifest name is __profile=xyz, then select profile xyz
		RESULT=`curl -s http://169.254.169.254/latest/meta-data/ami-manifest-path | grep "__profile="`
		if [[ "$RESULT" != "" ]]; then
			PROFILES=${RESULT##*__profile=}
        		echo $PROFILES >/etc/AWS-PROFILES
			$logger "No profiles explicity set, running profile from AMI manifest name: $PROFILES"
		fi
	fi
fi

for PROFILE in common $PLATFORM $PROFILES
do
	get_file -f profile-${PROFILE}.sh
	if [ ! -s "/etc/bootstrap.d/profile-${PROFILE}.sh" ]; then
		$logger "Can't find the profile $PROFILE, checking web profiles..."
		cd /etc/bootstrap.d
		curl -s -O --fail http://$WEBPROFILES/profile-${PROFILE}.sh
	fi
	if [ -s "/etc/bootstrap.d/profile-${PROFILE}.sh" ]; then
		$logger "Bootstrapping profile: $PROFILE"
		chmod 700 /etc/bootstrap.d/profile-${PROFILE}.sh
		echo -e "\033[0;34m> $PROFILE\033[0;38m" >>/etc/motd	
		$logger "Running /etc/bootstrap.d/profile-${PROFILE}.sh."	
		/etc/bootstrap.d/profile-${PROFILE}.sh 2>&1 >/var/log/profile-${PROFILE}.out
		$logger "Finished /etc/bootstrap.d/profile-${PROFILE}.sh."	
	else
		$logger "I can't find the profile $PROFILE, ignoring!"
	fi
done

##############################################################################################
# PUPPET

# Add a second stage puppet boot - this could/should/will eventually replace the bash profiles.
$logger "Puppet Boot: -"
echo -e "\033[0;34m7. Puppet Boot\033[0;38m" >>/etc/motd

mkdir -p /etc/puppet
# optionally read the puppet config
PUPPETCONFIG=`read_arg -n pupconf`
if [[ "$PUPPETCONFIG" == "" ]]; then
        $logger "Creating a default puppet config"
        #puppetmasterd --genconfig >/etc/puppet/puppet.conf
        echo "[agent]" >/etc/puppet/puppet.conf
        if [[ "$PUPPETSERVER" != "" ]]; then
                $logger "This puppet agent will connect to server: $PUPPETSERVER"
                echo "    server = $PUPPETSERVER" >>/etc/puppet/puppet.conf
        fi
        echo "    puppetport = $PUPPETPORT" >>/etc/puppet/puppet.conf
        echo "    pluginsync = true" >>/etc/puppet/puppet.conf
        echo "    pluginsource = puppet://\$server/plugins/" >>/etc/puppet/puppet.conf
        echo "    reportserver = \$server " >>/etc/puppet/puppet.conf
        echo "    report_server = \$server " >>/etc/puppet/puppet.conf
        echo "    inventory_server = \$server " >>/etc/puppet/puppet.conf
        echo "    ca_server = \$server " >>/etc/puppet/puppet.conf
        echo "    pidfile = /var/run/puppet/agent.pid" >>/etc/puppet/puppet.conf
else
        load_data -s $PUPPETCONFIG -d /etc/puppet
fi

# function load_puppet_module
# try to load the named module, $1 from the bootbucket, pclouds-cloudfront or using puppet-module.
function load_puppet_module {
	local MODULENAME=$1
	local FOUND=""
	local BUCKET=""
	local RESULT=""
	local ESCAPED=""

	$logger "Trying to load the puppet module \"$MODULENAME\"..."

	#look for the file in the bootbucket (if more than one than match the first found).
	# and then look in the practicalclouds cloudfront bucket.
	for BUCKET in $BOOTBUCKET pclouds-cloudfront
	do
		FOUND=`aws --simple --secrets-file=/root/.awssecret ls $BUCKET | awk "(\\\$3 ~ /^$MODULENAME/){print \\\$3} | head -1"`
		if [[ "$FOUND" != "" ]]; then
			load_data -s $FOUND -d /etc/puppet/modules/$MODULENAME
			if [[ "$?" != "0" ]]; then
				fatal_error "Failed to load puppet module $MODULENAME from s3://$BUCKET/$FOUND."
				return 1
			else
				$logger "Successfully loaded $MODULENAME from s3://$BUCKET/$FOUND"
				return 0
			fi
		else
			$logger "\"$MODULENAME\" not found in the $BUCKET"
		fi
	done

	# Try loading the module directly from practicalclouds.com
	DEST="/etc/puppet/modules"
	cd $DEST
	curl -s -O --fail http://$WEBPROFILES/$MODULENAME
        if [[ "$?" == "0" ]]; then
                # how do I extract it?
                case $MODULENAME in
                        *.tar)          LDEXTRACTCMD="--transform \"s,${DEST#/},,\" -xpf"
                                        ;;
                        *.tar.gz)       LDEXTRACTCMD="--transform \"s,${DEST#/},,\" -xpzf"
                                        ;;
                        *.tgz)          LDEXTRACTCMD="--transform \"s,${DEST#/},,\" -xpzf"
                                        ;;
                        *.tar.bz2)      LDEXTRACTCMD="--transform \"s,${DEST#/},,\" -xpjf"
                                        ;;
                        *.tar.xz|*.tar.lzma)    LDEXTRACTCMD="--lzma --transform \"s,${DEST#/},,\" -xpf"
                                        INSTALLED=`rpm -qa xz-lzma-compat`
                                        if [[ "$INSTALLED" == "" ]]; then
                                                $logger "Installing lzma (.xv) archive support..."
                                                yum -y install lzma
                                        fi
                                        ;;
                        *.tar.lz)       LDEXTRACTCMD="--lzip --transform \"s,${DEST#/},,\" -xpf"
					INSTALLED=`rpm -qa lzip`
                                        if [[ "$INSTALLED" == "" ]]; then
                                                $logger "Installing lzip (.lz) archive support..."
                                                yum -y install lzip
                                        fi
                                        ;;
                        *)              $logger "Error! I couldn't work out what sort of archive $MODULENAME is!"
                                        rm -f $DEST/$MODULENAME
                                        return 1
                                        ;;
                esac
                $logger "Extracting puppet module"
                eval tar $LDEXTRACTCMD $MODULENAME
                if [[ "$?" != "0" ]]; then
                        $logger "extract failed : tar $LDEXTRACTCMD $MODULENAME"
                        rm -f $MODULENAME
                        return 1
                else
                        rm -f $MODULENAME
                fi
		return 0
        else
                $logger "I couldn't download $MODULENAME from $WEBPROFILES"
                return 1
        fi
	

	# finally try puppet-module to load the required module	from PuppetForge
	# select the first one if multiple found.
	ESCAPED=`echo $MODULENAME | sed -e 's/\//\\\//g'`
	FOUND=`puppet-module search $MODULENAME | awk "(\\\$1 ~ /$ESCAPED/){print \\\$1}" | head -1` 
	if [[ "$FOUND" != "" ]]; then
		$logger "Loading puppet module \"$MODULENAME\", from PuppetForge: $FOUND"
		cd /etc/puppet/modules
		RESULT=`puppet-module install $FOUND`
		if [[ "$?" != "0" ]]; then
			fatal_error "I failed to load \"$FOUND\" from PuppetForge: $RESULT"
			return 1
		else
			$logger "Successfully loaded \"$MODULENAME\" from PuppetForge: $FOUND"
			return 0
		fi
	else
		$logger "I could not load \"$MODULE\" name from PuppetForge."
	fi

	fatal_error "I could not load the requested puppet module: $MODULENAME"
	return 1
}

# load any modules that have been requested by modules argument.
mkdir -p /etc/puppet/modules
PUPPETMODULES=`read_arg -n pupmod`
if [[ "$PUPPETMODULES" != "" ]]; then
	for MODULE in $PUPPETMODULES; do
		load_puppet_module $MODULE
	done
else
	$logger "No pupmod: Not loading any puppet modules."
fi

# If there is a puppet manifest in the user-data then apply it to the host.
# A manifest will be supplied within two `---puppet' delimiters.
curl -s http://169.254.169.254/latest/user-data | awk 'BEGIN{printit=0} ($1 ~ /^---puppet/ && printit == 0){printit=1;getline} ($1 ~ /^---puppet/ && printit == 1){printit=0;getline} (printit == 1){print}' >/etc/puppet/bootmanifest.pp
if [[ -s "/etc/puppet/bootmanifest.pp" ]]; then
	$logger "Applying bootmanifest supplied in user-data..."
	cat /etc/puppet/bootmanifest.pp >>/var/log/messages
	RESULT=`puppet apply --verbose /etc/puppet/bootmanifest.pp`
	if [[ "$?" != "0" ]]; then
		fatal_error "ERROR: Puppet failed failed to apply the bootmanifest!"
		$logger "ERROR: $RESULT"
	else
		$logger "Puppet successfully applied the bootmanifest"
	fi
else
	$logger "No ---puppet section in user-data"
fi

# Allow the user to run manifest/s saved in files in the bootbucket
# by specifying the manifest="a b c" argument.
PUPPETMAN=`read_arg -n pupman`
if [[ "$PUPPETMAN" != "" ]]; then
        for PMAN in $PUPPETMAN
        do
                $logger "Applying Puppet manifest in $PMAN"
                get_file -f $PMAN
                if [[ "$?" == "0" ]]; then
                        cp /etc/bootstrap.d/$PUPPETMAN /etc/puppet
                        RESULT=`puppet --verbose --no-daemonize /etc/puppet/$PMAN`
                        if [[ "$?" != "0" ]]; then
                                fatal_error "ERROR: Puppet failed failed to apply the manifest!"
                                $logger "ERROR: $RESULT"
                        else
                                $logger "Puppet successfully applied the manifest"
                        fi
                fi
        done
else
        $logger "No pupman argument: no manifests being applied."
fi

# Start a puppet agent, if we have a puppet master to connect to.
PUPPETSERVER=`read_arg -n pupserv`
PUPPETPORT=`read_arg -n pupport`

if [[ "$PUPPETSERVER" != "" ]]; then
        $logger "Configuring the puppet agent..."
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

	# make sure that the important puppet directories are properly owned by the puppet user!
	chown -R puppet:puppet /etc/puppet
	chown -R puppet:puppet /var/lib/puppet

	# Start the configured Puppet Agent
	$logger "Starting the puppet agent..."
	/sbin/service puppet start
	if [[ "$?" != "0" ]]; then
        	fatal_error "Sorry, the puppet agent failed to start!"
	fi

else
        $logger "No pupserv and pupport arguments, so not starting a puppet agent"
fi

# Configure and start the MCollective Agent
STOMPSERVER=`read_arg -n mchost`
STOMPPORT=`read_arg -n mcport`
STOMPUSER=`read_arg -n mcuser`
STOMPPASS=`read_arg -n mcpass`
STOMPPSK=`read_arg -n mcpsk`

if [[ "$STOMPSERVER" != "" && "$STOMPPORT" && "$STOMPUSER" != "" && "$STOMPPASS" != "" && "$STOMPPSK" != "" ]]; then
	$logger "Configuring and starting MCollective Agent..."
	for FILE in /etc/mcollective/client.cfg /etc/mcollective/server.cfg
        do
                if [[ -f "$FILE" ]]; then
                        sed -e 's/^plugin.psk\s*=.*$/plugin.psk = '$STOMPPSK'/' -i $FILE
                        sed -e 's/^plugin.stomp.host\s*=.*$/plugin.stomp.host = '$STOMPSERVER'/' -i $FILE
                        sed -e 's/^plugin.stomp.port\s*=.*$/plugin.stomp.port = '$STOMPPORT'/' -i $FILE
                        sed -e 's/^plugin.stomp.user\s*=.*$/plugin.stomp.user = '$STOMPUSER'/' -i $FILE
                        sed -e 's/^plugin.stomp.password\s*=.*$/plugin.stomp.password = '$STOMPPASS'/' -i $FILE
                fi
        done

        $logger "Starting MCollective agent..."
        service mcollective start
        if [[ "$?" != "0" ]]; then
                fatal_error "Sorry, MCollective failed to start!"
        fi
else
	$logger "Not starting an MCollective Agent."
fi

######################################################################################################################
# Finish up...

# Set the motd to show that we have finished booting...
echo -e "\033[0;34mPractical Clouds\033[0;38m - \033[0;35m $OS_NAME $OS_VERSION $ARCH AMI\033[0;38m" >/etc/motd
echo -e "\033[0;32mBootstrap complete. Visit http://www.practicalclouds.com for more information.\033[0;38m" >>/etc/motd
if [ -f "/etc/bootstrap.d/motd" ]; then
        cat /etc/bootstrap.d/motd >>/etc/motd
fi
echo "" >>/etc/motd

# now lets try and reduce the root users access credentials.  For example it no longer needs and
# shouldn't have access to the bootbucket files. We can override this by using a debug argument.

DEBUG=`read_arg -n debug`
if [[ "$DEBUG" == "" ]]; then
	$logger "Further Restricting the root user's EC2 and S3 access..."
	set_access -f restrictedroot-user-credentials
	if [[ $? != "0" ]]; then
		$logger "The root access could not be replaced with new credentials"
	fi

	# we remove the bootstrap.d and bootstrap-default directories for security and to
	# reclaim space on the root filesystem
	rm -rf /etc/bootstrap.d /etc/bootstrap-default
	# remove the rc.local file itself - we don't want someone to try and re-run the bootstrap
	rm -f /etc/rc.local
	$logger "Finished rc.local and removed all bootstrap files"
else
	$logger "Finished rc.local but debug was requested, not restricting root or removing bootstrap files!"
fi

