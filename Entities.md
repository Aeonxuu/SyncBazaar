# Original Draft

User
  user_id, name, email, role, assigned_event_id (nullable)

Company
  company_id, name, address, contact, incentive_percent, buffer_percent

BazaarEvent
  event_id, name, company_id, start_date, end_date, status (upcoming/ongoing/ended)

Product
  product_id, name, variant, size, base_price, image_url

EventInventory
  event_inventory_id, event_id, product_id, allocated_quantity, sold_quantity (calculated)

Sale
  sale_id, event_id, product_id, customer_name, employee_id (not a table in here, just the actualy employee customer's id), payment_method, qty, total, timestamp, order_status, synced

Order
  order_id, sale_id, event_id, order_status, updated_at

ApprovalRequest
  request_id, type (stock|soa), event_id, requester_id, status, details_json


# New Additions

Notification
  notification_id, user_id, type, title, details, timestamp, marked_as_read

DocumentRequest
  document_id, type (soa|list of orders), file_type (docx, csv, pdf), event_id, title, timestamp, file_url