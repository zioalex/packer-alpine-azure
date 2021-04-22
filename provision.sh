# Community package required for shadow
echo "http://dl-cdn.alpinelinux.org/alpine/v3.13/community" >> /etc/apk/repositories

apk update && apk upgrade

# SW Pre-reqs 
apk add openssl sudo shadow parted e2fsprogs iptables sfdisk
apk add python3 py3-setuptools
apk add curl unzip e2fsprogs-extra
apk add icu-libs krb5-libs libgcc libint libstdc++ zlib gcompat
apk add libintl libssl1.1
# .NET Requirements
apk add bash icu-libs krb5-libs libgcc libintl libssl1.1 libstdc++ zlib
apk add libgdiplus --repository https://dl-3.alpinelinux.org/alpine/edge/testing/
#

# Resize root disk
parted /dev/sda ---pretend-input-tty <<EOF
resizepart
2
Yes
100%
Yes
quit
EOF

resize2fs /dev/sda2

# Install WALinuxAgent
wget https://github.com/Azure/WALinuxAgent/archive/v2.2.19.tar.gz && \
tar xvzf v2.2.19.tar.gz && \
cd WALinuxAgent-2.2.19 && \
python setup.py install && \
cd .. && \
rm -rf WALinuxAgent-2.2.19 v2.2.19.tar.gz

# Update boot params
sed -i 's/^default_kernel_opts="[^"]*/\0 console=ttyS0 earlyprintk=ttyS0 rootdelay=300/' /etc/update-extlinux.conf
update-extlinux

# sshd configuration
sed -i 's/^#ClientAliveInterval 0/ClientAliveInterval 180/' /etc/ssh/sshd_config

# Start waagent at boot
cat > /etc/init.d/waagent <<EOF
#!/sbin/openrc-run                                                                 

export PATH=/usr/local/sbin:$PATH

start() {                                                                          
        ebegin "Starting waagent"                                                  
        start-stop-daemon --start --exec /usr/sbin/waagent --name waagent -- -start
        eend $? "Failed to start waagent"                                          
}
EOF

chmod +x /etc/init.d/waagent
rc-update add waagent default

# Workaround for default password
# Basically, useradd on Alpine locks the account by default if no password
# was given, and the user can't login, even via ssh public keys. The useradd.sh script
# changes the default password to a non-valid but non-locking string.
# The useradd.sh script is installed in /usr/local/sbin, which takes precedence
# by default over /usr/sbin where the real useradd command lives.
mkdir -p /usr/local/sbin
mv /tmp/useradd.sh /usr/local/sbin/useradd
chmod +x /usr/local/sbin/useradd

# Avoid mail Spool creation error
sed -i 's/^CREATE_MAIL_SPOOL=yes/CREATE_MAIL_SPOOL=no/' /etc/default/useradd

useradd -d /home/vsts -m vsts

echo "%vsts ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/vsts_nopw

# ADO Agent Pre-requisites

# https://github.com/microsoft/azure-pipelines-agent/releases
cat > /home/vsts/install_ado_agent.sh <<EOF
# .NET
curl -L https://dot.net/v1/dotnet-install.sh > dotnet-install.sh
bash ./dotnet-install.sh --runtime dotnet -v 2.1.0
echo PATH=$PATH:~/.dotnet >> ~/.profile

curl -v https://vstsagentpackage.azureedge.net/agent/2.185.1/vsts-agent-linux-x64-2.185.1.tar.gz > vsts-agent-linux-x64-2.185.1.tar.gz
tar xvf vsts-agent-linux-x64-2.185.1.tar.gz
EOF

chown vsts:vsts  /home/vsts/install_ado_agent.sh
chmod +x /home/vsts/install_ado_agent.sh
su - vsts -c /home/vsts/install_ado_agent.sh

# TODO In prod reset the root password to random.