# GO2 Agent

## Native Motion Daemon

The native motion daemon is a GO2-local Unix socket bridge to Unitree SDK2
`SportClient`.

Default mode is safe:

- `Move` is DRYRUN only.
- SDK2 is not initialized in daemon DRYRUN mode.
- Daemon `StopMove` is skipped in DRYRUN mode; the existing
  `NativeStopController` remains available as the separate real stop fallback.
- The daemon listens only on `/tmp/go2_motion_daemon.sock`.
- It does not open TCP, UDP, WebSocket, or any remote network listener.

Build on GO2:

```bash
cd ~/go2_agent/native
./build_helper.sh
```

Start daemon in default DRYRUN mode:

```bash
cd ~/go2_agent/native
./run_motion_daemon.sh
```

Daemon dry-run test:

```bash
cd ~/go2_agent/native
./test_motion_daemon.sh
```

Python controller dry-run test, with daemon already running:

```bash
cd ~/go2_agent
python3 test_native_motion_controller.py
```

The Python agent remains in DryRun by default:

```yaml
controller_mode: "dry_run"
```

The optional native daemon mode is only enabled by changing config:

```yaml
controller_mode: "native_daemon"
native_motion_socket: "/tmp/go2_motion_daemon.sock"
```

Real Move is prepared but must not be used in this phase. It requires explicit
operator acknowledgement and strict low-speed limits:

```bash
GO2_REAL_MOVE_ACK=YES ./run_motion_daemon.sh --enable-real-move
```

This phase forbids running real mode unless a later phase explicitly starts a
supervised real-motion test with on-site safety preparation.

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

## Phase2-G NativeStopController

Phase2-G connects only the native SDK2 stop helper into the GO2 Python safety
stop path. It does not connect real movement.

Build the helper first on GO2:

```bash
cd ~/go2_agent/native
./build_helper.sh
```

Test native stop directly:

```bash
cd ~/go2_agent
python3 test_native_stop.py
```

Expected output contains:

```text
[GO2][NATIVE_STOP] executing helper
[HELPER] stop-only mode
[HELPER] initializing SDK2 on iface=wlan0
[HELPER] calling StopMove only
[HELPER] StopMove complete
```

Runtime behavior:

```text
move() remains DryRun only.
stop() first calls DryRunController.stop().
stop() then calls the native helper with --stop-only when native_stop_enabled is true.
The native helper never calls Move() in this phase.
```

Relevant `config.yaml` options:

```yaml
native_stop_enabled: true
native_stop_helper_path: "./native/build/go2_sport_helper"
native_stop_interface: "wlan0"
native_stop_timeout_sec: 5.0
```

## Phase3-B GO2 Local DDS Topic Probe

Phase3-B only probes GO2 local DDS/ROS2 topics with the `ros2` CLI. DDS is used
only inside GO2 for read-only discovery. DDS is not bridged over WiFi; WiFi
continues to use WebSocket JSON only.

Run on GO2:

```bash
cd ~/go2_agent
./tools/list_go2_dds_topics.sh
python3 tools/probe_go2_topics.py
./tools/probe_topic_once.sh /lf/sportmodestate
```

The probe checks these candidate topics:

```text
/lf/sportmodestate
/sportmodestate
/lowstate
/lf/lowstate
/odom
/imu
/battery_state
/joint_states
```

Safety boundary:

```text
read-only ros2 topic list/info/echo
no SportClient
no Move
no StopMove
no RobotStateClient
no motion commands
no DDS over WiFi bridge
```

## Phase3-C Real DDS Topic State Sources

Phase3-C adds independent read-only ROS2 subscribers for the GO2-local topics:

```text
/lf/lowstate        unitree_go/msg/LowState
/lf/sportmodestate unitree_go/msg/SportModeState
```

The subscriber classes are:

```text
dds.LowStateSource
dds.SportStateSource
```

They accept an existing ROS2 node, use sensor-data QoS, and keep only the
latest received message. The caller owns `rclpy.init()`, node spinning, and
shutdown. Phase3-C does not connect these sources to `main.py` and does not
replace the existing mock sources.

Inspect and save the real message definitions on GO2:

```bash
cd ~/go2_agent
./tools/inspect_unitree_messages.sh
```

The definitions are saved under:

```text
tools/logs/unitree_messages_YYYYMMDD_HHMMSS.log
```

Manually inspect live messages:

```bash
./tools/echo_lowstate.sh
./tools/echo_sportstate.sh
```

Acceptance checks:

```text
LowState output contains the real battery and IMU-related fields exposed by
the installed unitree_go message definition.

SportModeState output contains the real robot mode/state fields exposed by
the installed unitree_go message definition.
```

