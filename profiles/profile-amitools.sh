#!/bin/bash

# profile-amitools.sh
# Dave McCormick
PROFILE_VERSION="2.11"
PROFILE_URL="http://www.practicalclouds.com/content/guide/amitools-tools"
PROFILE_DOWNLOAD="http://files001.practicalclouds.com/profile-amitools.sh"
MINIMUM_BOOTSTRAP_FUNCTIONS="2.0"

# please refer to the instructions on using this profile script at
# http://www.practicalclouds.com/content/guide/amitools

# 1.0  - initial, install ami tools
# 1.1  - add IAM user credentials file
# 1.2  - add automatic download and unbundle of image
# 1.3  - add create of updateAMI.sh script
# 1.4  - add deregister and delete of old AMI to updateAMI.sh
# 1.5  - change to use set_access function from bootstrap-functions
# 1.6  - Support bootstrap-functions v1.11 with command line style args
# 1.7  - make amitools profile wait for /data to be mounted.
# 1.8  - support version checking and use the fatal_error function.
# 1.9  - Print download failure messages and install ruby.
#        Install from own zip using arg 'install' or get latest version
#	 Optionally install ami credentials or default to root.
# 1.10 - Download the latest amitools from amazon website unless a zip
#        file is specified by 'install' arg.
# 1.11 - Update the updateAMI.sh script to allow easy upload to alternative
#        regions.
# 1.12 - make use of s3cmd to upload the bundle parts for improved stabilty
#        and easier acls.
#        Allow aliases of an AMI to be registered with different names and
#        descriptions.  Use the amialiases arg to specify a file where the
#        aliases are defined.  The updateAMI.sh script will then automatically
#        deregister the aliases and re-register them when an AMI is updated.
#
# 2.0  - Bootstap Version 2.0 - compatible
#        The AMI tools still depend on the old tools, ec2 api tools, ec2 ami
# 	 tools, Java and s3cmd!  As we are likely to ONLY need these for creating
#        AMIs we'll re-install them as part of this profile.  The user MUST now
#        specify and 'amiusercredentials' file containing a private key, cert and
#        .s3cfg file for the profile to be able to work (we'll now abort if not).
#	 Although this seems a pain, the boot process is improved as whole by
#	 not depending on these tools for other profiles.
# 2.1 -  Profile is now loaded via files001.practicalclouds.com if not in bootbucket.
# 2.2 -  Add us-west-2 region : Oregon
# 2.3 -  Add sa-east-1 region : Sao Paulo
# 2.4 -  Updated updateAMI.sh which can upload to multiple regions in one run.
# 2.5 -  Updated updateAMI.sh to assume that the AMI arch will be in the name of the ami.
#        This is to ensure that we can have two identical AMIs but for different
#        architectures but the update of one will not lead to the removal of the other.
# 2.6 -  The ami Name will also automatically contain the name of the Operating system.
#        This is to allow Fedora16 and CentOS6.2 versions of my AMIs.  You can set the 
#        OS using the amios argument (otherwise assume the same as the booted instance).
# 2.7 -  remove the use of xml2 which is not available in CentOS6, replace with bash
#        alternative.  Rename /mnt/fedora-base to /mnt/image-base.
# 2.8 -  Zero free space first in updateAMI.sh to create smaller images.
#        Massively save space by remove the cached package before the space zero.
# 2.9 -  Make it easier to create alternate versions of an AMI to test, most references
#        which used IMAGEFILE have been replaced with MANIFEST after the bundle. Change
#	 the MANIFEST var in updateAMI.sh to create a new version which does not remove
#        the old version.
#        Also add MAKEDEV and mounts so that the image has access to the network.
# 2.10 - Allow the version of the openjdk java to change. aka. cope with Fedora 17
# 2.11 - Make sure MAKEDEV is installed.

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

# The S3 id of the "za-team", used to give permission to launch AMI
ZA_TEAM="6aa5a366c34c1cbe25dc49211496e913e0351eb0e8c37aa3477e40942ec6b97c"

