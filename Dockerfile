FROM centos
MAINTAINER kusari-k

ARG SSL_DOMAIN 
ARG USER_DOMAIN

EXPOSE 25 587 993 995 110 119 143 406 563 993 995 1109 2003 2004 2005 3905 4190

RUN sed -i -e "\$a fastestmirror=true" /etc/dnf/dnf.conf
RUN dnf update -y && \
	dnf install -y rsyslog postfix cyrus-imapd cyrus-sasl cyrus-sasl-plain && \
	dnf clean all

COPY setting.log run.sh /usr/local/bin/
COPY /home/podman/certbot_pod/letsencrypt/ /etc/letsencrypt/

#/etc/postfix/main.cf
RUN postconf -e "inet_interfaces=all" && \
	postconf -e "mydestination=localhost" && \
	postconf -e "myhostname=localhost" && \
	postconf -e "mydomain=localhost" && \
	postconf -e "smtpd_tls_cert_file=/etc/letsencrypt/live/$SSL_DOMAIN/fullchain.pem" && \
	postconf -e "smtpd_tls_key_file=/etc/letsencrypt/live/$SSL_DOMAIN/privkey.pem" && \
	postconf -e "home_mailbox = Maildir/" && \
	postconf -e "smtpd_recipient_restrictions=permit_mynetworks permit_sasl_authenticated reject" && \
	postconf -e "smtpd_sasl_auth_enable=yes" && \
	postconf -e "virtual_transport=lmtp:unix:/run/cyrus/socket/lmtp" && \
	postconf -e "virtual_mailbox_domains=$USER_DOMAIN" && \
	postconf -e "virtual_mailbox_maps=hash:/etc/postfix/vmailbox" && \
	postconf -e "masquerade_domains =$USER_DOMAIN" && \
	postconf -e "inet_protocols =ipv4" && \
	postconf -e "local_recipient_maps=proxy:unix:passwd.byname $alias_maps hash:/etc/postfix/vmailbox" && \
	postconf -e "smtpd_banner = ESMTP" 

#/etc/imapd.conf
RUN sed -i -e "/sasl_pwcheck_method/ s/:.*/: auxprop/" \
	-e "/virtdomains/ s/:.*/: userid/" \
	-e "/tls_server_cert/ s/:.*/: \/etc\/letsencrypt\/live\/$SSL_DOMAIN\/fullchain.pem/" \
	-e "/tls_server_key/ s/:.*/: \/etc\/letsencrypt\/live\/$SSL_DOMAIN\/privkey.pem/" \
	-e "/tls_client_ca_file/ s/:.*/: \/etc\/letsencrypt\/live\/$SSL_DOMAIN\/chain.pem/" \
	-e "/tls_client_ca_dir/ s/:.*/: \/etc\/letsencrypt\/live\/$SSL_DOMAIN\//" /etc/imapd.conf

#	-e "\$a smtpd_tls_session_cache_database = btree:/var/lib/postfix/smtpd_scache" \
#	-e "\$a smtpd_tls_session_cache_timeout = 3600s" \
#	-e "\$a smtpd_tls_received_header = yes" \
#	-e "\$a smtpd_tls_loglevel = 1" \
#	-e "\$a relay_domains = $alias_DOMAIN" \
#	-e "\$a unknown_relay_recipient_reject_code = 550" \
#	-e "\$a smtp_sasl_password_maps = hash:/etc/postfix/sasl_password" \

#/etc/postfix/master.cf
RUN smtps_num=$(grep -n "^#smtps" /etc/postfix/master.cf|sed s/:.*//) && \
	sed -i -e "/^#submission/ s/^#//" \
	-e "1,$smtps_num  s/^#\(.*syslog_name.*\)/\1/" \
	-e "1,$smtps_num  s/^#\(.*smtpd_tls_security_level.*\)/\1/" \
	-e "1,$smtps_num  s/^#\(.*smtpd_sasl_auth_enable.*\)/\1/" \
	-e "1,$smtps_num  s/^#\(.*smtpd_tls_auth_only.*\)/\1/" \
	-e "1,$smtps_num  s/^#\(.*smtpd_reject_unlisted_recipient.*\)/\1/" \
	-e "1,$smtps_num  s/^#\(.*smtpd_recipient_restrictions.*\)/\1/" \
	-e "1,$smtps_num  s/^#\(.*smtpd_relay_restrictions.*\)/\1/" /etc/postfix/master.cf
#	-e "/smtpd_tls_wrappermode/ s/^#//" \
#	-e "/smtpd_sasl_auth_enable/ s/^#//" \
#	-e "$(grep -m1 -n smtpd_sasl_auth_enable /etc/postfix/master.cf|sed s/:.*//) s/^/#/" \
#	-e "/smtpd_relay_restrictions/ s/^#//" \
#	-e "$(grep -m1 -n smtpd_relay_restrictions /etc/postfix/master.cf|sed s/:.*//) s/^/#/" /etc/postfix/master.cf

#/etc/sasl2/smtpd.conf
RUN sed -i -e "s/saslauthd/auxprop/" /etc/sasl2/smtpd.conf 

#user setting
RUN grep "^user:" /usr/local/bin/setting.log | \
	sed "s/^user://" | \
	awk -F '[:@]' '{print $1,$2,$3}' | \
	sed -ze "s/\n/ /g" | \ 
	xargs -n 3 -d " " bash -c 'echo $2|saslpasswd2 -c -p -u $1 $0'

RUN grep "^user:" /usr/local/bin/setting.log | \
	sed "s/^user://" | \
	awk -F '[:]' '{print $1,$1}' > /etc/postfix/vmailbox && \
	postmap /etc/postfix/vmailbox
	
#authority setting
RUN mkdir -p -m 750 /var/lib/cyrus /var/spool/cyrus  && \
	chown -R cyrus:mail /var/lib/cyrus /var/spool/cyrus && \
	chmod 777 /etc/sasldb2 && \
	chmod -R 777 /etc/letsencrypt/ && \
	chmod 777 /etc/postfix/vmailbox

#/etc/rsyslog.conf
RUN sed -i -e "/imjournal/ s/^/#/" \
	-e "s/off/on/" /etc/rsyslog.conf

RUN  chmod 755 /usr/local/bin/run.sh
ENTRYPOINT ["/usr/local/bin/run.sh"]
