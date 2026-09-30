/*
    Script      : ErpDb_Reference_WithClassificationTree.sql
    Database    : ErpDb  (SQL Server 2014, compatibility level 120)
    Purpose     : Return every field of a Reference (by referId) together with its
                  complete classification tree, walking dbo.ReferClassification
                  upward from the leaf (Reference.referClassification) to the root
                  (referClassFather IS NULL).

    Result sets :
      1) One row  : all dbo.Reference columns + measurement unit descriptions
                    + full classification path + one column pair (Id/Name) per level.
      2) N rows   : the classification tree detail, one row per level (root = level 1).

    Notes       :
      - Read-only (SELECT only). No DDL/DML.
      - SQL Server 2014: STRING_AGG is not available, so the path is built inside
        the recursive CTE.
      - The flattened level columns cover up to 5 levels (current max depth in data).
        classFullPath and result set 2 are not limited by depth.
      - A reference with no classification still returns its row in result set 1
        (classification columns NULL) and an empty result set 2.
      - MAXRECURSION 100 protects against an accidental cycle in referClassFather.
*/

SET NOCOUNT ON;

DECLARE @referId bigint = 96195;   -- <<< reference to query

/* ---------------------------------------------------------------------------
   Result set 1: reference + flattened classification tree
--------------------------------------------------------------------------- */
WITH ClassTree AS
(
    -- Anchor: the leaf classification assigned to the reference
    SELECT  rc.referClassId,
            rc.referClassFather,
            rc.referClassName,
            rc.referClassDescription,
            rc.referClassGroupFactory,
            0                                         AS depthFromLeaf,
            CAST(rc.referClassName AS nvarchar(4000)) AS classPath
    FROM    dbo.Reference           AS r
    INNER JOIN dbo.ReferClassification AS rc
            ON rc.referClassId = r.referClassification
    WHERE   r.referId = @referId

    UNION ALL

    -- Recursive: climb to the parent, prepending its name to the path
    SELECT  p.referClassId,
            p.referClassFather,
            p.referClassName,
            p.referClassDescription,
            p.referClassGroupFactory,
            ct.depthFromLeaf + 1,
            CAST(p.referClassName + N' > ' + ct.classPath AS nvarchar(4000))
    FROM    dbo.ReferClassification AS p
    INNER JOIN ClassTree AS ct
            ON p.referClassId = ct.referClassFather
),
Leveled AS
(
    SELECT  ct.*,
            MAX(ct.depthFromLeaf) OVER () - ct.depthFromLeaf + 1 AS classLevel   -- root = 1
    FROM    ClassTree AS ct
),
TreeFlat AS
(
    -- Aggregate without GROUP BY: always returns exactly one row (NULLs if no tree)
    SELECT  MAX(CASE WHEN referClassFather IS NULL THEN classPath END)      AS classFullPath,
            MAX(classLevel)                                                 AS classDepth,
            MAX(CASE WHEN classLevel = 1 THEN referClassId   END)           AS classL1Id,
            MAX(CASE WHEN classLevel = 1 THEN referClassName END)           AS classL1Name,
            MAX(CASE WHEN classLevel = 2 THEN referClassId   END)           AS classL2Id,
            MAX(CASE WHEN classLevel = 2 THEN referClassName END)           AS classL2Name,
            MAX(CASE WHEN classLevel = 3 THEN referClassId   END)           AS classL3Id,
            MAX(CASE WHEN classLevel = 3 THEN referClassName END)           AS classL3Name,
            MAX(CASE WHEN classLevel = 4 THEN referClassId   END)           AS classL4Id,
            MAX(CASE WHEN classLevel = 4 THEN referClassName END)           AS classL4Name,
            MAX(CASE WHEN classLevel = 5 THEN referClassId   END)           AS classL5Id,
            MAX(CASE WHEN classLevel = 5 THEN referClassName END)           AS classL5Name
    FROM    Leveled
)
SELECT  -- dbo.Reference: all fields
        r.referId,
        r.referCod,
        r.referCod2,
        r.referName,
        r.referDescription,
        r.referClassification,
        r.referMeasuUnit,
        r.referAlterMeasuUnit,
        r.referConveFactor,
        r.referActive,
        r.referStandCost,
        r.referIva,
        r.referIca,
        r.referWithholding,
        -- Measurement units
        mu.measuUnitCode                AS measuUnitCode,
        mu.measuUnitName                AS measuUnitName,
        amu.measuUnitCode               AS alterMeasuUnitCode,
        amu.measuUnitName               AS alterMeasuUnitName,
        -- Classification tree
        tf.classFullPath,
        tf.classDepth,
        tf.classL1Id, tf.classL1Name,
        tf.classL2Id, tf.classL2Name,
        tf.classL3Id, tf.classL3Name,
        tf.classL4Id, tf.classL4Name,
        tf.classL5Id, tf.classL5Name
