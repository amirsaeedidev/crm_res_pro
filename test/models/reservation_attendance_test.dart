import 'package:flutter_test/flutter_test.dart';
import 'package:crm_panel/models/reservation_model.dart';

void main() {
  group('Reservation attendance states', () {
    test('parses delay details and arrival timestamp', () {
      final reservation = ReservationModel.fromJson({
        'id': 'reservation-1',
        'customer_name': 'Test Customer',
        'customer_phone': '09120000000',
        'date': '2026-11-01',
        'time': '18:30',
        'party_size': 3,
        'table_number': '4',
        'status': 'delayed',
        'arrived_at': '2026-11-01T18:40:00Z',
        'delayed_at': '2026-11-01T18:20:00Z',
        'delay_minutes': 20,
        'delay_note': 'در مسیر',
      });
      expect(reservation.status, ReservationStatus.delayed);
      expect(reservation.delayMinutes, 20);
      expect(reservation.delayNote, 'در مسیر');
      expect(reservation.arrivedAt, DateTime.parse('2026-11-01T18:40:00Z'));
    });

    test('maps no_show to the typed status', () {
      expect(ReservationStatusX.fromString('no_show'), ReservationStatus.noShow);
    });
  });
}
