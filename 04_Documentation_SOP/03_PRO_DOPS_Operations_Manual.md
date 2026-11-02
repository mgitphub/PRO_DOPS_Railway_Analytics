# PRO-DOPS: Standard Operating Procedures & Dashboard Architecture
Location: Dalli Rajhara, Balod District, Chhattisgarh

## 1. Power BI Layout Specification
### Page 1: 24x7 Real-Time Operations & Yield Management
- Top Strip KPI Cards:
  * Net Daily Operating Profit (INR Currency, Green font)
  * Total Base Fare Handled
  * Peak Tatkal Margin Ratio (8, 10, 11 AM slots)
  * Refund Due (PT Quota)
- Visual 1 (Clustered Column Chart):
  * X-axis: booking_slot_hour
  * Y-axis: Net Daily Operating Profit
- Visual 2 (Donut Chart):
  * Legend: Dim_IRCTC_Accounts[account_type]
  * Values: Count of booking_id
- Visual 3 (Table Visual with Data Alerts):
  * Columns: Token_ID, PNR, Customer Name, Train, Quota, Advance, Refund, Current Status
  * Rule: Highlight Red if Tatkal Waiting > 5

### Page 2: Multi-Source Telemetry & WL Velocity
- Delay Distribution (Line Chart): NTES vs WhereIsMyTrain vs IndianRailInfo delays.
- Chart Vacancy Matrix: Train Number x Class displaying vacant berths after chart prep.
- GNWL Route Optimizer: Initial WL vs Final CNF outcome across SECR boarding hubs.

## 2. Frontline Operational Workflow
1. Intake & Advance: Record customer name, target train, and maximum advance in Excel. Token generated on FIFO order.
2. Opening Time Execution:
   - 08:00 AM: AC Tatkal -> Customer Account Pool (20% Desk Fee)
   - 10:00 AM: Non-AC Tatkal -> Customer Account Pool (20% Desk Fee)
   - 11:00 AM: General & Special -> Customer Account Pool (20% Desk Fee)
   - All Other Times: Agent Master Account (10% Desk Fee)
3. Dynamic Refund: PT bookings evaluated post-allotment. Any unspent advance refunded immediately.
4. Telemetry Guidance: Transition high-risk TQWL tickets to GNWL boarding at Durg/Raipur.
