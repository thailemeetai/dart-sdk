import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'dart:async';

import 'package:tinode/src/models/future-callback.dart';
import 'package:tinode/src/services/configuration.dart';

class FutureManager {
  final Map<String, FutureCallback> _pendingFutures = {};
  Timer? _expiredFuturesCheckerTimer;
  late ConfigService _configService;
  final _logger = Logger();

  FutureManager() {
    _configService = GetIt.I.get<ConfigService>();
  }

  Future<dynamic> makeFuture(String id) {
    var completer = Completer();
    if (id.isNotEmpty) {
      _pendingFutures[id] =
          FutureCallback(completer: completer, ts: DateTime.now());
      _logger.i(
          'FutureManager - makeFuture - _pendingFutures[$id] value: ${_pendingFutures[id]}');
    }
    return completer.future;
  }

  void execFuture(String? id, int code, dynamic onOK, String? errorText) {
    var callbacks = _pendingFutures[id];

    if (callbacks != null) {
      _pendingFutures.remove(id);
      if (code >= 200 && code < 400) {
        callbacks.completer?.complete(onOK);
        _logger.i(
            'FutureManager - execFuture - id: $id, code: $code, _pending[$id]: ${_pendingFutures[id]}');
      } else {
        final exceptionMessage =
            (errorText ?? '') + ' (' + code.toString() + ')';
        _logger.e(
            'FutureManager - execFuture - id: $id, code: $code, error message: $exceptionMessage, _pending[$id]: ${_pendingFutures[id]}');
        callbacks.completer?.completeError(Exception(exceptionMessage));
      }
    }
  }

  void checkExpiredFutures() {
    var exception = Exception('Timeout (504)');
    var expires = DateTime.now().subtract(Duration(
        milliseconds: _configService.appSettings.expireFuturesTimeout));

    var markForRemoval = <String>[];
    _pendingFutures.forEach((String key, FutureCallback featureCB) {
      if (featureCB.ts!.isBefore(expires)) {
        markForRemoval.add(key);
        featureCB.completer?.completeError(exception);
        _logger.e(
            'FutureManager - checkExpiredFutures - completeError, key expired: $key, markForRemoval: $markForRemoval');
      }
    });
    if (markForRemoval.isNotEmpty) {
      _pendingFutures.removeWhere((key, value) {
        return markForRemoval.contains(key);
      });
      _logger.i(
          'FutureManager - checkExpiredFutures - _pendingFutures after removed: $_pendingFutures');
    }
  }

  void startCheckingExpiredFutures() {
    if (_expiredFuturesCheckerTimer != null &&
        _expiredFuturesCheckerTimer!.isActive) {
      return;
    }
    final expireFuturesPeriod = _configService.appSettings.expireFuturesPeriod;
    _expiredFuturesCheckerTimer =
        Timer.periodic(Duration(milliseconds: expireFuturesPeriod), (_) {
      checkExpiredFutures();
    });
  }

  void rejectAllFutures(int code, String reason) {
    _pendingFutures.forEach((String key, FutureCallback cb) {
      cb.completer?.completeError(reason);
    });
    _pendingFutures.clear();
    _logger.e(
        'FutureManager - rejectAllFutures - _pendingFutures: $_pendingFutures');
  }

  void stopCheckingExpiredFutures() {
    if (_expiredFuturesCheckerTimer != null) {
      _expiredFuturesCheckerTimer?.cancel();
      _expiredFuturesCheckerTimer = null;
      _logger.i(
          'FutureManager - stopCheckingExpiredFutures - _expiredFuturesCheckerTimer cancelled');
    }
  }

  void clear() {
    _pendingFutures.clear();
  }
}
