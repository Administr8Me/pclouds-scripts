#!/bin/bash

# profile-drupal.sh
# Dave McCormick
PROFILE_VERSION="2.0"
PROFILE_URL="http://www.practicalclouds.com/content/guide/vsftpd-ftp-server"
PROFILE_DOWNLOAD="http://files001.practicalclouds.com/profile-vsftpd.sh"
MINIMUM_BOOTSTRAP_FUNCTIONS="2.0"

# please refer to the instructions on using this profile script at
# http://www.practicalclouds.com/content/guide/vsftpd-ftp-server

# 1.0  - initial, load and configure vsftpd for ftp and sftp.
# 1.1  - Enable version checking and use the fatal_error function.
# 2.0  - Update to version 2.0 style boot.

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

EXTERNALIP=`read_arg -n ftpip`
if [[ "$EXTERNALIP" == "" ]]; then
	EXTERNALIP=`curl -s --fail http://169.254.169.254/latest/meta-data/public-ipv4`
fi
FTPCERT=`read_arg -n ftpcert`
FTPPKEY=`read_arg -n ftppkey`
BANNER=`read_arg -n ftpbanner`
if [[ "$BANNER" == "" ]]; then
	BANNER="Practical Clouds vsftpd server ready..."
fi
FTPCONF=`read_arg -n ftpconf`

$logger "Installing vsftpd"
yum -y install vsftpd

LOADEDCERTS="false"
# Download certs if we have them
if [[ "$CERT" != "" && "$PKEY" != "" ]]; then
	get_file -f $CERT
	LOCALCERT=`basename $CERT`
	if [[ -s "/etc/boostrap.d/$LOCALCERT" ]]; then
		get_file -f $PKEY
		LOCALKEY=`basename $PKEY`
		if [[ -s "/etc/boostrap.d/$LOCALKEY" ]]; then
			cp /etc/boostrap.d/$LOCALCERT /etc/vsftpd/cert.pem
			cp /etc/boostrap.d/$LOCALKEY /etc/vsftpd/pkey.pem 
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
	cat >/etc/vsftpd/cert.pem <<EOT
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
	cat >/etc/vsftpd/pkey.pem <<EOT
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
if [[ "$FTPCONF" != "" ]]; then
        $logger "Loading vsftpd configuration from $FTPCONF"
        rm -rf /etc/vsftpd/*
        load_data -s $FTPCONF -d /etc/vsftpd
        if [[ "$?" != "0" ]]; then
                fatal_error "I couldn't download the specified vsftpd configs file!"
                exit 1
        fi
else
	$logger "Automatically configuring vsftpd for local user access"
	sed -e 's/^anonymous_enable=YES/anonymous_enable=NO/' -i /etc/vsftpd/vsftpd.conf
	cat >>/etc/vsftpd/vsftpd.conf <<EOT
ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=NO
force_local_logins_ssl=NO
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
rsa_cert_file=/etc/vsftpd/cert.pem
rsa_private_key_file=/etc/vsftpd/pkey.pem
pasv_enable=YES
pasv_min_port=1024
pasv_max_port=1028
pasv_address=$EXTERNALIP
ftpd_banner=$BANNER
EOT
fi

$logger "Starting vsftpd..."
service vsftpd start
if [[ "$?" == "0" ]]; then
	$logger "Secure FTP Server is now ready..."
	$logger "Please ensure that incoming ports 20, 21, 1024-1028 are allowed in this servers security group."
else
	$logger "I couldn't start vsftpd - please investigate!"
fi

