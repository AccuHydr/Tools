#!/bin/bash

#公钥
PUBLIC_KEY = ""
USER = "root"

# 检查root权限
if [ "$(id -u)" != "0" ]; then
   echo "此脚本必须以root权限运行" 
   exit 1
fi

#apt换源
cat > /etc/apt/sources.list << 'EOL'
deb https://mirrors.cloud.tencent.com/debian/ bookworm main non-free non-free-firmware contrib
deb-src https://mirrors.cloud.tencent.com/debian/ bookworm main non-free non-free-firmware contrib
deb https://mirrors.cloud.tencent.com/debian-security/ bookworm-security main
deb-src https://mirrors.cloud.tencent.com/debian-security/ bookworm-security main
deb https://mirrors.cloud.tencent.com/debian/ bookworm-updates main non-free non-free-firmware contrib
deb-src https://mirrors.cloud.tencent.com/debian/ bookworm-updates main non-free non-free-firmware contrib
deb https://mirrors.cloud.tencent.com/debian/ bookworm-backports main non-free non-free-firmware contrib
deb-src https://mirrors.cloud.tencent.com/debian/ bookworm-backports main non-free non-free-firmware contrib
EOL
apt update

# 备份原始配置文件
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# 写入新的SSH配置
cat > /etc/ssh/sshd_config << 'EOF'
Port 22
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
AuthorizedKeysFile    .ssh/authorized_keys
ChallengeResponseAuthentication no
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem    sftp    /usr/lib/openssh/sftp-server
EOF

# 为root用户配置SSH密钥
ROOT_SSH_DIR="/$USER/.ssh"
mkdir -p $ROOT_SSH_DIR
echo $PUBLIC_KEY > $ROOT_SSH_DIR/authorized_keys

# 设置权限
chmod 700 $ROOT_SSH_DIR
chmod 600 $ROOT_SSH_DIR/authorized_keys

#设置防火墙
apt install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw enable

# 重启SSH服务
systemctl restart sshd

echo "SSH配置已完成并服务已重启"
echo "root用户的SSH密钥已配置在: $ROOT_SSH_DIR/authorized_keys"
echo "配置文件位置: /etc/ssh/sshd_config"
