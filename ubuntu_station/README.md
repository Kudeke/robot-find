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

## Mock IMU

After starting Ubuntu Station and GO2 Agent, verify the IMU topic:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./echo_imu.sh
```

Expected output contains:

```text
header:
  frame_id: base_link
orientation:
  z: ...
  w: ...
angular_velocity:
  z: 0.05
linear_acceleration:
  z: 9.81
```

RViz2:

```bash
source /opt/ros/jazzy/setup.bash
rviz2
```

Set `Fixed Frame` to `odom`, add `IMU`, and set the IMU topic to
`/remote/imu`.

## Phase1-E RViz2 Minimal Visualization

Terminal 1:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./run_station.sh
```

Terminal 2:

```bash
ssh unitree@<go2_ip>
cd ~/go2_agent
python3 main.py
```

Terminal 3:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./check_phase1_topics.sh
```

Terminal 4:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./start_rviz.sh
```

RViz2 should show:

```text
TF: odom -> base_link
Odometry: /remote/odom
IMU: /remote/imu
```

The RViz2 config is stored at:

```text
ubuntu_station/rviz/go2_phase1_mock.rviz
```

## Phase2-A cmd_vel DryRun Downlink

Terminal 1:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./run_station.sh
```

Terminal 2:

```bash
ssh unitree@<go2_ip>
cd ~/go2_agent
python3 main.py
```

Terminal 3:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./send_test_cmd_vel.sh
```

Expected Ubuntu output:

```text
[HOST] send cmd_vel seq=... linear_x=0.2 linear_y=0.0 angular_z=0.3
```

Expected GO2 output:

```text
[GO2] recv cmd_vel seq=...
[GO2][DRYRUN] move vx=0.2 vy=0.0 yaw_rate=0.3
```

Send a zero command:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./send_stop_cmd_vel.sh
```

Expected GO2 output:

```text
[GO2] recv cmd_vel seq=...
[GO2][DRYRUN] move vx=0.0 vy=0.0 yaw_rate=0.0
```

Phase2-A is dry-run only. It does not call Unitree SDK2, SportClient, or any
real robot motion API.

## Phase2-C SDK2 Environment Probe

Phase2-C only probes the GO2 SDK2 Python environment. It does not initialize
SDK2 communication, does not call `InitChannel`, does not instantiate or call
`SportClient`, and does not send any robot control command.

Run on GO2:

```bash
cd ~/go2_agent
python3 tools/probe_unitree_sdk2.py
python3 tools/list_unitree_examples.py
```

Expected result:

```text
probe_unitree_sdk2.py prints Python version, sys.path, import results, and
whether SportClient / RobotStateClient classes exist.

list_unitree_examples.py prints whether known Unitree SDK2 example directories
exist and lists sport / robot_state / video / lowlevel related files.
```

## Phase2-D unitree_sdk2py Import Repair Probe

Phase2-D investigates why `unitree_sdk2py` cannot import on GO2 when the error
is `No module named 'cyclonedds'`. This phase only searches files and imports
Python modules. It does not initialize DDS, does not call `InitChannel`, does
not instantiate `SportClient`, does not call `SportClient.move`, and does not
run any C++ SDK2 examples.

Run on GO2:

```bash
cd ~/go2_agent
python3 tools/probe_cyclonedds_python.py
python3 tools/inspect_go2_sport_example.py
```

Expected result:

```text
probe_cyclonedds_python.py prints Python version, sys.path, cyclonedds import
results, and any cyclonedds package or shared library matches under known GO2
paths.

inspect_go2_sport_example.py reads official Python go2_sport_client.py examples
without executing them and prints import / InitChannel / SportClient / motion
related lines.
```

## Phase3 Acceptance Test

Terminal 1, start Ubuntu Station:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./run_station.sh
```

Terminal 2, start GO2 Agent on GO2:

```bash
cd ~/go2_agent
./run_go2_agent.sh
```

