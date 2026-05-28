#!/bin/bash
# ============================================================
#  RHEL User Management Script
#  Author  : Preyansh Dhora
#  Version : 1.0
#  Desc    : Create/delete users, assign groups, set password
#            policies, and manage sudo permissions on RHEL
# ============================================================

# ---------- Colors for output ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ---------- Log file ----------
LOGFILE="/var/log/user_management.log"

# ---------- Must run as root ----------
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR] This script must be run as root (sudo).${NC}"
  exit 1
fi

# ---------- Logging function ----------
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
  echo -e "$1"
}

# ============================================================
#  FUNCTION: Create a new user
# ============================================================
create_user() {
  echo -e "\n${CYAN}=== CREATE USER ===${NC}"
  read -rp "Enter username to create: " USERNAME

  # Check if user already exists
  if id "$USERNAME" &>/dev/null; then
    log "${YELLOW}[WARN] User '$USERNAME' already exists.${NC}"
    return
  fi

  read -rp "Enter full name (comment): " FULLNAME
  read -rp "Enter home directory (leave blank for default /home/$USERNAME): " HOMEDIR
  HOMEDIR=${HOMEDIR:-/home/$USERNAME}

  read -rp "Enter shell (leave blank for /bin/bash): " SHELL
  SHELL=${SHELL:-/bin/bash}

  # Create the user
  useradd -m -d "$HOMEDIR" -s "$SHELL" -c "$FULLNAME" "$USERNAME"

  if [[ $? -eq 0 ]]; then
    log "${GREEN}[OK] User '$USERNAME' created successfully.${NC}"

    # Set password
    echo -e "${YELLOW}Set password for '$USERNAME':${NC}"
    passwd "$USERNAME"

    # Force password change on first login
    read -rp "Force password change on first login? (y/n): " FORCE_CHANGE
    if [[ "$FORCE_CHANGE" =~ ^[Yy]$ ]]; then
      chage -d 0 "$USERNAME"
      log "${GREEN}[OK] Password change enforced on first login for '$USERNAME'.${NC}"
    fi

  else
    log "${RED}[ERROR] Failed to create user '$USERNAME'.${NC}"
  fi
}

# ============================================================
#  FUNCTION: Delete a user
# ============================================================
delete_user() {
  echo -e "\n${CYAN}=== DELETE USER ===${NC}"
  read -rp "Enter username to delete: " USERNAME

  # Check if user exists
  if ! id "$USERNAME" &>/dev/null; then
    log "${RED}[ERROR] User '$USERNAME' does not exist.${NC}"
    return
  fi

  read -rp "Also delete home directory and mail spool? (y/n): " DEL_HOME

  if [[ "$DEL_HOME" =~ ^[Yy]$ ]]; then
    userdel -r "$USERNAME"
  else
    userdel "$USERNAME"
  fi

  if [[ $? -eq 0 ]]; then
    log "${GREEN}[OK] User '$USERNAME' deleted successfully.${NC}"
  else
    log "${RED}[ERROR] Failed to delete user '$USERNAME'.${NC}"
  fi
}

# ============================================================
#  FUNCTION: Assign user to group(s)
# ============================================================
assign_group() {
  echo -e "\n${CYAN}=== ASSIGN GROUP ===${NC}"
  read -rp "Enter username: " USERNAME

  if ! id "$USERNAME" &>/dev/null; then
    log "${RED}[ERROR] User '$USERNAME' does not exist.${NC}"
    return
  fi

  read -rp "Enter group name to assign: " GROUPNAME

  # Create group if it doesn't exist
  if ! getent group "$GROUPNAME" &>/dev/null; then
    read -rp "Group '$GROUPNAME' does not exist. Create it? (y/n): " CREATE_GRP
    if [[ "$CREATE_GRP" =~ ^[Yy]$ ]]; then
      groupadd "$GROUPNAME"
      log "${GREEN}[OK] Group '$GROUPNAME' created.${NC}"
    else
      return
    fi
  fi

  read -rp "Add as supplementary group? (y) or change primary group? (n): " GRP_TYPE

  if [[ "$GRP_TYPE" =~ ^[Yy]$ ]]; then
    usermod -aG "$GROUPNAME" "$USERNAME"
    log "${GREEN}[OK] User '$USERNAME' added to supplementary group '$GROUPNAME'.${NC}"
  else
    usermod -g "$GROUPNAME" "$USERNAME"
    log "${GREEN}[OK] Primary group of '$USERNAME' changed to '$GROUPNAME'.${NC}"
  fi

  echo -e "${GREEN}Current groups for '$USERNAME':${NC} $(groups $USERNAME)"
}

