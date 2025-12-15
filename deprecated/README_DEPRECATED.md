# Deprecated/Legacy/Buggy Playbooks and Scripts

This folder contains playbooks and scripts that are no longer supported, are known to be buggy, or have been superseded by better solutions. They are retained here for historical reference only and must not be used in any production or active deployment workflows.

## Contents
- **autosleep**: Playbooks and scripts for automatic node sleep/wake functionality. These are buggy, unreliable, and not recommended for use.
- **power-management**: Playbooks and scripts for cluster power management, including wake-on-LAN and spin-down features. These are deprecated due to reliability and maintainability issues.

## Why Deprecated?
- These playbooks/scripts have caused operational issues, are not maintained, or have been replaced by more robust solutions.
- They may not work with current cluster configurations or OS versions.
- Use of these files is unsupported and discouraged.

## What to Use Instead?
- For baseline configuration, infrastructure, and cluster management, use the playbooks in the main `ansible/playbooks/` directory.
- Do not reference or execute any files in this `deprecated/` folder in your automation or documentation.

---

**If you have questions about legacy power management or autosleep, consult the cluster maintainers.**
