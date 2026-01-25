import 'package:json_annotation/json_annotation.dart';

part 'device.g.dart';

@JsonSerializable()
class Device {
  final String id;
  final String name;
  final String? type;
  final bool? isOnline;
  final String? ip;

  const Device({
    required this.id,
    required this.name,
    this.type,
    this.isOnline,
    this.ip,
  });

  /// 判断是否为本地设备
  bool get isLocalDevice => id == 'local_device';

  /// 静态工厂：创建本地设备实例
  static const Device localDevice = Device(
    id: 'local_device',
    name: '本机播放',
    type: 'local',
    isOnline: true,
  );

  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceToJson(this);
}
