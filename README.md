## CrystalDiskInfo-PS-Wrapper

**Description:**

CrystalDiskInfo-PS-Wrapper.ps1 is a PowerShell script that enhances the functionality of CrystalDiskInfo by providing automated monitoring and alerting for disk health using SMART data. This script wraps around the CrystalDiskInfo tool, making it easier to deploy, run, and create SMART alerts in an automated way using your RMM. It automates the use of the application at scale for MSPs and other IT environments.

**Features:**

- Automatically downloads and installs CrystalDiskInfo if not already present.
- Verifies the version of CrystalDiskInfo to ensure compliance with specified requirements.
- Runs CrystalDiskInfo to generate SMART reports.
- Parses the SMART reports to identify 'Caution' or 'Bad' indicators.
- Sends alerts via a specified webhook when issues are detected.
- Optionally updates NinjaRMM SMART status based on disk health.
- Creates predictive disk failure events in the application log.
- Provides detailed logging for easy troubleshooting and audit.

**Usage:**

- Ensure PowerShell is installed on your system.
- Configure the script parameters such as webhook URL and desired version.
- Run the script to start monitoring disk health.

**Installation:**

- Clone the repository.
- Open the script file CrystalDiskInfo-PS-Wrapper.ps1.
- Modify the configuration variables as needed.
- Run the script using PowerShell.

## Disclaimer
Please note that while I have taken care to ensure the script works correctly, I am not responsible for any damage or issues that may arise from its use. Use this script at your own risk.

## Credit

This script was built to enhance the functionality of CrystalDiskInfo, created by Noriyuki Miyazaki. More information can be found at [CrystalMark](https://crystalmark.info/en/software/crystaldiskinfo/) and [CrystalDiskInfo GitHub repository](https://github.com/hiyohiyo/CrystalDiskInfo).

## License
This project is licensed under the terms of the GNU General Public License v3.0.
