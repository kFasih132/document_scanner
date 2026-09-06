/// Defines the detection architectural paradigm of the YOLO neural network
enum YoloModelType {
  /// Standard 2D Axis-Aligned Bounding Box (AABB) detection
  /// Output format: [cx, cy, w, h, (obj_conf), class_scores...]
  standardDetection,

  /// 4-Keypoint Quadrilateral / Pose detection
  /// Output format: [cx, cy, w, h, (score), x1, y1, conf1, x2, y2, conf2, x3, y3, conf3, x4, y4, conf4, ...]
  /// Used for diagonal boxes, documents, cards, limb poses, rotated bounding boxes
  pose4Points,
}
