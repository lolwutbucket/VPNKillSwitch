#!/bin/sh
#run script as computer boots

ipTablesFunction() {
	IP=$(wget https://duckduckgo.com/?q=whats+my+ip -q -O - | grep  -Eo '([0-9]{1,3}[\.]){3}[0-9]{1,3}')
	echo "IP address is $IP"
	 iptables -F
	 iptables -X
	 iptables -t nat -F
	 iptables -t nat -X
	 iptables -t mangle -F
	 iptables -t mangle -X
	
	 iptables -A INPUT -i lo -j ACCEPT
	 iptables -A OUTPUT -o lo -j ACCEPT #allow loopback access
	 iptables -A OUTPUT -d 255.255.255.255 -j  ACCEPT #make sure  you can communicate with any DHCP server
	 iptables -A INPUT -s 255.255.255.255 -j ACCEPT #make sure you   can communicate with any DHCP server
	 iptables -A INPUT -s 192.168.1.0/24 -d 192.168.1.0/24 -j ACCEPT   #make sure that you can communicate within your own network
	 iptables -A OUTPUT -s 192.168.1.0/24 -d 192.168.1.0/24 -j ACCEPT
	 iptables -A FORWARD -i wlan0 -o tun0 -j ACCEPT
	 iptables -A FORWARD -i tun0 -o wlan0 -j ACCEPT # make sure that   eth+ and tun+ can communicate
	 iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE # in the   POSTROUTING chain of the NAT table, map the tun+ interface     outgoing packet IP address, cease examining rules and let the header  be modified, so that we don't have to worry about ports or any other  issue - please check this rule with care if you have already a NAT  table in your chain
	 iptables -A OUTPUT -o wlan0 ! -d $IP -j DROP  # if destination for    outgoing packet on eth+ is NOT a.b.c.d, drop the packet, so that    nothing leaks if VPN disconnects
	echo "Created IP tables for standard usage"
	
	return 0
	}

vpnConnectFunction() {
	echo "connecting to VPN"
	 openvpn --daemon piBox --log /home/pi/openvpn.txt --cd /etc/openvpn --config Germany.ovpn #.ovpn has automated credentials
	sleep 15
	# http://forum.ipfire.org/viewtopic.php?t=12251
	ifconfig | grep tun0 > /dev/null
	t=$?
	if [ "$t" != 0 ]; then
		echo "no tunnel built"
		# logger -t TAPTEST "no tap-device available"
		# modprobe tun
		# openvpn --config $config
		# logger -t TAPTEST "tap started"
		# sleep 3
		return "1"
		
	else
		return "0"
		
	fi
}

vpnCreateWhiteListFunction() {
# this needs to be periodically/daily updated and stored as an offline iptables file, cannot be updated on an unsecured connection
#  UDP ports 9201, 1194, 8080 and 53 as well as TCP ports 443, 110, 80

echo "Creating a safe connection environment"

 iptables -F

 iptables -A OUTPUT -d germany.privateinternetaccess.com -p udp --dport 9201 -j ACCEPT
 iptables -A INPUT -d germany.privateinternetaccess.com -p udp --dport 9201 -j ACCEPT

 iptables -A OUTPUT -d germany.privateinternetaccess.com -p udp --dport 1194 -j ACCEPT
 iptables -A INPUT -d germany.privateinternetaccess.com -p udp --dport 1194 -j ACCEPT

 iptables -A OUTPUT -d germany.privateinternetaccess.com -p udp --dport 8080 -j ACCEPT
 iptables -A INPUT -d germany.privateinternetaccess.com -p udp --dport 8080 -j ACCEPT

 iptables -A OUTPUT -d germany.privateinternetaccess.com -p udp --dport 53 -j ACCEPT
 iptables -A INPUT -d germany.privateinternetaccess.com -p udp --dport 53 -j ACCEPT

 iptables -A OUTPUT -d germany.privateinternetaccess.com -p tcp --dport 443 -j ACCEPT
 iptables -A INPUT -d germany.privateinternetaccess.com -p tcp --dport 443 -j ACCEPT

 iptables -A OUTPUT -d germany.privateinternetaccess.com -p tcp --dport 110 -j ACCEPT
 iptables -A INPUT -d germany.privateinternetaccess.com -p tcp --dport 110 -j ACCEPT

 iptables -A OUTPUT -d germany.privateinternetaccess.com -p tcp --dport 80 -j ACCEPT
 iptables -A INPUT -d germany.privateinternetaccess.com -p tcp --dport 80 -j ACCEPT

 iptables-save > vpnwhitelist.rules

return 0
}

vpnRestoreWhiteListFunction() {

echo "Reverting to a safe connection environment"
 iptables-restore vpnwhitelist.rules

}

breakconnection() {
# https://fedoraproject.org/wiki/How_to_edit_iptables_rules#Inserting_Rules
 iptables -I OUTPUT 1 -d google.com -j DROP #sets google.com to a drop state, top of list
}

isPingGood=false # declare ping boolean
vpnCreateWhiteListFunction

#start actual script on forever loop
while true; do
	vpnConnectVar=1
	ipTablesVAR=1
	pingVAR=0
	if [ "$isPingGood" = false ]; then
		echo "Beginning VPN Session"
		vpnConnectFunction
		vpnConnectVAR=$?
		echo "The return code for vpnconnect function was $vpnConnectVAR"
		
		if [ "$vpnConnectVAR" -eq 0 ]; then
			ipTablesFunction
			ipTablesVAR=$?
				echo "The return code for iptables function was $ipTablesVAR"
		else
			#switch to vpnalternate connection here
			vpnRestoreWhiteListFunction
		fi
			
		if [ "$ipTablesVAR" -eq 0 ]; then
			# http://jeromejaglale.com/doc/unix/shell_scripts/ping
			ping -q -c5 google.com > /dev/null
			pingVAR=$?
			echo "PingVAR = Ping is (0 is good, 1 is bad) $pingVAR"
		fi
			
		if [ "$pingVAR" -eq 0 ] && [ "$ipTablesVAR" -eq 0 ] && [ "$vpnConnectVAR" -eq 0 ]; then
			echo "VPN connected, Ping Test Successful"
			isPingGood=true
		else
			echo "Connection was not established"
			isPingGood=false
		fi
		
		else
			echo "VPN appears good,testing now"
			# http://jeromejaglale.com/doc/unix/shell_scripts/ping
			ping -q -c5 google.com > /dev/null
			pingVAR=$?
			if [ "$pingVAR" -ne 0 ]; then
				echo "ping is bad"
				isPingGood=false # false boolean will reattempt the vpn session
				 ifconfig wlan0 down
				 killall -9 openvpn
				vpnRestoreWhiteListFunction
				 ifconfig wlan0 up
				
			else
				echo "Great!"
			fi
			
			echo "PingVAR = Ping is (0 is good, 1 is bad) $pingVAR"
			
	fi
	
done
	
	
