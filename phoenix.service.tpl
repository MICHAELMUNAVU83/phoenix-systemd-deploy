[Unit]
Description=@@APP_NAME@@ Phoenix application
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=@@APP_DIR@@
EnvironmentFile=-@@ENV_FILE@@
Environment=PHX_SERVER=true
ExecStart=@@APP_DIR@@/_build/prod/rel/@@APP_NAME@@/bin/server
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
KillSignal=SIGTERM
SyslogIdentifier=@@APP_NAME@@

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only
ReadWritePaths=@@APP_DIR@@

[Install]
WantedBy=default.target
