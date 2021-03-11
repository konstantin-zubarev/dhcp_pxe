#!/bin/bash

# Services install
echo Install PXE server
yum -y install epel-release

yum -y install dhcp-server
yum -y install tftp-server
yum -y install nginx

# open tftpd port in firewalld 
firewall-cmd --add-service=tftp
# disable selinux or permissive
setenforce 0
# 

# put dhcp configuration file
cat >>/etc/dhcp/dhcpd.conf <<EOF
option space pxelinux;
option pxelinux.magic code 208 = string;
option pxelinux.configfile code 209 = text;
option pxelinux.pathprefix code 210 = text;
option pxelinux.reboottime code 211 = unsigned integer 32;
option architecture-type code 93 = unsigned integer 16;
subnet 10.0.0.0 netmask 255.255.255.0 {
  #option routers 10.0.0.254;
  range 10.0.0.100 10.0.0.120;
  
  class "pxeclients" {
    match if substring (option vendor-class-identifier, 0, 9) = "PXEClient";
    next-server 10.0.0.20;
    
    if option architecture-type = 00:07 {
      filename "uefi/shim.efi";
    }
    else {
      filename "pxelinux/pxelinux.0";
    }
  }
}
EOF

# starting services
systemctl enable --now dhcpd

systemctl enable --now tftp.service

# install SYSLINUX modules in /var/lib/tftpboot, available for network booting
yum -y install syslinux-tftpboot.noarch
# create dir for pxelinux loader
mkdir /var/lib/tftpboot/pxelinux
# copy pxe loader and menu to pxelinux loader' folder
cp /tftpboot/pxelinux.0 /var/lib/tftpboot/pxelinux
cp /tftpboot/libutil.c32 /var/lib/tftpboot/pxelinux
cp /tftpboot/menu.c32 /var/lib/tftpboot/pxelinux
cp /tftpboot/libmenu.c32 /var/lib/tftpboot/pxelinux
cp /tftpboot/ldlinux.c32 /var/lib/tftpboot/pxelinux
cp /tftpboot/vesamenu.c32 /var/lib/tftpboot/pxelinux

# create pxe loader config folder
mkdir /var/lib/tftpboot/pxelinux/pxelinux.cfg

# create menu conf file
cat >/var/lib/tftpboot/pxelinux/pxelinux.cfg/default <<EOF
default menu
prompt 0
timeout 600
MENU TITLE PXE setup
LABEL local
  menu label Boot from ^local drive
  menu default
  localboot 0
LABEL linux
  menu label ^Install system
  kernel images/CentOS-8.2/vmlinuz
  append initrd=images/CentOS-8.2/initrd.img ip=enp0s3:dhcp inst.repo=http://10.0.0.20/pxe/centos8-install
LABEL linux-auto
  menu label ^Auto install system
  kernel images/CentOS-8.2/vmlinuz
  append initrd=images/CentOS-8.2/initrd.img ip=enp0s3:dhcp inst.ks=http://10.0.0.20/pxe/cfg/ks.cfg inst.repo=http://10.0.0.20/pxe/centos8-autoinstall
LABEL vesa
  menu label Install system with ^basic video driver
  kernel images/CentOS-8.2/vmlinuz
  append initrd=images/CentOS-8.2/initrd.img ip=dhcp inst.xdriver=vesa nomodeset
LABEL rescue
  menu label ^Rescue installed system
  kernel images/CentOS-8.2/vmlinuz
  append initrd=images/CentOS-8.2/initrd.img rescue
EOF

# create boot images folder and load images
mkdir -p /var/lib/tftpboot/pxelinux/images/CentOS-8.2/
curl -O http://mirror.nsc.liu.se/centos-store/8.2.2004/BaseOS/x86_64/os/images/pxeboot/initrd.img
curl -O http://mirror.nsc.liu.se/centos-store/8.2.2004/BaseOS/x86_64/os/images/pxeboot/vmlinuz
cp {vmlinuz,initrd.img} /var/lib/tftpboot/pxelinux/images/CentOS-8.2/


# Setup nginx auto install
curl -O http://mirror.nsc.liu.se/centos-store/8.2.2004/BaseOS/x86_64/os/images/boot.iso
mkdir -p /usr/share/nginx/html/pxe/centos8-install
mount -t iso9660 boot.iso /usr/share/nginx/html/pxe/centos8-install
systemctl enable --now nginx

autoinstall(){
# to speedup replace URL with closest mirror
curl -O http://mirror.nsc.liu.se/centos-store/8.2.2004/isos/x86_64/CentOS-8.2.2004-x86_64-minimal.iso
mkdir -p /usr/share/nginx/html/pxe/centos8-autoinstall
mount -t iso9660 CentOS-8.2.2004-x86_64-minimal.iso /usr/share/nginx/html/pxe/centos8-autoinstall
mkdir -p /usr/share/nginx/html/pxe/cfg

cat > /usr/share/nginx/html/pxe/cfg/ks.cfg <<EOF
#version=RHEL8
ignoredisk --only-use=sda
autopart --type=lvm
# Partition clearing information
clearpart --all --initlabel --drives=sda
# Use graphical install
graphical
# Keyboard layouts
keyboard --vckeymap=ru --xlayouts='ru','us' --switch='grp:alt_shift_toggle'
# System language
lang ru_RU.UTF-8

# Network information
network  --bootproto=dhcp --device=enp0s3 --ipv6=auto --activate
network  --bootproto=dhcp --device=enp0s8 --onboot=off --ipv6=auto --activate
network  --hostname=localhost.localdomain
# Root password
rootpw --iscrypted $6$DK7u.EvFwk5KSEUV$m8LuEqhoVHAKHvzk7HZ6FJiPIxaiDQ.5hxnaqsnHRKslTfsnUz1e4BltDztrb2Rsf7p3fPXKzyfnsR.sanvWk1
# Run the Setup Agent on first boot
firstboot --enable
# Do not configure the X Window System
skipx
# System services
services --enabled="chronyd"
# System timezone
timezone America/New_York --isUtc
user --name=vagrant --password=$6$75bCLHCpF69FKivF$.dAiDnD4MoOicCg6ulSM4G20k/09xtQQsW9f5bfbe3Snp2PvTz91sVl8G3SUWIdK.9yFR.6vG4.BNbiJ5.JGS1 --iscrypted --gecos="vagrant"

%packages
@^minimal-environment
kexec-tools

%end

%addon com_redhat_kdump --enable --reserve-mb='auto'

%end

%anaconda
pwpolicy root --minlen=6 --minquality=1 --notstrict --nochanges --notempty
pwpolicy user --minlen=6 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=6 --minquality=1 --notstrict --nochanges --notempty
%end
EOF

systemctl restart nginx
}

autoinstall