Safety boundary:

```text
GO2-local DDS subscriptions only
no RobotStateClient
no Service API
no SportClient
no Move or StopMove
no motion commands
no DDS over WiFi
WiFi remains WebSocket JSON only
```

## Phase3-E Real Battery Uplink

Phase3-E reads only `/lf/lowstate` on GO2, converts its battery fields to
WebSocket JSON, and publishes `sensor_msgs/msg/BatteryState` on Ubuntu.
RobotState, IMU, odometry, and movement behavior remain unchanged.

GO2:

```bash
cd ~/go2_agent
./run_go2_agent.sh
```

Ubuntu:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./run_station.sh
```

In another Ubuntu terminal:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./echo_battery.sh
```

Expected values include:

```text
percentage: 0.92
voltage: 31.x
current: 0.x
```

GO2 configuration:

```yaml
battery_source: "real_dds"
battery_topic: "/lf/lowstate"
battery_rate_hz: 1.0
```

Set `battery_source: "mock"` to use the mock battery source. DDS remains local
to GO2; only battery JSON is sent over the existing WebSocket connection.

## Phase3-F Real IMU Uplink

Phase3-F reads IMU fields from the GO2-local `/lf/lowstate` DDS topic and sends
only the converted IMU JSON over the existing WebSocket connection. Battery
and IMU share one `rclpy` node and one DDS spin loop.

Probe the source without WebSocket:

```bash
cd ~/go2_agent
./tools/run_probe_real_imu_source.sh
```

Run the full link:

```bash
cd ~/go2_agent
./run_go2_agent.sh
```

GO2 configuration:

```yaml
imu_source: "real_dds"
imu_topic: "/lf/lowstate"
imu_rate_hz: 10.0
```

Set `imu_source: "mock"` to restore `MockImuSource`.

Ubuntu continues to use its existing `/remote/imu` publisher and
`echo_imu.sh`. No Ubuntu-side Phase3-F code changes are required.

Safety boundary:

```text
read-only GO2-local DDS
no SportClient or Move
no new StopMove calls
no robot control
no DDS over WiFi
WebSocket carries IMU JSON only
```

## Phase3-G Real Odometry Uplink

Phase3-G reads odometry fields from the GO2-local `/lf/sportmodestate` DDS
topic and sends only converted odometry JSON over the existing WebSocket
connection. Battery, IMU, and odometry share the same `rclpy` node and DDS spin
loop.

Probe the source without WebSocket:

```bash
cd ~/go2_agent
./tools/run_probe_real_odom_source.sh
```

GO2 configuration:

```yaml
odom_source: "real_dds"
odom_topic: "/lf/sportmodestate"
odom_rate_hz: 10.0
```

Set `odom_source: "mock"` to restore `MockOdomSource`.

Ubuntu continues to use its existing `/remote/odom` publisher, odom to
`base_link` TF broadcaster, `echo_odom.sh`, and `check_tf.sh`. No Ubuntu-side
Phase3-G code changes are required.

Safety boundary:

```text
read-only GO2-local DDS
no SportClient or Move
no motion commands
no robot control
no DDS over WiFi
WebSocket carries odometry JSON only
```

## Phase3-H Real RobotState Uplink

Phase3-H reads robot state fields from the GO2-local
`/lf/sportmodestate` DDS topic and replaces only the mock `/go2/state`
payload. Ubuntu continues publishing the received JSON as
`std_msgs/msg/String`.

Probe without WebSocket:

```bash
cd ~/go2_agent
./tools/run_probe_real_robot_state_source.sh
```

GO2 configuration:

```yaml
state_source: "real_dds"
state_topic: "/lf/sportmodestate"
state_rate_hz: 1.0
```

Set `state_source: "mock"` to restore `MockStateSource`.

Battery, IMU, odometry, and RobotState share the same `rclpy` node and DDS
spin loop. No Ubuntu-side Phase3-H changes are required.

Safety boundary:

```text
read-only GO2-local DDS
no SportClient or Move
no motion commands
no robot control
no DDS over WiFi
WebSocket carries RobotState JSON only
```

## Phase4-A Intel RealSense D435i Environment Probe

Phase4-A only probes the GO2 environment and the externally connected Intel
RealSense D435i. It does not connect the camera to `main.py`, does not transmit
images over WebSocket or WebRTC, and does not control the robot.

Run the environment probe:

```bash
cd ~/go2_agent
./tools/probe_realsense_env.sh
```

The complete output is saved under:

```text
tools/logs/realsense_env_YYYYMMDD_HHMMSS.log
```

