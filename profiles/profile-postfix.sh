#!/bin/bash

# profile-postfix.sh
# Dave McCormick
PROFILE_VERSION="2.2"
PROFILE_URL="http://www.practicalclouds.com/content/guide/postfix-smtp-server"
PROFILE_DOWNLOAD="http://files001.practicalclouds.com/profile-postfix.sh"
MINIMUM_BOOTSTRAP_FUNCTIONS="2.0"

# please refer to the instructions on using this profile script at
# http://www.practicalclouds.com/content/guide/postfix

# 1.0 - Initial, install postfix and configure for smtp email with
#	optional dkim-milter
# 1.1 - Add antispam option with amavisd, clamav, spamassassin
# 1.2 - Remove need to set myhostname and add smart relay support.
# 1.3 - Include dovecot pop/imap server and options
#       Use dovecot SASL in place of cyrus SASL
#	Automatically configure TLS for SMTP, POP3 and IMAP
#	Allow mount of mailboxes from an EBS volume
#	Use MailDir mailbox format.
# 1.4 - Enable version checking and use fatal_error function.
# 2.0 - Update to version 2.0 bootstrap.
# 2.1 - Update to make compatible with Fedora 16
# 2.2 - minor sed syntax correction

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
        $logger "I couldn't load the bootstrap-functions2, aborting!"
        exit 1
fi

# Read all of our options...
DKIMKEY=`read_arg -n dkimkey`
ANTISPAM=`read_arg -n antispam`
MYDOMAIN=`read_arg -n mydomain`
MYHOSTNAME=`read_arg -n myhostname`
SMARTRELAY=`read_arg -n smartrelay`
MAILVOL=`read_arg -n mailvol`
ALIASES=`read_arg -n aliases`
CERT=`read_arg -n mailcert`
PKEY=`read_arg -n mailpkey`
WITHPOP3=`read_arg -n pop3`
WITHIMAP=`read_arg -n imap`

# Ports
# imap port = 143
# impas port = 993
# pop3 port = 110
# pop3s port = 995
# smtp = 25

# Work out what we are installing...
INSTALLPKG="postfix postfix-perl-scripts dovecot"
[[ "$DKIMKEY" != "" ]] && INSTALLPKG="$INSTALLPKG dkim-milter"
[[ "$ANTISPAM" == "true" ]] && INSTALLPKG="$INSTALLPKG spamassassin clamav clamav-update amavisd-new"

# Uninstall sendmail and install postfix
$logger "Removing sendmail"
service sendmail stop
yum -y remove sendmail
$logger "Installing Postfix and Dovecot : $INSTALLPKG"
yum -y install $INSTALLPKG

# If we have a mailvol arg then mount the ebs volume to /var/www
if [[ "$MAILVOL" != "" ]]; then
        $logger "Mounting ebs mail volume $MAILVOL"
        mount_ebsvol -n $MAILVOL -m /var/spool/mail
        if [[ "$?" != "0" ]]; then
                fatal_error "I couldn't attach the requested mail volume, $MAILVOL - aborting...!"
                exit 1
        fi
else
        $logger "We have not been requested to mount an EBS volume for the mail boxes"
fi

