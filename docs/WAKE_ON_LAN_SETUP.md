# Wake-on-LAN Setup Guide

This guide covers the setup and configuration of Wake-on-LAN (WoL) for VMStation cluster nodes.

## Overview

Wake-on-LAN allows you to remotely power on nodes by sending a special "magic packet" over the network. This is essential for:
- Waking nodes after auto-sleep
- On-demand cluster scaling
- Disaster recovery
- Remote maintenance

## Prerequisites

### Hardware Requirements

1. **Network Interface Card (NIC)**
   - Must support Wake-on-LAN
   - Most modern NICs (Intel, Realtek, Broadcom) support WoL

2. **BIOS/UEFI Settings**
   - WoL must be enabled
   - Often found under "Power Management" or "Network Boot"
   - May be labeled as:
     - Wake on LAN
     - Wake on PCI/PCIe
     - Power On by PCIE/PCI
     - Resume on LAN

3. **Network Switch**
   - Must forward broadcast packets (UDP port 9 or 7)
   - VLAN configuration may require specific settings

### Software Requirements

- `ethtool` - For configuring WoL on the interface
- `wakeonlan` or `etherwake` - For sending magic packets

## Hardware Setup

### Enable WoL in BIOS

1. Enter BIOS/UEFI setup (usually F2, Del, or F12 during boot)
2. Navigate to Power Management settings
3. Enable "Wake on LAN" or similar option
4. Save and exit

### Network Interface Configuration

#### Check WoL Support

```bash
# Check if interface supports WoL
ethtool eth0 | grep -i wake

# Output should show:
# Supports Wake-on: pumbg
# Wake-on: d
```

WoL modes:
- `p` - Wake on PHY activity
- `u` - Wake on unicast messages
- `m` - Wake on multicast messages
- `b` - Wake on broadcast messages
- `g` - Wake on magic packet (recommended)
- `d` - Disabled

#### Enable WoL

```bash
# Enable magic packet wake
sudo ethtool -s eth0 wol g

# Verify
ethtool eth0 | grep "Wake-on"
# Should show: Wake-on: g
```

## Persistent WoL Configuration

### Using systemd (Recommended)

Create a systemd service to enable WoL at boot:

```bash
sudo cat > /etc/systemd/system/wol.service << 'EOF'
[Unit]
Description=Enable Wake-on-LAN
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -s eth0 wol g
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable wol.service
sudo systemctl start wol.service
```

### Using Netplan (Ubuntu)

Edit `/etc/netplan/01-netcfg.yaml`:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      wakeonlan: true
      dhcp4: true
```

Apply:
```bash
sudo netplan apply
```

### Using Network Manager

```bash
# Get connection name
nmcli connection show

# Enable WoL
nmcli connection modify "Wired connection 1" 802-3-ethernet.wake-on-lan magic

# Reload
nmcli connection up "Wired connection 1"
```

## Ansible Deployment

### Setup Wake-on-LAN on All Nodes

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  power-management/playbooks/setup-wake-on-lan.yml
```

### What the Playbook Does

1. Installs required packages (ethtool, wakeonlan)
2. Enables WoL on the primary network interface
3. Creates persistence (systemd service)
4. Stores MAC addresses for the cluster registry
5. Creates per-node wake scripts

## Using Wake-on-LAN

### Command Line Tools

```bash
# Wake using MAC address
wakeonlan AA:BB:CC:DD:EE:FF

# Wake using hostname (if configured)
wakeonlan worker-01

# Wake with specific interface
wakeonlan -i eth0 AA:BB:CC:DD:EE:FF
```

### VMStation Wake Script

```bash
# Wake specific node
/opt/vmstation/power/vmstation-wake.sh worker-01

# Wake with verification
/opt/vmstation/power/vmstation-wake.sh worker-01 --verify

# Wake all nodes
/opt/vmstation/power/vmstation-wake.sh --all

# Wake only workers
/opt/vmstation/power/vmstation-wake.sh --workers

# List node status
/opt/vmstation/power/vmstation-wake.sh --list
```

### HTTP API (Wake Event Handler)

```bash
# Wake single node
curl -X POST http://master:9876/wake/worker-01 \
  -H "X-Auth-Token: your-token"

# Wake with verification
curl -X POST "http://master:9876/wake/worker-01?verify=true" \
  -H "X-Auth-Token: your-token"

# Wake all nodes
curl -X POST http://master:9876/wake/all \
  -H "X-Auth-Token: your-token"

# Check status
curl http://master:9876/status
```

## WoL Registry

### Registry Location

