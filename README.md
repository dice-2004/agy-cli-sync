# agy-cli-sync

A project for two-way synchronization of `antigravity-CLI` (agy) configuration files and conversation history between a disposable environment (such as a Dev Container) and a central server.

By using the scripts in this repository, you can retain your past conversation history (brain) and continue using `agy` seamlessly, even if you rebuild your container.

---

## 🛡️ Safe Synchronization Mechanism (SQLite DB Corruption Prevention)

`antigravity-CLI` (`agy`) uses SQLite databases (WAL mode) to store conversation history. Performing `rsync` synchronization while `agy` is writing to the database can cause inconsistencies with `.db-wal` files, corrupting the database and leading to CLI hangs.

`agy-cli-sync` prevents this issue with a **non-intrusive process-monitoring mechanism**:

1. **Automatic Sync Pause During Session**:
   - The background sync service constantly monitors active `agy` processes.
   - While `agy` is running, `rsync` synchronization is automatically skipped.
2. **Automatic Post-Session Sync**:
   - Immediately after the `agy` process finishes (conversation ends), a single instant sync (Push & Pull) is executed to secure conversation data on the server.
   - The service then automatically resumes normal background synchronization.
3. **Zero Configuration / Non-Intrusive**:
   - Your `agy` binary and shell configurations are completely untouched. You simply run `agy` as usual.

---

## 0. Preparation: Create an SSH Key for Sync

To securely synchronize data between the server and the container, create a dedicated SSH key pair.
Run the following command in your host machine's terminal (e.g., WSL, Ubuntu) to generate the key. (Leave the passphrase empty).

```bash
ssh-keygen -t ed25519 -f ~/.ssh/agy_key -N ""
```

This will generate a private key (`~/.ssh/agy_key`) and a public key (`~/.ssh/agy_key.pub`).
Display the contents of the public key and copy it.

```bash
cat ~/.ssh/agy_key.pub
# Example output: ssh-ed25519 AAAAC3Nza... (string specific to your environment)
```

---

## 1. Server-side Setup

Set up an SSH server container on your server (`10.10.10.51`) to receive and store the conversation data.

Place the `docker-compose.yml` included in this repository on your server.
**Before starting, replace the `PUBLIC_KEY` value with "your public key" copied in Step 0.**

Once modified, start the container.
*Note: Upon startup, the `agysync` user is automatically created and the public key is registered.*

```bash
docker-compose up -d
```

---

## 2. Client-side Preparation (Host side / Dev Container)

Copy the scripts in `client/` and the required authentication cache to a shared directory accessible by the container (e.g., `.local/` inside your project).

### 📦 Scripts (`client/` Directory)

| Script Name | Purpose | Execution Mode |
| :--- | :--- | :--- |
| **`setup-agy-init.sh`** | Initial setup script (`rsync` check, initial pull, background sync) | Run **once** at initial setup |
| **`setup-agy-start.sh`** | Subsequent startup script (starts process-monitoring sync loop) | Run on container restart or via systemd |
| **`agy-sync.service`** | Systemd user service definition for host machine | Register via `systemctl` |

---

## 3. Container Setup and Sync Initialization

### A. Dev Container Setup
Once attached to your container environment, run the setup script:

```bash
# On initial container build
bash /path/to/setup-agy-init.sh

# On subsequent container starts
bash /path/to/setup-agy-start.sh
```

---

### B. Host Machine Setup (systemd User Service)

To run as an automatic background service on WSL/Ubuntu startup:

```bash
# 1. Copy service file
mkdir -p ~/.config/systemd/user/
cp /path/to/client/agy-sync.service ~/.config/systemd/user/

# 2. Initial setup
bash /path/to/client/setup-agy-init.sh

# 3. Enable and start systemd user service
systemctl --user daemon-reload
systemctl --user enable --now agy-sync.service
```

---

## 💡 Verification

After running the script, you can verify if everything is working correctly with the following commands:

```bash
# Check if the sync process is running in the background
ps aux | grep setup-agy-start.sh

# Check systemd user service status (Host)
systemctl --user status agy-sync.service
```
