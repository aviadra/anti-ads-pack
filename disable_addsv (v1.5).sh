#!/bin/sh
########Debug commands for terminal############
echo "alias mem='cat /proc/meminfo'" >>/tmp/root/.profile
echo "alias ll='ls -lash --color=auto'" >>/tmp/root/.profile
echo "alias ls='ls --color=auto'" >>/tmp/root/.profile
echo "alias tlog='tail -f /var/log/messages'" >>/tmp/root/.profile
echo "alias clog='cat /var/log/messages | grep local0.notice'" >>/tmp/root/.profile
########Functions setup#########################
logger_ads()
{
logger -s -p local0.notice -t ad_blocker_script $1
}
 
softlink_func()
 {
 ln -s /tmp/$1 /jffs/dns/$2
        if [ "`echo $?`" -eq 0 ] ; then
 logger_ads "Created $3 softlink to RAM on JFFS"
        else
 logger_ads "The attempt to create $3 softlink to RAM on JFFS *FAILED*"
 logger_ads "it is obvious something IS *terribly wrong*. Will now exit.. bye bye (ads will not be blocked)"
 exit 1
        fi
 }
 
note_no_space()
 {
 logger_ads "I assure you this only takes $1 blocks, but I guess your too close to the edge for JFFSs comfort"
    logger_ads "deleting the half witted file, as to not confuse the DNS service and free up the JFFS space for other uses."
 }
##################################################
nvram set aviad_changed_nvram=0
logger_ads "###########Ads blocker started###########"

if [[ -z "$1" ]]; then
	logger_ads "Sleeping for 30 secs to give time for router boot"
	sleep 30
else
	logger_ads "override switch given"
	[[ $1 = "-h" || $1 = "/?" ]] && echo "use -m to override the 30 seconds delay and -f to force a list refresh" && exit 0	
	[ $1 = "-f" ] && rm /jffs/dns/dnsmasq.adblock.conf && rm /jffs/dns/dlhosts
fi

while ! ping www.google.com -c 1 > /dev/null ; do
	logger_ads "waiting for the internet connection to come up"
	sleep 5
done
 
logger_ads "New IP and ports setup"
	pixel="`ifconfig br0 | grep inet | awk '{ print $3 }' | awk -F ":" '{ print $2 }' | cut -c 1-10`"254
	/sbin/ifconfig br0:1 $pixel netmask "`ifconfig br0 | grep inet | awk '{ print $4 }' | awk -F ":" '{ print $2 }'`" broadcast "`ifconfig br0 | grep inet | awk '{ print $3 }' | awk -F ":" '{ print $2 }'`" up
if [[ -z "`ps | grep -v grep | grep "httpd -p 81"`" && `nvram get http_lanport` -ne 81 ]] ; then
	logger_ads "it seems that the web-GUI is not setup yet"
	stopservice httpd
	nvram set http_lanport=81
	nvram set aviad_changed_nvram=1
	startservice httpd
else
	logger_ads "The web-GUI is already setup"
fi
 
logger_ads "Adding a refresh cycle by puting the script in cron if it isnt there yet"
if [[ -z "`cat /tmp/crontab | grep "/jffs/dns/disable_adds.sh"`" ]] ; then
	echo '0 * * * * root /jffs/dns/disable_adds.sh -m' > /tmp/crontab
	stopservice cron && logger_ads "stopped the cron service"
	startservice cron && logger_ads "started the cron service"
else
	logger_ads "The script is already in cron"
fi

