# GO2 Agent

Phase1-A minimal WebSocket heartbeat client for Unitree GO2 EDU.

This project does not use ROS2, Unitree SDK2, OpenCV, camera input, or robot control.

## Run on GO2

```bash
cd go2_agent
pip install -r requirements.txt
python3 main.py
```

Dependencies are pinned for the Phase1-A runtime:

```text
websockets==12.0
PyYAML>=6.0
```

## Configuration

Edit `config.yaml` before running:

```yaml
server_url: "ws://192.168.41.1:8765/go2"
heartbeat_interval_sec: 1.0
reconnect_interval_sec: 2.0
log_level: "INFO"
```

Change the IP in `server_url` to the Ubuntu station IP address on the GO2 WiFi network.

## Test

1. Start `ubuntu_station` first on Ubuntu.
2. Update `go2_agent/config.yaml` so `server_url` points to Ubuntu.
3. Start `go2_agent` on GO2.
4. GO2 should print heartbeat send logs.
5. GO2 should print heartbeat acknowledgements from Ubuntu.
6. Stop the Ubuntu server.
7. GO2 should enter reconnect mode.
8. Restart the Ubuntu server.
9. GO2 should reconnect automatically.
