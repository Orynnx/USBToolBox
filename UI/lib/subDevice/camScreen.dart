// ignore_for_file: file_names

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'devicePage.dart';

/// 虚拟摄像头（UVC 协议）配置与预览页面
///
/// 允许用户将 Android 设备的物理摄像头（后置/前置）或屏幕画面模拟为 USB UVC 摄像头输出至主机端。
class CamScreen extends StatefulWidget {
  const CamScreen({super.key});

  @override
  State<CamScreen> createState() => _CamScreenState();
}

class _CamScreenState extends State<CamScreen> {
  /// 摄像头服务启停开关状态
  bool _enabled = false;

  /// 当前选中的视频输入采集源：
  /// - 'Back': 后置摄像头
  /// - 'Front': 前置摄像头
  /// - 'Screen': 屏幕内容捕获
  String _source = 'Back';

  /// 当前输出分辨率规格：'720p' | '1080p' | '4K'
  String _resolution = '1080p';

  @override
  Widget build(BuildContext context) {
    // 获取本地化国际化字符串辅助对象
    final l = context.l10n;

    return DeviceScaffold(
      title: l.text('virtualWebcam'), // 页面标题：“虚拟摄像头”
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 摄像头服务总开关状态卡片
          DeviceStatusCard(
            icon: Icons.videocam_rounded,
            title: l.text('cameraService'), // “摄像头服务”
            detail: _enabled ? l.text('videoReady') : l.text('disabled'),
            enabled: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),

          // 2. 取景器预览窗口小节
          DeviceSection(l.text('viewfinder')), // “取景器”
          DeviceCard(
            padding: EdgeInsets.zero,
            child: AspectRatio(
              aspectRatio: 16 / 9, // 保持标准 16:9 视频取景比例
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xff202127), // 深色暗调背景模拟画面预览窗
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Center(
                  child: Icon(
                    Icons.videocam_off_rounded,
                    size: 54,
                    color: Color(0xffb9bbc8),
                  ),
                ),
              ),
            ),
          ),

          // 3. 视频源选择小节
          DeviceSection(l.text('videoSource')), // “视频源”
          DeviceCard(
            child: Wrap(
              spacing: 8,
              children: const ['Back', 'Front', 'Screen']
                  .map(
                    (value) => ChoicePill(
                      label: value == 'Back'
                          ? l.text('back') // “后置”
                          : value == 'Front'
                          ? l.text('front') // “前置”
                          : l.text('screen'), // “屏幕”
                      selected: _source == value,
                      onTap: () => setState(() => _source = value),
                    ),
                  )
                  .toList(),
            ),
          ),

          // 4. 输出参数规格配置小节（分辨率与编码格式）
          DeviceSection(l.text('outputSpec')), // “输出规格”
          DeviceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 分辨率选择
                Text(
                  l.text('resolution'), // “分辨率”
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['720p', '1080p', '4K']
                      .map(
                        (v) => ChoicePill(
                          label: v,
                          selected: _resolution == v,
                          onTap: () => setState(() => _resolution = v),
                        ),
                      )
                      .toList(),
                ),
                const Divider(height: 28),
                // 编码格式说明
                Text(l.text('codec')), // “编码”
                const SizedBox(height: 5),
                Text(
                  l.text('codecValue'), // 编码参数（如 MJPEG / H.264 等）
                  style: const TextStyle(color: Color(0xff777986)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
