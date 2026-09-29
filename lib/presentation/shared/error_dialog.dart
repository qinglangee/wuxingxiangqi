import 'package:flutter/material.dart';

/// 操作失败报错对话框：模态弹窗，用户点击「知道了」后才消失
/// （不自动消失，区别于成功提示用的 SnackBar/FloatingToast）。
Future<void> showErrorDialog(BuildContext context, String message, {String title = "操作失败啦"}) {
  return showCustomeDialog(context, message, title: title);
}
Future<void> showInfoDialog(BuildContext context, String message, {String title = "信息"}) {
  return showCustomeDialog(context, message, title: title);
}
/// 对话框：模态弹窗，用户点击「知道了」后才消失
/// （不自动消失，区别于成功提示用的 SnackBar/FloatingToast）。
Future<void> showCustomeDialog(
  BuildContext context,
  String message, {
  String title = '信息',
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