# This profile installs the EC2 AMI Tools and new certs to use to update, upload and bundle new AMI images...

# load the bootstrap-functions2
if [ -s "/etc/bootstrap.d/bootstrap-functions2" ]; then
	. /etc/bootstrap.d/bootstrap-functions2
else
	logger "I couldn't load the bootstrap-fuctions2, aborting!"
	exit 1
fi

# Check and install JAVA
echo "hwcap 1 nosegneg" >/etc/ld.so.conf.d/libc6-xen.conf
ldconfig

HAVEJAVA=`which java 2>&1 | grep "no java in"`
if [[ "$HAVEJAVA" != "" ]]; then
	WHICH_JAVA=`yum list "java*openjdk*" | grep "^java.*openjdk" | head -1 | sed -e 's/openjdk.*/openjdk/'`
	$logger "Installing Java: $WHICH_JAVA"
	yum -y install $WHICH_JAVA
else
	$logger "Java already installed."
fi

# Install ruby and banner
yum -y install ruby banner MAKEDEV

# check and install EC2 API Tools
if [[ ! -d "/opt/EC2TOOLS" ]]; then
	mkdir -p /opt/EC2TOOLS
	curl -o /etc/bootstrap.d/ec2-api-tools.zip http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip
	if [[ ! -s "/etc/bootstrap.d/ec2-api-tools.zip" ]]; then
		fatal_error "ERROR:  I could not download the EC2 API Tools!"
		exit 1
	fi
	cd /etc/bootstrap.d
	unzip /etc/bootstrap.d/ec2-api-tools.zip
	cp -r /etc/bootstrap.d/ec2-api-tools-*/* /opt/EC2TOOLS
	$logger "EC2 API Tools installed to /opt/EC2TOOLS"
else 
	$logger "EC2 API Tools already installed."
fi

# check and optionally install the EC2 AMI tools...
if [[ ! -f "/opt/EC2TOOLS/bin/ec2-bundle-image" ]]; then
	$logger "Downloading EC2 AMI Tools from Amazon..."
	curl -o /etc/bootstrap.d/ec2-ami-tools.zip http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip
	if [[ ! -s "/etc/bootstrap.d/ec2-ami-tools.zip" ]]; then
		fatal_error "ERROR:  I could not download the EC2 AMI Tools!"
		exit 1
	fi
	cd /etc/bootstrap.d
	unzip ec2-ami-tools.zip
	cp -r /etc/bootstrap.d/ec2-ami-tools-*/* /opt/EC2TOOLS
	$logger "EC2 AMI Tools installed to /opt/EC2TOOLS"
else
	$logger "EC2 AMI Tools already installed."
fi

OSTYPE=`cat /etc/redhat-release | awk '{print $1}'`

# Check and install s3cmd
HAVESCMD=`which s3cmd 2>&1 | grep "no s3cmd in" `
if [[ "$HAVESCMD" != "" ]]; then
	$logger "Installing s3cmd..."
	case $OSTYPE in
		Fedora)	cat >/etc/yum.repos.d/s3tools.repo <<EOT
# 
# Save this file to /etc/yum.repos.d on your system
# and run "yum install s3cmd"
# 
[s3tools]
name=Tools for managing Amazon S3 - Simple Storage Service (Fedora_14)
type=rpm-md
baseurl=http://s3tools.org/repo/Fedora_14/
gpgcheck=1
gpgkey=http://s3tools.org/repo/Fedora_14/repodata/repomd.xml.key
enabled=1
EOT
				;;
		CentOS) cat >/etc/yum.repos.d/s3tools.repo <<EOT
