#!/bin/bash

# profile-common.sh
# Dave McCormick
PROFILE_VERSION="2.3"
PROFILE_URL="http://www.practicalclouds.com/content/guide/common"
PROFILE_DOWNLOAD="http://files001.practicalclouds.com/profile-common.sh"
MINIMUM_BOOTSTRAP_FUNCTIONS="2.0"

# please refer to the instructions on using this profile script at
# http://www.practicalclouds.com/content/guide/common

# 1.0 - initial, format ephemeral disk and set local timezone
# 1.1 - format ephemeral disk in the backgroup (don't delay
#       other profiles from running).
# 1.2 - restart crond and syslog after setting timezone
# 1.3 - Update timezone depending on region and test for fastest
#       yum mirror.  Update to use the boostrap-functions like other
#       profiles.
# 1.4 - Install vim and alias vi to it.
# 2.0 - Move to bootstap-functions version 2.0 and migrate to using
#       the CDN for files.
# 2.1 - Update: in CentOS6 the drive is xvde and not xvda
# 2.2 - Make compatible with Fedora 17 version of fdisk
# 2.3 - Fix, make sure vim continues to install after strange
#       rpm dependency issue.

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
        logger "I couldn't load the bootstrap-fuctions2, continuing..."
fi

function mount_ephemeral {
# format and mount the ephemeral disk /data
	DISK=`ls /dev/xvd* | head -1 | sed -e 's/.$//'`
	local CHECK=`fdisk -l 2>&1 | grep "Disk ${DISK}2:"`
	if [[ "$CHECK" != "" ]]; then
		$logger "Formating ${DISK}2 with an EXT4 filesystem..."
        	mkfs.ext4 ${DISK}2
        	mkdir -p /data
        	mount ${DISK}2 /data
        	$logger "Mounted ${DISK}2 as /data"
	else
		$logger "I couldn't find ${DISK}2 to format and mount!"
	fi
}

REGION=`cat /etc/AWS-AVZONE`
REGION=${REGION%?}
case $REGION in
	eu-west-1)	cp /usr/share/zoneinfo/GB /etc/localtime
			$logger "Setting timezone to /usr/share/zoneinfo/GB, because I'm in $REGION"
			;;
	us-east-1)	cp /usr/share/zoneinfo/US/Eastern /etc/localtime
			$logger "Setting timezone to /usr/share/zoneinfo/US/Eastern, because I'm in $REGION"
			;;
	us-west-1)	cp /usr/share/zoneinfo/US/Pacific /etc/localtime
			$logger "Setting timezone to /usr/share/zoneinfo/US/Pacific, because I'm in $REGION"
			;;
	ap-northeast-1)	cp /usr/share/zoneinfo/Japan /etc/localtime
			$logger "Setting timezone to /usr/share/zoneinfo/Japan, because I'm in $REGION"
			;;
	ap-southeast-1) cp /usr/share/zoneinfo/Singapore /etc/localtime
			$logger "Setting timezone to /usr/share/zoneinfo/Singapore, because I'm in $REGION"
			;;
esac
$logger "Restarting syslog and cron after timezone change."
service rsyslog restart
service crond restart

#add yum plugin so that it checks for the fastest repository mirror...
$logger "Installing yum-plugin-fastestmirror.noarch"
yum -y remove vim-minimal
yum -y install yum-plugin-fastestmirror.noarch vim sudo

# Set vim for all users
cat >/etc/profile.d/vim.sh <<EOT
if [ -n "\$BASH_VERSION" -o -n "\$KSH_VERSION" -o -n "\$ZSH_VERSION" ]; then
  # for bash and zsh, only if no alias is already set
  alias vi >/dev/null 2>&1 || alias vi=vim
fi
EOT

# format and mount the ephemeral disk to /data in background.
mount_ephemeral &

