import 'package:flutter/foundation.dart';
import '../models/ticket_model.dart';
import '../repositories/tickets_repository.dart';

class TicketsProvider extends ChangeNotifier {
  final TicketsRepository _repository;
  TicketsProvider(this._repository);
  bool _isLoading = false;
  bool _isWorking = false;
  String? _error;
  List<TicketModel> _tickets = [];
  TicketModel? _selectedTicket;
  String _search = '';
  String _status = 'all';
  Map<String, int> _counts = const {'total': 0, 'received': 0, 'unread': 0, 'answered': 0, 'closed': 0};
  int _page = 1;
  int _totalPages = 1;
  static const _pageSize = 20;

  bool get isLoading => _isLoading;
  bool get isWorking => _isWorking;
  String? get error => _error;
  List<TicketModel> get tickets => List.unmodifiable(_tickets);
  TicketModel? get selectedTicket => _selectedTicket;
  String get search => _search;
  String get status => _status;
  int get currentPage => _page;
  int get totalPages => _totalPages;
  Map<String, int> get counts => Map.unmodifiable(_counts);

  Future<void> fetchTickets() async {
    _isLoading = true; _error = null; notifyListeners();
    try { _tickets = await _repository.getTickets(page: _page, pageSize: _pageSize, search: _search, status: _status); _totalPages = _tickets.length == _pageSize ? _page + 1 : _page; _counts = await _repository.getTicketCounts(); }
    catch (e) { _error = e.toString(); }
    finally { _isLoading = false; notifyListeners(); }
  }
  Future<void> setSearch(String value) async { _search = value.trim(); _page = 1; await fetchTickets(); }
  Future<void> setStatus(String value) async { _status = value; _page = 1; await fetchTickets(); }
  Future<void> changePage(int value) async { if (value < 1 || value > _totalPages) return; _page = value; await fetchTickets(); }
  Future<void> fetchTicket(String id) async {
    _isLoading = true; _error = null; _selectedTicket = null; notifyListeners();
    try {
      _selectedTicket = await _repository.getTicketById(id);
      // Opening a ticket marks it as read in the repository; refresh unread counts immediately.
      _counts = await _repository.getTicketCounts();
      final index = _tickets.indexWhere((ticket) => ticket.id == id);
      if (index >= 0 && _selectedTicket != null) {
        _tickets[index] = _selectedTicket!;
      }
    } catch (e) { _error = e.toString(); }
    finally { _isLoading = false; notifyListeners(); }
  }
  Future<bool> reply(String id, String text) async {
    _isWorking = true; _error = null; notifyListeners();
    try {
      await _repository.replyToTicket(id, text);
      _selectedTicket = await _repository.getTicketById(id);
      _counts = await _repository.getTicketCounts();
      final index = _tickets.indexWhere((ticket) => ticket.id == id);
      if (index >= 0) _tickets[index] = _tickets[index].copyWith(status: 'answered');
      return true;
    } catch (e) { _error = e.toString(); return false; }
    finally { _isWorking = false; notifyListeners(); }
  }
  Future<bool> updateStatus(String id, String status) async {
    _isWorking = true; _error = null; notifyListeners();
    try {
      await _repository.updateTicketStatus(id, status);
      _counts = await _repository.getTicketCounts();
      final index = _tickets.indexWhere((ticket) => ticket.id == id);
      if (index >= 0) _tickets[index] = _tickets[index].copyWith(status: status);
      if (_selectedTicket?.id == id) _selectedTicket = _selectedTicket!.copyWith(status: status);
      return true;
    } catch (e) { _error = e.toString(); return false; }
    finally { _isWorking = false; notifyListeners(); }
  }
}
