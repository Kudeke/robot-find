from geometry_msgs.msg import TransformStamped
from nav_msgs.msg import Odometry
from tf2_ros import TransformBroadcaster


class OdomTfPublisher:
    def __init__(self, node):
        self.node = node
        self.publisher = self.node.create_publisher(Odometry, "/remote/odom", 10)
        self.tf_broadcaster = TransformBroadcaster(self.node)

    def publish_odom(self, payload):
        frame_id = str(payload.get("frame_id", "odom"))
        child_frame_id = str(payload.get("child_frame_id", "base_link"))
        position = payload.get("position", {})
        orientation = payload.get("orientation", {})
        linear_velocity = payload.get("linear_velocity", {})
        angular_velocity = payload.get("angular_velocity", {})
        stamp = self.node.get_clock().now().to_msg()

        odom_msg = Odometry()
        odom_msg.header.stamp = stamp
        odom_msg.header.frame_id = frame_id
        odom_msg.child_frame_id = child_frame_id
        odom_msg.pose.pose.position.x = float(position.get("x", 0.0))
        odom_msg.pose.pose.position.y = float(position.get("y", 0.0))
        odom_msg.pose.pose.position.z = float(position.get("z", 0.0))
        odom_msg.pose.pose.orientation.x = float(orientation.get("x", 0.0))
        odom_msg.pose.pose.orientation.y = float(orientation.get("y", 0.0))
        odom_msg.pose.pose.orientation.z = float(orientation.get("z", 0.0))
        odom_msg.pose.pose.orientation.w = float(orientation.get("w", 1.0))
        odom_msg.twist.twist.linear.x = float(linear_velocity.get("x", 0.0))
        odom_msg.twist.twist.linear.y = float(linear_velocity.get("y", 0.0))
        odom_msg.twist.twist.linear.z = float(linear_velocity.get("z", 0.0))
        odom_msg.twist.twist.angular.x = float(angular_velocity.get("x", 0.0))
        odom_msg.twist.twist.angular.y = float(angular_velocity.get("y", 0.0))
        odom_msg.twist.twist.angular.z = float(angular_velocity.get("z", 0.0))
        self.publisher.publish(odom_msg)

        transform = TransformStamped()
        transform.header.stamp = stamp
        transform.header.frame_id = frame_id
        transform.child_frame_id = child_frame_id
        transform.transform.translation.x = odom_msg.pose.pose.position.x
        transform.transform.translation.y = odom_msg.pose.pose.position.y
        transform.transform.translation.z = odom_msg.pose.pose.position.z
        transform.transform.rotation = odom_msg.pose.pose.orientation
        self.tf_broadcaster.sendTransform(transform)
