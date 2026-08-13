/// 歌词解析工具：将 LRC 文本解析为时间轴-歌词行列表
class LyricLine {
  final Duration time;
  final String text;

  LyricLine(this.time, this.text);
}

class LyricParser {
  /// 解析 LRC 格式歌词
  static List<LyricLine> parse(String? lrcText) {
    if (lrcText == null || lrcText.isEmpty) return [];

    final lines = <LyricLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})[.:](\d{2,3})\]');
    final lrcLines = lrcText.split('\n');

    for (final line in lrcLines) {
      final matches = regex.allMatches(line);
      if (matches.isEmpty) continue;
      final text = line.replaceAll(regex, '').trim();
      if (text.isEmpty) continue;
      for (final match in matches) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final msStr = match.group(3)!;
        final ms = msStr.length == 2 ? int.parse(msStr) * 10 : int.parse(msStr);
        final duration = Duration(minutes: min, seconds: sec, milliseconds: ms);
        lines.add(LyricLine(duration, text));
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// 合并原文歌词与翻译歌词
  static List<LyricLine> mergeTranslation(List<LyricLine> original, List<LyricLine>? translation) {
    if (translation == null || translation.isEmpty) return original;

    final result = <LyricLine>[];
    final transMap = <Duration, String>{};
    for (final t in translation) {
      transMap[t.time] = t.text;
    }

    for (final o in original) {
      // 找最接近的翻译行（1秒内）
      String? trans;
      Duration? bestDelta;
      for (final t in translation) {
        final delta = (t.time - o.time).abs();
        if (delta.inMilliseconds < 1000) {
          if (bestDelta == null || delta < bestDelta) {
            bestDelta = delta;
            trans = t.text;
          }
        }
      }
      result.add(LyricLine(o.time, trans != null ? '${o.text}\n$trans' : o.text));
    }
    return result;
  }

  /// 根据当前播放进度找到对应歌词索引
  static int findCurrentIndex(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return 0;
    int index = 0;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].time <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }
}
