-- ============================================================================
-- 授课讲义管理系统 - 增量更新 SQL（CREATE TABLE）V3.1
-- ----------------------------------------------------------------------------
-- 变更内容：
--   1. 新建 jygl_approver_folder（审批人授权账本）
--
-- 背景：审批授权撤旧原实现 revokeAllCollegePerms 遍历【全部 level=4】课程目录逐个撤，
--       课程目录多（上百）时每次进审批页都要发上百次 DeleteFolderPermission → 慢。
--       改为按人记账：撤旧只撤该人历史授过、且非当前课的 L4，请求量降到个位数，
--       且处长跨学院审批也安全（按 identity_id 记，不依赖学院名）。
--
-- 适用场景：开发环境增量更新（生产环境用 init SQL 全新部署，init 已含本表）
-- 执行顺序：依赖 V3.0，需先执行 V3.0（不影响，本表独立）
--
-- ⚠️⚠️ 重要：
--   本脚本执行在 【CodeWave 应用数据库】（jygl_ 自建表所在库），
--   不是教务库（<内网地址·已脱敏>:6001 只读，禁止写入）！
--   执行前请确认当前连接的库是应用库，可用以下语句核对：
--     SELECT table_schema FROM information_schema.tables
--     WHERE table_name = 'jygl_lecture_group';
-- ============================================================================

-- ============================================================================
-- 1. 新建 jygl_approver_folder（审批人授权账本）
-- ============================================================================
-- 记录"某人（identity_id）被授到哪门课程的 L4 目录（folder_id）"
-- 撤旧：SELECT folder_id FROM 本表 WHERE identity_id=? 只撤这批（≠ 当前课程）的目录
-- 授当前课：DELETE 该人全部记录 → INSERT 当前课程一条
-- 唯一键 (identity_id, folder_id)：同一人同一课程目录只一行，防重复插入
CREATE TABLE IF NOT EXISTS `jygl_approver_folder` (
  `id`            BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  `identity_id`   BIGINT       NOT NULL COMMENT '审批人鸿翼 identityId（授到 L4 目录的人）',
  `employee_id`   VARCHAR(32)  NULL     COMMENT '审批人工号（溯源冗余）',
  `folder_id`     VARCHAR(64)  NOT NULL COMMENT '已授的鸿翼课程目录 folderId（L4）',
  `course_code`   VARCHAR(64)  NOT NULL COMMENT '课程代码（用于判断是否当前授的课）',
  `course_name`   VARCHAR(255) NULL     COMMENT '课程名（溯源冗余，可空）',
  `college_name`  VARCHAR(255) NULL     COMMENT '开课学院（溯源冗余，可空）',
  `academic_year` VARCHAR(32)  NULL     COMMENT '学年（如 2026-2027）',
  `semester`      INT          NULL     COMMENT '学期（1/2）',
  `grant_time`    DATETIME     NULL     COMMENT '最近授权时间（授当前课程时刷新）',
  `created_by`    VARCHAR(255) NULL     COMMENT '创建人',
  `created_time`  DATETIME     NULL     COMMENT '创建时间',
  `updated_by`    VARCHAR(255) NULL     COMMENT '修改人',
  `updated_time`  DATETIME     NULL     COMMENT '更新时间',
  `is_delete`     TINYINT      DEFAULT 0 COMMENT '删除标识',
  PRIMARY KEY (`id`),
  UNIQUE INDEX `idx_identity_folder` (`identity_id`, `folder_id`),
  INDEX `idx_identity` (`identity_id`, `is_delete`)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '审批人授权账本（撤旧只撤该人历史授过的课程目录，防权限累积）';

-- ============================================================================
-- 校验：新表结构
-- ============================================================================
SELECT 'jygl_approver_folder' AS tbl, COUNT(*) AS column_count
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jygl_approver_folder';

-- ============================================================================
-- 执行完成。校验提示：
--   ① 应返回 column_count = 15
--   ② 全库已含 jygl_ 表清单核对：
--      SELECT table_name FROM information_schema.tables
--      WHERE table_schema = DATABASE() AND table_name LIKE 'jygl_%' ORDER BY table_name;
--      应含：jygl_approver_folder / jygl_hy_folder_map / jygl_hy_perm_config /
--            jygl_hy_token_cache / jygl_lecture_group / jygl_lecture_group_item / jygl_material_file
-- ============================================================================
