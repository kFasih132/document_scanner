import 'package:flutter/material.dart';

enum DeviceScreenType {
  mobile,
  tablet7Inch,
  tablet10Inch,
}

/// Adaptive Layout Builder that switches UI based on screen breakpoints:
/// Mobile: < 600px width
/// 7-inch Tablet (Medium): 600px - 840px width
/// 10-inch+ Tablet (Expanded): > 840px width
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet7Inch;
  final Widget? tablet10Inch;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet7Inch,
    this.tablet10Inch,
  });

  static DeviceScreenType getDeviceType(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    if (width >= 840) {
      return DeviceScreenType.tablet10Inch;
    } else if (width >= 600) {
      return DeviceScreenType.tablet7Inch;
    } else {
      return DeviceScreenType.mobile;
    }
  }

  static bool isMobile(BuildContext context) =>
      getDeviceType(context) == DeviceScreenType.mobile;

  static bool isTablet7Inch(BuildContext context) =>
      getDeviceType(context) == DeviceScreenType.tablet7Inch;

  static bool isTablet10Inch(BuildContext context) =>
      getDeviceType(context) == DeviceScreenType.tablet10Inch;

  static bool isTablet(BuildContext context) =>
      getDeviceType(context) != DeviceScreenType.mobile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 840 && tablet10Inch != null) {
          return tablet10Inch!;
        }
        if (constraints.maxWidth >= 600 && tablet7Inch != null) {
          return tablet7Inch!;
        }
        return mobile;
      },
    );
  }
}
