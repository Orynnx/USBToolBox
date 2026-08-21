class KeyStroke {
  const KeyStroke({
    this.modifiers = const [],
    required this.key,
  });

  final List<String> modifiers;
  final String key;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyStroke &&
          key == other.key &&
          modifiers.length == other.modifiers.length &&
          modifiers.every((m) => other.modifiers.contains(m));

  @override
  int get hashCode => Object.hash(key, Object.hashAll(modifiers));

  @override
  String toString() => modifiers.isEmpty ? key : '${modifiers.join("+")}+$key';
}

class KeyboardEncodingException implements Exception {
  KeyboardEncodingException(this.character);
  final String character;

  @override
  String toString() => 'Unsupported character: "$character"';
}

class KeyboardTextEncoder {
  static KeyStroke encodeChar(String char) {
    if (char.isEmpty || char.length != 1) {
      throw KeyboardEncodingException(char);
    }
    final code = char.codeUnitAt(0);

    // a-z
    if (code >= 97 && code <= 122) {
      return KeyStroke(key: char.toUpperCase());
    }
    // A-Z
    if (code >= 65 && code <= 90) {
      return KeyStroke(modifiers: const ['SHIFT'], key: char);
    }
    // 0-9
    if (code >= 48 && code <= 57) {
      return KeyStroke(key: char);
    }

    // Special ASCII punctuation and whitespace
    switch (char) {
      case ' ':
        return const KeyStroke(key: 'SPACE');
      case '\n':
        return const KeyStroke(key: 'ENTER');
      case '\t':
        return const KeyStroke(key: 'TAB');
      case '!':
        return const KeyStroke(modifiers: ['SHIFT'], key: '1');
      case '@':
        return const KeyStroke(modifiers: ['SHIFT'], key: '2');
      case '#':
        return const KeyStroke(modifiers: ['SHIFT'], key: '3');
      case r'$':
        return const KeyStroke(modifiers: ['SHIFT'], key: '4');
      case '%':
        return const KeyStroke(modifiers: ['SHIFT'], key: '5');
      case '^':
        return const KeyStroke(modifiers: ['SHIFT'], key: '6');
      case '&':
        return const KeyStroke(modifiers: ['SHIFT'], key: '7');
      case '*':
        return const KeyStroke(modifiers: ['SHIFT'], key: '8');
      case '(':
        return const KeyStroke(modifiers: ['SHIFT'], key: '9');
      case ')':
        return const KeyStroke(modifiers: ['SHIFT'], key: '0');
      case '-':
        return const KeyStroke(key: 'MINUS');
      case '_':
        return const KeyStroke(modifiers: ['SHIFT'], key: 'MINUS');
      case '=':
        return const KeyStroke(key: 'EQUAL');
      case '+':
        return const KeyStroke(modifiers: ['SHIFT'], key: 'EQUAL');
      case '[':
        return const KeyStroke(key: 'LEFTBRACKET');
      case '{':
        return const KeyStroke(modifiers: ['SHIFT'], key: 'LEFTBRACKET');
      case ']':
        return const KeyStroke(key: 'RIGHTBRACKET');
      case '}':
        return const KeyStroke(modifiers: ['SHIFT'], key: 'RIGHTBRACKET');
      case r'\':
        return const KeyStroke(key: 'BACKSLASH');
      case '|':
        return const KeyStroke(modifiers: ['SHIFT'], key: 'BACKSLASH');
      case ';':
        return const KeyStroke(key: 'SEMICOLON');
      case ':':
        return const KeyStroke(modifiers: ['SHIFT'], key: 'SEMICOLON');
      case "'":
        return const KeyStroke(key: 'QUOTE');
      case '"':
        return const KeyStroke(modifiers: ['SHIFT'], key: 'QUOTE');
      case '`':
        return const KeyStroke(key: 'GRAVE');
      case '~':
        return const KeyStroke(modifiers: ['SHIFT'], key: 'GRAVE');
      case ',':
        return const KeyStroke(key: 'COMMA');
      case '<':
        return const KeyStroke(modifiers: ['SHIFT'], key: 'COMMA');
      case '.':
        return const KeyStroke(key: 'DOT');
      case '>':
        return const KeyStroke(modifiers: ['SHIFT'], key: 'DOT');
      case '/':
        return const KeyStroke(key: 'SLASH');
      case '?':
        return const KeyStroke(modifiers: ['SHIFT'], key: 'SLASH');
      default:
        throw KeyboardEncodingException(char);
    }
  }

  static List<KeyStroke> encodeText(String text) {
    final strokes = <KeyStroke>[];
    final runes = text.runes.toList();
    for (int i = 0; i < runes.length; i++) {
      final rune = runes[i];
      final char = String.fromCharCode(rune);
      if (char == '\r') continue;
      strokes.add(encodeChar(char));
    }
    return strokes;
  }
}
