# Ubuntu Station

Phase1-A minimal WebSocket heartbeat server for Ubuntu 24.04.

This project does not use ROS2, Unitree SDK2, OpenCV, camera input, or robot control.

## Run on Ubuntu

```bash
cd ubuntu_station
source /opt/ros/jazzy/setup.bash
pip install -r requirements.txt
python3 main.py
```

Dependencies are pinned for the Phase1-A runtime:

```text
websockets==12.0
PyYAML>=6.0
```

## Configuration

Default `config.yaml`:

```yaml
host: "0.0.0.0"
port: 8765
path: "/go2"
log_level: "INFO"
```

The server listens on:

```text
ws://<ubuntu_ip>:8765/go2
```

## Test

1. Start `ubuntu_station` first on Ubuntu.
2. Modify `go2_agent/config.yaml` on GO2.
3. Set `server_url` to Ubuntu's IP address on the GO2 WiFi network.
4. Start `go2_agent` on GO2.
5. Ubuntu should continuously print heartbeat messages.
6. GO2 should continuously print `heartbeat_ack` messages.
7. Stop the Ubuntu server.
8. GO2 should enter automatic reconnect mode.
9. Restart the Ubuntu server.
10. GO2 should automatically restore the connection.

## Phase1-B RobotState ROS2 Topic

After starting Ubuntu Station and GO2 Agent, verify the ROS2 topic:

```bash
source /opt/ros/jazzy/setup.bash
ros2 topic echo /go2/state
```

Expected message data is a JSON string:

```json
{"robot_mode":"stand","battery_percent":88.5,"error_code":0,"online":true}
```

`rclpy` is provided by ROS2 Jazzy and is intentionally not listed in `requirements.txt`.
