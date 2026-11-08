import 'package:flutter_test/flutter_test.dart';
import 'package:crm_panel/models/reservation_model.dart';

void main() {
  group('ReservationModel', () {
    test('parses complete lifecycle metadata and reservation status', () {
      final reservation = ReservationModel.fromJson({
        'id': 'reservation-1',
        'user_id': 'customer-1',
        'table_id': 'table-1',
        'customer_name': 'مشتری نمونه',
        'customer_phone': '09120000000',
        'date': '2026-11-07',
        'time': '19:30:00',
        'party_size': 4,
        'table_number': '12',
        'duration_minutes': 120,
        'status': 'delayed',
        'delay_minutes': 20,
        'delay_note': 'ترافیک',
        'order_id': 'order-1',
        'created_at': '2026-11-07T15:00:00Z',
      });

      expect(reservation.status, ReservationStatus.delayed);
      expect(reservation.durationMinutes, 120);
      expect(reservation.delayMinutes, 20);
      expect(reservation.delayNote, 'ترافیک');
      expect(reservation.orderId, 'order-1');
      expect(reservation.partySize, 4);
    });

    test('maps arrival, no-show and cancellation states distinctly', () {
      expect(ReservationStatusX.fromString('arrived'), ReservationStatus.arrived);
      expect(ReservationStatusX.fromString('no_show'), ReservationStatus.noShow);
      expect(ReservationStatusX.fromString('cancelled'), ReservationStatus.cancelled);
    });
  });
}
