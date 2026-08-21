// ignore_for_file: file_names

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'devicePage.dart';

/// 虚拟 USB 串口设备（USB CDC-ACM / 虚拟 COM 端口）配置与监视页面
///
/// 通过 USB 将设备模拟为标准虚拟串口，支持与主机进行双向字符流传输、AT 指令调试及日志通信。
class SerialScreen extends StatefulWidget {
  const SerialScreen({super.key});

  @override
  State<SerialScreen> createState() => _SerialScreenState();
}

class _SerialScreenState extends State<SerialScreen> {
  /// 串口服务启停开关状态
  bool _enabled = false;

  /// 当前配置的串口波特率：'9600' | '57600' | '115200' | '921600'
  String _baud = '115200';

  @override
  Widget build(BuildContext context) {
    // 获取多语言本地化资源
    final l = context.l10n;

    return DeviceScaffold(
      title: l.text('virtualSerial'), // 页面标题：“虚拟串口”
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 串口服务启停状态卡片
          DeviceStatusCard(
            icon: Icons.terminal_rounded,
            title: l.text('serialService'), // “串口服务”
            detail: _enabled ? l.text('serialConnected') : l.text('disabled'),
            enabled: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),

          // 2. 串口通信参数配置小节
          DeviceSection(l.text('parameters')), // “通信参数”
          DeviceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 波特率选择
                Text(
                  l.text('baudRate'), // “波特率”
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  children: ['9600', '57600', '115200', '921600']
                      .map(
                        (v) => ChoicePill(
                          label: v,
                          selected: _baud == v,
                          onTap: () => setState(() => _baud = v),
                        ),
                      )
                      .toList(),
                ),
                const Divider(height: 28),

                // 数据格式说明（例如 8-N-1: 8位数据位，无校验，1位停止位）
                Text(
                  l.text('serialFormat'), // “数据格式：8 数据位，无校验，1 停止位 (8N1)”
                  style: const TextStyle(color: Color(0xff777986)),
                ),
              ],
            ),
          ),

          // 3. 串口数据终端监视器小节
          DeviceSection(l.text('monitor')), // “数据监视器”
          DeviceCard(
            child: Container(
              height: 190,
              padding: const EdgeInsets.all(12),
              color: const Color(0xff202127), // 深色暗黑背景模拟控制台终端
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  l.text('noSerialData'), // “暂无串口数据通信...”
                  style: const TextStyle(
                    fontFamily: 'monospace', // 等宽字体呈现终端字符
                    color: Color(0xffb9bbc8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
