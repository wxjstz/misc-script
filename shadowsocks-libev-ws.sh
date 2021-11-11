#! /bin/sh

check_installed(){
	which $1 >/dev/null
	return $?
}

[ $(id -u) -ne 0 ] && {
	echo !!! 请使用管理员权限运行 !!!
	exit 1
}

check_installed openssl || apt install -y openssl
CONFIG_PWD=$(openssl rand -base64 32 | tr -d /=+ | head -c 32)
CONFIG_PATH=$(openssl rand -base64 32 | tr -d /=+ | head -c 32)
read -p "Please enter an email address to receive notifications" CONFIG_EMAIL
read -p "Please enter the domain name of the current host" CONFIG_DOMAIN

# 停用相关服务
systemctl stop nginx.service 2>/dev/null
systemctl stop filebrowser.service 2>/dev/null
systemctl stop shadowsocks-libev-ws.service 2>/dev/null

# 安装配置ufw
check_installed ufw || apt install -y ufw
ufw default deny  incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable

# 安装配置acme.sh
check_installed curl  || apt install -y curl
check_installed socat || apt install -y socat
[ -d ~/.acme.sh ] || {
	curl -s https://get.acme.sh | sh -s email=$CONFIG_EMAIL
	~/.acme.sh/acme.sh --upgrade --auto-upgrade
}
[ -d ~/.acme.sh/$CONFIG_DOMAIN ] || {
	~/.acme.sh/acme.sh --issue -d $CONFIG_DOMAIN --standalone
	mkdir -p /etc/nginx/certs
	~/.acme.sh/acme.sh --install-cert -d $CONFIG_DOMAIN \
		--key-file /etc/nginx/certs/$CONFIG_DOMAIN.key \
		--fullchain-file /etc/nginx/certs/fullchain.cer
}

# 安装配置nginx
check_installed nginx || apt install -y nginx
cat << EOF > /etc/nginx/sites-enabled/default
server {
	listen 443 ssl default_server;
	listen [::]:443 ssl default_server;
	server_name $CONFIG_DOMAIN;
	ssl_certificate /etc/nginx/certs/fullchain.cer;
	ssl_certificate_key /etc/nginx/certs/$CONFIG_DOMAIN.key;
	ssl_session_cache shared:SSL:10m;
	ssl_session_timeout 10m;
	ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
	ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
	ssl_prefer_server_ciphers on;

	location /$CONFIG_PATH {
		proxy_redirect off;
		proxy_http_version 1.1;
		proxy_set_header Host \$http_host;
		proxy_set_header Upgrade \$http_upgrade;
		proxy_set_header Connection "Upgrade";
		proxy_pass http://127.0.0.1:8081;
	}

	location / {
		resolver 1.0.0.1;
		proxy_pass http://127.0.0.1:8080/;
	}
}
EOF
nginx -s reload

# 安装配置filebrowers
check_installed wget || apt install -y wget
url=$(curl -sL https://github.com/filebrowser/filebrowser/releases/latest | grep href | grep linux-amd64-filebrowser | awk -F\" '{print $2}')
url=https://github.com${url}
fn=$(echo $url | awk -F/ '{print $NF}')
cd /tmp
wget -qO $fn $url
tar -xvf $fn && {
	mv filebrowser /usr/bin/filebrowser
	chmod +x /usr/bin/filebrowser
}
cd -

mkdir -p /etc/filebrowser/
cat << EOF >/lib/systemd/system/filebrowser.service
[Unit]
Description=File Browser
After=network.target

[Service]
Type=exec
Restart=on-abort
ExecStartPre=mkdir -p /tmp/filebrowser
ExecStart=/usr/bin/filebrowser -d /etc/filebrowser/filebrowser.db -r /tmp/filebrowser

[Install]
WantedBy=multi-user.target
EOF
systemctl enable filebrowser.service
systemctl start  filebrowser.service

# 安装配置shadowsocks
check_installed ss-server || apt install -y shadowsocks-libev
check_installed ss-v2ray-plugin || apt install -y shadowsocks-v2ray-plugin
cat << EOF >/lib/systemd/system/shadowsocks-libev-ws.service
[Unit]
Description=shadowsocks-libev over websocket.
After=network.target

[Service]
Type=exec
Restart=on-abort
ExecStart=/usr/bin/ss-server -s 127.0.0.1 -p 8081 -m aes-256-gcm -k $CONFIG_PWD --plugin ss-v2ray-plugin --plugin-opts "server;path=/$CONFIG_PATH"

[Install]
WantedBy=multi-user.target
EOF
systemctl enable shadowsocks-libev-ws.service
systemctl start  shadowsocks-libev-ws.service

# 输出客户端配置参考信息
cat << EOF
clash配置参考 :
--------------------------------------------------------------------------------
- name: $CONFIG_DOMAIN
  type: ss
  server: $CONFIG_DOMAIN
  port: 443
  cipher: aes-256-gcm
  password: $CONFIG_PWD
  udp: false
  plugin: v2ray-plugin
  plugin-opts:
    mode: websocket
    tls: true
    mux: true
    host: $CONFIG_DOMAIN
    path: "/$CONFIG_PATH"

shadowsocks-libev客户端启动命令参考:
--------------------------------------------------------------------------------
/usr/bin/ss-local -l 1080 \\
	-s $CONFIG_DOMAIN -p 443 \\
	-m aes-256-gcm -k $CONFIG_PWD \\
	--plugin ss-v2ray-plugin \\
	--plugin-opts "tls;host=$CONFIG_DOMAIN;path=/$CONFIG_PATH"
/usr/bin/ss-redir -l 1081 \\
	-s $CONFIG_DOMAIN -p 443 \\
	-m aes-256-gcm -k $CONFIG_PWD \\
	--plugin ss-v2ray-plugin \\
	--plugin-opts "tls;host=$CONFIG_DOMAIN;path=/$CONFIG_PATH"

EOF
