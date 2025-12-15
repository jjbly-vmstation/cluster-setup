# Deprecated: Power Management Playbooks and Scripts

This directory contains legacy playbooks and scripts for cluster power management, including wake-on-LAN, autosleep, and spin-down features. These files are deprecated due to reliability, maintainability, and operational issues. Do not use these in production or active deployments.

## Deprecated Files
- configure-autosleep.yml
- setup-wake-on-lan.yml
- spin-down-cluster.yml
- vmstation-autosleep-monitor.sh
- vmstation-sleep.sh
- vmstation-wake.sh
- autosleep-monitor.service.j2
- autosleep-timer.timer.j2
- wake-event.service.j2

## Reason for Deprecation
- Known to be buggy and unreliable
- Not maintained or tested with current cluster stack
- Superseded by more robust solutions

**Retained for historical reference only.**