#!/bin/sh

__openssl="sudo openssl"

alert_days=10

domain_name=$1
cert_path=/etc/letsencrypt/live/${domain_name}/cert.pem

time_expiry_in_humanreadable=`${__openssl} x509 -in ${cert_path} -text |sed -e '/Not After/{s/^.* : //;p};d'`

time_expiry=`date "--date=${time_expiry_in_humanreadable}" +%s`
time_now=`date +%s`
time_alert=`echo "${time_expiry} - (${alert_days}*60*60*24)" | bc`
time_alert_in_humanreadable=`date -d "@${time_alert}"`

echo $time_expiry
echo $time_now
echo $time_alert

retval=0
if [ ${time_expiry} -le ${time_now} ]; then
  echo "Certificates for ${domain_name} expired at ${time_expiry_in_humanreadable}."
  retval=-1
elif [ ${time_alert} -le ${time_now} ]; then
  echo "Certificates for ${domain_name} will expire at ${time_alert_in_humanreadable}."
  retval=1
fi
exit $retval
