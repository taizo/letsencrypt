#!/bin/sh

__openssl="sudo openssl"

notif_subject="CERTIFICATES EXPIRATION NOTIFICATION"
notif_sender=
notif_recipient=

webserver=nginx  # nginx for Nginx, or httpd for Apache

aws_region="ap-northeast-1"
aws_sg_id=""
aws_global_opts="--region ${aws_region}"

alert_days_1=14  # Send Notification
alert_days_2=5   # Update Certificates

domain_name=$1
cert_path=/etc/letsencrypt/live/${domain_name}/cert.pem

RETCODE_VALID=0
RETCODE_EXPIRED=-1
RETCODE_WARN_EXPIRES_IN_ALERT_DAYS_1=1
RETCODE_WARN_EXPIRES_IN_ALERT_DAYS_2=2


time_expiry_in_humanreadable=`${__openssl} x509 -in ${cert_path} -text |sed -e '/Not After/{s/^.* : //;p};d'`
time_expiry=`date "--date=${time_expiry_in_humanreadable}" +%s`
time_now=`date +%s`
time_alert_days_1=`echo "${time_expiry} - (${alert_days_1}*60*60*24)" | bc`
time_alert_days_1_in_humanreadable=`date -d "@${time_alert_days_1}"`
time_alert_days_2=`echo "${time_expiry} - (${alert_days_2}*60*60*24)" | bc`
time_alert_days_2_in_humanreadable=`date -d "@${time_alert_days_2}"`

retval=${RETCODE_VALID}
if [ ${time_expiry} -le ${time_now} ]; then
  echo "Certificates for ${domain_name} expired at ${time_expiry_in_humanreadable}."
  retval=${RETCODE_EXPIRED}

elif [ ${time_alert_days_2} -le ${time_now} ]; then
  echo "The certs for ${domain_name} will expire at ${time_alert_days_2_in_humanreadable}."

  # Update Certificates
  if [ "x${aws_sg_id}" != "x" ]; then
    aws ${aws_global_opts} ec2 authorize-security-group-ingress \
      --group-id ${aws_sg_id} \
      --cidr 0.0.0.0/0 \
      --port 443 \
      --protocol tcp
    aws ${aws_global_opts} ec2 describe-security-groups \
      --group-ids ${aws_sg_id}
    sleep 3
  fi

  sudo service ${webserver} stop
  sudo ./letsencrypt-auto -v certonly \
       --renew-by-default \
       -d ${domain_name} \
       --server https://acme-v01.api.letsencrypt.org/directory
  sudo service ${webserver} start

  if [ "x${aws_sg_id}" != "x" ]; then
    aws ${aws_global_opts} ec2 revoke-security-group-ingress \
      --group-id ${aws_sg_id} \
      --cidr 0.0.0.0/0 \
      --port 443 \
      --protocol tcp
    aws ${aws_global_opts} ec2 describe-security-groups \
      --group-ids ${aws_sg_id}
  fi

  # Send Notification
  if [ "x${notif_sender}" != "x" -a "x${notif_recipient}" != "x" ]; then
    echo "The certs for ${domain_name} was renewed." | \
      mail -s "${notif_subject}" \
           -r "${notif_sender}" \
           ${notif_recipient}
  fi
  retval=${RETCODE_WARN_EXPIRES_IN_ALERT_DAYS_2}

elif [ ${time_alert_days_1} -le ${time_now} ]; then
  echo "The certs for ${domain_name} will expire at ${time_alert_days_1_in_humanreadable}."

  # Send Notification Only
  if [ "x${notif_sender}" != "x" -a "x${notif_recipient}" != "x" ]; then
    echo "The certs for ${domain_name} will expire at ${time_alert_days_1_in_humanreadable}." | \
      mail -s "${notif_subject}" \
           -r "${notif_sender}" \
           ${notif_recipient}
  fi
  retval=${RETCODE_WARN_EXPIRES_IN_ALERT_DAYS_1}
fi
exit $retval
