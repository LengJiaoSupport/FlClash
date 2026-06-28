import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_links/app_links.dart';

import 'print.dart';
import 'system.dart';

typedef InstallConfigCallBack = void Function(String url, String? label);

class LinkManager {
  static LinkManager? _instance;
  static const int _windowsForwardPort = 46382;
  late AppLinks _appLinks;
  StreamSubscription? subscription;
  ServerSocket? _windowsForwardServer;
  InstallConfigCallBack? _installConfigCallBack;

  LinkManager._internal() {
    _appLinks = AppLinks();
  }

  Future<void> initAppLinksListen(InstallConfigCallBack installConfigCallBack) async {
    commonPrint.log('initAppLinksListen');
    _installConfigCallBack = installConfigCallBack;
    destroy();
    await _startWindowsForwardServer();
    subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
    );
  }

  void _handleUri(Uri uri) {
    commonPrint.log('onAppLink: $uri');
    if (uri.host != 'install-config') return;
    final url = uri.queryParameters['url'];
    if (url == null) return;
    final label = uri.queryParameters['name'] ?? uri.queryParameters['label'];
    _installConfigCallBack?.call(url, label);
  }

  Future<void> _startWindowsForwardServer() async {
    if (!system.isWindows || _windowsForwardServer != null) return;
    try {
      _windowsForwardServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _windowsForwardPort,
        shared: true,
      );
      _windowsForwardServer?.listen((socket) async {
        try {
          final uri = await utf8.decoder.bind(socket).join();
          if (uri.isNotEmpty) {
            _handleUri(Uri.parse(uri));
          }
        } catch (e) {
          commonPrint.log('handle forwarded app link error: $e');
        } finally {
          await socket.close();
        }
      });
    } catch (e) {
      commonPrint.log('start windows app link forward server error: $e');
    }
  }

  Future<bool> forwardInitialLinkToPrimaryInstance() async {
    if (!system.isWindows) return false;
    final uri = Platform.executableArguments.firstWhere(
      _isInstallConfigUri,
      orElse: () => '',
    );
    if (uri.isEmpty) return false;
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _windowsForwardPort,
        timeout: const Duration(seconds: 1),
      );
      socket.write(uri);
      await socket.flush();
      await socket.close();
      return true;
    } catch (e) {
      commonPrint.log('forward app link to primary instance error: $e');
      return false;
    }
  }

  bool _isInstallConfigUri(String value) {
    try {
      final uri = Uri.parse(value);
      return uri.host == 'install-config' &&
          const {'clash', 'clashmeta', 'flclash'}.contains(uri.scheme);
    } catch (_) {
      return false;
    }
  }

  void destroy() {
    if (subscription != null) {
      subscription?.cancel();
      subscription = null;
    }
  }

  factory LinkManager() {
    _instance ??= LinkManager._internal();
    return _instance!;
  }
}

final linkManager = LinkManager();
