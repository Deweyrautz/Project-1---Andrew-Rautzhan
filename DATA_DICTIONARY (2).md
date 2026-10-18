# Ridgeline Outfitters — data dictionary

**MGIS 355 · Fall 2026**

An extract from Ridgeline's **operational (OLTP) database** — the system the registers and
the website write to as business happens. It is not a warehouse. It is normalized, it keeps
only the current state of things, and it was designed for recording transactions rather
than for answering questions.

**Coverage.** Orders from Q3 2025 in full (Jul 1 – Sep 30) and from Jul 1 – Aug 31, 2026.
The 2026 window ends on August 31 because that is the comparison window the extract was
requested for, not because the business stopped selling — a scoping decision someone else
made and you inherit.

**As of.** The extract was pulled in mid-October 2026. Orders are therefore frozen to the
windows above, but `returns` is current as of the pull: a return recorded in October 2026
against an August 2026 sale is in this file. Returns always lag the sale that produced
them, and the lag does not respect period boundaries.

> **Two warnings, before you compute anything.**
>
> 1. `order_ts` and every other timestamp are stored in **UTC**. The stores run on Eastern
>    time. In Q3 that is a four-hour difference, so a sale rung up at 11:40pm on
>    September 30 is stored with an October 1 date.
> 2. A store can be attached to an order in **three different columns**. Which one you use
>    is a definition, not a detail. See `orders` below.

---

## stores — 14 rows

One row per physical store.

| Column | Type | Notes |
|---|---|---|
| `store_id` | int | Primary key |
| `store_code` | text | Three letters, e.g. `BUR` |
| `store_name` | text | |
| `city`, `state_code` | text | |
| `district_id` | int | Stores group into three districts |
| `opened_date` | date | |
| `selling_sqft` | int | Floor area |
| `is_active` | bool | All true in this extract |

## products — 112 rows

One row per SKU.

| Column | Type | Notes |
|---|---|---|
| `product_id` | int | Primary key |
| `sku` | text | |
| `product_name` | text | |
| `department` | text | `Footwear`, `Apparel`, `Hardgoods`, `Camp` — the coarse level |
| `category` | text | e.g. `Trail Running` — the fine level. **Two levels of hierarchy; be clear which you mean.** |
| `brand` | text | |
| `unit_cost` | decimal | **Current** cost, not the cost as of any past sale. Margin computed from this re-prices history. |
| `list_price` | decimal | Current list. What was actually charged is on the order line. |

## customers — 4,200 rows

One row per known customer. Cash walk-ins never appear here.

| Column | Type | Notes |
|---|---|---|
| `customer_id` | int | Primary key |
| `email` | text | Synthetic |
| `created_at` | timestamp | |
| `home_store_id` | int | → `stores` |
| `basecamp_status` | text | `active` / `lapsed` / `never`. **Overwritten in place — there is no history.** Someone who joined last week reads as a member for every past order. |
| `basecamp_since` | date | Blank for `never` |

## orders — ~52,400 rows

One row per checkout event, whatever channel it came through.

| Column | Type | Notes |
|---|---|---|
| `order_id` | int | Primary key |
| `customer_id` | int | → `customers`. **Blank for cash walk-ins** — roughly a third of all orders. Any customer-level analysis silently drops them. |
| `order_ts` | timestamp | **UTC.** When the order was placed. |
| `channel` | text | `store` or `web` |
| `selling_store_id` | int | → `stores`. The store that rang the sale. **Blank for every web order.** |
| `fulfillment` | text | `carryout` (bought and taken from the store), `bopis` (bought online, collected in a store), `ship` (bought online, mailed) |
| `pickup_store_id` | int | → `stores`. Populated **only** for `bopis`. |
| `pickup_ts` | timestamp | When it was actually collected — days after `order_ts`. Blank unless `bopis`. |
| `ship_to_postal` | text | Blank unless `ship`. Reads as a number unless you force it to text. |
| `order_status` | text | `completed` or `cancelled`. **Order-level.** It cannot express a partial return. |
| `discount_amount` | decimal | **Order-level** promotion. Separate from, and never reconciled with, the line-level discount. |
| `shipping_amount` | decimal | Charged to the customer. Whether it is revenue is a policy question. |
| `tax_amount` | decimal | Order-level. |

**The attribution problem.** Which store gets credit for an order?

| Fulfillment | `selling_store_id` | `pickup_store_id` |
|---|---|---|
| `carryout` | set | blank |
| `bopis` | **blank** | set |
| `ship` | blank | blank |

BOPIS grew from about 6% of orders in 2025 to about 19% in 2026. Whichever rule you pick
now moves three times as much money as it did last year.

## order_items — ~130,600 rows

One row per product line within an order. **This is where the money is.** Averages about
2.5 lines per order, so joining orders to lines multiplies your order rows by 2.5 — and
with them every order-level column.

| Column | Type | Notes |
|---|---|---|
| `order_item_id` | int | Primary key |
| `order_id` | int | → `orders` |
| `product_id` | int | → `products` |
| `quantity` | int | |
| `unit_price` | decimal | Price actually charged per unit, before the line discount |
| `line_discount` | decimal | **Line-level** markdown, for the whole line. Not the same thing as `orders.discount_amount`. |

Line revenue is `quantity * unit_price - line_discount`.

## returns — ~7,100 rows

One row per returned **line**.

| Column | Type | Notes |
|---|---|---|
| `return_id` | int | Primary key |
| `order_item_id` | int | → `order_items`. **Keyed to the line, never to the order.** One line of a five-line order can come back alone. |
| `return_ts` | timestamp | **May fall in a later quarter than the sale.** |
| `return_store_id` | int | → `stores`. Blank when the item was mailed back — about a fifth of returns. |
| `quantity` | int | |
| `refund_amount` | decimal | |
| `reason_code` | text | `size` / `defect` / `changed_mind`, often blank |

## store_traffic — ~2,200 rows

One row per store per day. A door counter.

| Column | Type | Notes |
|---|---|---|
| `store_id` | int | → `stores` — part of the key |
| `business_date` | date | Part of the key. **Local date, not UTC.** |
| `visitor_count` | int | |

**No order key exists.** Traffic and orders cannot be joined at the order level. To compute
a conversion rate you must first roll orders up to store-day, which is a grain decision.

## store_targets — 28 rows

One row per store per fiscal quarter.

| Column | Type | Notes |
|---|---|---|
| `store_id` | int | → `stores` |
| `fiscal_year`, `fiscal_quarter` | int | |
| `revenue_target` | decimal | **One number for thirteen weeks**, set each June. Comparing a single week against it requires inventing an allocation rule. |

---

## Known quirks, collected

These are all real properties of the data. None of them is a mistake in the extract.

1. Timestamps are UTC; stores are Eastern. Quarter and day boundaries move.
2. A store can be attached through `selling_store_id`, `pickup_store_id`, or `returns.return_store_id`.
3. `orders → order_items` is one-to-many. Order-level amounts fan out on the join.
4. Returns are line-level; `order_status` is order-level. They cannot agree.
5. Discounts exist at two grains and are never reconciled.
6. `customer_id` is blank for cash walk-ins.
7. `basecamp_status` and `unit_cost` hold current values only — no history.
8. `department` and `category` are two levels of the same hierarchy.
9. `store_traffic` and `store_targets` are at grains that do not match orders.
10. The 2026 order window stops at August 31. Comparing it against a full 2025 quarter overstates the decline by roughly a third.
11. Returns run later than the orders they belong to, and later than the 2026 order window. Any period total that nets out returns is still moving after the period closes.
