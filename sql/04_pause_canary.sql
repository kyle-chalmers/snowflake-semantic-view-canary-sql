-- Pause the canary without dropping anything: the Task stops logging and the Alert stops emailing,
-- and CANARY_LOG keeps its history. Run as the role that owns both objects.
-- Suspend the Alert first so a morning without a Task run cannot trigger a "check never landed" email.
-- To restart, run the two ALTER ... RESUME statements at the end of 03_canary.sql.

ALTER ALERT ANALYTICS.CANARY.CANARY_ALERT SUSPEND;
ALTER TASK ANALYTICS.CANARY.CANARY_CHECK SUSPEND;

-- Check: both should show state = 'suspended'.
SHOW ALERTS LIKE 'CANARY_ALERT' IN SCHEMA ANALYTICS.CANARY;
SHOW TASKS LIKE 'CANARY_CHECK' IN SCHEMA ANALYTICS.CANARY;