# 
# Save this file to /etc/yum.repos.d on your system
# and run "yum install s3cmd"
# 
[s3tools]
name=Tools for managing Amazon S3 - Simple Storage Service (Fedora_14)
type=rpm-md
baseurl=http://s3tools.org/repo/RHEL_6/
gpgcheck=1
gpgkey=http://s3tools.org/repo/RHEL_6/repodata/repomd.xml.key
enabled=1
EOT
		;;
	esac
        yum -y install s3cmd
else
        $logger "s3cmd already installed."
fi



AMICRED=`read_arg -n amicredentials`
# get the ami user credentials
if [[ "$AMICRED" != "" ]]; then
	set_access -f $AMICRED -u root -a ami
	if [[ $? == "0" ]]; then
		ACCESS_KEY=`cat /root/.s3cfg-ami | grep "^access_key" | awk '{print $3}'`
		SECRET_KEY=`cat /root/.s3cfg-ami | grep "^secret_key" | awk '{print $3}'`
		# Use the AMI tools user credentials by default for the ec2/ami tools ...

		cat >/etc/profile.d/ec2tools.sh <<EOT
export JAVA_HOME=/usr
export EC2_HOME=/opt/EC2TOOLS
export EC2_PRIVATE_KEY="/root/.ec2/amikey.pem"
export EC2_CERT="/root/.ec2/amicert.pem"
export PATH=$PATH:/opt/EC2TOOLS/bin
EOT

		. /etc/profile.d/ec2tools.sh
	else
		fatal_error "Aborting, we can't continue without the ami user credentials sorry!"
		exit 1
	fi
else
	fatal_error "Sorry, AMI creation requires a user with keys and certificates configured.  You MUST specify an amicredentials file!"
	exit 1
fi

# Do we have a amibucket defined?
AMIBUCKET=`read_arg -n amibucket`
MANIFEST=`read_arg -n manifest`
AWSUSERNUMBER=`read_arg -n awsusernumber`
AMIOS=`read_arg -n amios`
if [[ "$AMIOS" == "" ]]; then
	AMIOS=`cat /etc/redhat-release | awk '{printf "%s %s",$1,$3}'`
fi
AMIARCH=`read_arg -n amiarch`
if [[ "$AMIARCH" == "" ]]; then
	AMIARCH=`uname -i`
fi
AMIALIASES=`read_arg -n amialiases`

if [[ "$AMIBUCKET" != "" && "$MANIFEST" != "" ]]; then
	# Do not proceed until /data has been formated and mounted.
	while [[ ! -d "/data" ]]; do
		$logger "Waiting for /data to be mounted (10 seconds until next check) ..."
		sleep 10
	done

	$logger "Downloading bundle s3://$AMIBUCKET/$MANIFEST..."
	cd /data
	if [[ "$AMICRED" != "" ]]; then
		$logger "ec2-download-bundle --bucket $AMIBUCKET --manifest $MANIFEST --access-key $ACCESS_KEY --secret-key $SECRET_KEY --privatekey /root/.ec2/amikey.pem"
		RESULT=`ec2-download-bundle --bucket $AMIBUCKET --manifest $MANIFEST --access-key $ACCESS_KEY --secret-key $SECRET_KEY --privatekey /root/.ec2/amikey.pem 2>&1`
	else
		$logger "ec2-download-bundle --bucket $AMIBUCKET --manifest $MANIFEST --access-key $ACCESS_KEY --secret-key $SECRET_KEY --privatekey /root/.ec2/mykey.pem"
		RESULT=`ec2-download-bundle --bucket $AMIBUCKET --manifest $MANIFEST --access-key $ACCESS_KEY --secret-key $SECRET_KEY --privatekey /root/.ec2/mykey.pem 2>&1`
	fi

	if [[ $? == "0" ]]; then
		$logger "Unbundling bundle /data/$MANIFEST..."
		if [[ "$AMICRED" != "" ]]; then
			ec2-unbundle --privatekey /root/.ec2/amikey.pem -m $MANIFEST 2>&1
		else
			ec2-unbundle --privatekey /root/.ec2/mykey.pem -m $MANIFEST 2>&1
		fi
		if [[ $? == "0" ]]; then
			[ -d "/mnt/image-base" ] || mkdir -p /mnt/image-base
			IMAGEFILE=`cat /data/$MANIFEST | sed -e 's/^.*<image><name>//' | sed -e 's/<\/name>.*//'`
			$logger "Mounting image file /data/$IMAGEFILE to /mnt/image-base."
			mount -o loop /data/$IMAGEFILE /mnt/image-base	
			MOUNTED=`mount | awk '($3 == "/mnt/image-base"){print}'`
			if [[ "$MOUNTED" != "" ]]; then
				$logger "Mounted ok"
			else
				$logger "Mount failed!"
			fi 
			# Add the devices so that the image can access the network...
			$logger "Adding devices so that the image can access the network"
			MAKEDEV -d /mnt/image-base/dev -x console
			MAKEDEV -d /mnt/image-base/dev -x null
			MAKEDEV -d /mnt/image-base/dev -x zero

			mount -o bind /dev /mnt/image-base/dev
			mount -o bind /dev/pts /mnt/image-base/dev/pts
			mount -o bind /dev/shm /mnt/image-base/dev/shm
			mount -o bind /proc /mnt/image-base/proc
			mount -o bind /sys /mnt/image-base/sys
		else
			$logger "I couldn't unbundle the ami image file, sorry!"
		fi
	else
		$logger "I couldn't download the ami bundle, sorry!"
		$logger "ERROR: $RESULT"
	fi
