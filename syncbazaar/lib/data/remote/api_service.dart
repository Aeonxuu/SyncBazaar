import 'dart:async';

class ApiService {
  // Replace mock methods with real endpoints later:
  // POST /api/login
  // GET  /api/products
  // GET/POST /api/events
  // GET  /api/events/:id/inventory
  // POST /api/sales
  // GET  /api/events/:id/reports
  // GET  /api/events/:id/soa

  Future<void> login(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Future<void> syncPayload(List<Map<String, dynamic>> payload) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
}