# ============================================================
#  FUNCTION: Set password policy
# ============================================================
set_password_policy() {
  echo -e "\n${CYAN}=== PASSWORD POLICY ===${NC}"
  read -rp "Enter username to set password policy: " USERNAME

  if ! id "$USERNAME" &>/dev/null; then
    log "${RED}[ERROR] User '$USERNAME' does not exist.${NC}"
    return
  fi

  echo -e "${YELLOW}Current password aging info for '$USERNAME':${NC}"
  chage -l "$USERNAME"

  echo ""
  read -rp "Minimum days between password changes (e.g. 7): " MIN_DAYS
  read -rp "Maximum days password is valid (e.g. 90): " MAX_DAYS
  read -rp "Days warning before password expires (e.g. 14): " WARN_DAYS
  read -rp "Days after expiry account gets disabled (e.g. 30): " INACTIVE_DAYS
  read -rp "Account expiry date (YYYY-MM-DD, leave blank to skip): " EXPIRY_DATE

  # Apply password aging policies
  chage -m "$MIN_DAYS" -M "$MAX_DAYS" -W "$WARN_DAYS" -I "$INACTIVE_DAYS" "$USERNAME"

  if [[ -n "$EXPIRY_DATE" ]]; then
    chage -E "$EXPIRY_DATE" "$USERNAME"
  fi

  log "${GREEN}[OK] Password policy applied for '$USERNAME'.${NC}"
  echo -e "${GREEN}Updated password aging info:${NC}"
  chage -l "$USERNAME"

  # Also apply system-wide policy via /etc/login.defs
  read -rp "Apply these settings system-wide in /etc/login.defs too? (y/n): " GLOBAL
  if [[ "$GLOBAL" =~ ^[Yy]$ ]]; then
    sed -i "s/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   $MAX_DAYS/" /etc/login.defs
    sed -i "s/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   $MIN_DAYS/" /etc/login.defs
    sed -i "s/^PASS_WARN_AGE.*/PASS_WARN_AGE   $WARN_DAYS/" /etc/login.defs
    log "${GREEN}[OK] System-wide password policy updated in /etc/login.defs.${NC}"
  fi
}

# ============================================================
#  FUNCTION: Manage sudo permissions
# ============================================================
manage_sudo() {
  echo -e "\n${CYAN}=== SUDO PERMISSIONS ===${NC}"
  echo "1. Grant full sudo access"
  echo "2. Grant limited sudo (specific commands only)"
  echo "3. Revoke sudo access"
  echo "4. View current sudo rules"
  read -rp "Choose option (1-4): " SUDO_OPT

  case $SUDO_OPT in

    1)
      read -rp "Enter username to grant full sudo: " USERNAME
      if ! id "$USERNAME" &>/dev/null; then
        log "${RED}[ERROR] User '$USERNAME' does not exist.${NC}"
        return
      fi
      usermod -aG wheel "$USERNAME"
      log "${GREEN}[OK] '$USERNAME' added to wheel group (full sudo access).${NC}"
      ;;

    2)
      read -rp "Enter username: " USERNAME
      if ! id "$USERNAME" &>/dev/null; then
        log "${RED}[ERROR] User '$USERNAME' does not exist.${NC}"
        return
      fi
      read -rp "Enter commands to allow (e.g. /usr/bin/systemctl,/usr/bin/dnf): " COMMANDS
      read -rp "Require password for sudo? (y/n): " REQ_PASS

      SUDOERS_FILE="/etc/sudoers.d/$USERNAME"

      if [[ "$REQ_PASS" =~ ^[Nn]$ ]]; then
        echo "$USERNAME ALL=(ALL) NOPASSWD: $COMMANDS" > "$SUDOERS_FILE"
      else
        echo "$USERNAME ALL=(ALL) $COMMANDS" > "$SUDOERS_FILE"
      fi

      # Validate the sudoers file
      visudo -c -f "$SUDOERS_FILE" &>/dev/null
      if [[ $? -eq 0 ]]; then
        chmod 440 "$SUDOERS_FILE"
        log "${GREEN}[OK] Limited sudo access granted to '$USERNAME' for: $COMMANDS${NC}"
      else
        rm -f "$SUDOERS_FILE"
        log "${RED}[ERROR] Invalid sudoers syntax. File removed.${NC}"
      fi
      ;;

    3)
      read -rp "Enter username to revoke sudo: " USERNAME
      # Remove from wheel group
      gpasswd -d "$USERNAME" wheel 2>/dev/null
      # Remove custom sudoers file if exists
      SUDOERS_FILE="/etc/sudoers.d/$USERNAME"
      if [[ -f "$SUDOERS_FILE" ]]; then
        rm -f "$SUDOERS_FILE"
        log "${GREEN}[OK] Custom sudoers file removed for '$USERNAME'.${NC}"
      fi
      log "${GREEN}[OK] Sudo access revoked for '$USERNAME'.${NC}"
      ;;

    4)
      echo -e "${YELLOW}=== Current Sudoers Rules ===${NC}"
      echo -e "\n--- /etc/sudoers.d/ files ---"
      ls /etc/sudoers.d/ 2>/dev/null
      echo -e "\n--- Wheel group members ---"
      getent group wheel
      ;;

    *)
      echo -e "${RED}Invalid option.${NC}"
      ;;
  esac
}

