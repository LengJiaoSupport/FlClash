import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/enum/enum.dart';

import 'print.dart';

typedef InstallConfigCallBack = void Function(String url, String? label);

class LinkManager {
  static LinkManager? _instance;
  late AppLinks _appLinks;
  StreamSubscription? subscription;
  ServerSocket? _forwardServer;
  InstallConfigCallBack? _installConfigCallBack;
  final List<Uri> _pendingUris = [];

  LinkManager._internal() {
    _appLinks = AppLinks();
  }

  Future<void> initAppLinksListen(InstallConfigCallBack installConfigCallBack) async {
    commonPrint.log('initAppLinksListen');
    _installConfigCallBack = installConfigCallBack;
    destroy();
    subscription = _appLinks.uriLinkStream.listen((uri) {
      commonPrint.log('onAppLink: $uri');
      _handleUri(uri);
    });
    if (_pendingUris.isNotEmpty) {
      for (final uri in List<Uri>.from(_pendingUris)) {
        _handleUri(uri);
      }
      _pendingUris.clear();
    }
  }

  Future<void> startForwardServer() async {
    if (_forwardServer != null) return;
    try {
      _forwardServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        appLinkForwardPort,
        shared: false,
      );
      _forwardServer!.listen((socket) async {
        final payload = await utf8.decoder.bind(socket).join();
        socket.destroy();
        final uri = Uri.tryParse(payload.trim());
        if (uri != null) {
          _handleUri(uri);
        }
      });
      commonPrint.log('app link forward server started');
    } catch (e) {
      commonPrint.log(
        'startForwardServer failed: $e',
        logLevel: LogLevel.warning,
      );
    }
  }

  Future<bool> forwardIfPossible() async {
    final urls = Platform.executableArguments
        .where((argument) => argument.contains('://'))
        .toList();
    if (urls.isEmpty) return false;
    for (final url in urls) {
      for (var i = 0; i < 5; i++) {
        try {
          final socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            appLinkForwardPort,
            timeout: const Duration(milliseconds: 200),
          );
          socket.write(url);
          await socket.flush();
          await socket.close();
          commonPrint.log('forwarded app link: $url');
          return true;
        } catch (_) {
          if (i == 4) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }
    return false;
  }

  void destroy() {
    if (subscription != null) {
      subscription?.cancel();
      subscription = null;
    }
  }

  void _handleUri(Uri uri) {
    if (uri.host != 'install-config') return;
    final parameters = uri.queryParameters;
    final url = parameters['url'];
    if (url == null) {
      _pendingUris.add(uri);
      return;
    }
    final label = parameters['name'] ?? parameters['label'];
    if (_installConfigCallBack == null) {
      _pendingUris.add(uri);
      return;
    }
    _installConfigCallBack!(url, label);
  }

  factory LinkManager() {
    _instance ??= LinkManager._internal();
    return _instance!;
  }
}

final linkManager = LinkManager();