# Configure global Dovecot options we require...
# Automatically create mailboxes when delivering mail...
sed -e 's/^#lda_mailbox_autocreate = no/lda_mailbox_autocreate = yes/' -i /etc/dovecot/conf.d/15-lda.conf
# Set location of mailboxes and specify as maildir format.
sed -e 's/^#mail_location =/mail_location = maildir:\/var\/spool\/mail\/%u/' -i /etc/dovecot/conf.d/10-mail.conf
# Set up the socket so that postfix can use Dovecot SASL.
sed -e 's/^  #unix_listener \/var\/spool\/postfix\/private\/auth {/  unix_listener \/var\/spool\/postfix\/private\/auth {\n    mode = 0666\n  }/' -i /etc/dovecot/conf.d/10-master.conf
# Give regular users access to /var/spool/mail
rm -rf /var/spool/mail/*
chmod 1777 /var/spool/mail

LOADEDCERTS="false"
# Download certs if we have them
if [[ "$CERT" != "" && "$PKEY" != "" ]]; then
	get_file -f $CERT
	LOCALCERT=`basename $CERT`
	if [[ -s "/etc/boostrap.d/$LOCALCERT" ]]; then
		get_file -f $PKEY
		LOCALKEY=`basename $PKEY`
		if [[ -s "/etc/boostrap.d/$LOCALKEY" ]]; then
			cp /etc/boostrap.d/$LOCALCERT /etc/postfix/cert.pem
			cp /etc/boostrap.d/$LOCALKEY /etc/postfix/pkey.pem 
			LOADEDCERTS="true"
			$logger "Installed your cert, $LOCALCERT and private key, $LOCALKEY."
		else
			$logger "I couldn't download your private key, $PKEY."
		fi
	else
		$logger "I couldn't download your certificate, $CERT"
	fi
fi

if [[ "$LOADEDCERTS" != "true" ]]; then
	$logger "You cert or key failed to install, or you didn't specify any..."
	$logger "Installing the default certificate instead."
	cat >/etc/postfix/cert.pem <<EOT
-----BEGIN CERTIFICATE-----
MIID0TCCArmgAwIBAgIJAIrtwO6JeHRTMA0GCSqGSIb3DQEBBQUAMH8xCzAJBgNV
BAYTAkdCMRUwEwYDVQQHDAxEZWZhdWx0IENpdHkxGTAXBgNVBAoMEFByYWN0aWNh
bCBDTG91ZHMxHDAaBgNVBAsME0RlZmF1bHQgQ2VydGlmaWNhdGUxIDAeBgNVBAMM
F3d3dy5wcmFjdGljYWxjbG91ZHMuY29tMB4XDTExMDkwOTIxMDAxNloXDTIxMDkw
NjIxMDAxNlowfzELMAkGA1UEBhMCR0IxFTATBgNVBAcMDERlZmF1bHQgQ2l0eTEZ
MBcGA1UECgwQUHJhY3RpY2FsIENMb3VkczEcMBoGA1UECwwTRGVmYXVsdCBDZXJ0
aWZpY2F0ZTEgMB4GA1UEAwwXd3d3LnByYWN0aWNhbGNsb3Vkcy5jb20wggEiMA0G
CSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC7hijXQzT3vD3Jzfp39N0Yenooc33Z
KlJT/bco5Y3Ce0wTyS1Bh0n/0d2gZcEwqkVteur+mRlXjN2WPhFR5At2lM1DTz5o
JekkxVkdc9DoJPM5HxffvGVHjWaGkqFcEVJs0KG9tM8Eb0XiXhlc+h3NT0Tnrqwa
/8crU+N0XpLZJ62tKiCC/Vy9ca1+WV+zIYEkarD8BGUKjqmJHZxSSVno3dv8Vq7t
YI+43ZI0OfffmCR0O8X7ZMpn7gNmpKcg2H0fumkPCWiaqAZrSJlqlxspYh9XDGND
YOmRWt8GoAC/+tAhihP3rCbDXBw/roxs3dAbmrmbT0Xiifs+SZw/kMlDAgMBAAGj
UDBOMB0GA1UdDgQWBBQJPfzaUkCCc7BQ8EQ0kUOVn9DmWDAfBgNVHSMEGDAWgBQJ
PfzaUkCCc7BQ8EQ0kUOVn9DmWDAMBgNVHRMEBTADAQH/MA0GCSqGSIb3DQEBBQUA
A4IBAQCssO8pXroHxOygPaFTSHFyFcGsu9x3OZuMJWvViAEc27wkb4aOVrcgU6k/
aStFmaeMJew3HqWEqPZQi71WjN2phxsS+xKAuZTLIeG0hkL9BNfB0PP3nSpbnkJT
ZUQPxK0toO9UJONu7Rx3YzHGvOB4GvuQDeO9VrfEkJmFRlwhL/hSN8WgRWPeG67/
7E0FxpJ3yaJwZ2dnROCmtlPkfmgpiDKBJ6/IVYp+oEp6F8MIyUHJcBx/a3GOhJIk
t7iAxCdJuZj5sQH5Kntv3bx6H+fwvQbOvWxb9gjw5oBDJOMQZPUxhgx26SrkXTwy
1zbjhP4pzLlzu4dIqnewMOWI+Esf
-----END CERTIFICATE-----
EOT
	cat >/etc/postfix/pkey.pem <<EOT
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7hijXQzT3vD3J
zfp39N0Yenooc33ZKlJT/bco5Y3Ce0wTyS1Bh0n/0d2gZcEwqkVteur+mRlXjN2W
PhFR5At2lM1DTz5oJekkxVkdc9DoJPM5HxffvGVHjWaGkqFcEVJs0KG9tM8Eb0Xi
Xhlc+h3NT0Tnrqwa/8crU+N0XpLZJ62tKiCC/Vy9ca1+WV+zIYEkarD8BGUKjqmJ
HZxSSVno3dv8Vq7tYI+43ZI0OfffmCR0O8X7ZMpn7gNmpKcg2H0fumkPCWiaqAZr
SJlqlxspYh9XDGNDYOmRWt8GoAC/+tAhihP3rCbDXBw/roxs3dAbmrmbT0Xiifs+
SZw/kMlDAgMBAAECggEBAIxSB52MnMYEBfhMOXApuofmniJGyZUHJjPTVoszurAc
swDbORIfui/DSqQLgFR6FRmnMNDynxP0RJt4Nl2g1zMUhcQoN/qW466wPc7cKyaK
/7Vunt68iszP8jgg4L2T+KmUNHNQKNiYqyKIZ1I7lrFa76St//r0CoVRcJJTcm8r
CcuwAjrfyNs55kOQpPpqZQ3R0u1X4OLXcQLqKjmrS7Ov1leLgaEahJJtyfmlZERS
BbhkDZSVdSAGw1QgV0xqW1iKek8lw5GaVk1N7o5VvXsF3lkg7QQoYsyoLy82JogC
UF/v74nTzpzTL3JID8YNZyfHQ3Eq1LESNiYhtYAOJIECgYEA3gLXgUUr1nyWi3RG
eGO9FKJSTc+xviU5MoJQAilpWXqzC2mWzcG2bnyhWukUOvtURnBkr4skCAv8n/Gu
FV2Ce+cAk1ZeYG//VCgitlNXaL7Fh3P3bhw7OidK7ggkv0r/oZ4H2DOBT1uFFGwv
k6/SfZmPJJuw2aYNi1z3mqn5Wf8CgYEA2DuvraJe07SwXG+E3mYdLlLeVaWK9MR3
MDpcxtMmoni26kKOouEufDVfu3kBVRrF8dbaex94QHOEn4l9pqkvNZNm9unc9wF+
JDtxFHkIV7SuADab+7mJNYbndEEwY3Xv8h1GLsTmzyIr/lwEmUfgElWz0th0i/8k
yHSIEZyWqL0CgYAHhvUjjuLTnNnF1KVnA4qvnmlH9hjCp6Ruz/hCeoD15bEYW/Ye
98hlqpgV6v0ims7arIjdYsxP8YgZLCqI0ujPpp9gX3dHscRoaAv1PpIiHQW5d/cV
pqNjb12dAG2uhq5wHlmJvQVPWX0Dmj9qtHVgiMpPpW+zkWu4I+jJN6YapQKBgGrH
VqKM2vz6bljHLTrR/DkC7Q4oOG1Uk3L6bxQz8xEqQVF/WoZuYpEtnj+qqpDHLtaU
/cDtMmnJYcWSlLz3MPvo9WCa7eYAE7V6sQWmGwuMipxKW068OVh4bNWI14dWFw5d
jGnODBhfTJBICnFTAACt16YYA72aWiSu/v6LcA6VAoGAUeH7eDjotRaXmOgRbuir
Z/7V7l2K9zltuW2MeTBk2thaV4f9QsNVgxqF0W095d0uO9caFcjQ/C41ppHrUpT1
V3IgYHiBsbIf1TjTx1YsL16b/W9VCiS7Mtmq4baJk3wsjFo1EalQ0tJHZeghBRX0
ZEOeTQGbuRodAjiHVEscXVs=
-----END PRIVATE KEY-----
EOT
fi

# optionally load configuration for advanced users
DOVECONF=`read_arg -n doveconf`
if [[ "$DOVECONF" != "" ]]; then
        $logger "Loading Dovecot configuration from $DOVECONF"
	rm -rf /etc/dovecot/*
        load_data -s $DOVECONF -d /etc/dovecot
        if [[ "$?" != "0" ]]; then
                fatal_error "I couldn't download the specified dovecot configs file!"
                exit 1
        fi
else
        $logger "Automatic Dovecot Configuration..."
	# Copy the same certs for use with Dovecot
	cp /etc/postfix/cert.pem /etc/pki/dovecot/certs/dovecot.pem
	cp /etc/postfix/pkey.pem /etc/pki/dovecot/private/dovecot.pem
        if [[ "$WITHIMAP" == "true" || "$WITHPOP3" == "true" ]]; then
                PROTOCOLS=""
                if [[ "$WITHIMAP" == "true" ]]; then
                        $logger "Enabling Dovecot IMAP Server"
                        PROTOCOLS="imap"
                fi
                if [[ "$WITHPOP3" == "true" ]]; then
                        $logger "Enabling Dovecot POP3 Server"
                        if [[ "$PROTOCOLS" == "" ]]; then
                                PROTOCOLS="pop3"
                        else
                                PROTOCOLS="$PROTOCOLS pop3"
                        fi
                fi
                # enable the right protocols in dovecot.conf
                sed -e "s/^#protocols = imap pop3 lmtp/protocols = $PROTOCOLS/" -i /etc/dovecot/dovecot.conf
        else
                $logger "No IMAP or POP3 requested, enabling Dovecot only for SASL"
                sed -e "s/^#protocols = imap pop3 lmtp/protocols = none/" -i /etc/dovecot/dovecot.conf
        fi
fi


# work out myhostname and mydomain from instance if they haven't been specified...
if [[ "$MYHOSTNAME" == "" ]]; then
	MYHOSTNAME=`curl -s --fail http://169.254.169.254/latest/meta-data/public-hostname`	
fi
if [[ "$MYDOMAIN" == "" ]]; then
	MYDOMAIN=${MYHOSTNAME#*.}
fi

# Configure Postfix
POSTCONF=`read_arg -n postconf`
if [[ "$POSTCONF" != "" ]]; then
	$logger "Replacing postfix configuration with $POSTCONF"
        rm -rf /etc/postfix/*
        load_data -s $POSTCONF -d /etc/postfix
        if [[ "$?" != "0" ]]; then
                fatal_error "I couldn't download the specified postfix configs file!"
                exit 1
        fi
	# Find out what mydomain and myhostname from configs
	MYDOMAIN=`cat /etc/postfix/main.cf | grep ^mydomain | head -1 | awk '{print $3}'`	
	MYHOSTNAME=`cat /etc/postfix/main.cf | grep ^myhostname | head -1 | awk '{print $3}'`	
	$logger "mydomain=\"$MYDOMAIN\" and myhostname=\"$MYHOSTNAME\" have been set by configs"
else
	if [[ "$MYDOMAIN" != "" && "$MYHOSTNAME" != "" ]]; then
		$logger "Automatically configuring postfix with mydomain=$MYDOMAIN and myhostname=$MYHOSTNAME"
		cat >/etc/postfix/main.cf <<EOT
queue_directory = /var/spool/postfix
command_directory = /usr/sbin
daemon_directory = /usr/libexec/postfix
data_directory = /var/lib/postfix
mail_owner = postfix

inet_interfaces = all
inet_protocols = all

mydomain=$MYDOMAIN
myhostname=$MYHOSTNAME
mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain
mynetworks_style=host

unknown_local_recipient_reject_code = 550
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
debug_peer_level = 2
debugger_command =
         PATH=/bin:/usr/bin:/usr/local/bin:/usr/X11R6/bin
         ddd \$daemon_directory/\$process_name \$process_id & sleep 5
sendmail_path = /usr/sbin/sendmail.postfix
newaliases_path = /usr/bin/newaliases.postfix
mailq_path = /usr/bin/mailq.postfix
setgid_group = postdrop
html_directory = no
manpage_directory = /usr/share/man
sample_directory = /usr/share/doc/postfix-2.7.5/samples
readme_directory = /usr/share/doc/postfix-2.7.5/README_FILES
mailbox_command = /usr/libexec/dovecot/deliver
#TLS - SMTP AUTH
disable_vrfy_command = yes
smtpd_use_tls = yes
smtpd_tls_auth_only = yes
tls_random_source = dev:/dev/urandom
smtpd_tls_cert_file = /etc/postfix/cert.pem
smtpd_tls_key_file = /etc/postfix/pkey.pem
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
broken_sasl_auth_clients = yes
# Add some security
smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination
EOT
		# Optionally configure a smartrelay host...
		if [[ "$SMARTRELAY" != "" ]]; then
			case $SMARTRELAY in
				*.*.*.*:*)	echo "relayhost = [${SMARTRELAY%:*}]:${SMARTRELAY#*:}" >>/etc/postfix/main.cf
						;;
				*.*.*.*)	echo "relayhost = [$SMARTRELAY]" >>/etc/postfix/main.cf 
						;;
				*)		echo "relayhost = $SMARTRELAY" >>/etc/postfix/main.cf		
						;;
			esac
		fi
	else
        	$logger "No postfix configs were specified, leaving as default configs"
	fi
		
fi

# do it again, in case they were not set in the postfix configs.
# work out myhostname and mydomain from instance if they haven't been specified...
if [[ "$MYHOSTNAME" == "" ]]; then
        MYHOSTNAME=`curl -s --fail http://169.254.169.254/latest/meta-data/public-hostname`
fi
if [[ "$MYDOMAIN" == "" ]]; then
        MYDOMAIN=${MYHOSTNAME#*.}
fi

# Replace the aliases file if requested to do so
if [[ "$ALIASES" != "" ]]; then
        get_file -f $ALIASES
        ALIASESFILE=`basename $ALIASES`
        if [[ -s /etc/bootstrap.d/$ALIASESFILE ]]; then
                cp /etc/bootstrap.d/$ALIASESFILE /etc/aliases
		newaliases
		$logger "Installed the new aliases"
	fi
fi

# Configure DKIM if a key has been provided, we assume that the selector is called "default"
if [[ "$DKIMKEY" != "" && "$MYDOMAIN" != "" ]]; then
	get_file -f $DKIMKEY
        KEYFILE=`basename $DKIMKEY`
        if [[ -s /etc/bootstrap.d/$KEYFILE ]]; then
        	cp /etc/bootstrap.d/$KEYFILE /etc/mail/dkim-milter/default
		chmod 600 /etc/mail/dkim-milter/default
		chown dkim-milter:dkim-milter /etc/mail/dkim-milter/default
		$logger "Configuring dkim-milter for $MYDOMAIN"
		echo "*:$MYDOMAIN:/etc/mail/dkim-milter/default" >>/etc/mail/dkim-milter/keys/keylist
		cat >/etc/mail/dkim-milter/dkim-filter.conf <<EOT
KeyList /etc/mail/dkim-milter/keys/keylist
Selector        default
Socket  inet:20209@127.0.0.1
Canonicalization        relaxed/relaxed
UMask   002
EOT
		merge_text /etc/postfix/main.cf "smtpd_milters = inet:localhost:20209" "non_smtpd_milters = inet:localhost:20209"
        	$logger "Starting dkim-milter"
		service dkim-milter start
	else
		$logger "I couldn't download the dkim key file. sorry can't configure the dkim-milter"
        fi
else
	$logger "You need to supply a dkim key and specify mydomain in order to configure the dkim-milter"
fi

# Configure Amavis, Spamassassin, ClamAV if antispam has been selected
if [[ "$ANTISPAM" == "true" ]]; then
	if [[ "$MYHOSTNAME" != "" && "$MYDOMAIN" != "" ]]; then
		$logger "Configuring Amavisd"
		mkdir -p /var/run/amavisd
		chown amavis:amavis /var/run/amavisd
		sed -e "s/^\$mydomain.*/\$mydomain = \"$MYDOMAIN\";/" -i /etc/amavisd/amavisd.conf
		sed -e "s/^# \$myhostname.*/\$myhostname = \"$MYHOSTNAME\";/" -i /etc/amavisd/amavisd.conf
		sed -e 's/^$sa_tag_level_deflt.*/$sa_tag_level_deflt  = '-9999';  # add spam info headers if at, or above that level/' -i /etc/amavisd/amavisd.conf
		sed -e 's/^$sa_tag2_level_deflt.*/$sa_tag2_level_deflt = 4.0;  # add spam detected headers at that level/' -i /etc/amavisd/amavisd.conf
		sed -e 's/^$sa_kill_level_deflt.*/$sa_kill_level_deflt = 15.0;  # triggers spam evasive actions (e.g. blocks mail)/' -i /etc/amavisd/amavisd.conf
		sed -e 's/^$sa_dsn_cutoff_level.*/$sa_dsn_cutoff_level = 15.0;   # spam level beyond which a DSN is not sent/' -i /etc/amavisd/amavisd.conf

		$logger "Configuring Spam Assassin"
		cat >>/etc/mail/spamassassin/local.cf <<EOT
