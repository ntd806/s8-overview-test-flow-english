-- Bacay player history check template
-- Source schema:
-- - vinplay.users
-- - vinplay.freeze_money
-- - vinplay.log_game_round
-- - vinplay.log_game_result
--
-- How to use:
-- 1. Update @nick, @from_time, @to_time
-- 2. Run each query block in order
-- 3. If needed, add AND fm.game_name = 'Bacay' after you confirm the real game_name value

-- File này đã có sẵn:

-- biến @nick
-- biến @from_time, @to_time
-- query tìm user
-- query tìm freeze_money
-- query xem log_game_round
-- query xem log_game_result
-- query join để đối chiếu theo session_id, room_id, thời gian

SET @nick := 'play_7481926';
SET @from_time := '2026-05-07 15:45:00';
SET @to_time := '2026-05-07 16:14:56';

-- 1. Find the real user record
SELECT
  u.id,
  u.user_name,
  u.nick_name,
  u.vin,
  u.vin_total,
  u.create_time
FROM vinplay.users u
WHERE u.nick_name = @nick
   OR u.user_name = @nick;

-- 2. Check recent freeze_money sessions for this player
SELECT
  fm.id,
  fm.session_id,
  fm.user_id,
  fm.nick_name,
  fm.game_name,
  fm.room_id,
  fm.money,
  fm.money_type,
  fm.status,
  fm.create_time,
  fm.update_time
FROM vinplay.freeze_money fm
WHERE fm.nick_name = @nick
  AND fm.create_time BETWEEN @from_time AND @to_time
ORDER BY fm.create_time DESC;

-- 3. List available game_name values for this player
SELECT DISTINCT
  fm.game_name
FROM vinplay.freeze_money fm
WHERE fm.nick_name = @nick
ORDER BY fm.game_name;

-- 4. Check raw round logs
SELECT
  lgr.id,
  lgr.user_name,
  lgr.pot,
  lgr.money,
  lgr.pot_result,
  lgr.fee,
  lgr.total_money,
  lgr.room_id,
  lgr.game_id,
  lgr.create_date
FROM vinplay.log_game_round lgr
WHERE lgr.user_name COLLATE utf8mb3_unicode_ci = @nick
  AND lgr.create_date BETWEEN @from_time AND @to_time
ORDER BY lgr.create_date ASC, lgr.id ASC;

-- 5. Check aggregated game result logs
SELECT
  lgrs.id,
  lgrs.user_name,
  lgrs.total_received,
  lgrs.total_bet,
  lgrs.total_win,
  lgrs.total_lose,
  lgrs.profit,
  lgrs.total_fee,
  lgrs.room_id,
  lgrs.create_date
FROM vinplay.log_game_result lgrs
WHERE lgrs.user_name COLLATE utf8mb3_unicode_ci = @nick
  AND lgrs.create_date BETWEEN @from_time AND @to_time
ORDER BY lgrs.create_date DESC, lgrs.id DESC;

-- 6. Join session info with round logs by nickname + room + nearby time
SELECT
  fm.session_id,
  fm.user_id,
  fm.nick_name,
  fm.game_name,
  fm.room_id AS freeze_room_id,
  fm.money AS freeze_money,
  fm.money_type,
  fm.status AS freeze_status,
  fm.create_time AS freeze_time,
  lgr.id AS round_log_id,
  lgr.pot,
  lgr.money AS round_money,
  lgr.pot_result,
  lgr.fee,
  lgr.total_money,
  lgr.room_id,
  lgr.game_id,
  lgr.create_date AS round_time
FROM vinplay.freeze_money fm
LEFT JOIN vinplay.log_game_round lgr
  ON lgr.user_name COLLATE utf8mb3_unicode_ci = fm.nick_name
 AND CAST(fm.room_id AS SIGNED) = lgr.room_id
 AND lgr.create_date BETWEEN fm.create_time - INTERVAL 5 MINUTE
                         AND fm.create_time + INTERVAL 30 MINUTE
WHERE fm.nick_name = @nick
  AND fm.create_time BETWEEN @from_time AND @to_time
ORDER BY fm.create_time DESC, lgr.create_date ASC;

-- 7. Join session info with result logs by nickname + room + nearby time
SELECT
  fm.session_id,
  fm.user_id,
  fm.nick_name,
  fm.game_name,
  fm.room_id AS freeze_room_id,
  fm.money AS freeze_money,
  fm.money_type,
  fm.status AS freeze_status,
  fm.create_time AS freeze_time,
  r.id AS result_id,
  r.total_received,
  r.total_bet,
  r.total_win,
  r.total_lose,
  r.profit,
  r.total_fee,
  r.room_id,
  r.create_date AS result_time
FROM vinplay.freeze_money fm
LEFT JOIN vinplay.log_game_result r
  ON r.user_name COLLATE utf8mb3_unicode_ci = fm.nick_name
 AND CAST(fm.room_id AS SIGNED) = r.room_id
 AND r.create_date BETWEEN fm.create_time - INTERVAL 5 MINUTE
                       AND fm.create_time + INTERVAL 30 MINUTE
WHERE fm.nick_name = @nick
  AND fm.create_time BETWEEN @from_time AND @to_time
ORDER BY fm.create_time DESC, r.create_date DESC;

-- 8. Summary per detected play session
SELECT
  fm.nick_name,
  fm.session_id,
  fm.user_id,
  fm.game_name,
  fm.room_id,
  fm.money,
  fm.money_type,
  fm.status,
  fm.create_time,
  COUNT(DISTINCT lgr.id) AS round_count,
  COUNT(DISTINCT r.id) AS result_count,
  MIN(lgr.create_date) AS first_round_time,
  MAX(lgr.create_date) AS last_round_time,
  MAX(r.create_date) AS last_result_time
FROM vinplay.freeze_money fm
LEFT JOIN vinplay.log_game_round lgr
  ON lgr.user_name COLLATE utf8mb3_unicode_ci = fm.nick_name
 AND CAST(fm.room_id AS SIGNED) = lgr.room_id
 AND lgr.create_date BETWEEN fm.create_time - INTERVAL 5 MINUTE
                         AND fm.create_time + INTERVAL 30 MINUTE
LEFT JOIN vinplay.log_game_result r
  ON r.user_name COLLATE utf8mb3_unicode_ci = fm.nick_name
 AND CAST(fm.room_id AS SIGNED) = r.room_id
 AND r.create_date BETWEEN fm.create_time - INTERVAL 5 MINUTE
                       AND fm.create_time + INTERVAL 30 MINUTE
WHERE fm.nick_name = @nick
  AND fm.create_time BETWEEN @from_time AND @to_time
GROUP BY
  fm.nick_name,
  fm.session_id,
  fm.user_id,
  fm.game_name,
  fm.room_id,
  fm.money,
  fm.money_type,
  fm.status,
  fm.create_time
ORDER BY fm.create_time DESC;
