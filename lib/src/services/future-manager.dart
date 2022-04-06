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
    _logger.i('FutureManager - makeFuture for id: $id');
    if (id.isNotEmpty) {
      _pendingFutures[id] =
          FutureCallback(completer: completer, ts: DateTime.now());
      _logger.i(
          'FutureManager - makeFuture - _pendingFutures[id] value: ${_pendingFutures[id]}');
    }
    return completer.future;
  }

  void execFuture(String? id, int code, dynamic onOK, String? errorText) {
    var callbacks = _pendingFutures[id];
    _logger.i(
        'FutureManager - execFuture - id: $id, code: $code, onOK: $onOK, errorText: $errorText, callbacks: $callbacks');
    _logger.i('FutureManager - execFuture - _pendingFutures: $_pendingFutures');
    if (callbacks != null) {
      _pendingFutures.remove(id);
      _logger.i(
          'FutureManager - execFuture - _pendingFutures after removed: $_pendingFutures');
      if (code >= 200 && code < 400) {
        _logger.i('FutureManager - execFuture - complete with onOk: $onOK');
        callbacks.completer?.complete(onOK);
      } else {
        final exceptionMessage =
            (errorText ?? '') + ' (' + code.toString() + ')';
        _logger.i(
            'FutureManager - execFuture - complete with error with message: $exceptionMessage');
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
      _logger.i(
          'FutureManager - checkExpiredFutures - key: $key, featureCB: $featureCB, expires: $expires');
      if (featureCB.ts!.isBefore(expires)) {
        _logger.e(
            'FutureManager - checkExpiredFutures - Promise expired for key ' +
                key.toString());
        markForRemoval.add(key);
        _logger.e(
            'FutureManager - checkExpiredFutures - markForRemoval: $markForRemoval');
        featureCB.completer?.completeError(exception);
        _logger.e(
            'FutureManager - checkExpiredFutures - completeError with exception: $exception');
      }
    });
    _pendingFutures.removeWhere((key, value) {
      _logger.i(
          'FutureManager - checkExpiredFutures - _pendingFutures remove key: $key, value: $value');
      return markForRemoval.contains(key);
    });
    _logger.i(
        'FutureManager - checkExpiredFutures - _pendingFutures after removed: $_pendingFutures');
  }

  void startCheckingExpiredFutures() {
    if (_expiredFuturesCheckerTimer != null &&
        _expiredFuturesCheckerTimer!.isActive) {
      _logger.i(
          'FutureManager - startCheckingExpiredFutures -_expiredFuturesCheckerTimer!.isActive: ${_expiredFuturesCheckerTimer!.isActive}');
      return;
    }
    final expireFuturesPeriod = _configService.appSettings.expireFuturesPeriod;
    _expiredFuturesCheckerTimer =
        Timer.periodic(Duration(milliseconds: expireFuturesPeriod), (_) {
      _logger.i(
          'FutureManager - startCheckingExpiredFutures -checkExpiredFutures after: $expireFuturesPeriod');
      checkExpiredFutures();
    });
  }

  void rejectAllFutures(int code, String reason) {
    _logger
        .e('FutureManager - rejectAllFutures - code: $code, reason: $reason');
    _pendingFutures.forEach((String key, FutureCallback cb) {
      cb.completer?.completeError(reason);
      _logger.e(
          'FutureManager - rejectAllFutures - completer completeError - key: $key, cd: $cb, reason: $reason');
    });
    _pendingFutures.clear();
    _logger.e(
        'FutureManager - rejectAllFutures - _pendingFutures: $_pendingFutures');
  }

  void stopCheckingExpiredFutures() {
    _logger.i('FutureManager - stopCheckingExpiredFutures');
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