use_bayes               1
bayes_auto_learn        1
skip_rbl_checks         0
use_razor2              1
use_pyzor               1
whitelist_from *@$MYDOMAIN
EOT
		$logger "Configuring ClamAV"
		# enable automatic updates
		sed -e 's/^FRESHCLAM_DELAY=.*//' -i /etc/sysconfig/freshclam
		sed -e 's/^Example/#Example/' -i  /etc/freshclam.conf	
		# update now
		$logger "Updating ClamAV Virus Signatures"
		freshclam
		if [[ "$?" != "0" ]]; then
			$logger "The update of ClamAV signatures failed!"
		fi

		# start the services
		$logger "Starting Amavisd, clamd and spamassassin..."
		service amavisd start
		if [[ "$?" != "0" ]]; then
			$logger "amavisd failed to start!"
		fi
		service clamd.amavisd start
		if [[ "$?" != "0" ]]; then
			$logger "clamd.amavisd failed to start!"
		fi
		service spamassassin start
		if [[ "$?" != "0" ]]; then
			$logger "spamassassin failed to start!"
		fi

		# configure postfix to use amavis
		merge_text /etc/postfix/master.cf "smtp-amavis unix -      -       n       -       2       smtp" "    -o smtp_data_done_timeout=1200" "    -o smtp_send_xforward_command=yes" "    -o disable_dns_lookups=yes" "    -o max_use=20" "127.0.0.1:10025 inet n  -       n       -       -  smtpd" "    -o content_filter=" "    -o local_recipient_maps=" "    -o relay_recipient_maps=" "    -o smtpd_restriction_classes=" "    -o smtpd_delay_reject=no" "    -o smtpd_client_restrictions=permit_mynetworks,reject" "    -o smtpd_helo_restrictions=" "    -o smtpd_sender_restrictions=" "    -o smtpd_recipient_restrictions=permit_mynetworks,reject" "    -o smtpd_data_restrictions=reject_unauth_pipelining" "    -o smtpd_end_of_data_restrictions=" "    -o mynetworks=127.0.0.0/8" "    -o smtpd_error_sleep_time=0" "    -o smtpd_soft_error_limit=1001" "    -o smtpd_hard_error_limit=1000" "    -o smtpd_client_connection_count_limit=0" "    -o smtpd_client_connection_rate_limit=0" "    -o receive_override_options=no_header_body_checks,no_unknown_recipient_checks,no_milters"
		merge_text /etc/postfix/main.cf "content_filter = smtp-amavis:[127.0.0.1]:10024"
	else
		$logger "You can't enable the anti spam features without myhostname or mydomain args, sorry!"
	fi
fi

$logger "Starting dovecot and postfix"
service dovecot start
if [[ "$?" != "0" ]]; then
	$logger "dovecot failed to start!"
fi
service postfix start
if [[ "$?" != "0" ]]; then
	$logger "postfix failed to start!"
fi