# ============================================================
#  FUNCTION: List all users
# ============================================================
list_users() {
  echo -e "\n${CYAN}=== ALL SYSTEM USERS ===${NC}"
  printf "%-20s %-6s %-6s %-30s %-20s\n" "USERNAME" "UID" "GID" "HOME" "SHELL"
  echo "--------------------------------------------------------------------------------"
  while IFS=: read -r user _ uid gid _ home shell; do
    if [[ $uid -ge 1000 && $uid -lt 65534 ]]; then
      printf "%-20s %-6s %-6s %-30s %-20s\n" "$user" "$uid" "$gid" "$home" "$shell"
    fi
  done < /etc/passwd
}

# ============================================================
#  FUNCTION: Lock / Unlock a user account
# ============================================================
lock_unlock_user() {
  echo -e "\n${CYAN}=== LOCK / UNLOCK USER ===${NC}"
  read -rp "Enter username: " USERNAME

  if ! id "$USERNAME" &>/dev/null; then
    log "${RED}[ERROR] User '$USERNAME' does not exist.${NC}"
    return
  fi

  echo "1. Lock account"
  echo "2. Unlock account"
  read -rp "Choose (1/2): " LU_OPT

  if [[ "$LU_OPT" == "1" ]]; then
    usermod -L "$USERNAME"
    log "${GREEN}[OK] Account '$USERNAME' locked.${NC}"
  elif [[ "$LU_OPT" == "2" ]]; then
    usermod -U "$USERNAME"
    log "${GREEN}[OK] Account '$USERNAME' unlocked.${NC}"
  else
    echo -e "${RED}Invalid option.${NC}"
  fi
}

# ============================================================
#  MAIN MENU
# ============================================================
main_menu() {
  while true; do
    echo -e "\n${CYAN}============================================${NC}"
    echo -e "${CYAN}      RHEL User Management Script           ${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo "  1. Create User"
    echo "  2. Delete User"
    echo "  3. Assign Group"
    echo "  4. Set Password Policy"
    echo "  5. Manage Sudo Permissions"
    echo "  6. List All Users"
    echo "  7. Lock / Unlock User"
    echo "  8. Exit"
    echo -e "${CYAN}============================================${NC}"
    read -rp "Choose an option (1-8): " CHOICE

    case $CHOICE in
      1) create_user ;;
      2) delete_user ;;
      3) assign_group ;;
      4) set_password_policy ;;
      5) manage_sudo ;;
      6) list_users ;;
      7) lock_unlock_user ;;
      8)
        echo -e "${GREEN}Exiting. Logs saved to $LOGFILE${NC}"
        exit 0
        ;;
      *)
        echo -e "${RED}Invalid option. Please choose 1-8.${NC}"
        ;;
    esac
  done
}

# ---------- Entry Point ----------
main_menu