Terminal 3, run the Phase3 acceptance test on Ubuntu:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./run_phase3_acceptance.sh
```

The test checks recent WebSocket-derived battery, IMU, odometry, and
RobotState data; required ROS2 topics; and the `odom -> base_link` transform.
Success ends with:

```text
=========================
PHASE3 PASSED
=========================
```

## Phase4 Acceptance

Phase4 acceptance only measures and verifies the existing remote camera
pipeline. It does not change the WebSocket protocol, robot control, or any
battery, IMU, odometry, TF, RobotState, or cmd_vel behavior.

Terminal 1, start Ubuntu Station:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./run_station.sh
```

Terminal 2, start the RealSense driver on GO2 and keep it running:

```bash
cd ~/go2_agent
./tools/start_realsense_test.sh
```

Terminal 3, start GO2 Agent:

```bash
cd ~/go2_agent
./run_go2_agent.sh
```

Confirm in RViz2 that an `Image` display subscribed to
`/remote/camera/color/compressed` continuously shows the remote color image.
Then run on Ubuntu:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./run_phase4_acceptance.sh
```

The test checks that the compressed camera topic exists, its measured
frequency is greater than zero, bandwidth and average message size statistics
are available, and the operator confirms the RViz2 image. Success ends with:

```text
=========================
PHASE4 PASSED
=========================
```

## Phase5-B LiDAR PointCloud2 Acceptance

Phase5-B restores the GO2 `/utlidar/cloud` WebSocket payload as:

```text
/remote/lidar/points
sensor_msgs/msg/PointCloud2
```

Terminal 1, start Ubuntu Station:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./run_station.sh
```

Terminal 2, start GO2 Agent on GO2:

```bash
cd ~/go2_agent
./run_go2_agent.sh
```

Terminal 3, verify the restored point cloud on Ubuntu:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./check_lidar_pipeline.sh
```

The check must report:

```text
[PASS] lidar topic exists
[PASS] lidar frequency
[PASS] lidar echo
```

To inspect messages continuously:

```bash
./echo_lidar.sh
```

In RViz2, set `Fixed Frame` to `utlidar_lidar`, add a `PointCloud2` display,
and select `/remote/lidar/points`. The source frame is intentionally preserved;
no odom-to-LiDAR TF is added in this phase.

Phase5-B does not control the robot and does not change battery, IMU, odometry,
TF, RobotState, camera, cmd_vel, or NativeStopController behavior. DDS remains
local to GO2; only PointCloud2 JSON/Base64 travels over WebSocket.

## Phase5-C LiDAR Pipeline Acceptance

LiDAR ROS2 output:

```text
Topic: /remote/lidar/points
Type: sensor_msgs/msg/PointCloud2
```

Before opening RViz2, keep the visualization-only static transform running:

```bash
source /opt/ros/jazzy/setup.bash
ros2 run tf2_ros static_transform_publisher \
  --x 0 --y 0 --z 0 \
  --roll 0 --pitch 0 --yaw 0 \
  --frame-id lidar_view \
  --child-frame-id utlidar_lidar
```

Open the supplied RViz2 configuration:

```bash
source /opt/ros/jazzy/setup.bash
rviz2 -d ~/go2wireless_webrct/ubuntu_station/rviz/lidar_only.rviz
```

The RViz2 configuration uses:

```text
Fixed Frame: lidar_view
Display: PointCloud2
Topic: /remote/lidar/points
Reliability: Best Effort
Durability: Volatile
```

The PointCloud2 publisher uses `sensor_data` QoS, so RViz2 must use `Best
Effort`. A `Reliable` subscription can show the topic name while receiving no
point-cloud messages.

Run the complete Phase5 acceptance check:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./run_phase5_acceptance.sh
```

Confirm the RViz2 prompt with `y` only when the point cloud updates
continuously. Success ends with:

```text
=========================
PHASE5 PASSED
=========================
```

To verify whether the bundled RViz configuration exists:

```bash
./save_lidar_rviz.sh
```

Phase5-C adds acceptance tooling and RViz configuration only. It does not
modify communication, PointCloud2 data, TF publication, camera, telemetry, or
robot control.
