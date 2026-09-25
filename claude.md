# SQL Server project rules
- Target: SQL Server, all no system databases of the same instance.
- Never execute DDL or DML. Write scripts to the /sql folder for human review.
- Triggers: set-based on inserted/deleted, SET NOCOUNT ON, handle multi-row
  updates, compare old vs new values with NULL handling.
- Use existing trigger dbo.trg_PEDIDOS_AfterInsert_OrderTables as the style reference.
- Every script must include a test block using BEGIN TRAN ... ROLLBACK.