else
	$logger "Missing bucket or manifest, so I can't try and download and unbundle an image for you!"
fi

#find out region
AVZONE=`cat /etc/AWS-AVZONE`
REGION=${AVZONE%?}

# Allow us to set the AMINAME (or set to be equal the IMAGEFILE)
AMINAME=`read_arg -n aminame`
if [[ "$AMINAME" == "" && "$IMAGEFILE" != "" ]]; then
	AMINAME="$IMAGEFILE"
fi

# Allow us to set the AMIDESC (or set to be equal the IMAGEFILE)
AMIDESC=`read_arg -n amidescription`
if [[ "$AMIDESC" == "" && "$IMAGEFILE" != "" ]]; then
	AMIDESC="$IMAGEFILE"
fi

# All your ducks need to be in line for this script to be of use to you...
if [[ "$MANIFEST" != "" && "$AWSUSERNUMBER" != "" && "$ACCESS_KEY" != "" && "$SECRET_KEY" != "" && "$AMIBUCKET" != "" && "$AMIARCH" != "" && "$IMAGEFILE" != "" ]]; then
	# write an updateAMI.sh script to make bundling, uploading and re-registering easier..
	$logger "Writing updateAMI.sh script."
	cat >/data/updateAMI.sh <<EOT
#!/bin/bash

VERSION="$PROFILE_VERSION"

AMIOS="$AMIOS"
AMIARCH="$AMIARCH"
# Please specify a list of region/bucket you wish to upload to...
REGIONS="$REGION/$AMIBUCKET"
AWSUSERNUMBER="$AWSUSERNUMBER"
MANIFEST="$MANIFEST"
ACCESS_KEY="$ACCESS_KEY"
SECRET_KEY="$SECRET_KEY"
IMAGEFILE="$IMAGEFILE"
# Is it a public AMI (TRUE), default is private.
PUBLIC=""
NAME="$AMINAME"
DESCRIPTION="$AMIDESC"

# Special section for creating practicalclouds AMIs..
#REGIONS="us-east-1/pcus1 us-west-1/pcus2 us-west-2/pcus3 eu-west-1/pceu1 ap-northeast-1/pcap1 ap-southeast-1/pcap2 sa-east-1/pcsa1"
#NAME="The www.practicalclouds.com boot AMI"
#DESCRIPTION="see http://www.practicalclouds.com/content/guide/practicalclouds-ami"
#PUBLIC="TRUE"

