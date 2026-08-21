class UvcConfiguration {
  const UvcConfiguration({
    required this.format,
    required this.width,
    required this.height,
    required this.fps,
  });

  final String format;
  final int width;
  final int height;
  final int fps;

  Map<String, dynamic> toJson() => {
    'enabled': true,
    'formats': [
      {
        'format': format,
        'frames': [
          {'width': width, 'height': height, 'fps': [fps]},
        ],
      },
    ],
  };
}
