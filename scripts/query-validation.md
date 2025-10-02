# Query Validation Documentation

## SQL Queries Implemented

### 1. Top 10 Orders by Order Total
**Query Name**: `top_orders_by_total`
**Purpose**: Shows the highest value orders with customer information

```sql
SELECT 
    o.order_id,
    o.customer_id,
    c.customer_name,
    c.email,
    o.order_date,
    o.order_total,
    o.status
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
ORDER BY o.order_total DESC
LIMIT 10;
```

**Expected Results**:
- 10 rows returned
- Highest order: ORD-061 ($1,245.50)
- All orders should have corresponding customer data
- Results ordered by order_total descending

### 2. Returns by Customer (LEFT JOIN)
**Query Name**: `returns_by_customer`
**Purpose**: Shows all customers and their return information (including customers with no returns)

```sql
SELECT 
    c.customer_id,
    c.customer_name,
    c.email,
    c.registration_date,
    r.return_id,
    r.order_id,
    r.return_date,
    r.return_reason,
    r.refund_amount,
    CASE 
        WHEN r.return_id IS NOT NULL THEN 'Has Returns'
        ELSE 'No Returns'
    END AS return_status
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
LEFT JOIN returns r ON o.order_id = r.order_id
ORDER BY c.customer_name, r.return_date DESC;
```

**Expected Results**:
- All 50 customers appear (some with NULL return data)
- 30 customers will have return information
- 20 customers will show "No Returns"
- Multiple rows per customer possible (one per return)

### 3. Orders That Were Returned (INNER JOIN)
**Query Name**: `orders_that_were_returned`  
**Purpose**: Shows only orders that have corresponding returns with financial analysis

```sql
SELECT 
    o.order_id,
    o.customer_id,
    c.customer_name,
    o.order_date,
    o.order_total,
    o.status AS order_status,
    r.return_id,
    r.return_date,
    r.return_reason,
    r.refund_amount,
    (o.order_total - r.refund_amount) AS net_revenue,
    ROUND((r.refund_amount / o.order_total) * 100, 2) AS return_percentage
FROM orders o
INNER JOIN returns r ON o.order_id = r.order_id
INNER JOIN customers c ON o.customer_id = c.customer_id
ORDER BY o.order_date DESC, r.return_date DESC;
```

**Expected Results**:
- Exactly 30 rows (one per return)
- Only orders with returns appear
- All return reasons: defective_product, wrong_size, not_as_described, customer_changed_mind, wrong_color
- Net revenue and return percentage calculated

## Data Relationships

### Sample Data Summary
- **Customers**: 50 records (CUST-001 to CUST-050)
- **Orders**: 200 records (ORD-001 to ORD-200)
- **Returns**: 30 records (RET-001 to RET-030)

### Key Relationships
- Each order belongs to exactly one customer
- Each return belongs to exactly one order
- Not all customers have orders
- Not all orders have returns
- Some customers have multiple orders
- Some orders may have multiple returns (in real scenarios)

### Foreign Key Relationships
```
customers.customer_id -> orders.customer_id
orders.order_id -> returns.order_id
```

## Testing Commands

### Manual Query Testing
```bash
# Run validation script
./scripts/validate-queries.sh

# Individual query testing
aws athena start-query-execution \
  --query-string "SELECT COUNT(*) FROM customers;" \
  --work-group "lean_demo_wg" \
  --result-configuration OutputLocation="s3://lean-analytics-699027953523-us-west-2/athena-results/" \
  --region "us-west-2"
```

### Expected Query Performance
- Simple COUNT queries: < 5 seconds
- JOIN queries with small dataset: < 10 seconds  
- Complex aggregations: < 15 seconds

### Troubleshooting
1. **Tables not found**: Run Glue crawler first
2. **Permission denied**: Check IAM roles and policies
3. **Syntax errors**: Verify Glue table schemas match CSV headers
4. **No results**: Ensure data was uploaded to S3 datasets/ folder