#!/bin/bash

# chmod +x /opt/netbox_db.sh && /bin/bash /opt/netbox_db.sh

read -s -p "Enter the password for the PSQL netbox user : " PASSWORD

echo

SQL_COMMANDS=$(cat <<EOF
CREATE DATABASE netbox;
CREATE USER netbox WITH PASSWORD '$PASSWORD';
ALTER DATABASE netbox OWNER TO netbox;
\connect netbox;
GRANT CREATE ON SCHEMA public TO netbox;
EOF
)

echo "${SQL_COMMANDS}" | sudo -u postgres psql