FROM    dbo.Reference  AS r
LEFT JOIN dbo.MeasurUnit AS mu
        ON mu.measuUnitId  = r.referMeasuUnit
LEFT JOIN dbo.MeasurUnit AS amu
        ON amu.measuUnitId = r.referAlterMeasuUnit
CROSS JOIN TreeFlat AS tf
WHERE   r.referId = @referId
OPTION (MAXRECURSION 100);

/* ---------------------------------------------------------------------------
   Result set 2: classification tree detail (one row per level, root first)
--------------------------------------------------------------------------- */
WITH ClassTree AS
(
    SELECT  rc.referClassId,
            rc.referClassFather,
            rc.referClassName,
            rc.referClassDescription,
            rc.referClassGroupFactory,
            0 AS depthFromLeaf
    FROM    dbo.Reference           AS r
    INNER JOIN dbo.ReferClassification AS rc
            ON rc.referClassId = r.referClassification
    WHERE   r.referId = @referId

    UNION ALL

    SELECT  p.referClassId,
            p.referClassFather,
            p.referClassName,
            p.referClassDescription,
            p.referClassGroupFactory,
            ct.depthFromLeaf + 1
    FROM    dbo.ReferClassification AS p
    INNER JOIN ClassTree AS ct
            ON p.referClassId = ct.referClassFather
)
SELECT  MAX(ct.depthFromLeaf) OVER () - ct.depthFromLeaf + 1 AS classLevel,
        ct.referClassId,
        ct.referClassFather,
        ct.referClassName,
        ct.referClassDescription,
        ct.referClassGroupFactory,
        CASE WHEN ct.depthFromLeaf = 0 THEN 1 ELSE 0 END      AS isReferenceLeaf
FROM    ClassTree AS ct
ORDER BY classLevel
OPTION (MAXRECURSION 100);
GO


/* ===========================================================================
   TEST BLOCK  (BEGIN TRAN ... ROLLBACK: nothing is persisted)
   Builds a throw-away 3-level tree + reference inside the transaction and
   checks that the query returns the expected path.
=========================================================================== */
/*
SET NOCOUNT ON;
BEGIN TRAN;

    DECLARE @unit   bigint = (SELECT TOP (1) measuUnitId FROM dbo.MeasurUnit ORDER BY measuUnitId);
    DECLARE @root   bigint, @mid bigint, @leaf bigint, @ref bigint;

    -- referClassId and referId are IDENTITY columns.
    INSERT dbo.ReferClassification (referClassFather, referClassName) VALUES (NULL,  N'ZZ_TEST_ROOT');
    SET @root = SCOPE_IDENTITY();
    INSERT dbo.ReferClassification (referClassFather, referClassName) VALUES (@root, N'ZZ_TEST_MID');
    SET @mid  = SCOPE_IDENTITY();
    INSERT dbo.ReferClassification (referClassFather, referClassName) VALUES (@mid,  N'ZZ_TEST_LEAF');
    SET @leaf = SCOPE_IDENTITY();

    INSERT dbo.Reference (referCod, referName, referClassification, referMeasuUnit,
                          referConveFactor, referActive, referStandCost, referIva, referIca, referWithholding)
    VALUES (N'ZZ_TEST_REF', N'ZZ test reference', @leaf, @unit, 1, 1, 0, 0, 0, 0);
    SET @ref = SCOPE_IDENTITY();

    -- Expected: classFullPath = 'ZZ_TEST_ROOT > ZZ_TEST_MID > ZZ_TEST_LEAF', classDepth = 3
    WITH ClassTree AS
    (
        SELECT rc.referClassId, rc.referClassFather, rc.referClassName, 0 AS depthFromLeaf,
               CAST(rc.referClassName AS nvarchar(4000)) AS classPath
        FROM dbo.Reference AS r
        INNER JOIN dbo.ReferClassification AS rc ON rc.referClassId = r.referClassification
        WHERE r.referId = @ref
        UNION ALL
        SELECT p.referClassId, p.referClassFather, p.referClassName, ct.depthFromLeaf + 1,
               CAST(p.referClassName + N' > ' + ct.classPath AS nvarchar(4000))
        FROM dbo.ReferClassification AS p
        INNER JOIN ClassTree AS ct ON p.referClassId = ct.referClassFather
    )
    SELECT  CASE WHEN MAX(CASE WHEN referClassFather IS NULL THEN classPath END)
                      = N'ZZ_TEST_ROOT > ZZ_TEST_MID > ZZ_TEST_LEAF'
                  AND MAX(depthFromLeaf) + 1 = 3
                 THEN 'PASS' ELSE 'FAIL' END AS testResult,
            MAX(CASE WHEN referClassFather IS NULL THEN classPath END) AS classFullPath,
            MAX(depthFromLeaf) + 1 AS classDepth
    FROM    ClassTree
    OPTION (MAXRECURSION 100);

ROLLBACK;
*/
