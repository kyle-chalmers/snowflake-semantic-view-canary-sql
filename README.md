# Snowflake Semantic View Canary

A Snowflake Semantic View can run clean and still give the wrong number. This project keeps one
correct over time with two checks built from native Snowflake features, plus an AI coding agent
that reads but never writes:

1. **A review** of the view's definition (its DDL) that catches a wrong mapping on the day the
   view is built.
2. **A canary**: a scheduled Task asks the view for numbers you have already validated, a log
   table keeps every answer, and an Alert emails you when one of them moves or a check never
   lands. It works on Snowflake Standard edition.

## What you need

- A Snowflake account (Standard edition is enough) with the `SNOWFLAKE_SAMPLE_DATA` share
  ([included by default in newer accounts](https://docs.snowflake.com/en/user-guide/sample-data-using))
  and a database named `ANALYTICS` (`sql/00` creates it if missing).
- The [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index) with two
  connections: one for a **read-only role** (used by the AI agent) and one for the role that
  **owns** the semantic view (used by you to run changes).
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview), or another AI coding
  agent, to read the definition and write SQL to files.
- A role that can create Tasks and Alerts, and an account admin to create one email notification
  integration.

## Setup

1. **Create the starting view.** As the owning role, run
   [`sql/00_create_starting_view.sql`](./sql/00_create_starting_view.sql). It builds
   `ANALYTICS.SEMANTIC_DEMO.TPCH_SEMANTIC_VIEW` over the TPC-H sample data.
2. **Give the agent read-only access.** As an account admin, adapt and run:
   ```sql
   CREATE ROLE IF NOT EXISTS SEMANTIC_REVIEWER;
   GRANT USAGE ON DATABASE ANALYTICS TO ROLE SEMANTIC_REVIEWER;
   GRANT USAGE ON SCHEMA ANALYTICS.SEMANTIC_DEMO TO ROLE SEMANTIC_REVIEWER;
   GRANT SELECT, REFERENCES ON SEMANTIC VIEW ANALYTICS.SEMANTIC_DEMO.TPCH_SEMANTIC_VIEW TO ROLE SEMANTIC_REVIEWER;
   GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE_SAMPLE_DATA TO ROLE SEMANTIC_REVIEWER;
   GRANT USAGE ON WAREHOUSE <your_warehouse> TO ROLE SEMANTIC_REVIEWER;
   GRANT ROLE SEMANTIC_REVIEWER TO USER <agent_user>;
   ```
   Give the agent its own user, so your own admin roles never reach its session.
3. **Point the agent at that connection.** Start the agent with the read-only connection as the
   Snowflake CLI default, for example `SNOWFLAKE_DEFAULT_CONNECTION_NAME=<read_only_connection> claude`.
4. **Create the email integration** (account admin, once):
   ```sql
   CREATE NOTIFICATION INTEGRATION CANARY_EMAIL
     TYPE = EMAIL
     ENABLED = TRUE
     ALLOWED_RECIPIENTS = ('<a verified email of a user in this account>');
   ```
   Recipients must be verified users in the same account.

## How the canary works

- Pick a **closed period** whose totals should never move on their own, such as last quarter
  after the books close.
- Freeze **one validated number per metric**. A canary only guards the numbers you chose.
- A **Task** asks the view for those numbers on a schedule and writes one row per metric to a log
  table. An **Alert**, scheduled after the Task, fires when the latest check is incomplete or any
  number moved, so a failed run alerts too.
- Tasks and Alerts are **created suspended**: resume both, or nothing ever runs.
- When you change a definition on purpose, or a closed period is legitimately restated, update
  the expected values. That is part of owning the view.

## The files, in run order

| File | What it does | Run as |
|---|---|---|
| [`sql/00_create_starting_view.sql`](./sql/00_create_starting_view.sql) | The starting semantic view over the TPC-H sample data | the owning role |
| [`sql/01_copy_tpch.sql`](./sql/01_copy_tpch.sql) | Copies the three TPC-H tables into a schema you own, so the view stops depending on the sample share | the owning role |
| [`sql/02_fix_semantic_view.sql`](./sql/02_fix_semantic_view.sql) | Repoints the view at the copy and fixes the revenue metrics the review found | the owning role |
| [`sql/03_canary.sql`](./sql/03_canary.sql) | The canary: log table, a view over `SEMANTIC_VIEW()`, the Task and the Alert. Replace `<owner email>` with your verified address first | a role that can create Tasks and Alerts |
| [`sql/04_pause_canary.sql`](./sql/04_pause_canary.sql) | Pauses the canary without losing its history | the canary's owning role |

## Build a canary for your own semantic view

The canary here watches the TPC-H demo view. To build one for your own view, there is a free agent
skill for Claude Code and Codex: it reads your view's definition, asks for the numbers you have
validated, checks the view agrees, and writes the setup, canary and test SQL for you to review and
run. Get it at
[kclabs.ai/resources/semantic-view-canary](https://kclabs.ai/resources/semantic-view-canary?utm_source=github&utm_medium=readme&utm_campaign=43a-semantic-layer-snowflake).

## References

- [Semantic View Autopilot](https://docs.snowflake.com/en/user-guide/views-semantic/autopilot)
- [CREATE SEMANTIC VIEW](https://docs.snowflake.com/en/sql-reference/sql/create-semantic-view)
- [Semantic view modeling best practices](https://docs.snowflake.com/en/user-guide/views-semantic/best-practices-modeling)
- [Cortex Agent evaluations](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-evaluations)
- [Introduction to tasks](https://docs.snowflake.com/en/user-guide/tasks-intro)
- [EXECUTE TASK](https://docs.snowflake.com/en/sql-reference/sql/execute-task)
- [Alerts](https://docs.snowflake.com/en/user-guide/alerts)
- [Email notification integrations](https://docs.snowflake.com/en/sql-reference/sql/create-notification-integration-email)
- [Data quality monitoring](https://docs.snowflake.com/en/user-guide/data-quality-intro)

## Author

Built by Kyle Chalmers. More on AI for data professionals at
[youtube.com/@kylechalmersdataai](https://www.youtube.com/@kylechalmersdataai).