# Allow aliases to be created...
if [[ -s "/data/aliases" ]]; then
	. /data/aliases
fi

# remove history, logs and cached packages
echo "Removing history, logs and cached packages"
rm -f /mnt/image-base/root/.bash_history
rm -rf /mnt/image-base/var/cache/yum
rm -rf /mnt/image-base/var/lib/yum
rm -rf /mnt/image-base/var/log/*

echo "Zero-ing free space..."
echo "Expect a \"No space left on device\" message - it works by filling up the disk"
cat </dev/zero >/mnt/image-base/zerofile
rm -f /mnt/image-base/zerofile

# Re-bundle, upload and reregister the same AMI we downloaded
# (assuming all the args were supplied ok)
sync
sync

echo "Bundling Image: \${MANIFEST%.manifest.xml} ..."
rm -f /data/\${MANIFEST%.manifest.xml}.part.*
/opt/EC2TOOLS/bin/ec2-bundle-image --image \$IMAGEFILE --prefix \${MANIFEST%.manifest.xml} --user \$AWSUSERNUMBER --destination /data --arch \$AMIARCH --cert \$EC2_CERT --privatekey \$EC2_PRIVATE_KEY

# The main loop, performed for all of the REGIONS we want to upload to...
for REGION in \$REGIONS
do
	RNAME=\${REGION%/*}
	BUCKET=\${REGION#*/}

	banner \$RNAME

	# lookup the right kernel for the region
	case \$AMIARCH in
   		i386)   euwest1="aki-64695810"
       			useast1="aki-805ea7e9"
       			uswest1="aki-83396bc6"  
       			uswest2="aki-c2e26ff2"
       			apnortheast1="aki-ec5df7ed"
       			apsoutheast1="aki-a4225af6"
       			saeast1="aki-bc3ce3a1"
       			;;      
   		x86_64) euwest1="aki-62695816"
       			useast1="aki-825ea7eb"
       			uswest1="aki-8d396bc8"
       			uswest2="aki-ace26f9c"
       			apnortheast1="aki-ee5df7ef"
       			apsoutheast1="aki-aa225af8"
       			saeast1="aki-cc3ce3d1"
       			;;
	esac
	eval AKI=\\\$\${RNAME//-/}

	# First, we want to deregister the AMI and all of the aliases (if any are specified)

	echo
	echo "Looking for the old AMI: \$NAME (\$AMIOS \$AMIARCH)"
	/opt/EC2TOOLS/bin/ec2-describe-images --region \$RNAME >/data/images
	AMIID=\`cat /data/images | grep "\$NAME (\$AMIOS \$AMIARCH)" | awk '{print \$2}'\`
	if [[ "\$AMIID" != "" ]]; then
        	echo "De-registering the existing AMI with EC2 : \$AMIID ..."
        	/opt/EC2TOOLS/bin/ec2-deregister --region \$RNAME \$AMIID
	else
		echo "\$NAME (\$AMIOS \$AMIARCH) not found."
	fi
	echo

	ALIASINDEX="0"
	eval ALIASNAME=\\\$NAME\${ALIASINDEX}
	while [[ "\$ALIASNAME" != "" ]]; do
        	eval ALIASDESC=\\\$DESCRIPTION\${ALIASINDEX}
        	eval ALIASMANIFEST=\\\$MANIFEST\${ALIASINDEX}
        	echo
        	echo "NAME=\$ALIASNAME"
        	echo "DESCRIPTION=\$ALIASDESC"
        	echo "MANIFEST=\$ALIASMANIFEST"
        	echo
        	if [[ "\$ALIASMANIFEST" != "" ]]; then
                	# de-register the existing AMI
                	echo "Looking for old AMI: \$ALIASNAME..."
			# Grep for name up to the first space.
			ALIASGREP="\${ALIASNAME%% *}.*\${AMIOS}.*\${AMIARCH}"
                	AMIID=\`cat /data/images | grep "\$ALIASGREP" | awk '{print \$2}'\`
			if [[ "\$AMIID" != "" ]]; then
				for DREG in \$AMIID; do
                        		echo "De-registering the existing AMI alias : \$DREG ..."
                        		/opt/EC2TOOLS/bin/ec2-deregister --region \$RNAME \$DREG
				done
				REMOVENAME=\${ALIASMANIFEST%%-*}
                        	echo "Removing the existing manifest file..."
				AMIOSNOSPACE=\${AMIOS// /-}
                        	s3cmd --config /root/.s3cfg-ami del s3://\$BUCKET/\${REMOVENAME}*\${AMIOSNOSPACE}*\${AMIARCH}*
			fi
		fi
                ALIASNAME=""
                ALIASDESC=""
                ALIASMANIFEST=""
                ALIASINDEX=\$(( ALIASINDEX + 1 ))
                eval ALIASNAME=\\\$NAME\${ALIASINDEX}
	done

	# Second, remove the image files..
	echo "Removing existing image files from s3://\$BUCKET/\${MANIFEST%.manifest.xml}*..."
	s3cmd --config /root/.s3cfg-ami del s3://\$BUCKET/\${MANIFEST}
	s3cmd --config /root/.s3cfg-ami del s3://\$BUCKET/\${MANIFEST%.manifest.xml}.part.*
	echo

	# Third, upload the new bundle
	echo "Uploading Bundle to: \$BUCKET ..."
	# Upload using s3cmd, it is more reliable than ec2-upload-bundle on poorer links
	#ec2-upload-bundle --manifest \$MANIFEST --bucket \$BUCKET --access-key \$ACCESS_KEY --secret-key \$SECRET_KEY
	if [[ "\$PUBLIC" == "TRUE" ]]; then
		s3cmd -c /root/.s3cfg-ami -P put \${MANIFEST%.manifest.xml}.* s3://\$BUCKET
	else
		s3cmd -c /root/.s3cfg-ami put \${MANIFEST%.manifest.xml}.* s3://\$BUCKET
		s3cmd -c /root/.s3cfg-ami --acl-grant=read:${ZA_TEAM} setacl s3://\$BUCKET/\${MANIFEST%.manifest.xml}.*	
	fi
	echo

	# Fourth, register the new AMI
	echo "Registering the new AMI: \$BUCKET/\$MANIFEST in \$RNAME (\$AMIOS \$AMIARCH) \$AKI ..."
	AMIID=\`/opt/EC2TOOLS/bin/ec2-register -K \$EC2_PRIVATE_KEY -C \$EC2_CERT \$BUCKET/\$MANIFEST --description "\$DESCRIPTION" --name "\$NAME (\$AMIOS \$AMIARCH)" --architecture \$AMIARCH --region \$RNAME --kernel \$AKI | awk '{print \$2}'\`
	echo "Registered AMI: \$AMIID"
	if [[ "\$PUBLIC" == "TRUE" ]]; then
		echo "Setting public access on \$AMIID"
		/opt/EC2TOOLS/bin/ec2-modify-image-attribute -K \$EC2_PRIVATE_KEY -C \$EC2_CERT --region \$RNAME -l -a all \$AMIID
	fi
	echo
	echo "Core AMI updated, now processing any aliases..."

	ALIASINDEX="0"
	eval ALIASNAME=\\\$NAME\${ALIASINDEX}
	while [[ "\$ALIASNAME" != "" ]]; do
		# add the OS and archiecture to the name
		ALIASNAME="\$ALIASNAME (\${AMIOS} \${AMIARCH})"
		eval ALIASDESC=\\\$DESCRIPTION\${ALIASINDEX}	
		eval ALIASMANIFEST=\\\$MANIFEST\${ALIASINDEX}	
		# add the OS and archiecture to the manifest name
		NEWMANIFEST=\`echo \$ALIASMANIFEST | sed -e "s/__profile/-\${AMIOS}-\${AMIARCH}__profile/"\`	
		NEWMANIFEST=\${NEWMANIFEST// /-}
		ALIASMANIFEST="\${NEWMANIFEST}"
		echo
		echo "NAME=\$ALIASNAME"
		echo "DESCRIPTION=\$ALIASDESC"
		echo "MANIFEST=\$ALIASMANIFEST"
		echo
		if [[ "\$ALIASMANIFEST" != "" ]]; then
			# copy the manifest as alias and upload to s3
			cp /data/\${MANIFEST} /data/\$ALIASMANIFEST
			if [[ "\$PUBLIC" == "TRUE" ]]; then
        			s3cmd -c /root/.s3cfg-ami -P put \${ALIASMANIFEST} s3://\$BUCKET
			else
        			s3cmd -c /root/.s3cfg-ami put \${ALIASMANIFEST} s3://\$BUCKET
        			s3cmd -c /root/.s3cfg-ami --acl-grant=read:${ZA_TEAM} setacl s3://\$BUCKET/\${ALIASMANIFEST}   
			fi

			# Now register the alias ...
			echo
			echo "Registering the alias : \$ALIASNAME in \$RNAME (\$AMIOS \$AMIARCH) \$AKI ..."
			AMIID=\`/opt/EC2TOOLS/bin/ec2-register -K \$EC2_PRIVATE_KEY -C \$EC2_CERT \$BUCKET/\$ALIASMANIFEST --description "\$ALIASDESC" --name "\$ALIASNAME" --architecture \$AMIARCH --region \$RNAME --kernel \$AKI | awk '{print \$2}'\`
			echo "Registered AMI: \$AMIID"
			if [[ "\$PUBLIC" == "TRUE" ]]; then
        			echo "Setting public access on \$AMIID"
        			/opt/EC2TOOLS/bin/ec2-modify-image-attribute -K \$EC2_PRIVATE_KEY -C \$EC2_CERT --region \$RNAME -l -a all \$AMIID
			fi

		else 
			echo "I can't make an alias without a NAME or a MANIFEST"
		fi

		ALIASNAME=""
		ALIASDESC=""
		ALIASMANIFEST=""
		ALIASINDEX=\$(( ALIASINDEX + 1 ))
		eval ALIASNAME=\\\$NAME\${ALIASINDEX}	
	done
done

echo "updateAMI.sh Finished!"
EOT
	chmod u+x /data/updateAMI.sh
	if [[ "$AMIALIASES" != "" ]]; then
		$logger "Looking for an ami aliases file..."
		get_file -f $AMIALIASES -d /data/aliases
		if [[ ! -s "/data/aliases" ]]; then
			$logger "I couldn't download the aliases file!"
		fi 
	fi
else
	$logger "Not enough information in order to create the /data/updateAMI.sh script, sorry!"
fi	

# Note: -
# The ami user credentials should have been given the following IAM security
# policy: -
#
#{
#  "Statement": [
#    {
#      "Sid": "Stmt1306858111769",
#      "Action": [
#        "ec2:BundleInstance",
#        "ec2:CancelBundleTask",
#        "ec2:CreateImage",
#        "ec2:DescribeBundleTasks",
#        "ec2:DescribeImageAttribute",
#        "ec2:DescribeImages",
#        "ec2:ModifyImageAttribute",
#        "ec2:RegisterImage",
#        "ec2:ResetImageAttribute",
#        "ec2:DeregisterImage"
#      ],
#      "Effect": "Allow",
#      "Resource": "*"
#    },
#    {
#      "Sid": "Stmt1306858207079",
#      "Action": "s3:*",
#      "Effect": "Allow",
#      "Resource": [
#        "arn:aws:s3:::practicalclouds-ami",
#        "arn:aws:s3:::practicalclouds-ami/*",
#        "arn:aws:s3:::practicalclouds-publicami",
#        "arn:aws:s3:::practicalclouds-publicami/*" ]
#    }
#  ]
#}

