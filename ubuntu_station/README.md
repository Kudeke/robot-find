# Ubuntu Station

Phase1-A minimal WebSocket heartbeat server for Ubuntu 24.04.

This project does not use ROS2, Unitree SDK2, OpenCV, camera input, or robot control.

## Run on Ubuntu

```bash
cd ~/go2wireless_webrct/ubuntu_station
./run_station.sh
```

Keep this terminal running.

The launcher sources ROS2 Jazzy and uses the project-local virtual environment
if one exists at `venv/` or `.venv/`. If no virtual environment exists yet,
create one with:

```bash
cd ~/go2wireless_webrct/ubuntu_station
python3 -m venv --system-site-packages venv
source venv/bin/activate
pip install -r requirements.txt
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
cd ~/go2wireless_webrct/ubuntu_station
./echo_state.sh
```

Expected message data is a JSON string:

```json
{"robot_mode":"stand","battery_percent":88.5,"error_code":0,"online":true}
```

`rclpy` is provided by ROS2 Jazzy and is intentionally not listed in `requirements.txt`.

## Phase1-C Mock Odom + TF

Ubuntu terminal 1:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./run_station.sh
```

GO2:

```bash
cd ~/go2wireless_webrct/go2_agent
python3 main.py
```

Ubuntu terminal 2:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./echo_odom.sh
```

Expected output contains:

```text
header:
  frame_id: odom
child_frame_id: base_link
pose:
  pose:
    position:
      x: ...
twist:
  twist:
    linear:
      x: 0.05
```

Ubuntu terminal 3:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./check_tf.sh
```

Expected output contains:

```text
At time ...
- Translation: [...]
- Rotation: in Quaternion (xyzw) [...]
```

RViz2:

```bash
source /opt/ros/jazzy/setup.bash
rviz2
```

Set `Fixed Frame` to `odom`, add `TF`, add `Odometry`, and set the
Odometry topic to `/remote/odom`.
