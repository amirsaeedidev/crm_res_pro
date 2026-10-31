import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_error_handler.dart';
import 'logger_service.dart';
import 'supabase_service.dart';

typedef RealtimeStatusCallback = void Function(
  RealtimeSubscribeStatus status,
  String? message,
);

class RealtimeService {
  RealtimeService._();

  static final Map<String, RealtimeChannel> _channels = {};
  static final StreamController<String> _connectionErrors =
      StreamController<String>.broadcast();

  static Stream<String> get connectionErrors => _connectionErrors.stream;
  static bool get hasActiveChannels => _channels.isNotEmpty;

  /// Supabase Realtime handles WebSocket reconnection and channel rejoin.
  /// Consumers should refresh their data after a reconnect.
  static RealtimeChannel subscribeToTable({
    required String table,
    String schema = 'public',
    required void Function(PostgresChangePayload payload) onInsert,
    required void Function(PostgresChangePayload payload) onUpdate,
    required void Function(PostgresChangePayload payload) onDelete,
    RealtimeStatusCallback? onStatus,
    void Function(String message)? onError,
  }) {
    final key = '$schema:$table';
    final existing = _channels[key];
    if (existing != null) {
      LoggerService.warning('Realtime subscription already exists for $key');
      return existing;
    }

    LoggerService.info('Starting realtime subscription for $key');

    void handleEvent(
      String eventName,
      PostgresChangePayload payload,
      void Function(PostgresChangePayload) callback,
    ) {
      try {
        callback(payload);
      } catch (error, stackTrace) {
        LoggerService.error(
          'Realtime $eventName callback failed for $key',
          error: error,
          stackTrace: stackTrace,
        );
        _reportError(
          'دریافت تغییرات زنده ناموفق بود. اطلاعات صفحه را تازه‌سازی کنید.',
          onError,
        );
      }
    }

    final channel = SupabaseService.client
        .channel('crm:$schema:$table')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: schema,
          table: table,
          callback: (payload) => handleEvent('INSERT', payload, onInsert),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: schema,
          table: table,
          callback: (payload) => handleEvent('UPDATE', payload, onUpdate),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: schema,
          table: table,
          callback: (payload) => handleEvent('DELETE', payload, onDelete),
        )
        .subscribe((status, error) {
          final detail = error == null ? null : AppErrorHandler.message(error);
          LoggerService.info('Realtime $key status: $status');
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            _reportError(
              detail ??
                  'ارتباط زنده با سرور قطع شد. پس از اتصال مجدد، اطلاعات صفحه را تازه‌سازی کنید.',
              onError,
            );
          } else if (status == RealtimeSubscribeStatus.subscribed) {
            LoggerService.info('Realtime connected for $key');
          } else if (status == RealtimeSubscribeStatus.closed) {
            LoggerService.warning('Realtime channel closed for $key');
          }
          onStatus?.call(status, detail);
        });

    _channels[key] = channel;
    return channel;
  }

  static void _reportError(
    String message,
    void Function(String message)? callback,
  ) {
    if (!_connectionErrors.isClosed) _connectionErrors.add(message);
    callback?.call(message);
    LoggerService.warning(message);
  }

  static Future<void> unsubscribe(RealtimeChannel channel) async {
    final keys = _channels.entries
        .where((entry) => identical(entry.value, channel))
        .map((entry) => entry.key)
        .toList();
    for (final key in keys) {
      _channels.remove(key);
    }

    try {
      await SupabaseService.client.removeChannel(channel);
      LoggerService.info('Realtime channel removed');
    } catch (error, stackTrace) {
      LoggerService.error(
        'Realtime channel removal failed',
        error: error,
        stackTrace: stackTrace,
      );
      _reportError(
        'قطع ارتباط زنده با سرور کامل نشد. برنامه را دوباره باز کنید.',
        null,
      );
    }
  }

  static Future<void> unsubscribeAll() async {
    final channels = _channels.values.toSet().toList();
    _channels.clear();
    for (final channel in channels) {
      try {
        await SupabaseService.client.removeChannel(channel);
      } catch (error, stackTrace) {
        LoggerService.error(
          'Realtime channel cleanup failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  static Future<void> dispose() async {
    await unsubscribeAll();
    await _connectionErrors.close();
  }
}
