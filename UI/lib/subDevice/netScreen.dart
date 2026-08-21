// ignore_for_file: file_names

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'devicePage.dart';

/// 虚拟 USB 网络适配器（USB RNDIS / CDC-ECM / NCM 网络共享）配置页面
///
/// 通过 USB 接口将移动设备模拟为虚拟以太网网卡，为主机提供网络连接、网络调试或点对点局域网通道。
class NetScreen extends StatefulWidget {
  const NetScreen({super.key});

  @override
  State<NetScreen> createState() => _NetScreenState();
}

class _NetScreenState extends State<NetScreen> {
  /// 虚拟网卡服务总启停状态
  bool _enabled = false;

  /// 是否启用内置 DHCP 自动为接入的主机分配 IP 地址
  bool _dhcp = true;

  @override
  Widget build(BuildContext context) {
    // 获取多语言本地化资源对象
    final l = context.l10n;

    return DeviceScaffold(
      title: l.text('virtualNetwork'), // 页面标题：“虚拟网络”
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 虚拟网络适配器服务开关卡片
          DeviceStatusCard(
            icon: Icons.lan_rounded,
            title: l.text('networkAdapter'), // “网络适配器”
            detail: _enabled ? l.text('networkActive') : l.text('disabled'),
            enabled: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),

          // 2. 网络参数与模式配置小节
          DeviceSection(l.text('networkMode')), // “网络模式”
          DeviceCard(
            child: Column(
              children: [
                // DHCP 服务开关
                SwitchListTile(
                  title: Text(l.text('dhcp')), // “DHCP 服务”
                  subtitle: Text(l.text('dhcpSummary')), // “自动为主机分配 IPv4 地址”
                  value: _dhcp,
                  onChanged: (v) => setState(() => _dhcp = v),
                ),
                const Divider(height: 1),

                // 主机网关与子网信息
                ListTile(
                  leading: const Icon(Icons.router_rounded),
                  title: Text(l.text('hostAddress')), // “主机端 IP 地址”
                  subtitle: const Text('192.168.42.1 / 24'),
                ),

                // DNS 转发配置项
                ListTile(
                  leading: const Icon(Icons.dns_rounded),
                  title: Text(l.text('dnsForwarding')), // “DNS 转发”
                  subtitle: Text(l.text('dnsSummary')), // “使用移动端上游 DNS 解析”
                ),
              ],
            ),
          ),

          // 3. 主机连接链路检测小节
          DeviceSection(l.text('hostConnection')), // “主机连接状态”
          DeviceCard(
            child: Row(
              children: [
                const Icon(Icons.link_off_rounded, color: Color(0xff777986)),
                const SizedBox(width: 12),
                // 主机连接状态文本（例如“未检测到主机链路”）
                Expanded(child: Text(l.text('noHost'))),
                // 刷新网络链路检测按钮（服务启用时可用）
                OutlinedButton(
                  onPressed: _enabled
                      ? () {
                          // TODO: 重新查询 USB 网卡驱动握手状态
                        }
                      : null,
                  child: Text(l.text('refresh')), // “刷新”
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