logger_ads "Redirect setup & Appending to the FW script"
[[ -z "`iptables -L -n -t nat | grep $(nvram get lan_ipaddr) | grep 81`" ]] && logger_ads "did NOT find an active redirect rule with the iptable command, injecting it now." && /usr/sbin/iptables -t nat -I PREROUTING 1 -d $(nvram get lan_ipaddr) -p tcp --dport 80 -j DNAT --to $(nvram get lan_ipaddr):81
nvram get rc_firewall > /tmp/fw.tmp
if [[ -z "`cat /tmp/fw.tmp | grep "/usr/sbin/iptables -t nat -I PREROUTING 1 -d $(nvram get lan_ipaddr) -p tcp --dport 80 -j DNAT --to $(nvram get lan_ipaddr):81"`" ]] ; then
	echo "/usr/sbin/iptables -t nat -I PREROUTING 1 -d $(nvram get lan_ipaddr) -p tcp --dport 80 -j DNAT --to $(nvram get lan_ipaddr):81" >> /tmp/fw.tmp
	nvram set rc_firewall="`cat /tmp/fw.tmp`"
	logger_ads "DONE appending to FW script"
	nvram set aviad_changed_nvram=1
else
	logger_ads "The FW script is already in place"
fi
rm /tmp/fw.tmp
 
logger_ads "Starting or Restarting pixelsrv"
killall pixelserv
/jffs/dns/pixelserv $pixel -p 80
 
logger_ads "Get the online lists"
[ ! -e /jffs/dns/whitelist ] && echo google-analytics > /jffs/dns/whitelist && echo googleadservices >> /jffs/dns/whitelist
if [[ -n "$(find /jffs/dns/dlhosts -mtime +3)" || -n "$(find /jffs/dns/dnsmasq.adblock.conf -mtime +3)" || ! -e /jffs/dns/dlhosts || ! -e /jffs/dns/dnsmasq.adblock.conf ]]; then
	logger_ads "The lists are NOT setup at all yet, or more then 3 days old. will now retrieve them from the web"
	logger_ads "Retrieving the MVPS hosts list"
	wget -q -O - http://www.mvps.org/winhelp2002/hosts.txt | grep "^127.0.0.1" | grep -v localhost | tr -d '\015' >/tmp/dlhosts.tmp
	logger_ads "adjusting the MVPS hosts list for our use"
	cat /jffs/dns/whitelist | while read line; do sed -i /${line}/d /tmp/dlhosts.tmp ; done
	sed -i s/127.0.0.1/$pixel/g /tmp/dlhosts.tmp
	logger_ads "done adjusting the MVPS hosts list use"
	logger_ads "retrieving the Yoyo domain list"
	wget -q "http://pgl.yoyo.org/adservers/serverlist.php?hostformat=dnsmasq&showintro=0&mimetype=plaintext" -O /tmp/adblock.tmp
	logger_ads "adjusting the Yoyo domain list for our use"
	cat /jffs/dns/whitelist | while read line; do sed -i /${line}/d /tmp/adblock.tmp ; done
	sed -i s/127.0.0.1/$pixel/g /tmp/adblock.tmp
	if [ "`df| grep /jffs | awk '{ print $4 }'`" -ge 65 ] ; then
		logger_ads "Moving the Yoyo list to JFFS (as it looks that there is enough space for it)"
		mv /tmp/adblock.tmp /jffs/dns/dnsmasq.adblock.conf
			if [ "`echo $?`" -eq 0 ] ; then
				logger_ads "Moving the YoYo domain list to JFFS operation was successful"
			else
				note_no_space 20
				rm /jffs/dns/dnsmasq.adblock.conf
				softlink_func adblock.tmp dnsmasq.adblock.conf YoYo
			fi
	else
		logger_ads "*NOT* Moving the Yoyo list to JFFS (as it looks that there is *NOT* enough space for it)"
		softlink_func adblock.tmp dnsmasq.adblock.conf YoYo
	fi
	if [ "`df| grep /jffs | awk '{ print $4 }'`" -ge 100 ] ; then
		logger_ads "Moving the MVPS hosts list to JFFS (as it looks like there is enough space for it)"
		mv /tmp/dlhosts.tmp /jffs/dns/dlhosts
			if [ "`echo $?`" -eq 0 ] ; then
				logger_ads "Moving the MVPS hosts list to JFFS operation was successful"
			else
				note_no_space 72
			  	rm /jffs/dns/dlhosts
				softlink_func dlhosts.tmp dlhosts MVPS
			fi
	else
				logger_ads "*NOT* Moving the MVPS list to JFFS (as it looks that there is *NOT* enough space for it)"
				softlink_func dlhosts.tmp dlhosts MVPS
	fi
