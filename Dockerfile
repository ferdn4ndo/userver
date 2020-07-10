FROM amazonlinux:2

# To ensure that the output of "rpm -qa" matches on both machines
# (tip: use http://www.listdiff.com/compare-2-lists-difference-tool)
RUN yum update -y && yum install -y \
   acpid amazon-linux-extras-yum-plugin amazon-ssm-agent at attr audit authconfig aws-cfn-bootstrap awscli \
   bash-completion bc bind-export-libs bind-libs bind-libs-lite bind-license bind-utils binutils blktrace \
   boost-date-time boost-system boost-thread bridge-utils bzip2 chrony cloud-init cloud-utils-growpart cronie \
   cronie-anacron crontabs cryptsetup cyrus-sasl-plain device-mapper-event device-mapper-event-libs \
   device-mapper-persistent-data dhclient dhcp-common dhcp-libs dmidecode dmraid dmraid-events dosfstools dracut \
   dracut-config-generic dyninst e2fsprogs e2fsprogs-libs ec2-hibinit-agent ec2-instance-connect ec2-net-utils \
   ec2-utils ed ethtool file freetype gdisk generic-logos GeoIP gettext gettext-libs git glibc-all-langpacks \
   glibc-locale-source gpm-libs grub2 grub2-common grub2-pc grub2-pc-modules grub2-tools grub2-tools-extra \
   grub2-tools-minimal grubby gssproxy hardlink hibagent hostname hunspell hunspell-en hunspell-en-GB hunspell-en-US \
   hwdata initscripts iproute iptables iputils irqbalance jansson jbigkit-libs json-c kbd kbd-legacy \
   kbd-misc kernel kernel-tools keyutils kpartx kpatch-runtime langtable langtable-data langtable-python libaio \
   libbasicobjects libcollection libconfig libdaemon libdrm libdwarf libestr libicu libidn libini_config libjpeg-turbo \
   libnfsidmap libnl3 libnl3-cli libpath_utils libpciaccess libpipeline libpng libref_array libss libsss_idmap \
   libsss_nss_idmap libstoragemgmt libstoragemgmt-python libstoragemgmt-python-clibs libsysfs libteam libtiff libtirpc \
   libverto-libevent libwebp libxml2-python libyaml lm_sensors-libs lsof lvm2 lvm2-libs make man-db man-pages \
   man-pages-overrides mariadb-libs mdadm microcode_ctl mlocate mtr nano net-tools newt-python nfs-utils ntsysv \
   numactl-libs openssh-server openssl os-prober parted passwd pciutils pciutils-libs pkgconfig plymouth \
   plymouth-core-libs plymouth-scripts pm-utils policycoreutils postfix procps-ng psacct psmisc pystache \
   python-babel python-backports python-backports-ssl_match_hostname python-cffi python-chardet python-colorama \
   python-configobj python-daemon python-devel python-docutils python-enum34 python-idna python-ipaddress \
   python-jinja2 python-jsonpatch python-jsonpointer python-jwcrypto python-kitchen python-lockfile python-markupsafe \
   python-pillow python-ply python-pycparser python-repoze-lru python-requests python-six python-urllib3 \
   python2-botocore python2-cryptography python2-dateutil python2-futures python2-jmespath python2-jsonschema \
   python2-oauthlib python2-pyasn1 python2-rsa python2-s3transfer python2-setuptools PyYAML quota quota-nls rdate \
   rng-tools rootfiles rpcbind rpm-plugin-systemd-inhibit rsync rsyslog scl-utils screen selinux-policy \
   selinux-policy-targeted setserial setuptool sgpio shadow-utils sssd-client strace sudo sysctl-defaults sysstat \
   systemd-sysv systemtap-runtime sysvinit-tools tar tcp_wrappers tcp_wrappers-libs tcpdump tcsh teamd time traceroute \
   unzip update-motd usermode vim-common vim-enhanced vim-filesystem virt-what wget which words xfsdump yajl \
   yum-langpacks yum-utils zip

RUN amazon-linux-extras install -y docker

WORKDIR /userver

CMD tail -f /dev/null
#ENTRYPOINT ./setup.sh