```bash
/etc/vmstation/wol-registry.conf
```

### Registry Format

```
# hostname|ip|mac|interface
worker-01|192.168.1.11|AA:BB:CC:DD:EE:F1|eth0
worker-02|192.168.1.12|AA:BB:CC:DD:EE:F2|eth0
worker-03|192.168.1.13|AA:BB:CC:DD:EE:F3|eth0
```

### Generate Registry

The registry is automatically generated when running the WoL setup playbook:

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  power-management/playbooks/setup-wake-on-lan.yml
```

## Network Configuration

### Switch Configuration

Ensure your switch:
1. Forwards broadcast packets on UDP port 7 or 9
2. Doesn't block magic packets
3. Has STP (Spanning Tree Protocol) configured correctly

### VLAN Considerations

If nodes are on different VLANs:
1. Configure a wake proxy/relay on each VLAN
2. Use directed broadcast instead of subnet broadcast
3. Consider using IP-directed broadcast

### Firewall Rules

Allow WoL packets:

```bash
# iptables
iptables -A INPUT -p udp --dport 7 -j ACCEPT
iptables -A INPUT -p udp --dport 9 -j ACCEPT

# ufw
ufw allow 7/udp
ufw allow 9/udp

# firewalld
firewall-cmd --permanent --add-port=7/udp
firewall-cmd --permanent --add-port=9/udp
firewall-cmd --reload
```

## Troubleshooting

### Node Won't Wake

#### Check 1: BIOS Settings
- Enter BIOS and verify WoL is enabled
- Check power supply standby power is sufficient

#### Check 2: WoL Enabled on Interface
```bash
ethtool eth0 | grep "Wake-on"
# Should show: Wake-on: g
```

#### Check 3: Correct MAC Address
```bash
ip link show eth0
# Look for the MAC address
```

#### Check 4: Magic Packet Reaches Node
Use tcpdump on a running node to verify:
```bash
tcpdump -i eth0 ether proto 0x0842 or udp port 7 or udp port 9
```

#### Check 5: Power Cable Connected
WoL requires the node to have power (standby)

### Packet Not Reaching Node

1. Check switch configuration
2. Verify VLAN settings
3. Test from same subnet first
4. Check firewall rules

### WoL Works Sometimes

1. Check for power saving modes in NIC
2. Verify WoL persistence after reboot
3. Check BIOS power management settings

### Debug Magic Packet

```bash
# Send packet with verbose output
wakeonlan -v AA:BB:CC:DD:EE:FF

# Capture packets
tcpdump -XX -i eth0 'ether proto 0x0842 or udp port 7 or udp port 9'
```

## Magic Packet Format

A magic packet consists of:
1. 6 bytes of `0xFF` (synchronization stream)
2. 16 repetitions of the target MAC address
3. Optional: 6-byte password (SecureOn)

Example for MAC `AA:BB:CC:DD:EE:FF`:
```
FF FF FF FF FF FF           <- Sync stream
AA BB CC DD EE FF           <- MAC address (repeated 16 times)
AA BB CC DD EE FF
... (14 more repetitions)
```

## Advanced Configuration

### Secure Wake-on-LAN

Some NICs support SecureOn, requiring a password:

```bash
# Enable with password
ethtool -s eth0 wol s password aa:bb:cc:dd:ee:ff

# Send packet with password
wakeonlan -p aa:bb:cc:dd:ee:ff AA:BB:CC:DD:EE:FF
```

### Wake-on-LAN over Internet

For remote wake over the internet:
1. Configure port forwarding on your router
2. Use a VPN for security
3. Consider wake-on-WAN tools

```bash
# Forward UDP port 9 to broadcast
# (Router configuration varies)
```

### Integration with Monitoring

Configure Prometheus/Grafana to:
1. Track node power state
2. Alert on failed wake attempts
3. Monitor power consumption

## Best Practices

1. **Document MAC addresses** - Keep a secure record
2. **Test regularly** - Verify WoL works monthly
3. **Monitor wake success** - Track success/failure rates
4. **Secure the wake endpoint** - Use authentication
5. **Have a backup plan** - Physical access for emergencies
6. **Consider power costs** - WoL requires standby power

## Quick Reference

| Command | Description |
|---------|-------------|
| `ethtool eth0 \| grep Wake` | Check WoL status |
| `ethtool -s eth0 wol g` | Enable WoL |
| `wakeonlan MAC` | Send magic packet |
| `vmstation-wake.sh --list` | Show node status |
| `vmstation-wake.sh --all` | Wake all nodes |
