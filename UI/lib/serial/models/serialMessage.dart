// ignore_for_file: file_names
enum SerialDirection { tx, rx }

class SerialMessage {
  const SerialMessage({
    required this.timestamp,
    required this.direction,
    required this.message,
  });
  final DateTime timestamp;
  final SerialDirection direction;
  final String message;
}
