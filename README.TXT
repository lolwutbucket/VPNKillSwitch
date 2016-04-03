sudo apt-get install open-vpn
place <VPNCERT>.ovpn in /etc/openvpn/
place a file called userpass into this same folder with VPN credentials
place OVPN_Connect with chmod 744 permissions in /etc/network/if-up.d/
edit /etc/resolvconf.conf and add a static DNS server to force over Tun0, the UFW rules block the gateway port 53
	http://itsfoss.com/resolvconf-permanent-ubuntu/
Apply UFW firewall rules
	https://www.reddit.com/r/VPN/comments/2vxrey/is_there_a_way_to_set_up_ubuntu_so_that_it_will/comog21