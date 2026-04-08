# OpenVPN Access Server: Backup, Restore & Audit Tool

This Bash script provides a reliable way to manage backups and monitor user activity for **OpenVPN Access Server (AS)**. It follows the official OpenVPN recommendation by using `sqlite3 .dump` to ensure database integrity.

## ✨ Features

* **Reliable Backups**: Creates SQL dumps of all critical databases instead of just copying files.
* **Selective Archiving**: Backs up configuration files (`/etc/`) but excludes heavy binary directories (like Windows installers) to save space.
* **Easy Restoration**: Interactive menu to choose a backup and restore the entire server state.
* **User Activity Audit**: A color-coded terminal report showing:
    * 🔴 **Red**: Blocked users (`prop_deny`).
    * 🟡 **Yellow**: Inactive users (over 30 days) or new accounts.
    * 🟢 **Green**: Recently active users.
* **Automation Ready**: Detects if it's running in a terminal or via Cron.
* **Notifications**: Sends HTML email reports after backup tasks.
* **Housekeeping**: Automatically rotates old backups and logs.

## 🛠 Prerequisites

* **OS**: Linux (tested on Ubuntu/Debian).
* **Software**: `sqlite3`, `rsync`, `curl`, `tar`.
* **Access**: Must be run with `sudo` or as `root`.

## 🚀 Installation

1.  **Clone the repository or download the script:**
    ```bash
    wget https://raw.githubusercontent.com/saym101/openvpn-access-server-backup/main/backup-ovpn.sh
    ```

2.  **Make it executable:**
    ```bash
    chmod +x backup-ovpn.sh
    ```

3.  **Configure your settings:**
    Open the script and fill in your SMTP details and backup paths:
    ```bash
    nano backup-ovpn.sh
    ```
    > ⚠️ **IMPORTANT**: Never commit your real passwords to a public repository! Use dummy values in the script if you plan to share it.

## 📅 Automation (Cron)

To run the backup automatically every night at 2:00 AM, add this to your crontab:

```bash
sudo crontab -e
```
Add the following line:
```cron
0 2 * * * /usr/local/bin/backup-ovpn.sh
```

## 📖 Usage

### Interactive Menu
Simply run the script to access the menu:
```bash
sudo ./backup-ovpn.sh
```

### Options:
1.  **Backup Now**: Stops the service, dumps DBs, archives `/etc/`, and starts the service.
2.  **Restore from Backup**: Lists available archives and restores the selected one.
3.  **List Backups**: Shows all `.tar.gz` files in the backup directory.
4.  **Show User Activity**: Displays a grouped and alphabetized list of users with their connection status.

## 📂 Backup Structure
Inside each `.tar.gz` archive, you will find:
* `db_dumps/`: SQL text dumps of all OpenVPN databases.
* `etc_config/`: All files from `/usr/local/openvpn_as/etc/` (excluding original DBs and installers).

## 🛡 License
Distributed under the MIT License. See `LICENSE` for more information.
