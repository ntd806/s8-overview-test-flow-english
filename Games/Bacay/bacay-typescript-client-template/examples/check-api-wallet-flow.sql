-- API wallet flow check template
-- Based on schema:
-- - vinplay.users
-- - vinplay.topup
-- - vinplay.withdraw
--
-- Use this file to verify:
-- 1. account creation result
-- 2. deposit transaction
-- 3. withdraw transaction
-- 4. final user balance
--
-- Update the variables below before running.

SET @username := 'curlv21778173291';
SET @account_id := 6548779;
SET @deposit_tx := 'dep_curlv21778173291';
SET @withdraw_tx := 'wd_curlv21778173291';
SET @from_time := '2026-05-08 00:01:31';
SET @to_time := '2026-05-08 00:02:10';

-- 1. Check account record
SELECT
  u.id,
  u.user_name,
  u.nick_name,
  u.vin,
  u.vin_total,
  u.xu,
  u.xu_total,
  u.create_time,
  u.status
FROM vinplay.users u
WHERE u.id = @account_id
   OR u.user_name = @username
   OR u.nick_name = @username;

-- 2. Check deposit transaction
SELECT
  t.id,
  t.user_id,
  t.user_name,
  t.amount,
  t.transaction_code,
  t.order_no,
  t.channel,
  t.message,
  t.create_time,
  t.status,
  t.type
FROM vinplay.topup t
WHERE t.transaction_code = @deposit_tx
   OR (
        t.user_name = @username
    AND t.create_time BETWEEN @from_time AND @to_time
      )
ORDER BY t.create_time DESC;

-- 3. Check withdraw transaction
SELECT
  w.id,
  w.user_id,
  w.user_name,
  w.amount,
  w.transaction_code,
  w.message,
  w.create_time,
  w.approve_time,
  w.status,
  w.type,
  w.previous_balance,
  w.balance_fluctuation,
  w.updated_time
FROM vinplay.withdraw w
WHERE w.transaction_code = @withdraw_tx
   OR (
        w.user_name = @username
    AND w.create_time BETWEEN @from_time AND @to_time
      )
ORDER BY w.create_time DESC;

-- 4. Compare deposit and withdraw in one result set
SELECT
  'deposit' AS flow_type,
  t.user_name,
  t.transaction_code,
  t.amount,
  t.create_time,
  t.status
FROM vinplay.topup t
WHERE t.transaction_code = @deposit_tx

UNION ALL

SELECT
  'withdraw' AS flow_type,
  w.user_name,
  w.transaction_code,
  w.amount,
  w.create_time,
  w.status
FROM vinplay.withdraw w
WHERE w.transaction_code = @withdraw_tx;

-- 5. Check final balance after the flow
SELECT
  u.id,
  u.user_name,
  u.nick_name,
  u.vin AS current_vin_balance,
  u.vin_total,
  u.create_time,
  u.status
FROM vinplay.users u
WHERE u.id = @account_id
   OR u.user_name = @username
   OR u.nick_name = @username;

-- 6. Summarize total deposit and withdraw in the selected time window
SELECT
  u.id,
  u.user_name,
  u.nick_name,
  u.vin AS current_balance,
  COALESCE(td.total_deposit, 0) AS total_deposit_in_window,
  COALESCE(wd.total_withdraw, 0) AS total_withdraw_in_window,
  COALESCE(td.total_deposit, 0) - COALESCE(wd.total_withdraw, 0) AS net_change
FROM vinplay.users u
LEFT JOIN (
  SELECT
    t.user_name,
    SUM(t.amount) AS total_deposit
  FROM vinplay.topup t
  WHERE t.user_name = @username
    AND t.create_time BETWEEN @from_time AND @to_time
  GROUP BY t.user_name
) td
  ON td.user_name = u.user_name
LEFT JOIN (
  SELECT
    w.user_name,
    SUM(w.amount) AS total_withdraw
  FROM vinplay.withdraw w
  WHERE w.user_name = @username
    AND w.create_time BETWEEN @from_time AND @to_time
  GROUP BY w.user_name
) wd
  ON wd.user_name = u.user_name
WHERE u.id = @account_id
   OR u.user_name = @username
   OR u.nick_name = @username;