else
    logger_ads "The lists are less then 3 days old, saving on flash erosion and NOT refreshing them"
    fi
 
logger_ads "Injecting the DNSMasq nvram options with the dynamic block lists"
nvram get dnsmasq_options > /tmp/dns-options.tmp
if [[ -z "`cat /tmp/dns-options.tmp | grep "/jffs/dns/dnsmasq.adblock.conf"`" || -z "`cat /tmp/dns-options.tmp | grep "/jffs/dns/dlhosts"`" && -e /jffs/dns/dnsmasq.adblock.conf ]] ; then
	logger_ads "Did not find DNSMsaq options in nvram and adding them now"
	echo "conf-file=/jffs/dns/dnsmasq.adblock.conf" >> /tmp/dns-options.tmp
	echo "addn-hosts=/jffs/dns/dlhosts" >> /tmp/dns-options.tmp
	nvram set aviad_changed_nvram=1
	logger_ads "Added options to nvram DNSMasq options"
else
	logger_ads "The DNSMaq options are already in place"
fi
 
logger_ads "Checking if the personal list is a file"
if [[ -z "`cat /tmp/dnsmasq.conf | grep conf-file=/jffs/dns/personal-ads-list.conf`" && -z "`nvram get dnsmasq_options | grep "/jffs/dns/personal-ads-list.conf"`" && -e /jffs/dns/personal-ads-list.conf ]] ; then
	logger_ads "Yes the personal list is in the form of a file"
	logger_ads "Removing whitelist from the personal file"
	cat /jffs/dns/whitelist | while read line; do sed -i /${line}/d /jffs/dns/personal-ads-list.conf ; done
	echo "conf-file=/jffs/dns/personal-ads-list.conf" >> /tmp/dns-options.tmp
	nvram set aviad_changed_nvram=1
else
	[ ! -e /jffs/dns/personal-ads-list.conf ] && logger_ads "The personal list (assuming there is one) is not in a file"
	[ -n "`nvram get dnsmasq_options | grep "/jffs/dns/personal-ads-list.conf"`" ] && logger_ads "The personal list is a file, and... it is already in place according to the NVRAM options readout"
	[ $1 = "-f" ] && cat /jffs/dns/whitelist | while read line; do sed -i /${line}/d /jffs/dns/personal-ads-list.conf ; done && logger_ads "overide switch given so removed whitelist from personal file"
fi
 
logger_ads "Final settings implementer"
if [ "`nvram get aviad_changed_nvram`" -eq 1 ] ; then
	nvram set dnsmasq_options="`cat /tmp/dns-options.tmp`"
	logger_ads "Found that NVRAM was changed and committing changes now"
	nvram commit
	nvram set aviad_changed_nvram=0
	logger_ads "Refreshing DNS settings"
	stopservice dnsmasq && logger_ads "stopped the dnsmasq service"
	startservice dnsmasq && logger_ads "started the dnsmasq service"
else
	logger_ads "Nothing to commit"
fi
	rm /tmp/dns-options.tmp
#######uncomment to enable blinking##############
#logger_ads "Blink the SES Leds"
#tmp=20
#while [ $tmp -ge 0 ]; do
#	/sbin/gpio enable 3
#	ping "`nvram get lan_ipaddr`" -c 1 > /dev/null
#	/sbin/gpio disable 3
#	tmp=`expr $tmp - 1`
#done
#/sbin/gpio enable 2
#/sbin/gpio disable 3
logger_ads "##########The Ads blocker script has finished its run and you should up and running##########"