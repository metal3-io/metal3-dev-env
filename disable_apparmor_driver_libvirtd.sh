selinux="#security_driver = \"selinux\""
apparmor="security_driver = \"apparmor\""
none="security_driver = \"none\""
sudo sed -i "s/$selinux/$none/g" /etc/libvirt/qemu.conf
sudo sed -i "s/$apparmor/$none/g" /etc/libvirt/qemu.conf
sudo systemctl restart libvirtd 
