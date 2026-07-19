# Uni-NaVid VLN

## Action Translator DryRun

`action_translator_node.py` subscribes to `/vln/uninavid/actions`, maps high-level
Uni-NaVid actions to short `geometry_msgs/msg/Twist` debug commands, and
publishes only to `/cmd_vel_debug`.

It never publishes to `/cmd_vel` and does not control GO2.

Run the translator:

```bash
cd ~/go2_uninavid/ubuntu_station
./run_action_translator_dryrun.sh
```

Check the dry-run mapping:

```bash
cd ~/go2_uninavid/ubuntu_station
./check_action_translator_dryrun.sh
```

Default mapping:

```text
forward -> linear.x=0.12, angular.z=0.0
left    -> linear.x=0.0,  angular.z=0.25
right   -> linear.x=0.0,  angular.z=-0.25
stop    -> linear.x=0.0,  angular.z=0.0
```

Every action lasts `0.35` seconds and is followed by a zero Twist.

## Safety Gate DryRun

`safety_gate_node.py` forwards `/cmd_vel_debug` to `/cmd_vel` only when the gate
is manually enabled and all safety checks pass.

The gate starts disabled:

```bash
cd ~/go2_uninavid/ubuntu_station
./run_safety_gate.sh
```

Enable forwarding:

```bash
./enable_safety_gate.sh
```

Disable forwarding:

```bash
./disable_safety_gate.sh
```

Latch emergency stop:

```bash
./emergency_stop.sh
```

Clear emergency stop. The gate remains disabled after clearing:

```bash
source /opt/ros/jazzy/setup.bash
ros2 service call \
  /vln/safety_gate/clear_emergency_stop \
  std_srvs/srv/Trigger \
  "{}"
```

Run the dry-run safety check:

```bash
./check_safety_gate.sh
```

Safety checks include speed limiting, command timeout, LiDAR timeout, forward
obstacle blocking, manual emergency stop, and shutdown stop. This stage assumes
the GO2 side is still using `DryRunController`; no real SDK2 Move is implemented
here.
