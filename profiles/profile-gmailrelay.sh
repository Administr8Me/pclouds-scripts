#!/bin/bash

# profile-gmailrelay.sh
# Dave McCormick
PROFILE_VERSION="1.0"

# please refer to the instructions on using this profile script at
# http://www.practicalclouds.com/content/guide/common

# 1.0 - initial, install postfix and configure for relay via
# 	a googlemail account.

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
if [ -s "/etc/bootstrap.d/bootstrap-functions" ]; then
        . /etc/bootstrap.d/bootstrap-functions
else
        $logger "I couldn't load the bootstrap-fuctions, aborting!"
        exit 1
fi

GMAILADDR=`read_tag -t gmailaddr`
if [[ "$GMAILADDR" == "" ]]; then
	$logger "Error!  I can't proxy email without a googlemail email address!, aborting."
	exit 1
fi

GMAILPASS=`read_tag -t gmailpass`
if [[ "$GMAILPASS" == "" ]]; then
	$logger "Error!  I can't proxy email without a googlemail password!, aborting."
	exit 1
fi

# Uninstall sendmail and install postfix
$logger "Removing sendmail"
service sendmail stop
yum -y remove sendmail
$logger "Installing Postfix"
yum -y install postfix

# Add the postfix sasl configurarion
$logger "Configuring Postfix to use SASL"
cat >>/etc/postfix/main.cf <<EOT
relayhost = [smtp.gmail.com]:587

#auth
smtp_sasl_auth_enable=yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd

#tls
smtp_use_tls = yes
smtp_sasl_security_options = noanonymous
smtp_sasl_tls_security_options = noanonymous
smtp_tls_note_starttls_offer = yes
tls_random_source = dev:/dev/urandom
smtp_tls_enforce_peername = no
EOT

$logger "Writing SASL Password file"
cat >/etc/postfix/sasl_passwd <<EOT
gmail-smtp.l.google.com $GMAILADDR:$GMAILPASS
smtp.gmail.com $GMAILADDR:$GMAILPASS
EOT
postmap /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd*

$logger "Starting postfix"
service postfix start

