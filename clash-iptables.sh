#! /bin/sh
case $1 in
start)
	ip rule  add fwmark 1 table 100
	ip route add local default dev lo table 100
	iptables -t mangle -N CLASH_EXTERNAL
	iptables -t mangle -A CLASH_EXTERNAL -d 0.0.0.0/8 -j RETURN
	iptables -t mangle -A CLASH_EXTERNAL -d 10.0.0.0/8 -j RETURN
	iptables -t mangle -A CLASH_EXTERNAL -d 127.0.0.0/8 -j RETURN
	iptables -t mangle -A CLASH_EXTERNAL -d 169.254.0.0/16 -j RETURN
	iptables -t mangle -A CLASH_EXTERNAL -d 172.16.0.0/12 -j RETURN
	iptables -t mangle -A CLASH_EXTERNAL -d 192.168.0.0/16 -j RETURN
	iptables -t mangle -A CLASH_EXTERNAL -d 224.0.0.0/4 -j RETURN
	iptables -t mangle -A CLASH_EXTERNAL -d 240.0.0.0/4 -j RETURN
	iptables -t mangle -A CLASH_EXTERNAL -p tcp -j TPROXY --on-port 7893 --tproxy-mark 1
	iptables -t mangle -A CLASH_EXTERNAL -p udp -j TPROXY --on-port 7893 --tproxy-mark 1
	iptables -t mangle -A PREROUTING -j CLASH_EXTERNAL

	iptables -t mangle -N CLASH_LOCAL
	iptables -t mangle -A CLASH_LOCAL -m cgroup --path "bypass.slice"  -j RETURN
	iptables -t mangle -A CLASH_LOCAL -d 0.0.0.0/8 -j RETURN
	iptables -t mangle -A CLASH_LOCAL -d 10.0.0.0/8 -j RETURN
	iptables -t mangle -A CLASH_LOCAL -d 127.0.0.0/8 -j RETURN
	iptables -t mangle -A CLASH_LOCAL -d 169.254.0.0/16 -j RETURN
	iptables -t mangle -A CLASH_LOCAL -d 172.16.0.0/12 -j RETURN
	iptables -t mangle -A CLASH_LOCAL -d 192.168.0.0/16 -j RETURN
	iptables -t mangle -A CLASH_LOCAL -d 224.0.0.0/4 -j RETURN
	iptables -t mangle -A CLASH_LOCAL -d 240.0.0.0/4 -j RETURN
	iptables -t mangle -A CLASH_LOCAL -p tcp -j MARK --set-mark 1
	iptables -t mangle -A CLASH_LOCAL -p udp -j MARK --set-mark 1
	iptables -t mangle -A OUTPUT -j CLASH_LOCAL
	;;
stop)
	ip rule  del fwmark 1 table 100
	ip route del local default dev lo table 100
	iptables -t mangle -D PREROUTING -j CLASH_EXTERNAL
	iptables -t mangle -F CLASH_EXTERNAL
	iptables -t mangle -X CLASH_EXTERNAL
	iptables -t mangle -D OUTPUT -j CLASH_LOCAL
	iptables -t mangle -F CLASH_LOCAL
	iptables -t mangle -X CLASH_LOCAL
	;;
esac
exit 0