If the `realsense2_camera` ROS2 package exists, start the read-only test driver:

```bash
./tools/start_realsense_test.sh
```

In another GO2 terminal, inspect currently available topics:

```bash
cd ~/go2_agent
./tools/probe_realsense_topics.sh
```

Inspect camera information and image topic rates without printing image data:

```bash
./tools/echo_realsense_once.sh
```

Safety boundary:

```text
camera environment and ROS2 topic probing only
no main.py integration
no WebSocket image transmission
no WebRTC
no SLAM
no robot control
no changes to Phase1-3 telemetry and safety paths
```

## Phase4-C RealSense Topic Auto-Discovery

Phase4-C discovers the active RealSense namespace from `ros2 topic list -t`.
It supports `sensor_msgs/msg/Image`, `sensor_msgs/msg/CompressedImage`, and
`sensor_msgs/msg/CameraInfo` topics whose names contain camera plus color,
depth, or infra.

Start the read-only RealSense driver:

```bash
cd ~/go2_agent
./tools/start_realsense_test.sh
```

In another GO2 terminal, inspect every discovered camera topic:

```bash
cd ~/go2_agent
./tools/probe_realsense_topics.sh
./tools/echo_realsense_once.sh
```

Run the automatic pipeline acceptance check:

```bash
./tools/check_realsense_pipeline.sh
```

The acceptance check requires:

```text
one color Image or CompressedImage topic
one depth Image or CompressedImage topic
one color CameraInfo topic
one depth CameraInfo topic
```

Success ends with:

```text
=========================
REALSENSE PIPELINE PASSED
=========================
```

Phase4-C remains read-only. It does not connect to `main.py`, transmit images
over WebSocket or WebRTC, run SLAM, or control the robot.

## Phase4-D Camera Capture Probe

Phase4-D verifies that GO2 can read the RealSense color image topic and save
three JPEG files locally. It does not connect camera capture to `main.py` and
does not transmit images.

Keep the read-only RealSense driver running, then execute:

```bash
cd ~/go2_agent
./tools/run_probe_camera_capture.sh
```

Expected output:

```text
[GO2][CAMERA] frame received
[GO2][CAMERA] saved capture_001.jpg
[GO2][CAMERA] saved capture_002.jpg
[GO2][CAMERA] saved capture_003.jpg
[GO2][CAMERA] saved_count=3
```

The JPEG files are saved under:

```text
tools/captures/capture_001.jpg
tools/captures/capture_002.jpg
tools/captures/capture_003.jpg
```

Phase4-D is a local read-only probe. It does not use WebSocket, WebRTC, SLAM,
or robot control and does not modify the existing telemetry, protocol, or
movement logic.

## Phase4-E JPEG WebSocket Camera Probe

Phase4-E sends one color JPEG frame per second from GO2 to Ubuntu:

```text
RealSense Image -> JPEG quality 70 -> Base64 -> WebSocket JSON
-> ROS2 sensor_msgs/msg/CompressedImage
```

GO2 configuration:

```yaml
camera_enabled: true
camera_topic: "/camera/camera/color/image_raw"
camera_rate_hz: 1.0
camera_jpeg_quality: 70
```

