import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 封面中转代理：当手机直连各平台封面 CDN 失败时，经我们的服务器中转加载。
class CoverProxy {
  static const String proxyBase = 'http://161.118.252.183/cover-proxy';
  static const String _proxy = 'http://161.118.252.183';

  /// 生成代理 URL：按域名匹配，仅命中已知封面 CDN 才走代理，其他平台直连。
  static String? toProxy(String? url) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.host;

    String? prefix;
    if (host.endsWith('music.126.net')) {
      prefix = proxyBase; // 网易云封面
    } else if (host.endsWith('imge.kugou.com')) {
      prefix = '$_proxy/img-kugou'; // 酷狗封面
    } else if (host.endsWith('p.qpic.cn')) {
      prefix = '$_proxy/img-qq'; // QQ 歌单封面
    } else if (host.endsWith('qpic.y.qq.com')) {
      prefix = '$_proxy/img-qqy'; // QQ 歌单封面(备用域名)
    } else if (host.endsWith('y.gtimg.cn')) {
      prefix = '$_proxy/img-ygtimg'; // QQ 单曲封面
    } else {
      return null;
    }
    var path = uri.path;
    if (uri.hasQuery) path = '$path?${uri.query}';
    return '$prefix$path';
  }
}

/// 智能封面：
/// 1. 直连原始 URL（其他平台或网络通畅时零开销）
/// 2. 加载失败自动切换服务器中转代理（解决网易云封面在某些网络下加载不出）
/// 3. 全部失败才显示占位图
class SmartCover extends StatefulWidget {
  final String? url;
  final BoxFit fit;
  final Widget Function() placeholder;

  const SmartCover({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    required this.placeholder,
  });

  @override
  State<SmartCover> createState() => _SmartCoverState();
}

class _SmartCoverState extends State<SmartCover> {
  late List<String?> _urls;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _initUrls();
  }

  @override
  void didUpdateWidget(SmartCover old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _initUrls();
    }
  }

  void _initUrls() {
    final list = <String?>[widget.url];
    final proxy = CoverProxy.toProxy(widget.url);
    if (proxy != null && proxy != widget.url) list.add(proxy);
    _urls = list;
    _attempt = 0;
  }

  void _nextAttempt() {
    if (!mounted) return;
    if (_attempt < _urls.length - 1) {
      setState(() => _attempt++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = (_attempt < _urls.length) ? _urls[_attempt] : null;
    if (url == null || url.isEmpty) {
      return widget.placeholder();
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: widget.fit,
      placeholder: (_, __) => widget.placeholder(),
      errorWidget: (_, __, ___) {
        // 失败后自动切换到下一个 URL（延迟到 build 之后执行，避免 setState 时序问题）
        Future.microtask(_nextAttempt);
        return widget.placeholder();
      },
    );
  }
}
