SyncBazaar Dashboard Specification
Overview

The dashboard serves as the primary landing page after login. Content adapts based on user role (Admin, Owner, Employee) to show only relevant data. The design follows a clean card-based layout with purple (#6C4AB6) accent and white (#FEFEFE) background.
Dashboard Components by User Role
1. Overview Cards (Top Row)

Four cards displayed in a grid.
Card	Admin	Owner	Employee
Total Revenue	All bazaars, current month	All bazaars, current month	Today's sales (assigned bazaar only)
Active Bazaars	Count of ongoing bazaars	Count of ongoing bazaars	Remaining stock (assigned bazaar)
Total Orders	All orders this month	All orders this month	Orders completed today
Pending Approvals	Count + link to approvals	Count + link to approvals	Not shown

Data Sources:

    Revenue: SUM(sales.total) filtered by date and event_id

    Active Bazaars: COUNT(bazaar_events WHERE status = 'ongoing')

    Orders: COUNT(sales.id) filtered by date

    Pending Approvals: COUNT(approval_requests WHERE status = 'pending')

    Remaining Stock: SUM(event_inventory.allocated_quantity - event_inventory.sold_quantity)

2. Revenue Chart (Middle Row Left)

Visual representation of sales over time.
User	Content
Admin	Line/bar chart: Daily sales for current month across all bazaars
Owner	Same as Admin
Employee	Line/bar chart: Daily sales for assigned bazaar only

Data Source: sales table grouped by DATE(timestamp)
3. Top Selling Products (Middle Row Right)

List of products with highest sales volume.
User	Content
Admin	Top 5 products across all bazaars, showing name, image (optional), units sold
Owner	Same as Admin
Employee	Top 3 products in their assigned bazaar only

Data Source: sales joined with products, grouped by product_id, ordered by SUM(quantity) DESC
4. Active Bazaars Progress (Bottom Left)

Cards for ongoing bazaars showing progress.
User	Content
Admin	Cards for all ongoing bazaars
Owner	Same as Admin
Employee	Card for their assigned bazaar only (if any)

Each card includes:

    Bazaar name

    Company name

    Date range (start - end)

    Today's sales amount

    Stock progress bar: percentage of allocated stock sold

    Days remaining

Data Source:

    bazaar_events with status = 'ongoing'

    event_inventory for allocated vs sold

    sales for today's sales

5. Slow Moving Stock / Low Stock Alert (Bottom Middle)
User	Content	Data Source
Admin	Products with <10% sold of allocated stock across all bazaars. Include suggestion: "Consider discount"	event_inventory grouped by product
Owner	Same as Admin	Same
Employee	Products in assigned bazaar with remaining stock <5 units. Show alert: "Low stock: restock soon"	event_inventory for assigned event

Threshold logic:

    Slow moving: (sold_quantity / allocated_quantity) < 0.10 and allocated > 0

    Low stock: (allocated_quantity - sold_quantity) < 5

6. Recent Orders / Pending Orders (Bottom Right)
User	Content
Admin	Table of last 5 orders across all bazaars: Customer Name, Product, Bazaar, Status
Owner	Same as Admin
Employee	List of orders in assigned bazaar with status = 'Pending' or 'Incomplete'

Data Source: sales table, ordered by timestamp DESC, filtered by role
7. AI Insight Card (Optional - Bottom Below Charts)

Simple rule-based suggestions (placeholder for future AI).
User	Content
Admin	"Products that could benefit from promotion: [names from slow moving stock]"
Owner	Same as Admin
Employee	Not shown
8. Quick Actions (Employee Only)

Buttons for quick navigation:

    Open POS → Navigate to POS screen for assigned bazaar

    View Orders → Navigate to Orders screen

9. SOA Drafts Pending (Owner Only)

List of pending SOAs awaiting owner approval. Each item shows:

    Bazaar name

    Date submitted

    Gross amount

    Net amount after deductions

Data Source: approval_requests where type = 'soa' and status = 'pending'
Dashboard Layout (Mobile/Tablet Landscape)
text

┌─────────────────────────────────────────────────────────────────────────────┐
│  SyncBazaar                                                    🔔  👤     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │ Card 1      │  │ Card 2      │  │ Card 3      │  │ Card 4      │       │
│  │ [Value]     │  │ [Value]     │  │ [Value]     │  │ [Value]     │       │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘       │
│                                                                             │
│  ┌─────────────────────────────────┐  ┌─────────────────────────────────┐  │
│  │ Revenue Chart                   │  │ Top Selling Products            │  │
│  │ [Line/Bar Chart]                │  │ 1. Product A     XX units       │  │
│  │                                 │  │ 2. Product B     XX units       │  │
│  └─────────────────────────────────┘  │ 3. Product C     XX units       │  │
│                                        └─────────────────────────────────┘  │
│                                                                             │
│  ┌─────────────────────────────────┐  ┌─────────────────────────────────┐  │
│  │ Active Bazaars                  │  │ Slow Moving / Low Stock         │  │
│  │ • Bazaar A (Date range)         │  │ • Product X (XX left)           │  │
│  │   Today's sales: ₱X,XXX         │  │   💡 Suggestion                 │  │
│  │   Stock: ████████░░ 78%         │  │ • Product Y (XX left)           │  │
│  │                                 │  │   💡 Suggestion                 │  │
│  └─────────────────────────────────┘  └─────────────────────────────────┘  │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ Recent Orders / Pending Orders                                     │   │
│  │ Name          │ Product      │ Bazaar        │ Status              │   │
│  │ Customer A    │ Product A    │ Bazaar A      │ Completed           │   │
│  │ Customer B    │ Product B    │ Bazaar B      │ Pending             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

Design Specifications
Element	Value
Primary Color	#6C4AB6
Accent Color	#FFC107
Background	#f3f3f4
Surface/Card Background	#fefdfd
Card thin outline color #e8e8e8
Text Primary	#212529
Error (font color)	#DC3545
Good/Great (font color) #45cd34
Border Radius	12px
Font Family	Inter (Google Fonts) with Roboto fallback
Spacing	16px margins, 12px between cards
Data Refresh

    Dashboard refreshes:

        On screen load

        After completing a sale (POS)

        After sync completes

        Pull-to-refresh gesture

    Use FutureBuilder or StreamBuilder with local database queries

Implementation Notes

    Role determination: Store user role after login (Admin/Owner/Employee) and pass via Provider or InheritedWidget.

    Database queries: Create helper methods in database_service.dart for each dashboard component to keep screens clean.

    Charts: Use fl_chart package for revenue chart.

    Progress bars: Use LinearProgressIndicator with value between 0 and 1.

    Placeholders: For slow-moving stock and AI insights, use simple SQL calculations first; AI can be added later.

API Reference (Database Methods)
Method	Returns	Used For
getTotalRevenue(eventId?, dateRange)	double	Overview Card 1
getActiveBazaarsCount()	int	Overview Card 2
getTotalOrders(eventId?, dateRange)	int	Overview Card 3
getPendingApprovalsCount()	int	Overview Card 4
getSalesByDate(eventId?)	Map<DateTime, double>	Revenue Chart
getTopSellingProducts(limit, eventId?)	List<ProductSales>	Top Selling
getActiveBazaars()	List<BazaarProgress>	Active Bazaars Cards
getSlowMovingStock(threshold)	List<ProductSuggestion>	Admin/Owner
getLowStockAlert(eventId, threshold)	List<Product>	Employee
getRecentOrders(limit, eventId?)	List<Sale>	Recent Orders
getPendingSOAs()	List<SOADraft>	Owner Only
Next Steps

    Create dashboard_screen.dart

    Add fl_chart to pubspec.yaml

    Implement role-based visibility using Consumer or Provider.of<UserRole>

    Add pull-to-refresh using RefreshIndicator

    Test with mock data first