Start Ubuntu Station:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./run_station.sh
```

Keep the RealSense driver running on GO2, then start the agent:

```bash
cd ~/go2_agent
./run_go2_agent.sh
```

Verify the Ubuntu ROS2 stream:

```bash
cd ~/go2wireless_webrct/ubuntu_station
./echo_camera.sh
```

The published topic is:

```text
/remote/camera/color/compressed
sensor_msgs/msg/CompressedImage
```

For an isolated camera-only WebSocket probe, stop the normal GO2 agent first
and run:

```bash
cd ~/go2_agent
python3 tools/probe_camera_ws.py
```

Phase4-E does not use WebRTC, SLAM, YOLO, or VLN and does not control the
robot. GO2-local ROS2 image data is converted to JPEG; only the JPEG Base64
payload is transported over WebSocket.

## Phase5-A GO2 LiDAR DDS Probe

Phase5-A only inspects ROS2 Foxy topics that are already available on GO2. It
does not start a LiDAR node or driver, change DDS configuration, send data over
WebSocket, or control the robot.

List all typed topics, automatically find LiDAR candidates, print topic
information, and measure each candidate for five seconds:

```bash
cd ~/go2_agent
./tools/probe_lidar_topics.sh
```

Print the ROS2 message definition for every discovered candidate:

```bash
./tools/inspect_lidar_messages.sh
```

Echo one message from every discovered `sensor_msgs/msg/PointCloud2` topic:

```bash
./tools/echo_lidar.sh
```

Echo one message from every discovered `sensor_msgs/msg/LaserScan` topic:

```bash
./tools/echo_scan.sh
```

Candidates are selected by the `LaserScan`, `PointCloud2`, or `PointCloud`
message type, or by topic names containing `scan`, `cloud`, `point`, `lidar`,
`utlidar`, `velodyne`, or `livox`.

Safety boundary:

```text
read-only ROS2 topic and interface inspection
no node or driver startup
no DDS modification
no main.py, ws_client.py, or protocol.py integration
no WebSocket transmission
no robot control
```

## Phase5-B LiDAR PointCloud2 WebSocket Bridge

Phase5-B reads the existing GO2-local `/utlidar/cloud` topic and sends at most
five PointCloud2 frames per second through the existing WebSocket connection.
DDS remains local to GO2; WiFi carries only JSON with Base64 point data.

Configuration:

```yaml
lidar_enabled: true
lidar_topic: "/utlidar/cloud"
lidar_rate_hz: 5.0
```

Start Ubuntu Station, then run GO2 Agent:

```bash
cd ~/go2_agent
./run_go2_agent.sh
```

Expected GO2 output:

```text
[GO2] lidar source=real_dds PointCloud2
[GO2] send lidar_points seq=... width=... bytes=...
```

This bridge is read-only. It reuses the existing DDS Node, does not initialize
another ROS2 context, does not transport DDS over WiFi, and does not call any
robot control API.

## GO2 Agent → Native Motion Daemon dryrun integration

This stage routes GO2 Agent motion commands to the local Native Motion Daemon
over a Unix Domain Socket, while the daemon remains in DRYRUN mode.

Safety boundary:

```text
daemon must be started without --enable-real-move
daemon status must report real_move_enabled=false
allow_real_move_daemon must remain false
SportClient.Move is not called in this stage
the robot must remain physically stationary
```

Start the daemon on GO2:

```bash
cd ~/go2_agent/native
./run_motion_daemon.sh
```

In another GO2 terminal, check the daemon:

```bash
cd ~/go2_agent
./tools/check_native_daemon_ready.sh
```

Temporarily switch `config.yaml` for this integration test:

```yaml
controller_mode: "native_daemon"
allow_real_move_daemon: false
native_motion_socket: "/tmp/go2_motion_daemon.sock"
```

Run the local dryrun integration test:

```bash
cd ~/go2_agent
python3 test_agent_native_daemon_dryrun.py
```

Optional acceptance helper:

```bash
./run_native_daemon_agent_acceptance.sh
```

Then start GO2 Agent:

```bash
./run_go2_agent.sh
```

Expected logs after a `/cmd_vel` command arrives:

```text
[GO2] recv cmd_vel seq=...
[GO2][NATIVE_DAEMON] move vx=... vy=... yaw_rate=...
[GO2][NATIVE_DAEMON] move ack seq=... real_move=false
```

The daemon terminal should show:

```text
[MOTION_DAEMON][DRYRUN] move ...
```

Do not set `GO2_REAL_MOVE_ACK=YES` and do not pass `--enable-real-move` during
this stage.

## GO2 REAL MOVE ACCEPTANCE

This is the first real SDK2 `SportClient.Move()` test in this project.

It intentionally bypasses:

```text
Uni-NaVid
WebSocket
Safety Gate
Native Motion Daemon
```

The test directly calls SDK2:

```text
ChannelFactory::Init
SportClient::Init
SportClient::SwitchJoystick(false)
SportClient::StandUp
SportClient::BalanceStand
SportClient::SpeedLevel(1)
SportClient::ClassicWalk(true)
SportClient::Move(0.05, 0.0, 0.0) repeated at 20 Hz for 1.0 second
SportClient::StopMove
SportClient::ClassicWalk(false)
SportClient::SwitchJoystick(true)
```

Expected real motion:

```text
forward
0.05 m/s
1.0 second
about 5 cm
```

Build on GO2:

```bash
cd ~/go2_agent/native
./build_helper.sh
```

Run only in an open area with emergency stop ready:

```bash
export GO2_REAL_MOVE_ACK=YES
./run_real_move_acceptance.sh
```

The program prints a warning and waits for exact manual input:

```text
YES
```

If the input is anything else, it exits without moving.

See:

```bash
go2_agent/native/test_real_move_acceptance.md
```

This acceptance test does not modify or depend on the dryrun controller,
Native Motion Daemon, Safety Gate, WebSocket path, or Uni-NaVid.
It temporarily disables joystick control during the short real-move window and
restores joystick control on normal exit, cancellation, or exception cleanup.
